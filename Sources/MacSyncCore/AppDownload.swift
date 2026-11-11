import CryptoKit
import Foundation

/// An app that came from neither Homebrew nor the App Store (a direct download such as ArtCraft).
/// Other Macs get it from where it is published, never as a copy of this Mac's app.
public struct DirectApp: Codable, Equatable, Hashable {
    public var bundleID: String
    /// The app's file name in Applications, without ".app".
    public var name: String
    public var version: String?
    /// The Homebrew cask that publishes this app, used only to find its official download.
    public var cask: String?
    /// The app's own update feed (Sparkle `SUFeedURL`), which names its latest download.
    public var feed: String?

    public init(bundleID: String, name: String, version: String? = nil, cask: String? = nil, feed: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.cask = cask
        self.feed = feed
    }

    public var canDownload: Bool { cask != nil || feed != nil }

    static func isSafeBundleID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]{0,154}$", options: .regularExpression) != nil && !id.contains("..")
    }

    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 120 && !name.contains("/") && !name.hasPrefix(".")
            && name.rangeOfCharacter(from: .controlCharacters) == nil
    }

    static func isSafeCask(_ token: String) -> Bool {
        token.range(of: "^[a-z0-9][a-z0-9@+_.-]{0,99}$", options: .regularExpression) != nil
    }

    /// A public https address with no credentials. Query strings are refused because download
    /// links sometimes carry a person's session or a signed token.
    static func isSafeURL(_ text: String) -> Bool {
        guard text.count <= 2000, let url = URL(string: text), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return false }
        return true
    }

    static func isSafeFeed(_ text: String) -> Bool {
        isSafeURL(text) && URL(string: text)?.query == nil
    }

    /// Keeps only the fields that are safe to act on, for a record that came from another Mac.
    var sanitized: DirectApp {
        var copy = self
        if let cask, !Self.isSafeCask(cask) { copy.cask = nil }
        if let feed, !Self.isSafeFeed(feed) { copy.feed = nil }
        return copy
    }
}

/// Homebrew's public list of casks: which cask publishes which app, and where it downloads from.
/// Read from formulae.brew.sh and kept for a day. Nothing is sent but the request for the list.
struct CaskCatalog {
    static let address = "https://formulae.brew.sh/api/cask.json"
    static let maxAge: TimeInterval = 86_400

    struct Entry {
        var token: String; var url: String; var sha256: String?; var intelURL: String?; var intelSHA256: String?
        var name: String? = nil; var desc: String? = nil; var homepage: String? = nil
    }

    let byApp: [String: [String]]
    let entries: [String: Entry]
    /// Casks by the bundle IDs they quit on uninstall, which catches .pkg apps (Office, Zoom) that have no app artifact.
    var byBundleID: [String: [String]] = [:]

    static func load(env: MacSyncEnvironment, runner: CommandRunning, now: Date) -> CaskCatalog? {
        let cache = env.dataDirectory.appendingPathComponent("cask-catalog.json")
        let fm = FileManager.default
        let modified = (try? fm.attributesOfItem(atPath: cache.path)[.modificationDate] as? Date) ?? .distantPast
        if now.timeIntervalSince(modified) > maxAge || !fm.fileExists(atPath: cache.path) {
            try? fm.createDirectory(at: env.dataDirectory, withIntermediateDirectories: true)
            let temp = cache.appendingPathExtension("part")
            let result = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--max-time", "120", "-o", temp.path, address],
                                    input: nil, environment: [:])
            if result.status == 0, fm.fileExists(atPath: temp.path) {
                try? fm.removeItem(at: cache)
                try? fm.moveItem(at: temp, to: cache)
            } else {
                try? fm.removeItem(at: temp)
            }
        }
        let stamp = (try? fm.attributesOfItem(atPath: cache.path)[.modificationDate] as? Date) ?? .distantPast
        if let hit = Memo.shared.get(cache.path, stamp) { return hit }
        guard let data = try? Data(contentsOf: cache), let catalog = parse(data) else { return nil }
        Memo.shared.set(cache.path, stamp, catalog)
        return catalog
    }

    /// The parsed list, so a sync doesn't read 20 MB of JSON each time.
    private final class Memo: @unchecked Sendable {
        static let shared = Memo()
        private let lock = NSLock()
        private var value: (path: String, stamp: Date, catalog: CaskCatalog)?
        func get(_ path: String, _ stamp: Date) -> CaskCatalog? {
            lock.lock(); defer { lock.unlock() }
            guard let value, value.path == path, value.stamp == stamp else { return nil }
            return value.catalog
        }
        func set(_ path: String, _ stamp: Date, _ catalog: CaskCatalog) {
            lock.lock(); value = (path, stamp, catalog); lock.unlock()
        }
    }

    static func parse(_ data: Data) -> CaskCatalog? {
        guard let casks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var byApp: [String: [String]] = [:]
        var byBundleID: [String: [String]] = [:]
        var entries: [String: Entry] = [:]
        for cask in casks {
            guard let token = cask["token"] as? String, DirectApp.isSafeCask(token), let url = cask["url"] as? String else { continue }
            for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
                for app in artifact["app"] as? [Any] ?? [] {
                    if let path = app as? String { byApp[(path as NSString).lastPathComponent, default: []].append(token) }
                }
                for (id, apps) in Self.uninstallHints(artifact) {
                    if let id { byBundleID[id, default: []].append(token) }
                    for app in apps where !(byApp[app]?.contains(token) ?? false) { byApp[app, default: []].append(token) }
                }
            }
            // Intel builds are listed as variations named like "x86_64_sonoma".
            let intel = (cask["variations"] as? [String: [String: Any]] ?? [:])
                .filter { $0.key.hasPrefix("x86_64") }.sorted { $0.key > $1.key }.first?.value
            entries[token] = Entry(token: token, url: url, sha256: cask["sha256"] as? String,
                                   intelURL: intel?["url"] as? String, intelSHA256: intel?["sha256"] as? String,
                                   name: (cask["name"] as? [String])?.first, desc: cask["desc"] as? String,
                                   homepage: cask["homepage"] as? String)
        }
        return CaskCatalog(byApp: byApp, entries: entries, byBundleID: byBundleID)
    }

    /// Bundle IDs a cask quits, and app bundles it deletes, on uninstall.
    static func uninstallHints(_ artifact: [String: Any]) -> [(String?, [String])] {
        var out: [(String?, [String])] = []
        for key in ["uninstall"] {
            for step in artifact[key] as? [[String: Any]] ?? [] {
                let quits = (step["quit"] as? [String]) ?? (step["quit"] as? String).map { [$0] } ?? []
                let deletes = (step["delete"] as? [String]) ?? (step["delete"] as? String).map { [$0] } ?? []
                let apps = deletes.filter { $0.hasPrefix("/Applications/") && $0.hasSuffix(".app") && !$0.contains("*") }
                    .map { ($0 as NSString).lastPathComponent }
                for id in quits where DirectApp.isSafeBundleID(id) { out.append((id, [])) }
                if !apps.isEmpty { out.append((nil, apps)) }
            }
        }
        return out
    }

    /// The cask for an app, by bundle ID, when its file name doesn't match.
    func cask(forBundleID id: String) -> String? {
        let tokens = byBundleID[id] ?? []
        return tokens.first { !$0.contains("@") } ?? tokens.first
    }

    /// The cask for an app bundle such as "Google Chrome.app". Prefers the main release over
    /// "@beta" and similar channels.
    func cask(forApp file: String) -> String? {
        let tokens = byApp[file] ?? []
        return tokens.first { !$0.contains("@") } ?? tokens.first
    }
}

/// Fetches an app's installer from where it is published and opens it, so the person finishes
/// installing it the usual way. Downloads are marked as coming from the internet, so macOS
/// checks them like any other download.
struct AppDownloader {
    let env: MacSyncEnvironment
    let runner: CommandRunning
    let now: () -> Date
    var isIntel: Bool = {
        #if arch(x86_64)
        return true
        #else
        return false
        #endif
    }()

    struct Download { var url: String; var sha256: String? }

    var downloadsDirectory: URL {
        URL(fileURLWithPath: env.homeDirectory).appendingPathComponent("Downloads", isDirectory: true)
    }

    func resolve(_ app: DirectApp) -> Download? {
        if let token = app.cask, DirectApp.isSafeCask(token),
           let entry = CaskCatalog.load(env: env, runner: runner, now: now())?.entries[token] {
            let url = isIntel ? (entry.intelURL ?? entry.url) : entry.url
            let sum = isIntel && entry.intelURL != nil ? entry.intelSHA256 : entry.sha256
            if DirectApp.isSafeURL(url) { return Download(url: url, sha256: sum == "no_check" ? nil : sum) }
        }
        if let feed = app.feed, DirectApp.isSafeFeed(feed) {
            let result = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--max-time", "60", feed], input: nil, environment: [:])
            if result.status == 0, let url = Self.latestEnclosure(in: result.stdout), DirectApp.isSafeURL(url) {
                return Download(url: url, sha256: nil)
            }
        }
        return nil
    }

    /// Downloads the installer into Downloads and opens it. Returns the file's path.
    func fetch(_ app: DirectApp) -> Result<String, EngineError> {
        guard DirectApp.isSafeName(app.name) else { return .failure(.refused("That app's name isn't valid.")) }
        guard app.canDownload else {
            return .failure(.refused("MacSync doesn't know where \(app.name) is published. Get it from the developer's website."))
        }
        guard let download = resolve(app) else {
            return .failure(.refused("MacSync couldn't find the download for \(app.name). Check your internet connection and try again."))
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let partial = downloadsDirectory.appendingPathComponent(".\(app.name)-\(UUID().uuidString.prefix(8)).download")
        let result = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--proto-redir", "=https", "--max-time", "3600",
                                                  "-o", partial.path, download.url], input: nil, environment: [:])
        guard result.status == 0, fm.fileExists(atPath: partial.path) else {
            try? fm.removeItem(at: partial)
            return .failure(.refused("\(app.name) didn't download. Check your internet connection and try again."))
        }
        if let expected = download.sha256?.lowercased(), Self.sha256(of: partial) != expected {
            try? fm.removeItem(at: partial)
            return .failure(.refused("The download of \(app.name) didn't match its published checksum, so it was deleted."))
        }
        let target = uniqueTarget(name: app.name, url: download.url, file: partial)
        do { try fm.moveItem(at: partial, to: target) } catch {
            try? fm.removeItem(at: partial)
            return .failure(.refused("\(app.name) couldn't be saved to Downloads."))
        }
        let stamp = String(Int(now().timeIntervalSince1970), radix: 16)
        _ = runner.run("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0081;\(stamp);MacSync;", target.path], input: nil, environment: [:])
        _ = runner.run("/usr/bin/open", [target.path], input: nil, environment: [:])
        return .success(target.path)
    }

    private func uniqueTarget(name: String, url: String, file: URL) -> URL {
        var ext = (URL(string: url)?.pathExtension ?? "").lowercased()
        if !["dmg", "zip", "pkg", "tbz", "xip"].contains(ext) { ext = Self.sniff(file) }
        var target = downloadsDirectory.appendingPathComponent("\(name).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = downloadsDirectory.appendingPathComponent("\(name) \(n).\(ext)")
            n += 1
        }
        return target
    }

    static func sniff(_ file: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "dmg" }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4)) ?? Data()
        if head.starts(with: [0x50, 0x4B]) { return "zip" }
        if head.starts(with: Array("xar!".utf8)) { return "pkg" }
        return "dmg"
    }

    static func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The download in a Sparkle feed's newest item.
    static func latestEnclosure(in feed: Data) -> String? {
        final class Reader: NSObject, XMLParserDelegate {
            var urls: [String] = []
            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                        attributes: [String: String] = [:]) {
                if name == "enclosure", let url = attributes["url"] { urls.append(url) }
            }
        }
        let parser = XMLParser(data: feed)
        let reader = Reader()
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        parser.parse()
        return reader.urls.first
    }
}
