import AppKit
import Foundation

/// An app or tool with a newer version waiting.
public struct OutdatedItem: Codable, Equatable, Identifiable {
    public var token: String
    public var name: String
    public var from: String
    public var to: String
    public var bundleID: String?
    public var id: String { token }
}

public struct UpgradeReport: Codable, Equatable {
    public var ranAt: Date
    public var upgraded: [OutdatedItem] = []
    /// Open right now, so they wait: updating would quit them.
    public var waiting: [OutdatedItem] = []
    public var failures: [String] = []
    public var summary: String {
        if upgraded.isEmpty && waiting.isEmpty && failures.isEmpty { return "Everything is up to date" }
        var parts: [String] = []
        if !upgraded.isEmpty { parts.append("Updated \(upgraded.count)") }
        if !waiting.isEmpty { parts.append("\(waiting.count) waiting until you quit them") }
        if !failures.isEmpty { parts.append("\(failures.count) didn't update") }
        return parts.joined(separator: " · ")
    }
}

/// Keeps Homebrew apps and tools, npm global packages and uv tools on their newest versions,
/// including apps that update themselves, like Raycast. An app that is open waits, so nothing
/// you are using quits under you.
public struct Upgrader {
    let env: MacSyncEnvironment
    let runner: CommandRunning
    /// Bundle IDs of apps that are open. Tests pass their own.
    var isRunning: (String) -> Bool = { id in !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }

    public init(env: MacSyncEnvironment, runner: CommandRunning) { self.env = env; self.runner = runner }

    public static let interval: TimeInterval = 6 * 3600
    var stateURL: URL { env.dataDirectory.appendingPathComponent("upgrades.json") }

    public func lastReport() -> UpgradeReport? {
        (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder.iso.decode(UpgradeReport.self, from: $0) }
    }

    public func isDue(now: Date = Date()) -> Bool {
        guard let last = lastReport()?.ranAt else { return true }
        return now.timeIntervalSince(last) > Self.interval
    }

    /// What has a newer version, from Homebrew's own list.
    public func outdated() -> [OutdatedItem] {
        guard let brew = env.brewPath else { return [] }
        let benv = InventoryReader.brewEnvironment(brew)
        _ = runner.run(brew, ["update", "--quiet"], input: nil, environment: benv)
        let result = runner.run(brew, ["outdated", "--greedy", "--json=v2"], input: nil, environment: benv)
        guard let data = result.output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var items: [OutdatedItem] = []
        for formula in root["formulae"] as? [[String: Any]] ?? [] {
            guard let name = formula["name"] as? String, AppRef(source: .formula, name: name).isSafe else { continue }
            items.append(OutdatedItem(token: "formula:" + name, name: name,
                                      from: (formula["installed_versions"] as? [String])?.last ?? "?",
                                      to: formula["current_version"] as? String ?? "?"))
        }
        let casks = (root["casks"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            .filter { $0 != "macsync" && AppRef(source: .cask, name: $0).isSafe }
        let apps = casks.isEmpty ? [:] : appNames(casks, brew: brew)
        for cask in root["casks"] as? [[String: Any]] ?? [] {
            guard let name = cask["name"] as? String, casks.contains(name) else { continue }
            let app = apps[name]
            items.append(OutdatedItem(token: "cask:" + name, name: app?.name ?? name,
                                      from: (cask["installed_versions"] as? [String])?.last ?? "?",
                                      to: cask["current_version"] as? String ?? "?", bundleID: app?.bundleID))
        }
        return items
    }

    private func appNames(_ casks: [String], brew: String) -> [String: (name: String, bundleID: String?)] {
        let info = runner.run(brew, ["info", "--json=v2", "--cask"] + casks, input: nil, environment: InventoryReader.brewEnvironment(brew))
        guard let data = info.output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: (String, String?)] = [:]
        for cask in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = cask["token"] as? String else { continue }
            let file = (cask["artifacts"] as? [[String: Any]] ?? []).compactMap { ($0["app"] as? [Any])?.first as? String }.first
            let bundle = file.flatMap { InventoryReader.bundleID(at: env.applicationsDirectory.appendingPathComponent($0).path) }
            out[token] = ((cask["name"] as? [String])?.first ?? token, bundle)
        }
        return out
    }

    /// Updates everything that isn't open, then npm and uv tools. Saves the report.
    @discardableResult
    public func upgradeAll(now: Date = Date(), progress: (String) -> Void = { _ in }) -> UpgradeReport {
        var report = UpgradeReport(ranAt: now)
        if let brew = env.brewPath {
            progress("Checking for updates…")
            let items = outdated()
            report.waiting = items.filter { item in item.bundleID.map(isRunning) ?? false }
            let ready = items.filter { item in !report.waiting.contains(item) }
            for item in ready {
                progress("Updating \(item.name)…")
                if let problem = upgrade(item, brew: brew) { report.failures.append("\(item.name): \(problem)") }
                else { report.upgraded.append(item) }
            }
        }
        if let npm = Packages.npm.first(where: FileManager.default.isExecutableFile) {
            progress("Updating npm packages…")
            let result = runner.run(npm, ["update", "-g"], input: nil, environment: Packages.toolEnv)
            if result.status != 0 { report.failures.append("npm packages: \(Self.lastLine(result.stderr))") }
        }
        if let uv = Packages.uv.first(where: FileManager.default.isExecutableFile) {
            progress("Updating uv tools…")
            let result = runner.run(uv, ["tool", "upgrade", "--all"], input: nil, environment: Packages.toolEnv)
            if result.status != 0 { report.failures.append("uv tools: \(Self.lastLine(result.stderr))") }
        }
        try? FileManager.default.createDirectory(at: env.dataDirectory, withIntermediateDirectories: true)
        try? JSONEncoder.iso.encode(report).write(to: stateURL, options: .atomic)
        return report
    }

    /// Quits an open app, updates it and opens it again.
    public func upgradeNow(_ item: OutdatedItem) -> Result<Void, EngineError> {
        guard let brew = env.brewPath else { return .failure(.refused("Homebrew isn't on this Mac.")) }
        if let id = item.bundleID {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) { app.terminate() }
            let deadline = Date().addingTimeInterval(10)
            while isRunning(id) && Date() < deadline { usleep(200_000) }
        }
        let problem = upgrade(item, brew: brew)
        if let id = item.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        if var report = lastReport() {
            report.waiting.removeAll { $0.token == item.token }
            if problem == nil { report.upgraded.append(item) }
            try? JSONEncoder.iso.encode(report).write(to: stateURL, options: .atomic)
        }
        return problem.map { .failure(.refused($0)) } ?? .success(())
    }

    /// Nil when it updated, else why not.
    private func upgrade(_ item: OutdatedItem, brew: String) -> String? {
        let isCask = item.token.hasPrefix("cask:")
        let name = String(item.token.dropFirst(isCask ? 5 : 8))
        let args = isCask ? ["upgrade", "--cask", "--greedy", name] : ["upgrade", "--formula", name]
        let result = runner.run(brew, args, input: nil, environment: InventoryReader.brewEnvironment(brew))
        guard result.status != 0 else { return nil }
        if result.stderr.contains("Operation not permitted") {
            return "allow MacSync in System Settings → Privacy & Security → App Management, then try again"
        }
        if result.stderr.contains("is not there") {
            // Deleted by hand while Homebrew still listed it: install it fresh.
            let again = runner.run(brew, ["install", "--cask", "--force", name], input: nil, environment: InventoryReader.brewEnvironment(brew))
            if again.status == 0 { return nil }
        }
        return Engine.brewProblem(result.stderr, name: name, status: result.status)
    }

    static func lastLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).last.map(String.init) ?? "it didn't work"
    }
}
