import AppKit
import Foundation
import Security

/// One app from ArtCraft's own catalog, with what this Mac has of it.
public struct CraftApp: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var version: String
    public var dmgURL: String
    public var sha256: String?
    public var sizeBytes: Int64?
    /// What's installed here, if anything.
    public var installedVersion: String?
    public var installedPath: String?
    /// From ArtCraft Launcher's catalog.
    public var tagline: String?
    public var bundleID: String?
    public var bundleName: String?
    public var team: String?
    public var publisher: String?
    public var repo: String?
    public var iconURL: String?
    public var iconSHA256: String?
    /// False when the app has no Mac download yet (MailCraft today).
    public var availableOnMac: Bool { !dmgURL.isEmpty }

    public init(id: String, name: String, version: String, dmgURL: String, sha256: String? = nil, sizeBytes: Int64? = nil) {
        self.id = id; self.name = name; self.version = version; self.dmgURL = dmgURL; self.sha256 = sha256; self.sizeBytes = sizeBytes
    }

    public var isInstalled: Bool { installedVersion != nil }
    public var needsUpdate: Bool {
        guard let installedVersion else { return false }
        return SelfUpdater.isNewer(version, than: installedVersion)
    }
    /// The token MacSync uses for "not needed on this Mac".
    public var skipToken: String { "craft:" + id }
}

/// The ArtCraft suite, from ArtCraft's public catalog (the same one ArtCraft Launcher reads).
///
/// MacSync installs a Craft app from its official download, checks it against the published
/// SHA-256, puts it in ArtCraft Launcher's install folder, and records it in the launcher's own
/// list, so the launcher knows it's there and keeps it updated.
public struct ArtCraft {
    public static let catalogAddress = "https://api.storyteller.ai/v1/craft_apps/release_info"
    static let launcherBundleID = "ai.storyteller.artcraft-launcher"
    static let maxAge: TimeInterval = 3600

    let env: MacSyncEnvironment
    let runner: CommandRunning
    let now: () -> Date

    var home: URL { URL(fileURLWithPath: env.homeDirectory) }
    var recordsURL: URL { home.appendingPathComponent("Library/Application Support/ArtCraft Launcher/installed.json") }
    var settingsURL: URL { home.appendingPathComponent("Library/Application Support/ai.storyteller.artcraft-launcher/app.ron") }
    var cacheURL: URL { env.dataDirectory.appendingPathComponent("artcraft-catalog.json") }

    // MARK: Catalog

    /// ArtCraft Launcher's own catalog: every app it offers, official and community, as it grows.
    public static let launcherCatalogAddresses = [
        "https://getartcraft.com/launcher-catalog.toml",
        "https://raw.githubusercontent.com/storytold/craft-launcher/main/crates/core/catalog.toml",
    ]

    struct Listing { var id, name: String; var fields: [String: String] }

    /// The apps in ArtCraft Launcher's catalog (TOML: one [[apps]] table per app).
    static func parseLauncherCatalog(_ text: String) -> [Listing] {
        var listings: [Listing] = []
        for chunk in text.components(separatedBy: "[[apps]]").dropFirst() {
            var fields: [String: String] = [:]
            for line in chunk.split(separator: "\n") {
                let line = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[") { break }  // [apps.details] and below: not needed
                guard let eq = line.firstIndex(of: "=") else { continue }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { continue }
                value = String(value.dropFirst().dropLast())
                fields[key] = value
            }
            guard let id = fields["id"], id.range(of: "^[a-z0-9][a-z0-9-]{0,60}$", options: .regularExpression) != nil else { continue }
            listings.append(Listing(id: id, name: String((fields["name"] ?? id).prefix(60)), fields: fields))
        }
        return listings
    }

    /// Every app ArtCraft Launcher offers, with its newest Mac download (cached for an hour).
    /// Versions and downloads come from ArtCraft's release list, or from each app's GitHub release
    /// page and its SHA256SUMS file. GitHub's API isn't used, so its request limit never applies.
    func catalog(refresh: Bool = false) -> [CraftApp] {
        let fm = FileManager.default
        let age = ((try? fm.attributesOfItem(atPath: cacheURL.path))?[.modificationDate] as? Date).map { now().timeIntervalSince($0) } ?? .infinity
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode([CraftApp].self, from: $0) }
        if !refresh, age < Self.maxAge, let cached, !cached.isEmpty { return cached }

        var listings: [Listing] = []
        for address in Self.launcherCatalogAddresses where listings.isEmpty {
            let r = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--max-time", "30", address], input: nil, environment: [:])
            if r.status == 0 { listings = Self.parseLauncherCatalog(r.output) }
        }
        let releases = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--max-time", "30", Self.catalogAddress], input: nil, environment: [:])
        let known = Dictionary((releases.status == 0 ? Self.parse(releases.stdout) : []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // The launcher itself is in the release list but not in its own catalog.
        var apps: [CraftApp] = known["artcraft-launcher"].map { [$0] } ?? []
        for listing in listings {
            let f = listing.fields
            var app = known[listing.id] ?? latestFromGitHub(id: listing.id, repo: f["repo"])
                ?? CraftApp(id: listing.id, name: listing.name, version: "", dmgURL: "")
            app.name = listing.name
            app.tagline = f["tagline"].map { String($0.prefix(80)) }
            app.bundleID = f["mac_bundle_id"].flatMap { DirectApp.isSafeBundleID($0) ? $0 : nil }
            app.bundleName = f["mac_bundle_name"].flatMap { DirectApp.isSafeName($0) ? $0 : nil }
            app.team = f["mac_team"].flatMap { $0.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil ? $0 : nil }
            app.publisher = f["publisher"].map { String($0.prefix(40)) }
            app.repo = f["repo"]
            app.iconURL = f["icon_url"].flatMap { DirectApp.isSafeURL($0) ? $0 : nil }
            app.iconSHA256 = f["icon_sha256"]?.lowercased()
            // Like the launcher: an app from another developer needs a signing team to be installed.
            if app.team == nil, (app.publisher ?? "ArtCraft") != "ArtCraft" { app.dmgURL = "" }
            apps.append(app)
        }
        if listings.isEmpty { apps = Array(known.values) }  // catalog unreachable: the release list alone
        guard !apps.isEmpty else { return cached ?? [] }
        apps.sort { a, b in (a.id == "artcraft-launcher" ? 0 : 1, a.name) < (b.id == "artcraft-launcher" ? 0 : 1, b.name) }
        try? fm.createDirectory(at: env.dataDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(apps) { try? data.write(to: cacheURL, options: .atomic) }
        return apps
    }

    /// The newest release of a GitHub repository, from its release page and SHA256SUMS file.
    func latestFromGitHub(id: String, repo: String?) -> CraftApp? {
        guard let repo, repo.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else { return nil }
        let page = runner.run("/usr/bin/curl", ["-sS", "--proto", "=https", "--max-time", "20", "-o", "/dev/null", "-w", "%{redirect_url}",
                                                "https://github.com/\(repo)/releases/latest"], input: nil, environment: [:])
        guard page.status == 0, let range = page.output.range(of: "/releases/tag/") else { return nil }
        let tag = String(page.output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard tag.range(of: "^[A-Za-z0-9._-]{1,40}$", options: .regularExpression) != nil else { return nil }
        let base = "https://github.com/\(repo)/releases/download/\(tag)/"
        let sums = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--max-time", "20", base + "SHA256SUMS.txt"], input: nil, environment: [:])
        guard sums.status == 0 else { return nil }
        let lines = sums.output.split(whereSeparator: \.isNewline).map { $0.split(separator: " ", omittingEmptySubsequences: true) }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let wanted = ["\(id)-\(version)-macos-universal.dmg", "\(id)-\(version)-macos-\(Self.arch).dmg", "\(id)-macos-universal.dmg"]
        for name in wanted {
            if let line = lines.first(where: { $0.count == 2 && String($0[1]) == name }) {
                return CraftApp(id: id, name: id, version: version, dmgURL: base + name, sha256: String(line[0]).lowercased())
            }
        }
        return nil
    }

    static func parse(_ data: Data) -> [CraftApp] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["release_info"] as? [String: Any], let apps = info["apps"] as? [String: Any] else { return [] }
        return apps.compactMap { key, value -> CraftApp? in
            guard key.range(of: "^[a-z0-9][a-z0-9-]{0,60}$", options: .regularExpression) != nil,
                  let app = value as? [String: Any], let release = app["latest_release"] as? [String: Any],
                  release["prerelease"] as? Bool != true, let version = release["version"] as? String,
                  let assets = release["assets"] as? [[String: Any]] else { return nil }
            let dmg = assets.first { asset in
                let platform = asset["platform"] as? [String: Any]
                return platform?["os"] as? String == "macos" && platform?["package_type"] as? String == "dmg"
                    && ["universal", Self.arch].contains(platform?["arch"] as? String ?? "")
            }
            guard let dmg, let url = dmg["download_url"] as? String, DirectApp.isSafeURL(url),
                  url.hasPrefix("https://github.com/storytold/") else { return nil }
            let name = (app["name"] as? String).map { String($0.prefix(60)) } ?? key
            return CraftApp(id: key, name: name, version: String(version.prefix(30)), dmgURL: url,
                            sha256: (dmg["sha256"] as? String)?.lowercased(), sizeBytes: (dmg["size_bytes"] as? NSNumber)?.int64Value)
        }
        .sorted { a, b in (a.id == "artcraft-launcher" ? 0 : 1, a.name) < (b.id == "artcraft-launcher" ? 0 : 1, b.name) }
    }

    static var arch: String {
        #if arch(x86_64)
        return "x86_64"
        #else
        return "arm64"
        #endif
    }

    // MARK: What's here

    /// ArtCraft Launcher's install folder, from its settings; otherwise Applications/Artcraft if it
    /// exists; otherwise Applications.
    /// A folder the person picked in MacSync, used over the launcher's own setting.
    var chosenFolder: URL?

    func installFolder() -> URL {
        if let chosenFolder { return chosenFolder }
        if let text = try? String(contentsOf: settingsURL, encoding: .utf8),
           let regex = try? NSRegularExpression(pattern: #"install_locations:\(root:Some\(\\?"([^"\\]+)\\?"\)"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let path = String(text[range])
            if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        }
        // The launcher's own default. Installing makes it if this Mac doesn't have it yet.
        return env.applicationsDirectory.appendingPathComponent("Artcraft")
    }

    /// The launcher's list of what it installed: id → (version, path).
    func records() -> [String: [String: Any]] {
        guard let data = try? Data(contentsOf: recordsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return root["apps"] as? [String: [String: Any]] ?? [:]
    }

    /// The catalog with what's installed here: from the launcher's list when the app is where it
    /// says, otherwise from the install folder or Applications.
    public func status(refresh: Bool = false) -> [CraftApp] {
        let records = records()
        let folder = installFolder()
        return catalog(refresh: refresh).map { app in
            var app = app
            var candidates: [String] = []
            if let path = records[app.id]?["path"] as? String { candidates.append(path) }
            let file = (app.bundleName ?? app.name) + ".app"
            candidates += [folder.appendingPathComponent(file).path, env.applicationsDirectory.appendingPathComponent(file).path,
                           env.applicationsDirectory.appendingPathComponent("Artcraft").appendingPathComponent(file).path]
            for path in candidates where FileManager.default.fileExists(atPath: path) {
                let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
                app.installedVersion = (info?["CFBundleShortVersionString"] as? String) ?? (records[app.id]?["version"] as? String) ?? "?"
                app.installedPath = path
                break
            }
            return app
        }
    }

    /// Craft apps that are on this Mac but missing from ArtCraft Launcher's list: installed by an
    /// earlier MacSync, or by hand. Each is checked against its catalog signing team first.
    func unlisted() -> [(CraftApp, String)] {
        let records = records()
        return status().compactMap { app in
            guard let path = app.installedPath, records[app.id] == nil, app.id != "artcraft-launcher" else { return nil }
            if let team = app.team, case .team(let found) = Self.signingTeam(of: URL(fileURLWithPath: path), within: 10), found != team {
                return nil
            }
            return (app, path)
        }
    }

    /// Adds them to the launcher's list, with the launcher closed for the write.
    @discardableResult
    func registerUnlisted() -> [String] {
        let found = unlisted()
        guard !found.isEmpty else { return [] }
        editRecords { apps in for (app, path) in found { apps[app.id] = Self.record(app, path: path, now: now()) } }
        return found.map(\.0.name)
    }

    // MARK: Installing

    /// Installs or updates apps one by one, then records them in the launcher's list in one go.
    public func install(_ apps: [CraftApp], progress: (String) -> Void = { _ in },
                        finished: (CraftApp, Result<String, EngineError>) -> Void = { _, _ in }) -> [(CraftApp, Result<String, EngineError>)] {
        // The launcher first: it knows about the others and keeps them up to date.
        let apps = apps.filter(\.availableOnMac).sorted { ($0.id == "artcraft-launcher" ? 0 : 1) < ($1.id == "artcraft-launcher" ? 0 : 1) }
        let folder = installFolder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var results: [(CraftApp, Result<String, EngineError>)] = []
        // The launcher keeps its list in memory and writes it back, so it stays closed while the
        // apps go in; each one is added to its list the moment it's done, and it reopens at the end.
        let wasOpen = quitLauncher()
        defer { if wasOpen { reopenLauncher() } }
        for app in apps {
            progress("\(app.isInstalled ? "Updating" : "Installing") \(app.name)…")
            let started = Date()
            log("\(app.name) \(app.version): start, into \(folder.path), checksum \(app.sha256 == nil ? "unknown" : "known"), team \(app.team ?? "none")")
            let result = withoutActuallyEscaping(progress) { report in
                installOne(app, into: folder) { message in
                    log("\(app.name) +\(Int(Date().timeIntervalSince(started)))s: \(message)")
                    report(message)
                }
            }
            switch result {
            case .success(let path): log("\(app.name) +\(Int(Date().timeIntervalSince(started)))s: installed at \(path)")
            case .failure(let error): log("\(app.name) +\(Int(Date().timeIntervalSince(started)))s: FAILED: \(error.localizedDescription)")
            }
            results.append((app, result))
            if case .success(let path) = result { writeRecords { apps in apps[app.id] = Self.record(app, path: path, now: now()) } }
            // Each app's outcome shows as soon as it's known, not when the whole batch ends.
            finished(app, result)
        }
        return results
    }

    enum SigningCheck { case team(String), unsigned, timedOut }

    /// The team that signed an app, read by macOS's Security framework on this Mac: no other
    /// program and no network, and it gives up after `seconds`.
    static func signingTeam(of app: URL, within seconds: TimeInterval, slow: (() -> Void)? = nil) -> SigningCheck {
        var answer: SigningCheck = .unsigned
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            var code: SecStaticCode?
            var info: CFDictionary?
            if SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
               SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
               let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String {
                answer = .team(team)
            }
            done.signal()
        }
        // Taking a while means macOS is busy (often scanning apps that just arrived): say so.
        if let slow, seconds > 8, done.wait(timeout: .now() + 8) == .timedOut {
            slow()
            return done.wait(timeout: .now() + seconds - 8) == .timedOut ? .timedOut : answer
        }
        return done.wait(timeout: .now() + seconds) == .timedOut ? .timedOut : answer
    }

    /// One line per step, with how long since the app started, to ~/Library/Logs/MacSync/craft.log
    /// and to MacSync/logs in this person's iCloud Drive, so it can be read from their other Macs.
    func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) \(env.machineName): \(line)\n"
        let places = [URL(fileURLWithPath: env.homeDirectory).appendingPathComponent("Library/Logs/MacSync/craft.log"),
                      env.syncDirectory.appendingPathComponent("logs/\(env.machineID)-craft.log")]
        for url in places {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if old.count > 200_000 { old = String(old.suffix(100_000)) }
            try? (old + text).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Opens a disk image read-only and out of sight. macOS 26 and later prefer diskutil; older
    /// systems use hdiutil. Either answers a license agreement and gives up after 3 quiet minutes.
    static func attach(_ dmg: URL, at mount: URL, runner: CommandRunning) -> CommandResult {
        if #available(macOS 26.0, *), FileManager.default.isExecutableFile(atPath: "/usr/sbin/diskutil") {
            let result = runner.stream("/usr/sbin/diskutil", ["image", "attach", "--readOnly", "--nobrowse", "--mountPoint", mount.path, dmg.path],
                                       input: Data("Y\n".utf8), environment: [:], idleTimeout: 180) { _ in }
            if result.status == 0 { return result }
        }
        return runner.stream("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-noverify", "-mountpoint", mount.path, dmg.path],
                             input: Data("Y\n".utf8), environment: ["PAGER": "/bin/cat"], idleTimeout: 180) { _ in }
    }

    /// Closes it again, giving it 30 seconds.
    static func detach(_ mount: URL, runner: CommandRunning) {
        _ = runner.stream("/usr/bin/hdiutil", ["detach", mount.path, "-force"], input: nil, environment: [:], idleTimeout: 30) { _ in }
    }

    /// Downloads with curl while watching the file grow, so the window can show how far it is.
    static func watchedDownload(runner: CommandRunning, url: String, to file: URL, expected: Int64?,
                                progress: @escaping (Int?, Int64) -> Void) -> CommandResult {
        var result = CommandResult(status: -1)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            // Gives up on a connection that never answers (30 s) or a download that stalls below
            // 1 KB/s for a minute, and tries twice more, instead of waiting out half an hour.
            result = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--proto-redir", "=https", "--max-time", "1800",
                                                  "--connect-timeout", "30", "--speed-limit", "1024", "--speed-time", "60",
                                                  "--retry", "2", "--retry-delay", "3",
                                                  "-o", file.path, url], input: nil, environment: [:])
            done.signal()
        }
        var last: Int64 = -1
        while done.wait(timeout: .now() + 0.5) == .timedOut {
            guard let size = ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.int64Value,
                  size != last else { continue }
            last = size
            // Without a published size, say how much has arrived.
            progress(expected.flatMap { $0 > 0 ? min(99, Int(size * 100 / $0)) : nil }, size)
        }
        return result
    }

    private func installOne(_ app: CraftApp, into folder: URL, progress: @escaping (String) -> Void = { _ in }) -> Result<String, EngineError> {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("macsync-craft-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: work) }
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        let dmg = work.appendingPathComponent(app.id + ".dmg")
        progress("Connecting to ArtCraft's downloads for \(app.name)…")
        let get = Self.watchedDownload(runner: runner, url: app.dmgURL, to: dmg, expected: app.sizeBytes) { percent, bytes in
            progress(percent.map { "Downloading \(app.name)… \($0)%" }
                     ?? "Downloading \(app.name)… \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
        }
        guard get.status == 0, fm.fileExists(atPath: dmg.path) else {
            let why: String
            switch get.status {
            case 28: why = "The download of \(app.name) stopped making progress. Check the connection and try again."
            case 6, 7: why = "ArtCraft's downloads couldn't be reached. Check the connection and try again."
            case 22: why = "ArtCraft's download server turned the request down (\(get.stderr.contains("429") || get.stderr.contains("403") ? "too many requests for now" : "not found")). Try again in a few minutes."
            default: why = "\(app.name) didn't download. Try again."
            }
            return .failure(.refused(why))
        }
        progress("Verifying \(app.name)…")
        if let expected = app.sha256, AppDownloader.sha256(of: dmg) != expected {
            return .failure(.refused("The download of \(app.name) didn't match ArtCraft's published checksum, so it wasn't installed."))
        }
        let mount = work.appendingPathComponent("mount")
        try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
        progress("Opening \(app.name)'s disk image…")
        let attach = Self.attach(dmg, at: mount, runner: runner)
        guard attach.status == 0 else {
            Self.detach(mount, runner: runner)
            return .failure(.refused(attach.status == -2 ? "\(app.name)'s disk image didn't open within 3 minutes. Try again."
                                                         : "\(app.name)'s disk image couldn't be opened."))
        }
        let found = ((try? fm.contentsOfDirectory(atPath: mount.path)) ?? []).first { $0.hasSuffix(".app") }
        guard let found, DirectApp.isSafeName(String(found.dropLast(4))) else {
            Self.detach(mount, runner: runner)
            return .failure(.refused("\(app.name)'s disk image has no app in it."))
        }
        // Copied straight off the disk image, which is then closed: every check below reads the
        // copy on this Mac's own disk, never the mounted image.
        progress("Copying \(app.name) out of its disk image…")
        let local = work.appendingPathComponent(found)
        let copy = runner.stream("/usr/bin/ditto", [mount.appendingPathComponent(found).path, local.path], input: nil,
                                 environment: [:], idleTimeout: 180) { _ in }
        Self.detach(mount, runner: runner)
        guard copy.status == 0, fm.fileExists(atPath: local.path) else {
            return .failure(.refused(copy.status == -2 ? "Copying \(app.name) off its disk image stopped making progress. Try again."
                                                       : "\(app.name) couldn't be copied off its disk image."))
        }
        let source = local
        guard Bundle(url: source)?.bundleIdentifier != nil else {
            return .failure(.refused("\(app.name)'s disk image doesn't hold a proper app."))
        }
        if let team = app.team {
            progress("Checking \(app.name)'s signature…")
            // First Apple's codesign, which reads the team from the app's own signature and doesn't
            // check certificates over the network; then the Security framework, which can.
            var check: SigningCheck = .timedOut
            let sig = runner.stream("/usr/bin/codesign", ["-dv", "--verbose=2", source.path], input: nil, environment: [:],
                                    idleTimeout: 15) { _ in }
            if let line = (sig.stderr + sig.output).split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("TeamIdentifier=") }) {
                let team = String(line.dropFirst("TeamIdentifier=".count))
                check = team == "not set" ? .unsigned : .team(team)
            } else if sig.status != -2 {
                check = .unsigned
            } else {
                progress("Waiting for macOS to check \(app.name); it's busy checking new apps…")
                check = Self.signingTeam(of: source, within: 15)
            }
            switch check {
            case .team(let found) where found == team:
                break
            case .timedOut where app.sha256 != nil:
                // macOS didn't answer, but the download matched ArtCraft's published checksum, and
                // macOS checks the signature itself the first time the app opens.
                progress("\(app.name): macOS didn't answer the signature check; the checksum matched, so it's installed…")
            case .timedOut:
                return .failure(.refused("macOS didn't finish checking \(app.name)'s signature. Try again in a minute."))
            default:
                return .failure(.refused("\(app.name) isn't signed by its developer as ArtCraft's catalog says, so it wasn't installed."))
            }
        }
        let target = folder.appendingPathComponent(found)
        let staged = folder.appendingPathComponent(".macsync-\(UUID().uuidString.prefix(6))-" + found)
        progress("Copying \(app.name) into \(folder.lastPathComponent)…")
        do { try fm.moveItem(at: source, to: staged) } catch {
            try? fm.removeItem(at: staged)
            return .failure(.refused("\(app.name) couldn't be copied into \(folder.lastPathComponent)."))
        }
        // An update: the old copy goes to the Trash, where it can be put back.
        if fm.fileExists(atPath: target.path) {
            guard (try? fm.trashItem(at: target, resultingItemURL: nil)) != nil else {
                try? fm.removeItem(at: staged)
                return .failure(.refused("The old \(app.name) couldn't be replaced. Quit it and try again."))
            }
        }
        do { try fm.moveItem(at: staged, to: target) } catch {
            try? fm.removeItem(at: staged)
            return .failure(.refused("\(app.name) couldn't be moved into \(folder.lastPathComponent)."))
        }
        return .success(target.path)
    }

    /// Moves apps to the Trash (asking for the password when macOS requires it) and takes them off
    /// ArtCraft Launcher's list, so it shows them as not installed.
    public func remove(_ apps: [CraftApp], progress: (String) -> Void = { _ in }) -> [(CraftApp, Result<String, EngineError>)] {
        var results: [(CraftApp, Result<String, EngineError>)] = []
        for app in apps {
            guard let path = app.installedPath else { results.append((app, .success(""))); continue }
            progress("Removing \(app.name)…")
            let url = URL(fileURLWithPath: path)
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil || Engine.recycleAskingForPassword(url) {
                results.append((app, .success(path)))
            } else {
                results.append((app, .failure(.refused("\(app.name) wasn't moved to the Trash. Quit it and try again."))))
            }
        }
        let removed = results.compactMap { pair -> String? in
            if case .success = pair.1 { return pair.0.id }
            return nil
        }
        if !removed.isEmpty { forget(removed) }
        return results
    }

    private func forget(_ ids: [String]) {
        editRecords { apps in for id in ids { apps[id] = nil } }
    }

    /// Changes ArtCraft Launcher's list with the launcher closed, then reopens it if it was open.
    private func editRecords(_ change: (inout [String: Any]) -> Void) {
        let wasOpen = quitLauncher()
        writeRecords(change)
        if wasOpen { reopenLauncher() }
    }

    /// Quits ArtCraft Launcher if it's running. True when it was.
    /// Left while MacSync has the launcher closed, so a MacSync that was stopped meanwhile reopens it next time.
    var launcherClosedMarker: URL { env.dataDirectory.appendingPathComponent("launcher-closed-by-macsync") }

    private func quitLauncher() -> Bool {
        // Only the real launcher of the real home folder; tests and demos use pretend ones.
        guard env.homeDirectory == NSHomeDirectory() else { return false }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.launcherBundleID)
        if !running.isEmpty {
            try? FileManager.default.createDirectory(at: env.dataDirectory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: launcherClosedMarker.path, contents: Data())
        }
        for app in running { app.terminate() }
        for _ in 0..<20 where running.contains(where: { !$0.isTerminated }) { Thread.sleep(forTimeInterval: 0.25) }
        // A tray app can decline to quit; it must be gone, or it writes its old list back over ours.
        for app in running where !app.isTerminated { app.forceTerminate() }
        for _ in 0..<12 where running.contains(where: { !$0.isTerminated }) { Thread.sleep(forTimeInterval: 0.25) }
        return !running.isEmpty
    }

    /// Back in the menu bar the way it was, not as a window in front of you.
    func reopenLauncher() {
        try? FileManager.default.removeItem(at: launcherClosedMarker)
        guard env.homeDirectory == NSHomeDirectory(), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.launcherBundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--hidden"]
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    static func record(_ app: CraftApp, path: String, now: Date) -> [String: Any] {
        let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
        return ["version": (info?["CFBundleShortVersionString"] as? String) ?? app.version, "kind": "Dmg", "path": path,
                "installed_at": Int(now.timeIntervalSince1970), "files": [String](), "needs_root": false]
    }

    /// Writes the launcher's list. Only call it with the launcher closed.
    private func writeRecords(_ change: (inout [String: Any]) -> Void) {
        var root = ((try? Data(contentsOf: recordsURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        var apps = root["apps"] as? [String: Any] ?? [:]
        change(&apps)
        root["apps"] = apps
        try? FileManager.default.createDirectory(at: recordsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: recordsURL, options: .atomic)
        }
    }

    /// Adds the apps to ArtCraft Launcher's list, the same way it records its own installs. The
    /// launcher rewrites that file while it runs, so it is closed for the write and reopened.
    private func record(_ done: [(CraftApp, String)]) {
        editRecords { apps in
            for (app, path) in done {
                let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
                apps[app.id] = ["version": (info?["CFBundleShortVersionString"] as? String) ?? app.version, "kind": "Dmg", "path": path,
                                "installed_at": Int(now().timeIntervalSince1970), "files": [String](), "needs_root": false] as [String: Any]
            }
        }
    }
}

extension ArtCraft {
    /// The app's icon from ArtCraft's catalog, checked against its published SHA-256 and kept
    /// on this Mac. Uses the network the first time.
    func iconFile(for app: CraftApp) -> URL? {
        guard let address = app.iconURL else { return nil }
        let folder = env.dataDirectory.appendingPathComponent("craft-icons", isDirectory: true)
        let file = folder.appendingPathComponent(app.id + ".png")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temp = folder.appendingPathComponent(app.id + ".part")
        defer { try? FileManager.default.removeItem(at: temp) }
        let r = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--max-time", "20", "-o", temp.path, address], input: nil, environment: [:])
        guard r.status == 0, NSImage(contentsOf: temp) != nil else { return nil }
        if let expected = app.iconSHA256, AppDownloader.sha256(of: temp) != expected { return nil }
        try? FileManager.default.moveItem(at: temp, to: file)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
}

extension Engine {
    public func craftIconFile(_ app: CraftApp) -> URL? { ArtCraft(env: env, runner: runner, now: now).iconFile(for: app) }

    /// ArtCraft's apps with what this Mac has. Uses the network; call it off the main thread.
    public func craftApps(refresh: Bool = false) -> [CraftApp] {
        ArtCraft(env: env, runner: runner, now: now).status(refresh: refresh)
    }

    public func installCraft(_ apps: [CraftApp], into folder: URL? = nil, progress: (String) -> Void = { _ in },
                             finished: (CraftApp, Result<String, EngineError>) -> Void = { _, _ in }) -> [(CraftApp, Result<String, EngineError>)] {
        var craft = ArtCraft(env: env, runner: runner, now: now)
        craft.chosenFolder = folder
        var apps = apps
        // A Craft app without the launcher: get the launcher too, first.
        if !apps.contains(where: { $0.id == "artcraft-launcher" }),
           let launcher = craft.status().first(where: { $0.id == "artcraft-launcher" }), !launcher.isInstalled, launcher.availableOnMac {
            apps.insert(launcher, at: 0)
        }
        return craft.install(apps, progress: progress, finished: finished)
    }

    /// MacSync closed ArtCraft Launcher and was stopped before reopening it: reopen it now, hidden.
    public func reopenLauncherIfLeftClosed() {
        let craft = ArtCraft(env: env, runner: runner, now: now)
        guard FileManager.default.fileExists(atPath: craft.launcherClosedMarker.path) else { return }
        craft.reopenLauncher()
    }

    /// Lists Craft apps that are installed but missing from ArtCraft Launcher's list. Returns their names.
    @discardableResult
    public func registerUnlistedCraft() -> [String] { ArtCraft(env: env, runner: runner, now: now).registerUnlisted() }

    /// Where ArtCraft apps go on this Mac: the folder picked in MacSync, else the launcher's.
    public func craftInstallFolder(chosen: URL? = nil) -> URL {
        var craft = ArtCraft(env: env, runner: runner, now: now)
        craft.chosenFolder = chosen
        return craft.installFolder()
    }

    public func removeCraft(_ apps: [CraftApp], everywhere: Bool = false,
                            progress: (String) -> Void = { _ in }) -> [(CraftApp, Result<String, EngineError>)] {
        let results = ArtCraft(env: env, runner: runner, now: now).remove(apps, progress: progress)
        if everywhere {
            // Like other apps: every Mac is asked to remove it, and MacSync stops offering it.
            let gone = results.filter { if case .success = $0.1 { return true }; return false }.map(\.0)
            recordRemovals(gone.map { ($0.skipToken, $0.name) })
        }
        return results
    }

    /// Installing a removed Craft app again brings it back on every Mac.
    /// Installing a Craft app again takes back a "remove from all Macs" for it, when there is one.
    public func installCraftAgain(_ apps: [CraftApp]) {
        let removed = Set(currentRemovals().filter(\.active).map(\.token))
        for app in apps where removed.contains(app.skipToken) { try? cancelRemoval(app.skipToken) }
    }
}
