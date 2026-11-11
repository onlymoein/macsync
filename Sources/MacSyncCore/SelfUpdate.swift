import Foundation

/// Keeps MacSync itself up to date from its GitHub releases.
///
/// Installed with Homebrew, it updates through `brew upgrade --cask macsync`, so Homebrew stays
/// in charge of the app it installed. Otherwise it downloads the release zip, checks it against
/// the release's published SHA-256, checks it is MacSync signed by the same developer as the copy
/// that is running, and swaps it in.
public struct SelfUpdater {
    public struct Release: Equatable {
        public var version: String
        public var zipURL: String
        public var checksumURL: String?
        public var notes: String?
    }

    public static let bundleID = "com.onlymehdi.macsync"

    let runner: CommandRunning
    let brewPath: String?
    /// The running app's bundle, e.g. /Applications/MacSync.app.
    let appURL: URL
    let currentVersion: String

    public init(runner: CommandRunning, brewPath: String?, appURL: URL, currentVersion: String = MacSyncEnvironment.appVersion) {
        self.runner = runner
        self.brewPath = brewPath
        self.appURL = appURL
        self.currentVersion = currentVersion
    }

    public static let releasesPage = "https://github.com/onlymoein/macsync/releases/latest"
    static let downloadBase = "https://github.com/onlymoein/macsync/releases/download/"

    /// The latest release, when it is newer than this copy. It reads where GitHub's "latest
    /// release" page points rather than GitHub's API, which limits each network to 60 requests an
    /// hour; the files follow the release's fixed names.
    public func check() -> Release? {
        var found: [Release] = []
        let result = runner.run("/usr/bin/curl", ["-sS", "--proto", "=https", "--max-time", "30", "-o", "/dev/null",
                                                  "-w", "%{redirect_url}", Self.releasesPage], input: nil, environment: [:])
        if result.status == 0, let release = Self.release(fromRedirect: result.output) { found.append(release) }
        // GitHub's "latest" address is cached and can point at the previous release for a while;
        // the releases feed has the new one straight away.
        let feed = runner.run("/usr/bin/curl", ["-sS", "--proto", "=https", "--max-time", "30", Self.releasesFeed],
                              input: nil, environment: [:])
        if feed.status == 0 { found += Self.releases(fromFeed: feed.output) }
        guard let newest = found.max(by: { Self.isNewer($1.version, than: $0.version) }),
              Self.isNewer(newest.version, than: currentVersion) else { return nil }
        return newest
    }

    static let releasesFeed = "https://github.com/onlymoein/macsync/releases.atom"

    /// Releases named in GitHub's releases feed.
    static func releases(fromFeed text: String) -> [Release] {
        guard let regex = try? NSRegularExpression(pattern: "onlymoein/macsync/releases/tag/(v[0-9.]+)") else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { release(fromRedirect: "/releases/tag/" + text[$0]) }
        }
    }

    static func release(fromRedirect url: String) -> Release? {
        guard let range = url.range(of: "/releases/tag/") else { return nil }
        let tag = url[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard version.range(of: "^[0-9]+(\\.[0-9]+){0,3}$", options: .regularExpression) != nil else { return nil }
        let zip = Self.downloadBase + "v\(version)/MacSync-\(version).zip"
        return Release(version: version, zipURL: zip, checksumURL: zip + ".sha256", notes: nil)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Whether Homebrew installed this copy.
    public var installedWithBrew: Bool {
        guard let brew = brewPath else { return false }
        let result = runner.run(brew, ["list", "--cask", "macsync"], input: nil, environment: InventoryReader.brewEnvironment(brew))
        return result.status == 0
    }

    /// Installs the release in place of the running app. The caller relaunches afterwards.
    public func install(_ release: Release) -> Result<Void, EngineError> {
        // MacSync replaces itself even when Homebrew installed it: macOS lets an app update its own
        // bundle, but stops Homebrew (run from MacSync) from doing it, and a half-finished Homebrew
        // upgrade leaves no app behind. The cask is marked auto_updates, so Homebrew doesn't mind.
        let direct = installDirectly(release)
        guard case .failure = direct, let brew = brewPath, installedWithBrew,
              FileManager.default.fileExists(atPath: appURL.path) else { return direct }
        let env = InventoryReader.brewEnvironment(brew)
        _ = runner.run(brew, ["update", "--quiet"], input: nil, environment: env)
        let result = runner.run(brew, ["upgrade", "--cask", "macsync"], input: nil, environment: env)
        return result.status == 0 ? .success(()) : direct
    }

    private func installDirectly(_ release: Release) -> Result<Void, EngineError> {
        guard let checksumURL = release.checksumURL else {
            return .failure(.refused("The release has no checksum, so MacSync didn't install it."))
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("macsync-update-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: work) }
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("MacSync.zip")
        let get = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--proto-redir", "=https", "--max-time", "600",
                                               "-o", zip.path, release.zipURL], input: nil, environment: [:])
        let sum = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--max-time", "30", checksumURL],
                             input: nil, environment: [:])
        guard get.status == 0, sum.status == 0 else { return .failure(.refused("The update didn't download.")) }
        let expected = sum.output.split(separator: " ").first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let expected, expected.count == 64, AppDownloader.sha256(of: zip) == expected else {
            return .failure(.refused("The update didn't match its published checksum, so it wasn't installed."))
        }
        let unpack = work.appendingPathComponent("unpacked")
        guard runner.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpack.path], input: nil, environment: [:]).status == 0 else {
            return .failure(.refused("The update couldn't be unpacked."))
        }
        let newApp = unpack.appendingPathComponent("MacSync.app")
        guard let bundle = Bundle(url: newApp), bundle.bundleIdentifier == Self.bundleID,
              (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) == release.version else {
            return .failure(.refused("The update isn't the MacSync release it claims to be, so it wasn't installed."))
        }
        // Signed by the same developer as the copy that is running, when this copy is signed.
        if let team = teamID(appURL) {
            guard runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path], input: nil, environment: [:]).status == 0,
                  teamID(newApp) == team else {
                return .failure(.refused("The update isn't signed by MacSync's developer, so it wasn't installed."))
            }
        }
        let old = work.appendingPathComponent("old.app")
        do {
            try fm.moveItem(at: appURL, to: old)
            do { try fm.moveItem(at: newApp, to: appURL) } catch {
                try? fm.moveItem(at: old, to: appURL)
                throw error
            }
        } catch {
            return .failure(.refused("MacSync couldn't replace itself in \(appURL.deletingLastPathComponent().path)."))
        }
        return .success(())
    }

    func teamID(_ app: URL) -> String? {
        let result = runner.run("/usr/bin/codesign", ["-dv", "--verbose=2", app.path], input: nil, environment: [:])
        let text = result.stderr + result.output
        guard let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("TeamIdentifier=") }) else { return nil }
        let team = String(line.dropFirst("TeamIdentifier=".count))
        return team == "not set" ? nil : team
    }
}
