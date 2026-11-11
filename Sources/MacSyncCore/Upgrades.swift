import AppKit
import Foundation

/// An app or tool with a newer version waiting.
public struct OutdatedItem: Codable, Equatable, Identifiable {
    public init(token: String, name: String, from: String, to: String, bundleID: String? = nil) {
        self.token = token; self.name = name; self.from = from; self.to = to; self.bundleID = bundleID
    }
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
    /// Newer versions found and not installed yet.
    public var outdated: [OutdatedItem]?
    public init(ranAt: Date, upgraded: [OutdatedItem] = [], waiting: [OutdatedItem] = [], failures: [String] = [], outdated: [OutdatedItem]? = nil) {
        self.ranAt = ranAt; self.upgraded = upgraded; self.waiting = waiting; self.failures = failures; self.outdated = outdated
    }
    public var summary: String {
        let pending = outdated ?? []
        if upgraded.isEmpty && waiting.isEmpty && failures.isEmpty && pending.isEmpty { return "Everything is up to date" }
        var parts: [String] = []
        if !pending.isEmpty { parts.append("\(pending.count) to update") }
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

    /// Apps on this Mac from neither Homebrew nor the App Store, with their versions.
    var directApps: [DirectApp] = []

    public init(env: MacSyncEnvironment, runner: CommandRunning) { self.env = env; self.runner = runner }

    public static let interval: TimeInterval = 6 * 3600
    static let leftToTheirLauncher: Set<String> = Set(AppSuite.all.flatMap { $0.members.map(\.cask) })
    var stateURL: URL { env.dataDirectory.appendingPathComponent("upgrades.json") }

    public func lastReport() -> UpgradeReport? {
        (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder.iso.decode(UpgradeReport.self, from: $0) }
    }

    public func isDue(now: Date = Date()) -> Bool {
        guard let last = lastReport()?.ranAt else { return true }
        return now.timeIntervalSince(last) > Self.interval
    }

    /// What has a newer version: Homebrew apps and tools, npm packages and uv tools.
    public func outdated() -> [OutdatedItem] {
        brewOutdated() + directOutdated() + appStoreOutdated() + npmOutdated() + uvOutdated()
    }

    /// Apps that update themselves (ChatGPT, Claude, Grok) and weren't installed with Homebrew,
    /// when Homebrew publishes a newer version than the one here. Updating hands them to Homebrew.
    func directOutdated() -> [OutdatedItem] {
        guard env.brewPath != nil, !directApps.isEmpty,
              let catalog = CaskCatalog.load(env: env, runner: runner, now: Date()) else { return [] }
        return directApps.compactMap { app in
            guard let token = app.cask ?? catalog.cask(forApp: app.name + ".app") ?? catalog.cask(forBundleID: app.bundleID),
                  !Self.leftToTheirLauncher.contains(token), token != "macsync", DirectApp.isSafeCask(token),
                  let latest = catalog.entries[token]?.version, let mine = app.version,
                  SelfUpdater.isNewer(latest, than: mine) else { return nil }
            return OutdatedItem(token: "adopt:" + token, name: app.name, from: mine, to: latest, bundleID: app.bundleID)
        }
    }

    /// App Store apps with updates, through mas when it's installed.
    func appStoreOutdated() -> [OutdatedItem] {
        guard let mas = ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"].first(where: FileManager.default.isExecutableFile) else { return [] }
        let result = runner.stream(mas, ["outdated"], input: nil, environment: Packages.toolEnv, idleTimeout: 60) { _ in }
        guard result.status == 0, let regex = try? NSRegularExpression(pattern: "^(\\d+)\\s+(.+?)\\s+\\((\\S+)\\s+->\\s+(\\S+)\\)") else { return [] }
        return InventoryReader.lines(result.output).compactMap { line in
            guard let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let id = Range(m.range(at: 1), in: line), let name = Range(m.range(at: 2), in: line),
                  let from = Range(m.range(at: 3), in: line), let to = Range(m.range(at: 4), in: line) else { return nil }
            let path = env.applicationsDirectory.appendingPathComponent(line[name] + ".app").path
            return OutdatedItem(token: "mas:" + line[id], name: String(line[name]), from: String(line[from]), to: String(line[to]),
                                bundleID: InventoryReader.bundleID(at: path))
        }
    }

    func npmOutdated() -> [OutdatedItem] {
        guard let npm = Packages.npm.first(where: FileManager.default.isExecutableFile) else { return [] }
        let result = runner.run(npm, ["outdated", "-g", "--json"], input: nil, environment: Packages.toolEnv)
        guard let data = result.output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        return root.compactMap { name, info in
            guard Packages.isSafe("npm:" + name), let latest = info["latest"] as? String,
                  (info["current"] as? String) != latest else { return nil }
            return OutdatedItem(token: "npm:" + name, name: name, from: info["current"] as? String ?? "?", to: latest)
        }.sorted { $0.name < $1.name }
    }

    func uvOutdated() -> [OutdatedItem] {
        guard let uv = Packages.uv.first(where: FileManager.default.isExecutableFile) else { return [] }
        let result = runner.run(uv, ["tool", "list", "--outdated"], input: nil, environment: Packages.toolEnv)
        guard result.status == 0, let regex = try? NSRegularExpression(pattern: "^(\\S+) v(\\S+) \\[latest: v?([^\\]]+)\\]") else { return [] }
        return InventoryReader.lines(result.output).compactMap { line in
            guard let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let a = Range(m.range(at: 1), in: line), let b = Range(m.range(at: 2), in: line), let c = Range(m.range(at: 3), in: line),
                  Packages.isSafe("uv:" + line[a]) else { return nil }
            return OutdatedItem(token: "uv:" + line[a], name: String(line[a]), from: String(line[b]), to: String(line[c]))
        }
    }

    func brewOutdated() -> [OutdatedItem] {
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
            // ArtCraft Launcher keeps the Craft apps up to date itself.
            .filter { $0 != "macsync" && !Self.leftToTheirLauncher.contains($0) && !$0.hasSuffix("craft") && AppRef(source: .cask, name: $0).isSafe }
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

    /// Looks for newer versions without installing anything, and saves what it found.
    @discardableResult
    public func check(now: Date = Date()) -> UpgradeReport {
        var report = UpgradeReport(ranAt: now)
        report.outdated = outdated()
        save(report)
        return report
    }

    /// Updates everything that isn't open. Saves the report.
    @discardableResult
    public func upgradeAll(now: Date = Date(), progress: (String) -> Void = { _ in }) -> UpgradeReport {
        progress("Checking for updates…")
        return upgrade(outdated(), now: now, progress: progress)
    }

    /// Updates these. An app that is open waits, so it doesn't quit under you.
    @discardableResult
    public func upgrade(_ items: [OutdatedItem], now: Date = Date(), progress: (String) -> Void = { _ in }) -> UpgradeReport {
        var report = UpgradeReport(ranAt: now)
        let previous = lastReport()
        report.waiting = items.filter { item in item.bundleID.map(isRunning) ?? false }
        for item in items where !report.waiting.contains(item) {
            progress("Updating \(item.name)…")
            if let problem = upgradeOne(item) { report.failures.append("\(item.name): \(problem)") }
            else { report.upgraded.append(item) }
        }
        // Anything found earlier and not part of this run is still waiting to be updated.
        let handled = Set(items.map(\.token))
        report.outdated = (previous?.outdated ?? []).filter { !handled.contains($0.token) }
        save(report)
        return report
    }

    private func save(_ report: UpgradeReport) {
        try? FileManager.default.createDirectory(at: env.dataDirectory, withIntermediateDirectories: true)
        try? JSONEncoder.iso.encode(report).write(to: stateURL, options: .atomic)
    }

    private func upgradeOne(_ item: OutdatedItem) -> String? {
        let name = String(item.token.drop { $0 != ":" }.dropFirst())
        switch Packages.kind(item.token) {
        case "adopt":
            // Homebrew installs its copy over this one and keeps it updated from then on.
            guard let brew = env.brewPath, DirectApp.isSafeCask(name) else { return "Homebrew isn't on this Mac" }
            let result = runner.stream(brew, ["install", "--cask", "--force", name], input: nil,
                                       environment: InventoryReader.brewEnvironment(brew), idleTimeout: 600) { _ in }
            if result.status == 0 { return nil }
            if result.stderr.contains("Operation not permitted") {
                return "allow MacSync in System Settings → Privacy & Security → App Management, then try again"
            }
            return Engine.brewProblem(result.stderr, name: name, status: result.status)
        case "mas":
            guard let mas = ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"].first(where: FileManager.default.isExecutableFile),
                  name.allSatisfy(\.isNumber) else { return "mas isn't on this Mac" }
            let result = runner.stream(mas, ["upgrade", name], input: nil, environment: Packages.toolEnv, idleTimeout: 600) { _ in }
            return result.status == 0 ? nil : Self.lastLine(result.stderr)
        case "npm":
            guard let npm = Packages.npm.first(where: FileManager.default.isExecutableFile) else { return "npm isn't on this Mac" }
            let result = runner.run(npm, ["install", "-g", name + "@latest"], input: nil, environment: Packages.toolEnv)
            return result.status == 0 ? nil : Self.lastLine(result.stderr)
        case "uv":
            guard let uv = Packages.uv.first(where: FileManager.default.isExecutableFile) else { return "uv isn't on this Mac" }
            let result = runner.run(uv, ["tool", "upgrade", name], input: nil, environment: Packages.toolEnv)
            return result.status == 0 ? nil : Self.lastLine(result.stderr)
        default:
            guard let brew = env.brewPath else { return "Homebrew isn't on this Mac" }
            return upgrade(item, brew: brew)
        }
    }

    /// Quits an open app, updates it and opens it again.
    public func upgradeNow(_ item: OutdatedItem) -> Result<Void, EngineError> {
        guard let brew = env.brewPath else { return .failure(.refused("Homebrew isn't on this Mac.")) }
        if let id = item.bundleID {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) { app.terminate() }
            let deadline = Date().addingTimeInterval(10)
            while isRunning(id) && Date() < deadline { usleep(200_000) }
        }
        let problem = upgradeOne(item)
        _ = brew
        if let id = item.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        if var report = lastReport() {
            report.waiting.removeAll { $0.token == item.token }
            report.outdated?.removeAll { $0.token == item.token }
            if problem == nil { report.upgraded.append(item) }
            save(report)
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
