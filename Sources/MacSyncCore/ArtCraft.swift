import AppKit
import Foundation

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
    func installFolder() -> URL {
        if let text = try? String(contentsOf: settingsURL, encoding: .utf8),
           let regex = try? NSRegularExpression(pattern: #"install_locations:\(root:Some\(\\?"([^"\\]+)\\?"\)"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let path = String(text[range])
            if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        }
        let suite = env.applicationsDirectory.appendingPathComponent("Artcraft")
        return Engine.isUsableFolder(suite) ? suite : env.applicationsDirectory
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

    // MARK: Installing

    /// Installs or updates apps one by one, then records them in the launcher's list in one go.
    public func install(_ apps: [CraftApp], progress: (String) -> Void = { _ in }) -> [(CraftApp, Result<String, EngineError>)] {
        let apps = apps.filter(\.availableOnMac)
        let folder = installFolder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var results: [(CraftApp, Result<String, EngineError>)] = []
        for app in apps {
            progress("\(app.isInstalled ? "Updating" : "Installing") \(app.name)…")
            results.append((app, installOne(app, into: folder)))
        }
        let done = results.compactMap { pair -> (CraftApp, String)? in
            if case .success(let path) = pair.1 { return (pair.0, path) }
            return nil
        }
        if !done.isEmpty { record(done) }
        return results
    }

    private func installOne(_ app: CraftApp, into folder: URL) -> Result<String, EngineError> {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("macsync-craft-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: work) }
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        let dmg = work.appendingPathComponent(app.id + ".dmg")
        let get = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--proto-redir", "=https", "--max-time", "1800",
                                               "-o", dmg.path, app.dmgURL], input: nil, environment: [:])
        guard get.status == 0, fm.fileExists(atPath: dmg.path) else { return .failure(.refused("\(app.name) didn't download.")) }
        if let expected = app.sha256, AppDownloader.sha256(of: dmg) != expected {
            return .failure(.refused("The download of \(app.name) didn't match ArtCraft's published checksum, so it wasn't installed."))
        }
        let mount = work.appendingPathComponent("mount")
        try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
        guard runner.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path],
                         input: nil, environment: [:]).status == 0 else {
            return .failure(.refused("\(app.name)'s disk image couldn't be opened."))
        }
        defer { _ = runner.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"], input: nil, environment: [:]) }
        let found = ((try? fm.contentsOfDirectory(atPath: mount.path)) ?? []).first { $0.hasSuffix(".app") }
        guard let found, DirectApp.isSafeName(String(found.dropLast(4))) else {
            return .failure(.refused("\(app.name)'s disk image has no app in it."))
        }
        let source = mount.appendingPathComponent(found)
        guard Bundle(url: source)?.bundleIdentifier != nil else {
            return .failure(.refused("\(app.name)'s disk image doesn't hold a proper app."))
        }
        if let team = app.team {
            let sig = runner.run("/usr/bin/codesign", ["-dv", "--verbose=2", source.path], input: nil, environment: [:])
            guard (sig.stderr + sig.output).contains("TeamIdentifier=\(team)") else {
                return .failure(.refused("\(app.name) isn't signed by its developer as ArtCraft's catalog says, so it wasn't installed."))
            }
        }
        let target = folder.appendingPathComponent(found)
        let staged = folder.appendingPathComponent(".macsync-\(UUID().uuidString.prefix(6))-" + found)
        guard runner.run("/usr/bin/ditto", [source.path, staged.path], input: nil, environment: [:]).status == 0 else {
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
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.launcherBundleID)
        for app in running { app.terminate() }
        for _ in 0..<20 where running.contains(where: { !$0.isTerminated }) { Thread.sleep(forTimeInterval: 0.25) }
        var root = ((try? Data(contentsOf: recordsURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        var apps = root["apps"] as? [String: Any] ?? [:]
        change(&apps)
        root["apps"] = apps
        try? FileManager.default.createDirectory(at: recordsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: recordsURL, options: .atomic)
        }
        if !running.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.launcherBundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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

    public func installCraft(_ apps: [CraftApp], progress: (String) -> Void = { _ in }) -> [(CraftApp, Result<String, EngineError>)] {
        ArtCraft(env: env, runner: runner, now: now).install(apps, progress: progress)
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
    public func installCraftAgain(_ apps: [CraftApp]) {
        for app in apps { try? cancelRemoval(app.skipToken) }
    }
}
