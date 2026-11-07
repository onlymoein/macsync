import Foundation

public struct MachineSummary: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var osVersion: String
    public var savedAt: Date
    public var isThisMac: Bool
    public var isLayoutSource: Bool
    public var dockMatchesSource: Bool
    public var dockItemCount: Int
    public var appCount: Int
}

public struct RestorePointInfo: Codable, Equatable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var sourceMachine: String
    public var summary: String
    public var installed: [String]
    public var undoneAt: Date?
}

public struct SyncOverview: Codable, Equatable {
    public var iCloudAvailable: Bool
    public var brewAvailable: Bool
    public var syncedAt: Date
    public var machines: [MachineSummary]
    public var dockPlan: DockPlan?
    public var dockMissing: [DockItem]
    public var missingApps: [MissingApp]
    public var selectedApps: [String]
    public var issues: [String]
    public var lastRestorePoint: RestorePointInfo?

    public var hasPendingChanges: Bool { dockPlan != nil || !missingApps.isEmpty }
}

public struct InstallResult: Codable, Equatable, Identifiable {
    public enum Outcome: String, Codable { case installed, openedInAppStore, failed }
    public var app: AppRef
    public var outcome: Outcome
    public var message: String?
    public var id: String { app.token }
}

public struct ApplyRequest {
    public var applyDock: Bool
    public var apps: [AppRef]
    public init(applyDock: Bool, apps: [AppRef]) {
        self.applyDock = applyDock
        self.apps = apps
    }
}

public struct ApplyReport: Codable, Equatable {
    public var restorePoint: RestorePointInfo?
    public var dockChanged: Bool
    public var skippedDockItems: [DockItem]
    public var results: [InstallResult]
    public var hasFailures: Bool { results.contains { $0.outcome == .failed } }
}

public enum EngineError: Error, LocalizedError {
    case busy
    case nothingToUndo
    case refused(String)
    public var errorDescription: String? {
        switch self {
        case .busy: return "MacSync is already applying changes. Try again in a moment."
        case .nothingToUndo: return "There's nothing to undo."
        case .refused(let why): return why
        }
    }
}

/// The one implementation of sync, preview, apply and undo. The menu bar app, the CLI
/// and (through the CLI) Raycast all go through here.
public final class Engine {
    struct LocalState: Codable {
        var firstSeenAt: Date
        var dockHash: String?
        var dockChangedAt: Date?
        var dockBasedOn: String?
        var inventory: Inventory?
        var inventoryAt: Date?
        var selectedApps: [String] = []
        var publishedHash: String?
        var publishedAt: Date?
    }

    public static let maxRestorePoints = 20
    static let republishInterval: TimeInterval = 3600
    static let maxDockWriteAttempts = 4

    let env: MacSyncEnvironment
    let dock: DockStoring
    let locator: AppLocating
    let runner: CommandRunning
    let store: SyncStore
    let now: () -> Date

    public init(env: MacSyncEnvironment, dock: DockStoring, locator: AppLocating, runner: CommandRunning,
                now: @escaping () -> Date = Date.init) {
        self.env = env
        self.dock = dock
        self.locator = locator
        self.runner = runner
        self.store = SyncStore(env: env)
        self.now = now
    }

    public static func live(env: MacSyncEnvironment = .current()) -> Engine {
        let runner = SystemCommandRunner()
        let dock: DockStoring = env.dockFile.map { FileDockStore(url: $0) } ?? SystemDockStore(runner: runner)
        return Engine(env: env, dock: dock, locator: SystemAppLocator(), runner: runner)
    }

    // MARK: Sync

    /// Saves this Mac's setup and works out what the other Macs would change. Never changes this Mac.
    @discardableResult
    public func sync(refreshInventory: Bool = true) throws -> SyncOverview {
        var state = loadState()
        let local = try captureDock(&state)
        if refreshInventory || state.inventory == nil {
            state.inventory = InventoryReader(runner: runner, env: env).read()
            state.inventoryAt = now()
        }
        let snapshot = makeSnapshot(state: state, dock: local)
        var issues: [String] = []
        do {
            try publishIfNeeded(snapshot, state: &state)
        } catch {
            issues.append(error.localizedDescription)
        }
        try saveState(state)
        return overview(snapshot: snapshot, state: state, issues: issues)
    }

    public func setSelectedApps(_ tokens: Set<String>) throws {
        var state = loadState()
        state.selectedApps = tokens.sorted()
        try saveState(state)
    }

    private func captureDock(_ state: inout LocalState) throws -> DockSection {
        let raw = try dock.readRaw()
        var section = DockCapture.section(from: raw, changedAt: state.dockChangedAt ?? Date(timeIntervalSince1970: 0),
                                          basedOn: state.dockBasedOn, home: env.homeDirectory)
        let hash = section.contentHash
        if state.dockHash == nil {
            // First run: an existing setup is a starting point, not an edit, so it can't beat other Macs.
            state.dockChangedAt = section.changedAt
        } else if state.dockHash != hash {
            section.changedAt = now()
            section.basedOn = nil
            state.dockChangedAt = section.changedAt
            state.dockBasedOn = nil
        }
        state.dockHash = hash
        return section
    }

    private func makeSnapshot(state: LocalState, dock: DockSection) -> MachineSnapshot {
        MachineSnapshot(machineID: env.machineID, machineName: env.machineName,
                        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                        appVersion: MacSyncEnvironment.appVersion, firstSeenAt: state.firstSeenAt,
                        savedAt: now(), dock: dock, inventory: state.inventory)
    }

    private func publishIfNeeded(_ snapshot: MachineSnapshot, state: inout LocalState) throws {
        var comparable = snapshot
        comparable.savedAt = Date(timeIntervalSince1970: 0)
        let hash = Hashing.sha256(try SnapshotCodec.encode(comparable))
        let stale = state.publishedAt.map { now().timeIntervalSince($0) > Self.republishInterval } ?? true
        guard hash != state.publishedHash || stale else { return }
        try store.save(snapshot)
        state.publishedHash = hash
        state.publishedAt = now()
    }

    private func overview(snapshot: MachineSnapshot, state: LocalState, issues: [String]) -> SyncOverview {
        let loaded = store.load()
        let others = loaded.machines.filter { $0.machineID != env.machineID }
        let everyone = others + [snapshot]
        let winner = Planner.winner(among: everyone)
        var plan: DockPlan?
        if let winner, let target = winner.dock, winner.machineID != env.machineID, let local = snapshot.dock {
            plan = Planner.dockPlan(current: local, target: target, source: winner.machineName, locator: locator)
        }
        func keys(_ section: DockSection?) -> [String] { ((section?.apps ?? []) + (section?.others ?? [])).map(\.key) }
        let summaries = everyone.map { machine -> MachineSummary in
            let isSource = machine.machineID == winner?.machineID
            // In sync means it copied this exact layout (even if it lacks some apps) or looks identical.
            let copied = machine.dock?.basedOn == winner?.machineID && machine.dock?.changedAt == winner?.dock?.changedAt
            let identical = keys(machine.dock) == keys(winner?.dock) && machine.dock?.tileSize == winner?.dock?.tileSize
                && machine.dock?.orientation == winner?.dock?.orientation
            let matches = isSource || copied || identical
            let inventory = machine.inventory
            return MachineSummary(
                id: machine.machineID, name: machine.machineName, osVersion: machine.osVersion, savedAt: machine.savedAt,
                isThisMac: machine.machineID == env.machineID, isLayoutSource: isSource, dockMatchesSource: matches,
                dockItemCount: keys(machine.dock).count,
                appCount: (inventory?.casks.count ?? 0) + (inventory?.formulae.count ?? 0) + (inventory?.appStore.count ?? 0))
        }.sorted { ($0.isThisMac ? 0 : 1, $0.name) < ($1.isThisMac ? 0 : 1, $1.name) }
        return SyncOverview(
            iCloudAvailable: env.iCloudAvailable,
            brewAvailable: state.inventory?.brewAvailable ?? false,
            syncedAt: now(),
            machines: summaries,
            dockPlan: plan?.hasChanges == true ? plan : nil,
            dockMissing: plan?.missing ?? [],
            missingApps: Planner.missingApps(local: state.inventory ?? Inventory(), others: others),
            selectedApps: state.selectedApps,
            issues: issues + loaded.issues,
            lastRestorePoint: restorePoints().first { $0.undoneAt == nil })
    }

    // MARK: Apply

    /// Backs up first, then installs, then changes the Dock. Each install reports its own result.
    public func apply(_ request: ApplyRequest, progress: (String) -> Void = { _ in }) throws -> ApplyReport {
        let lock = try acquireLock()
        defer { close(lock) }
        let before = try sync(refreshInventory: false)
        let allowed = Set(before.missingApps.map(\.app))
        let apps = request.apps.filter { allowed.contains($0) && $0.isSafe }
        let wantsDock = request.applyDock && before.dockPlan != nil
        guard wantsDock || !apps.isEmpty else {
            return ApplyReport(restorePoint: nil, dockChanged: false, skippedDockItems: before.dockMissing, results: [])
        }

        let source = before.dockPlan?.sourceMachine ?? before.machines.first { !$0.isThisMac }?.name ?? "another Mac"
        var point = try createRestorePoint(source: source, summary: Self.summary(dock: wantsDock ? before.dockPlan : nil, apps: apps))

        var results: [InstallResult] = []
        for app in apps {
            progress("Installing \(app.name)…")
            results.append(install(app))
        }
        point.installed = results.filter { $0.outcome == .installed }.map(\.app.token)
        try writeRestoreInfo(point)

        var dockChanged = false
        var skipped: [DockItem] = before.dockMissing
        var state = loadState()
        if !apps.isEmpty { state.inventory = InventoryReader(runner: runner, env: env).read(); state.inventoryAt = now() }
        if wantsDock {
            progress("Updating the Dock…")
            // Plan again: anything just installed can now take its place in the Dock.
            let snapshotDock = try captureDock(&state)
            let everyone = store.load().machines.filter { $0.machineID != env.machineID }
                + [makeSnapshot(state: state, dock: snapshotDock)]
            if let winner = Planner.winner(among: everyone), winner.machineID != env.machineID, let target = winner.dock {
                let plan = Planner.dockPlan(current: snapshotDock, target: target, source: winner.machineName, locator: locator)
                skipped = plan.missing
                if plan.hasChanges {
                    try write(plan: plan, target: target, backup: point)
                    dockChanged = true
                    state.dockChangedAt = target.changedAt
                    state.dockBasedOn = winner.machineID
                    state.dockHash = DockCapture.section(from: try dock.readRaw(), changedAt: target.changedAt, home: env.homeDirectory).contentHash
                }
            }
        }
        try saveState(state)
        pruneRestorePoints()
        _ = try? sync(refreshInventory: false)
        return ApplyReport(restorePoint: point, dockChanged: dockChanged, skippedDockItems: skipped, results: results)
    }

    private func install(_ app: AppRef) -> InstallResult {
        switch app.source {
        case .appStore:
            // `mas install` needs root. The App Store page needs nothing and can't fail silently.
            let result = runner.run("/usr/bin/open", ["macappstore://apps.apple.com/app/id\(app.appStoreID ?? "")"], input: nil, environment: [:])
            return InstallResult(app: app, outcome: result.status == 0 ? .openedInAppStore : .failed,
                                 message: result.status == 0 ? "Click Get in the App Store to finish." : result.stderr)
        case .cask, .formula:
            guard let brew = env.brewPath else {
                return InstallResult(app: app, outcome: .failed, message: "Homebrew isn't installed. Get it at brew.sh.")
            }
            let args = app.source == .cask ? ["install", "--cask", app.name] : ["install", app.name]
            let result = runner.run(brew, args, input: nil, environment: InventoryReader.brewEnvironment(brew))
            guard result.status != 0 else { return InstallResult(app: app, outcome: .installed, message: nil) }
            let lastLine = result.stderr.split(whereSeparator: \.isNewline).last.map(String.init)
            return InstallResult(app: app, outcome: .failed, message: lastLine ?? "brew exited with \(result.status).")
        }
    }

    private func write(plan: DockPlan, target: DockSection, backup: RestorePointInfo) throws {
        guard !(plan.targetApps.isEmpty && !target.apps.isEmpty) else {
            throw EngineError.refused("None of the apps in that Dock are on this Mac, so the Dock was left alone.")
        }
        let original = try dock.exportPlist()
        try original.write(to: restoreDirectory(backup.id).appendingPathComponent("dock.plist"), options: .atomic)
        let raw = try dock.readRaw()
        let merged = try merge(raw: raw, plan: plan, target: target)
        let data = try PropertyListSerialization.data(fromPropertyList: merged, format: .xml, options: 0)
        let expected = DockFingerprint(apps: plan.targetApps, others: plan.targetOthers,
                                       tileSize: target.tileSize ?? (raw["tilesize"] as? NSNumber)?.doubleValue,
                                       orientation: target.orientation)
        do {
            try commit(data, expecting: expected)
        } catch {
            try? commit(original, expecting: fingerprint(of: original))
            throw EngineError.refused("The Dock didn't accept the new layout, so it was restored.")
        }
    }

    /// What must be true of the Dock once it has restarted.
    struct DockFingerprint: Equatable {
        var keys: [String]
        var tileSize: Double?
        var orientation: String
        init(apps: [DockItem], others: [DockItem], tileSize: Double?, orientation: String) {
            keys = (apps + others).map(\.key)
            self.tileSize = tileSize
            self.orientation = orientation
        }
    }

    private func fingerprint(of raw: [String: Any]) -> DockFingerprint {
        let section = DockCapture.section(from: raw, changedAt: now(), home: env.homeDirectory)
        return DockFingerprint(apps: section.apps, others: section.others, tileSize: section.tileSize, orientation: section.orientation)
    }

    private func fingerprint(of plist: Data) throws -> DockFingerprint {
        guard let raw = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any] else {
            throw DockStoreError.failed("That Dock backup is not in the expected format.")
        }
        return fingerprint(of: raw)
    }

    /// A running Dock saves its own list when it quits or restarts, which can overwrite a write
    /// that just landed. So success is only judged after the restart, and the write is retried.
    private func commit(_ data: Data, expecting expected: DockFingerprint) throws {
        for _ in 0..<Self.maxDockWriteAttempts {
            try dock.replacePlist(data)
            dock.restartDock()
            if fingerprint(of: try dock.readRaw()) == expected { return }
        }
        throw DockStoreError.failed("The Dock kept its old layout.")
    }

    private func merge(raw: [String: Any], plan: DockPlan, target: DockSection) throws -> [String: Any] {
        var result = raw
        result["persistent-apps"] = try tiles(existing: raw["persistent-apps"], other: raw["persistent-others"], items: plan.targetApps)
        result["persistent-others"] = try tiles(existing: raw["persistent-others"], other: raw["persistent-apps"], items: plan.targetOthers)
        if let size = target.tileSize { result["tilesize"] = size }
        // Unset means bottom. Don't add the key unless the position really differs.
        if raw["orientation"] != nil || target.orientation != "bottom" { result["orientation"] = target.orientation }
        return result
    }

    /// Reuses this Mac's own tile wherever it can, keeping its bookmark and icon data intact.
    private func tiles(existing: Any?, other: Any?, items: [DockItem]) throws -> [[String: Any]] {
        var pool: [String: [[String: Any]]] = [:]
        let existingTiles = existing as? [[String: Any]] ?? []
        for tile in existingTiles + (other as? [[String: Any]] ?? []) {
            if let key = DockCapture.item(from: tile, home: env.homeDirectory)?.key { pool[key, default: []].append(tile) }
        }
        var output: [[String: Any]] = []
        for item in items {
            if var tile = pool[item.key]?.isEmpty == false ? pool[item.key]?.removeFirst() : nil {
                if item.kind == .folder, var data = tile["tile-data"] as? [String: Any] {
                    DockCapture.apply(item.folder, to: &data)
                    tile["tile-data"] = data
                }
                output.append(tile)
            } else if let tile = DockCapture.newTile(for: item, localPath: Planner.resolve(item, locator: locator)) {
                output.append(tile)
            }
        }
        // Tiles of a type MacSync doesn't understand stay where they were rather than vanish.
        output += existingTiles.filter { DockCapture.item(from: $0, home: env.homeDirectory) == nil }
        return output
    }

    static func summary(dock: DockPlan?, apps: [AppRef]) -> String {
        var parts: [String] = []
        if let dock {
            let total = dock.added.count + dock.removed.count + dock.moved.count
            parts.append(total == 0 ? "Dock settings" : "\(total) Dock change\(total == 1 ? "" : "s")")
        }
        if !apps.isEmpty { parts.append("\(apps.count) app\(apps.count == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    // MARK: Undo

    /// Puts the Dock back exactly as it was. Installed apps stay installed, and the result says so.
    public func undoLast() throws -> RestorePointInfo {
        let lock = try acquireLock()
        defer { close(lock) }
        guard var point = restorePoints().first(where: { $0.undoneAt == nil }) else { throw EngineError.nothingToUndo }
        let file = restoreDirectory(point.id).appendingPathComponent("dock.plist")
        let backup = try Data(contentsOf: file)
        try commit(backup, expecting: try fingerprint(of: backup))
        point.undoneAt = now()
        try writeRestoreInfo(point)
        // The restored Dock counts as a new edit here, so it isn't immediately overwritten again.
        try sync(refreshInventory: false)
        return point
    }

    public func restorePoints() -> [RestorePointInfo] {
        let directory = env.dataDirectory.appendingPathComponent("restore-points")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names.compactMap { name in
            let url = directory.appendingPathComponent(name).appendingPathComponent("info.json")
            return (try? Data(contentsOf: url)).flatMap { try? decoder.decode(RestorePointInfo.self, from: $0) }
        }.sorted { $0.id > $1.id }
    }

    private func restoreDirectory(_ id: String) -> URL {
        env.dataDirectory.appendingPathComponent("restore-points").appendingPathComponent(id)
    }

    private func createRestorePoint(source: String, summary: String) throws -> RestorePointInfo {
        let date = now()
        let id = String(format: "%013.0f-%@", date.timeIntervalSince1970 * 1000, String(UUID().uuidString.prefix(8)))
        let point = RestorePointInfo(id: id, createdAt: date, sourceMachine: source, summary: summary, installed: [], undoneAt: nil)
        try FileManager.default.createDirectory(at: restoreDirectory(id), withIntermediateDirectories: true)
        try dock.exportPlist().write(to: restoreDirectory(id).appendingPathComponent("dock.plist"), options: .atomic)
        try writeRestoreInfo(point)
        return point
    }

    private func writeRestoreInfo(_ point: RestorePointInfo) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(point).write(to: restoreDirectory(point.id).appendingPathComponent("info.json"), options: .atomic)
    }

    private func pruneRestorePoints() {
        for point in restorePoints().dropFirst(Self.maxRestorePoints) {
            try? FileManager.default.removeItem(at: restoreDirectory(point.id))
        }
    }

    // MARK: Local state

    private var stateURL: URL { env.dataDirectory.appendingPathComponent("state.json") }

    private func loadState() -> LocalState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: stateURL), let state = try? decoder.decode(LocalState.self, from: data) {
            return state
        }
        return LocalState(firstSeenAt: now())
    }

    private func saveState(_ state: LocalState) throws {
        try FileManager.default.createDirectory(at: env.dataDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    private func acquireLock() throws -> Int32 {
        try FileManager.default.createDirectory(at: env.dataDirectory, withIntermediateDirectories: true)
        let descriptor = open(env.dataDirectory.appendingPathComponent("apply.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            throw EngineError.busy
        }
        return descriptor
    }
}
