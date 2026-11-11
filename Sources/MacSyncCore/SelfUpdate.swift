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

    public static let releasesAPI = "https://api.github.com/repos/onlymoein/macsync/releases/latest"
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

    /// The latest release, when it is newer than this copy.
    public func check() -> Release? {
        let result = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--max-time", "30",
                                                  "-H", "Accept: application/vnd.github+json", Self.releasesAPI],
                                input: nil, environment: [:])
        guard result.status == 0, let release = Self.parse(result.stdout),
              Self.isNewer(release.version, than: currentVersion) else { return nil }
        return release
    }

    static func parse(_ data: Data) -> Release? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["draft"] as? Bool != true, root["prerelease"] as? Bool != true,
              let tag = root["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard version.range(of: "^[0-9]+(\\.[0-9]+){0,3}$", options: .regularExpression) != nil else { return nil }
        let assets = (root["assets"] as? [[String: Any]] ?? []).compactMap { asset -> (String, String)? in
            guard let name = asset["name"] as? String, let url = asset["browser_download_url"] as? String,
                  url.hasPrefix("https://github.com/onlymoein/macsync/releases/download/") else { return nil }
            return (name, url)
        }
        guard let zip = assets.first(where: { $0.0 == "MacSync-\(version).zip" })?.1 else { return nil }
        let sum = assets.first(where: { $0.0 == "MacSync-\(version).zip.sha256" })?.1
        return Release(version: version, zipURL: zip, checksumURL: sum, notes: root["body"] as? String)
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
        if let brew = brewPath, installedWithBrew {
            // Refresh Homebrew's lists first, or it won't know the new version exists yet.
            let env = InventoryReader.brewEnvironment(brew)
            _ = runner.run(brew, ["update", "--quiet"], input: nil, environment: env)
            let result = runner.run(brew, ["upgrade", "--cask", "macsync"], input: nil, environment: env)
            return result.status == 0 ? .success(())
                : .failure(.refused("Homebrew couldn't update MacSync: \(result.stderr.split(whereSeparator: \.isNewline).last ?? "")"))
        }
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
