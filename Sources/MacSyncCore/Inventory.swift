import Foundation

/// What can be installed. Snapshots are input from another machine, so names are checked
/// before they reach a command line.
public struct AppRef: Hashable, Codable, Identifiable, Comparable {
    public enum Source: String, Codable { case cask, formula, appStore }
    public var source: Source
    public var name: String
    public var appStoreID: String?

    public init(source: Source, name: String, appStoreID: String? = nil) {
        self.source = source
        self.name = name
        self.appStoreID = appStoreID
    }

    /// Stable text form, also the CLI's syntax: cask:ghostty, formula:jq, mas:497799835.
    public var token: String {
        switch source {
        case .cask: return "cask:\(name)"
        case .formula: return "formula:\(name)"
        case .appStore: return "mas:\(appStoreID ?? name)"
        }
    }

    public var id: String { token }
    public static func < (a: AppRef, b: AppRef) -> Bool { a.token < b.token }

    public var isSafe: Bool {
        switch source {
        case .cask, .formula:
            return name.range(of: "^[A-Za-z0-9][A-Za-z0-9@+_./-]*$", options: .regularExpression) != nil
        case .appStore:
            return appStoreID?.range(of: "^[0-9]+$", options: .regularExpression) != nil
        }
    }
}

public struct InventoryReader {
    let runner: CommandRunning
    let env: MacSyncEnvironment

    public init(runner: CommandRunning, env: MacSyncEnvironment) {
        self.runner = runner
        self.env = env
    }

    static func brewEnvironment(_ brew: String) -> [String: String] {
        let prefix = (brew as NSString).deletingLastPathComponent
        return ["PATH": "\(prefix):/usr/bin:/bin:/usr/sbin:/sbin",
                "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1", "NONINTERACTIVE": "1"]
    }

    public func read() -> Inventory {
        var inventory = Inventory(appStore: appStoreApps())
        guard let brew = env.brewPath else { return inventory }
        let brewEnv = Self.brewEnvironment(brew)
        let casks = runner.run(brew, ["list", "--cask", "-1"], input: nil, environment: brewEnv)
        // Only what the person asked for, not what those formulae pulled in.
        let leaves = runner.run(brew, ["leaves", "--installed-on-request"], input: nil, environment: brewEnv)
        guard casks.status == 0, leaves.status == 0 else { return inventory }
        inventory.brewAvailable = true
        inventory.casks = Self.lines(casks.output)
        inventory.formulae = Self.lines(leaves.output)
        return inventory
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.sorted()
    }

    /// Apps from the Mac App Store carry a receipt, and Spotlight knows their store ID.
    /// This needs no extra tools, so it works on a Mac that has never seen a terminal.
    func appStoreApps() -> [AppStoreApp] {
        let fm = FileManager.default
        let apps = (try? fm.contentsOfDirectory(atPath: env.applicationsDirectory.path)) ?? []
        return apps.filter { $0.hasSuffix(".app") }.sorted().compactMap { name in
            let path = env.applicationsDirectory.appendingPathComponent(name).path
            guard fm.fileExists(atPath: path + "/Contents/_MASReceipt/receipt") else { return nil }
            let result = runner.run("/usr/bin/mdls", ["-raw", "-name", "kMDItemAppStoreAdamID", path],
                                    input: nil, environment: [:])
            let id = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.status == 0, id.range(of: "^[0-9]+$", options: .regularExpression) != nil else { return nil }
            return AppStoreApp(id: id, name: String(name.dropLast(4)))
        }
    }
}
