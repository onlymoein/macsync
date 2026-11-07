import Foundation
@testable import MacSyncCore

struct TestLocator: AppLocating {
    var apps: Set<String> = []
    var paths: Set<String> = []
    func path(forBundleID bundleID: String) -> String? { apps.contains(bundleID) ? "/Applications/\(bundleID).app" : nil }
    func exists(path: String) -> Bool { paths.contains(path) }
}

/// Records commands and pretends brew and friends succeed, unless told otherwise.
final class FakeRunner: CommandRunning {
    var calls: [[String]] = []
    var failing: Set<String> = []
    var casks: [String] = []
    var formulae: [String] = []

    func run(_ executable: String, _ arguments: [String], input: Data?, environment: [String: String]) -> CommandResult {
        calls.append([executable] + arguments)
        if arguments.first == "list" { return CommandResult(status: 0, stdout: Data(casks.joined(separator: "\n").utf8)) }
        if arguments.first == "leaves" { return CommandResult(status: 0, stdout: Data(formulae.joined(separator: "\n").utf8)) }
        if let name = arguments.last, failing.contains(name) {
            return CommandResult(status: 1, stderr: "Error: \(name) needs a password")
        }
        if arguments.first == "install", let name = arguments.last {
            if arguments.contains("--cask") { casks.append(name) } else { formulae.append(name) }
        }
        return CommandResult(status: 0)
    }
}

/// Behaves like the real Dock: on restart it can write back the list it had in memory.
final class StubbornDock: DockStoring {
    let inner: FileDockStore
    var overwritesLeft: Int
    private(set) var restarts = 0
    init(inner: FileDockStore, overwrites: Int) {
        self.inner = inner
        overwritesLeft = overwrites
    }

    func exportPlist() throws -> Data { try inner.exportPlist() }
    func importPlist(_ data: Data) throws {
        if overwritesLeft > 0 { memory = try inner.exportPlist() }
        try inner.importPlist(data)
    }
    func removeKeys(_ keys: [String]) throws { try inner.removeKeys(keys) }
    func restartDock() {
        restarts += 1
        if overwritesLeft > 0, let memory {
            overwritesLeft -= 1
            try? inner.importPlist(memory)
        }
    }
    private var memory: Data?
}

/// A temp folder holding one or more simulated Macs that share a sync folder.
final class TestWorld {
    let root: URL
    var sync: URL { root.appendingPathComponent("iCloud/MacSync") }
    var clock = Date(timeIntervalSince1970: 1_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("macsync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("iCloud"), withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    final class Mac {
        let engine: Engine
        let dockStore: FileDockStore
        let runner: FakeRunner
        let id: String
        init(engine: Engine, dockStore: FileDockStore, runner: FakeRunner, id: String) {
            self.engine = engine
            self.dockStore = dockStore
            self.runner = runner
            self.id = id
        }
    }

    func engine(for mac: Mac, dock: DockStoring, locate: Set<String>) -> Engine {
        let folder = root.appendingPathComponent(mac.id)
        let env = MacSyncEnvironment(
            syncDirectory: sync, dataDirectory: folder.appendingPathComponent("data"), machineID: mac.id, machineName: mac.id.capitalized,
            dockFile: nil, brewPath: "/fake/brew", applicationsDirectory: folder.appendingPathComponent("Applications"),
            homeDirectory: "/Users/test")
        return Engine(env: env, dock: dock, locator: TestLocator(apps: locate), runner: mac.runner, now: { [unowned self] in self.clock })
    }

    func mac(_ id: String, dock: [String], locate: Set<String>? = nil, brew: String? = "/fake/brew") throws -> Mac {
        let folder = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dockURL = folder.appendingPathComponent("dock.plist")
        let store = FileDockStore(url: dockURL)
        try store.importPlist(try Self.plist(apps: dock))
        let env = MacSyncEnvironment(
            syncDirectory: sync, dataDirectory: folder.appendingPathComponent("data"), machineID: id, machineName: id.capitalized,
            dockFile: dockURL, brewPath: brew, applicationsDirectory: folder.appendingPathComponent("Applications"),
            homeDirectory: "/Users/test")
        let runner = FakeRunner()
        let engine = Engine(env: env, dock: store, locator: TestLocator(apps: locate ?? Set(dock)), runner: runner,
                            now: { [unowned self] in self.clock })
        return Mac(engine: engine, dockStore: store, runner: runner, id: id)
    }

    func tick(_ seconds: TimeInterval = 60) { clock = clock.addingTimeInterval(seconds) }

    static func plist(apps: [String], size: Double = 48, orientation: String? = nil) throws -> Data {
        var raw: [String: Any] = [
            "tilesize": size,
            "recent-apps": [tile("recent.app")],
            "persistent-apps": apps.map(tile),
            "persistent-others": [[String: Any]](),
        ]
        if let orientation { raw["orientation"] = orientation }
        return try PropertyListSerialization.data(fromPropertyList: raw, format: .xml, options: 0)
    }

    static func tile(_ bundleID: String) -> [String: Any] {
        ["GUID": abs(bundleID.hashValue) % 100000, "tile-type": "file-tile", "tile-data": [
            "file-label": bundleID, "bundle-identifier": bundleID, "file-type": 41, "book": Data("local-bookmark-\(bundleID)".utf8),
            "file-data": ["_CFURLString": "file:///Applications/\(bundleID).app/", "_CFURLStringType": 15],
        ] as [String: Any]]
    }

    static func app(_ id: String) -> DockItem { DockItem(kind: .app, label: id, bundleID: id, path: "/Applications/\(id).app") }

    static func snapshot(id: String, apps: [String], changedAt: Date) -> MachineSnapshot {
        MachineSnapshot(machineID: id, machineName: id, osVersion: "27", appVersion: "t", firstSeenAt: Date(timeIntervalSince1970: 0),
                        savedAt: Date(timeIntervalSince1970: 0),
                        dock: DockSection(changedAt: changedAt, apps: apps.map(app), others: []), inventory: Inventory())
    }
}
