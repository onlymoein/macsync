import AppKit
import Foundation

/// Keeps Homebrew's records of Craft apps true without downloading anything twice.
///
/// ArtCraft Launcher updates the Craft apps by itself, hours before Homebrew's casks catch up, so
/// Homebrew keeps listing the old version and Raycast or `brew outdated` show updates that are
/// already installed. The launcher downloads the very disk image Homebrew's cask names, then
/// deletes it. MacSync keeps a second link to that file (no copy, no extra space), and once the
/// cask names that version with a matching checksum, hands it to Homebrew's download cache and
/// runs an ordinary `brew upgrade`: Homebrew finds the file, checks it, downloads nothing, and its
/// record matches the app again. ArtCraft and the person's Homebrew settings are never changed.
public struct CraftRecords {
    let env: MacSyncEnvironment
    let runner: CommandRunning
    let launcherDownloads: URL
    let keepFolder: URL
    let isRunning: (String) -> Bool

    public init(env: MacSyncEnvironment, runner: CommandRunning, launcherDownloads: URL? = nil,
                isRunning: @escaping (String) -> Bool = { id in !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }) {
        self.env = env
        self.runner = runner
        self.launcherDownloads = launcherDownloads
            ?? URL(fileURLWithPath: env.homeDirectory).appendingPathComponent("Library/Caches/ArtCraft Launcher/downloads")
        self.keepFolder = env.dataDirectory.appendingPathComponent("craft-downloads")
        self.isRunning = isRunning
    }

    public var watchedFolder: URL { launcherDownloads }

    /// Adds a second link to each file in the launcher's downloads folder, so it outlives the
    /// launcher deleting it. A link to the same file: nothing is copied. Returns the new ones.
    @discardableResult
    public func catchDownloads() -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: launcherDownloads.path) else { return [] }
        try? fm.createDirectory(at: keepFolder, withIntermediateDirectories: true)
        var caught: [String] = []
        for name in names where !name.hasPrefix(".") {
            let file = launcherDownloads.appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: file.path), attrs[.type] as? FileAttributeType == .typeRegular,
                  let inode = attrs[.systemFileNumber] as? UInt64 else { continue }
            // Named by the file's inode: the same download, even while the launcher renames it.
            let kept = keepFolder.appendingPathComponent("\(inode)")
            guard !fm.fileExists(atPath: kept.path) else { continue }
            if (try? fm.linkItem(at: file, to: kept)) != nil { caught.append(name) }
        }
        return caught
    }

    /// Homebrew-installed Craft apps whose record is behind the app on disk, and whose disk image
    /// MacSync kept: each is put in Homebrew's cache and upgraded there. Returns the casks fixed.
    @discardableResult
    public func reconcile(refreshHomebrew: Bool = false) -> [String] {
        guard env.dockFile == nil, let brew = env.brewPath else { return [] }
        prune()
        let benv = InventoryReader.brewEnvironment(brew)
        if refreshHomebrew { _ = runner.run(brew, ["update", "--quiet"], input: nil, environment: benv) }
        let outdated = runner.run(brew, ["outdated", "--cask", "--greedy", "--json=v2"], input: nil, environment: benv)
        guard let root = try? JSONSerialization.jsonObject(with: outdated.stdout) as? [String: Any] else { return [] }
        let behind = (root["casks"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            .filter { Self.isCraft($0) && DirectApp.isSafeCask($0) }
        guard !behind.isEmpty, !keptFiles().isEmpty else { return [] }
        let info = runner.run(brew, ["info", "--cask", "--json=v2"] + behind, input: nil, environment: benv)
        guard let infoRoot = try? JSONSerialization.jsonObject(with: info.stdout) as? [String: Any] else { return [] }
        var sums: [String: URL] = [:]
        for file in keptFiles() { if let sum = AppDownloader.sha256(of: file) { sums[sum] = file } }
        var fixed: [String] = []
        for cask in infoRoot["casks"] as? [[String: Any]] ?? [] {
            guard let token = cask["token"] as? String, let version = cask["version"] as? String,
                  let sha = cask["sha256"] as? String, let kept = sums[sha.lowercased()],
                  let app = Self.appPath(cask, applications: env.applicationsDirectory) else { continue }
            // Only a record that's behind an app already at this version: a real update stays the launcher's.
            let info = NSDictionary(contentsOf: URL(fileURLWithPath: app).appendingPathComponent("Contents/Info.plist"))
            let onDisk = info?["CFBundleShortVersionString"] as? String
            let wanted = version.split(separator: ",").first.map(String.init) ?? version
            guard onDisk == wanted else { continue }
            // An open app waits for the next round rather than being swapped while in use.
            if let id = info?["CFBundleIdentifier"] as? String, isRunning(id) { continue }
            let cachePath = runner.run(brew, ["--cache", "--cask", token], input: nil, environment: benv).output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard cachePath.hasPrefix("/") else { continue }
            let fm = FileManager.default
            if !fm.fileExists(atPath: cachePath) {
                try? fm.createDirectory(at: URL(fileURLWithPath: cachePath).deletingLastPathComponent(), withIntermediateDirectories: true)
                guard (try? fm.linkItem(at: kept, to: URL(fileURLWithPath: cachePath))) != nil
                        || (try? fm.copyItem(at: kept, to: URL(fileURLWithPath: cachePath))) != nil else { continue }
            }
            let run = runner.stream(brew, ["upgrade", "--cask", "--greedy", token], input: nil, environment: benv, idleTimeout: 300) { _ in }
            let now = runner.run(brew, ["list", "--cask", "--versions", token], input: nil, environment: benv).output
            if run.status == 0, now.contains(wanted) {
                fixed.append(token)
                try? fm.removeItem(at: kept)
            }
            log("\(token) \(wanted): " + (fixed.last == token ? "Homebrew's record matches the app, no download" : "brew upgrade didn't take (\(run.status))"))
        }
        return fixed
    }

    static func isCraft(_ cask: String) -> Bool {
        Upgrader.leftToTheirLauncher.contains(cask) || cask.hasSuffix("craft")
    }

    /// Where the cask puts its app: its own target, else Applications.
    static func appPath(_ cask: [String: Any], applications: URL) -> String? {
        for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
            guard let app = artifact["app"] as? [Any], let name = app.first as? String else { continue }
            if let target = artifact["target"] as? String { return target }
            if let options = app.dropFirst().first as? [String: Any], let target = options["target"] as? String { return target }
            return applications.appendingPathComponent(name).path
        }
        return nil
    }

    func keptFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: keepFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
    }

    /// Kept files go after two weeks: by then Homebrew has caught up, or never will.
    func prune(now: Date = Date()) {
        for file in keptFiles() {
            let made = (try? FileManager.default.attributesOfItem(atPath: file.path)[.creationDate]) as? Date ?? now
            if now.timeIntervalSince(made) > 14 * 86_400 { try? FileManager.default.removeItem(at: file) }
        }
    }

    func log(_ line: String) {
        let url = env.dataDirectory.appendingPathComponent("craft-records.log")
        let text = ISO8601DateFormatter().string(from: Date()) + " " + line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close() }
        else { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }
}
