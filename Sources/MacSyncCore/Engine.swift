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
    /// Nil on restore points from before these existed, which are treated as touching the Dock.
    public var touchedDock: Bool?
    public var touchedSettings: Bool?
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
    public var proEnabled: Bool
    public var settingsPlan: SettingsPlan?
    public var settingsSkipped: [String]
    public var appPrefDomains: [String]
    /// Apps from other Macs the person said this Mac doesn't need. Remembered on this Mac only.
    public var skippedApps: [String] = []

    public var hasPendingChanges: Bool { dockPlan != nil || settingsPlan != nil || !wantedApps.isEmpty }
    /// Missing apps, minus the ones this Mac doesn't need.
    public var wantedApps: [MissingApp] { missingApps.filter { !skippedApps.contains($0.app.token) } }
}

public struct InstallResult: Codable, Equatable, Identifiable {
    public enum Outcome: String, Codable { case installed, openedInAppStore, downloaded, failed }
    public var app: AppRef
    public var outcome: Outcome
    public var message: String?
    /// The name people recognize ("Android Studio", "PhotoCraft").
    public var displayName: String? = nil
    /// For a downloaded installer: where it was saved.
    public var path: String? = nil
    public var id: String { app.token }
}

public struct ApplyRequest {
    public var applyDock: Bool
    public var apps: [AppRef]
    public var applySettings: Bool
    /// Dock items (by key) to take out of every Mac's Dock.
    public var removeFromDock: [String]
    public init(applyDock: Bool, apps: [AppRef], applySettings: Bool = true, removeFromDock: [String] = []) {
        self.applyDock = applyDock
        self.apps = apps
        self.applySettings = applySettings
        self.removeFromDock = removeFromDock
    }
}

public struct ApplyReport: Codable, Equatable {
    public var restorePoint: RestorePointInfo?
    public var dockChanged: Bool
    public var skippedDockItems: [DockItem]
    public var results: [InstallResult]
    public var settingsChanged = false
    public var settingsSkipped: [String] = []
    public var settingsError: String?
    public var hasFailures: Bool { results.contains { $0.outcome == .failed } || settingsError != nil }
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
        /// Apps the person unticked. Everything else from the other Macs is installed by default.
        var deselectedApps: [String]?
        var lastMissing: [String]?
        /// Non-spacer Dock keys at the last capture, and this Mac's view of every item's history.
        var dockKeys: [String]?
        var dockEvents: [String: DockEvent]?
        var publishedHash: String?
        var publishedAt: Date?
        var settingsHash: String?
        var settingsChangedAt: Date?
        var settingsBasedOn: String?
        var appPrefDomains: [String]?
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
    let prefs: PreferencesStoring
    let proUnlocked: Bool
    private var missingNames: [String: String] = [:]
    private var missingDownloads: [String: DirectApp] = [:]

    public init(env: MacSyncEnvironment, dock: DockStoring, locator: AppLocating, runner: CommandRunning,
                prefs: PreferencesStoring = InMemoryPreferences(), proUnlocked: Bool = ProLicense.isUnlocked,
                now: @escaping () -> Date = Date.init) {
        self.prefs = prefs
        self.proUnlocked = proUnlocked
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
        // A simulated Mac (its Dock lives in a file) must not touch this Mac's real settings.
        let prefs: PreferencesStoring = env.dockFile == nil ? SystemPreferences(runner: runner) : InMemoryPreferences()
        return Engine(env: env, dock: dock, locator: SystemAppLocator(), runner: runner, prefs: prefs)
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
        let settings = capturePrefs(&state)
        let snapshot = makeSnapshot(state: state, dock: local, settings: settings)
        var issues: [String] = []
        do {
            try publishIfNeeded(snapshot, state: &state)
        } catch {
            issues.append(error.localizedDescription)
        }
        if env.iCloudAvailable { removeOldCopies() }
        let result = overview(snapshot: snapshot, state: state, issues: issues)
        state.lastMissing = result.missingApps.map(\.app.token)
        try saveState(state)
        return result
    }

    /// MacSync 0.3.0 copied apps through iCloud Drive. Apps now download from where they are
    /// published, so any copies it left behind are deleted to free the space.
    private func removeOldCopies() {
        let old = env.syncDirectory.appendingPathComponent("apps", isDirectory: true)
        if FileManager.default.fileExists(atPath: old.path) { try? FileManager.default.removeItem(at: old) }
    }

    /// Marks an app as not needed on this Mac, or brings it back. Kept even after it stops being
    /// offered, so it stays hidden if another Mac installs it again later.
    public func setSkipped(_ token: String, _ skipped: Bool) throws {
        var state = loadState()
        var set = Set(state.deselectedApps ?? [])
        if skipped { set.insert(token) } else { set.remove(token) }
        state.deselectedApps = set.sorted()
        try saveState(state)
    }

    /// Records the choice as what was unticked, so apps that turn up later start ticked.
    public func setSelectedApps(_ tokens: Set<String>) throws {
        var state = loadState()
        let shown = Set(state.lastMissing ?? [])
        let kept = Set(state.deselectedApps ?? []).subtracting(shown)
        state.deselectedApps = kept.union(shown.subtracting(tokens)).sorted()
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
        recordDockEvents(section, &state)
        section.events = state.dockEvents
        return section
    }

    /// Turns what changed in this Mac's Dock since the last look into added and removed events.
    private func recordDockEvents(_ section: DockSection, _ state: inout LocalState) {
        let now = now()
        let current = Planner.startingEvents(section, at: now)
        var events = state.dockEvents ?? [:]
        if let previous = state.dockKeys {
            let before = Set(previous), after = Set(current.keys)
            for key in after.subtracting(before) { events[key] = current[key] }
            for key in before.subtracting(after) {
                if let old = events[key] { events[key] = DockEvent(present: false, at: now, item: old.item, inApps: old.inApps) }
            }
        } else {
            // First look: a starting point, which never beats a removal made on another Mac.
            for (key, event) in Planner.startingEvents(section) where events[key] == nil { events[key] = event }
        }
        // Keep the freshest description of items still here (a renamed app, a moved folder).
        for (key, event) in current { if let old = events[key], old.present { events[key]?.item = event.item; _ = old } }
        state.dockEvents = events
        state.dockKeys = current.keys.sorted()
    }

    private static let epoch = Date(timeIntervalSince1970: 0)

    private func capturePrefs(_ state: inout LocalState) -> PrefsSection? {
        guard proUnlocked else { return nil }
        let domains = (state.appPrefDomains ?? []).sorted()
        let captured = PrefsCapture.values(prefs: prefs, appDomains: domains, home: env.homeDirectory)
        var section = PrefsSection(changedAt: state.settingsChangedAt ?? Self.epoch, basedOn: state.settingsBasedOn,
                                   covered: captured.covered, values: captured.values, appDomains: domains)
        let hash = section.contentHash
        if state.settingsHash == nil {
            // Same rule as the Dock: the first look at a Mac's settings is a starting point, not an edit.
            state.settingsChangedAt = section.changedAt
        } else if state.settingsHash != hash {
            section.changedAt = now()
            section.basedOn = nil
            state.settingsChangedAt = section.changedAt
            state.settingsBasedOn = nil
        }
        state.settingsHash = hash
        return section
    }

    private func currentPrefsHash(_ state: LocalState) -> String {
        let domains = (state.appPrefDomains ?? []).sorted()
        let captured = PrefsCapture.values(prefs: prefs, appDomains: domains, home: env.homeDirectory)
        return PrefsSection(changedAt: Self.epoch, covered: captured.covered, values: captured.values, appDomains: domains).contentHash
    }

    private func settingsWinner(_ machines: [MachineSnapshot]) -> MachineSnapshot? {
        guard proUnlocked else { return nil }
        return Planner.winner(among: machines) { $0.settings.map { ($0.changedAt, $0.basedOn) } }
    }

    private func makeSnapshot(state: LocalState, dock: DockSection, settings: PrefsSection? = nil) -> MachineSnapshot {
        MachineSnapshot(machineID: env.machineID, machineName: env.machineName,
                        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                        appVersion: MacSyncEnvironment.appVersion, firstSeenAt: state.firstSeenAt,
                        savedAt: now(), dock: dock, inventory: state.inventory, settings: settings)
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
        var mergedTarget: DockSection?
        if let local = snapshot.dock,
           let merged = Planner.mergedDock(among: everyone, preferring: Set((local.apps + local.others).map(\.key))) {
            mergedTarget = merged.target
            plan = Planner.dockPlan(current: local, target: merged.target, source: Self.sourceLabel(merged, everyone: everyone),
                                    locator: locator)
        }
        var settingsPlan: SettingsPlan?
        if let sw = settingsWinner(everyone), sw.machineID != env.machineID, let target = sw.settings {
            settingsPlan = SettingsPlanner.plan(target: target, source: sw.machineName, sourceID: sw.machineID,
                                                prefs: prefs, home: env.homeDirectory)
        }
        let missing = missingApps(state, others: others)
        let deselected = Set(state.deselectedApps ?? [])
        func keys(_ section: DockSection?) -> [String] { ((section?.apps ?? []) + (section?.others ?? [])).map(\.key) }
        let summaries = everyone.map { machine -> MachineSummary in
            let isSource = machine.machineID == winner?.machineID
            // In sync means it copied this exact layout (even if it lacks some apps) or looks identical.
            let copied = machine.dock?.basedOn == winner?.machineID && machine.dock?.changedAt == winner?.dock?.changedAt
            let target = mergedTarget ?? winner?.dock
            let identical = keys(machine.dock) == keys(target) && machine.dock?.tileSize == target?.tileSize
                && machine.dock?.orientation == target?.orientation
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
            missingApps: missing,
            selectedApps: missing.filter(\.canInstall).map(\.app.token).filter { !deselected.contains($0) },
            issues: issues + loaded.issues,
            lastRestorePoint: restorePoints().first { $0.undoneAt == nil },
            proEnabled: proUnlocked,
            settingsPlan: settingsPlan?.hasChanges == true ? settingsPlan : nil,
            settingsSkipped: settingsPlan?.skipped ?? [],
            appPrefDomains: state.appPrefDomains ?? [],
            skippedApps: missing.map(\.app.token).filter { deselected.contains($0) })
    }

    /// Apps on other Macs that this one lacks, leaving out any this Mac already has under another
    /// name or source (AnyDesk from Homebrew on one Mac, downloaded on another).
    private func missingApps(_ state: LocalState, others: [MachineSnapshot]) -> [MissingApp] {
        let found = Planner.missingApps(local: state.inventory ?? Inventory(), others: others)
        // A Mac on an older MacSync sends only cask names: fill in the real names from Homebrew's list.
        let catalog = found.contains { $0.app.source == .cask && $0.detail?.displayName == nil }
            ? CaskCatalog.load(env: env, runner: runner, now: now()) : nil
        return found.map { missing in
            guard missing.app.source == .cask, missing.detail?.displayName == nil,
                  let entry = catalog?.entries[missing.app.name] else { return missing }
            var copy = missing
            var detail = copy.detail ?? AppDetail()
            detail.displayName = entry.name.map { String($0.prefix(80)) }
            if detail.summary == nil { detail.summary = entry.desc.map { String($0.prefix(160)) } }
            copy.detail = detail
            return copy
        }.filter { missing in
            // A simulated Mac (its Dock lives in a file) has only its own Applications folder, not this Mac's apps.
            guard env.dockFile == nil,
                  let bundle = missing.detail?.bundleID ?? (missing.app.source == .direct ? missing.app.name : nil) else { return true }
            return locator.path(forBundleID: bundle) == nil
        }
    }

    static func sourceLabel(_ merged: Planner.MergedDock, everyone: [MachineSnapshot]) -> String {
        let names = everyone.filter { $0.dock != nil }.map(\.machineName)
        return names.count <= 1 ? merged.orderSourceName : "your Macs"
    }

    // MARK: Apply

    /// Backs up first, then installs, then changes the Dock. Each install reports its own result.
    public func apply(_ request: ApplyRequest, progress: (String) -> Void = { _ in }) throws -> ApplyReport {
        let lock = try acquireLock()
        defer { close(lock) }
        let before = try sync(refreshInventory: false)
        let allowed = Set(before.missingApps.map(\.app))
        let apps = request.apps.filter { allowed.contains($0) && $0.isSafe }
        let removals = request.applyDock ? Set(request.removeFromDock).intersection(
            ((before.dockPlan?.targetApps ?? []) + (before.dockPlan?.targetOthers ?? [])).map(\.key)) : []
        let wantsDock = request.applyDock && (before.dockPlan != nil || !removals.isEmpty)
        let wantsSettings = request.applySettings && before.settingsPlan != nil
        guard wantsDock || wantsSettings || !apps.isEmpty else {
            return ApplyReport(restorePoint: nil, dockChanged: false, skippedDockItems: before.dockMissing, results: [])
        }

        let source = before.dockPlan?.sourceMachine ?? before.settingsPlan?.sourceMachine ?? before.machines.first { !$0.isThisMac }?.name ?? "another Mac"
        var point = try createRestorePoint(source: source, summary: Self.summary(dock: wantsDock ? before.dockPlan : nil,
                                                                                     settings: wantsSettings ? before.settingsPlan : nil, apps: apps))

        var results: [InstallResult] = []
        missingNames = Dictionary(before.missingApps.map { ($0.app.token, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        missingDownloads = Dictionary(before.missingApps.compactMap { m in m.download.map { (m.app.token, $0) } },
                                      uniquingKeysWith: { a, _ in a })
        for app in apps {
            progress("Installing \(missingNames[app.token] ?? app.name)…")
            var result = install(app)
            result.displayName = missingNames[app.token]
            results.append(result)
        }
        point.installed = results.filter { $0.outcome == .installed }.map(\.app.token)
        try writeRestoreInfo(point)

        var dockChanged = false
        var settingsChanged = false
        var settingsError: String?
        var skipped: [DockItem] = before.dockMissing
        var state = loadState()
        if !apps.isEmpty { state.inventory = InventoryReader(runner: runner, env: env).read(); state.inventoryAt = now() }
        // Settings go first: Dock behaviour keys live in the Dock's own preferences, and the layout
        // write below must start from them. The restore point's Dock backup predates both.
        if wantsSettings, let plan = before.settingsPlan {
            progress("Updating settings…")
            do {
                try applySettings(plan, point: point)
                settingsChanged = true
                state.settingsChangedAt = plan.sourceChangedAt
                state.settingsBasedOn = plan.sourceMachineID
                state.settingsHash = currentPrefsHash(state)
            } catch {
                settingsError = error.localizedDescription
            }
        }
        if wantsDock {
            progress("Updating the Dock…")
            // Plan again: anything just installed can now take its place in the Dock.
            var snapshotDock = try captureDock(&state)
            // Removing here counts as a removal made on this Mac now, so every other Mac follows.
            for key in removals {
                let known = state.dockEvents?[key] ?? before.dockPlan.flatMap { plan in
                    (plan.targetApps.map { ($0, true) } + plan.targetOthers.map { ($0, false) }).first { $0.0.key == key }
                        .map { DockEvent(present: true, at: Self.epoch, item: $0.0, inApps: $0.1) }
                }
                if let known { state.dockEvents?[key] = DockEvent(present: false, at: now(), item: known.item, inApps: known.inApps) }
            }
            snapshotDock.events = state.dockEvents
            let everyone = store.load().machines.filter { $0.machineID != env.machineID }
                + [makeSnapshot(state: state, dock: snapshotDock)]
            let localKeys = Set((snapshotDock.apps + snapshotDock.others).map(\.key))
            if let merged = Planner.mergedDock(among: everyone, preferring: localKeys) {
                let target = merged.target
                let plan = Planner.dockPlan(current: snapshotDock, target: target, source: Self.sourceLabel(merged, everyone: everyone),
                                            locator: locator)
                skipped = plan.missing
                if plan.hasChanges {
                    try write(plan: plan, target: target, backup: point)
                    dockChanged = true
                    if merged.orderSourceID != env.machineID {
                        state.dockChangedAt = target.changedAt
                        state.dockBasedOn = merged.orderSourceID
                    }
                    let written = DockCapture.section(from: try dock.readRaw(), changedAt: target.changedAt, home: env.homeDirectory)
                    state.dockHash = written.contentHash
                    // What was applied came from other Macs: adopt their history rather than record it as edits here.
                    state.dockEvents = merged.events
                    state.dockKeys = Planner.startingEvents(written).keys.sorted()
                }
            }
        }
        point.touchedDock = dockChanged
        point.touchedSettings = settingsChanged
        try writeRestoreInfo(point)
        try saveState(state)
        pruneRestorePoints()
        _ = try? sync(refreshInventory: false)
        return ApplyReport(restorePoint: point, dockChanged: dockChanged, skippedDockItems: skipped, results: results,
                           settingsChanged: settingsChanged, settingsSkipped: before.settingsSkipped, settingsError: settingsError)
    }

    /// Gets one app straight away, outside Apply: installs it with Homebrew, opens its App Store
    /// page, or downloads its installer from the developer. Nothing else on the Mac changes.
    public func getApp(_ missing: MissingApp) -> InstallResult {
        guard missing.app.isSafe else { return InstallResult(app: missing.app, outcome: .failed, message: "That app's name isn't valid.") }
        missingNames[missing.app.token] = missing.displayName
        if let download = missing.download { missingDownloads[missing.app.token] = download.sanitized }
        var result = install(missing.app)
        result.displayName = missing.displayName
        if result.outcome == .installed {
            var state = loadState()
            state.inventory = InventoryReader(runner: runner, env: env).read()
            state.inventoryAt = now()
            try? saveState(state)
        }
        return result
    }

    private func install(_ app: AppRef) -> InstallResult {
        switch app.source {
        case .appStore:
            // `mas install` needs root. The App Store page needs nothing and can't fail silently.
            let result = runner.run("/usr/bin/open", ["macappstore://apps.apple.com/app/id\(app.appStoreID ?? "")"], input: nil, environment: [:])
            return InstallResult(app: app, outcome: result.status == 0 ? .openedInAppStore : .failed,
                                 message: result.status == 0 ? "Click Get in the App Store to finish." : result.stderr)
        case .direct:
            let name = missingNames[app.token] ?? app.name
            guard let source = missingDownloads[app.token] else {
                return InstallResult(app: app, outcome: .failed,
                                     message: "MacSync doesn't know where \(name) is published. Get it from the developer's website.")
            }
            switch AppDownloader(env: env, runner: runner, now: now).fetch(source) {
            case .success(let path):
                return InstallResult(app: app, outcome: .downloaded,
                                     message: "Saved to Downloads as \((path as NSString).lastPathComponent) and opened. Finish installing it there.",
                                     path: path)
            case .failure(let error):
                return InstallResult(app: app, outcome: .failed, message: error.localizedDescription)
            }
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

    static func summary(dock: DockPlan?, settings: SettingsPlan? = nil, apps: [AppRef]) -> String {
        var parts: [String] = []
        if let dock {
            let total = dock.added.count + dock.removed.count + dock.moved.count
            parts.append(total == 0 ? "Dock settings" : "\(total) Dock change\(total == 1 ? "" : "s")")
        }
        if let settings { parts.append("\(settings.changes.count) setting\(settings.changes.count == 1 ? "" : "s")") }
        if !apps.isEmpty { parts.append("\(apps.count) app\(apps.count == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    // MARK: Settings

    struct SettingsBackupEntry: Codable {
        var domain: String
        var key: String
        var value: PrefValue?
        var type: SettingType?
        var restart: RestartTarget?
    }

    private func settingsBackupURL(_ id: String) -> URL { restoreDirectory(id).appendingPathComponent("settings-before.json") }

    /// Saves every value about to change, writes the new ones, restarts what needs it, then
    /// checks. If the checks fail everything goes back.
    private func applySettings(_ plan: SettingsPlan, point: RestorePointInfo) throws {
        let backup = plan.changes.map {
            SettingsBackupEntry(domain: $0.domain, key: $0.key, value: prefs.value(domain: $0.domain, key: $0.key),
                                type: $0.type, restart: $0.restart)
        }
        try JSONEncoder().encode(backup).write(to: settingsBackupURL(point.id), options: .atomic)
        let entries = plan.changes.map { SettingsBackupEntry(domain: $0.domain, key: $0.key, value: $0.to, type: $0.type, restart: $0.restart) }
        do {
            try commitSettings(entries)
        } catch {
            try? commitSettings(backup)
            throw EngineError.refused("Some settings didn't take effect, so they were put back.")
        }
    }

    private func restoreSettings(from point: RestorePointInfo) throws {
        let data = try Data(contentsOf: settingsBackupURL(point.id))
        try commitSettings(try JSONDecoder().decode([SettingsBackupEntry].self, from: data))
    }

    /// A value is only trusted after the processes that cache it have restarted.
    private func commitSettings(_ entries: [SettingsBackupEntry]) throws {
        let targets = Set(entries.compactMap(\.restart))
        for _ in 0..<Self.maxDockWriteAttempts {
            for entry in entries {
                if let value = entry.value {
                    prefs.set(domain: entry.domain, key: entry.key, value: value, type: entry.type)
                } else {
                    prefs.remove(domain: entry.domain, key: entry.key)
                }
            }
            for target in targets.sorted(by: { $0.rawValue < $1.rawValue }) {
                if target == .dock { dock.restartDock() } else { prefs.restart(target) }
            }
            if entries.allSatisfy({ prefs.value(domain: $0.domain, key: $0.key) == $0.value }) { return }
        }
        throw EngineError.refused("The settings didn't stick.")
    }

    // MARK: App preferences (Pro)

    public var proEnabledForCLI: Bool { proUnlocked }

    public func appPrefDomains() -> [String] { loadState().appPrefDomains ?? [] }

    public func setAppPrefDomains(_ domains: [String]) throws {
        var state = loadState()
        let valid = domains.filter { $0.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
            && !$0.hasPrefix("com.apple.") && $0 != "NSGlobalDomain" }
        state.appPrefDomains = Array(Set(valid)).sorted()
        try saveState(state)
    }

    /// Apps that have saved preferences on this Mac, for the person to choose from.
    public func availableAppPrefDomains() -> [String] {
        let folder = URL(fileURLWithPath: env.homeDirectory).appendingPathComponent("Library/Preferences")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".plist") }.map { String($0.dropLast(6)) }
            .filter { !$0.hasPrefix("com.apple.") && !$0.hasPrefix(".") && $0.contains(".") }.sorted()
    }

    // MARK: Undo

    /// Puts the Dock back exactly as it was. Installed apps stay installed, and the result says so.
    public func undoLast() throws -> RestorePointInfo {
        let lock = try acquireLock()
        defer { close(lock) }
        guard var point = restorePoints().first(where: { $0.undoneAt == nil }) else { throw EngineError.nothingToUndo }
        if point.touchedDock != false {
            let backup = try Data(contentsOf: restoreDirectory(point.id).appendingPathComponent("dock.plist"))
            try commit(backup, expecting: try fingerprint(of: backup))
        }
        if point.touchedSettings == true { try restoreSettings(from: point) }
        if let data = try? Data(contentsOf: restoreDirectory(point.id).appendingPathComponent("dock-history.json")),
           let history = try? JSONDecoder.iso.decode(DockHistory.self, from: data) {
            var state = loadState()
            state.dockKeys = history.keys
            state.dockEvents = history.events
            try saveState(state)
        }
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
        // This Mac's Dock history as it was, so undo puts this Mac back without counting as removals elsewhere.
        let state = loadState()
        let history = DockHistory(keys: state.dockKeys, events: state.dockEvents)
        try JSONEncoder.iso.encode(history).write(to: restoreDirectory(id).appendingPathComponent("dock-history.json"), options: .atomic)
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

    struct DockHistory: Codable { var keys: [String]?; var events: [String: DockEvent]? }

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

extension JSONEncoder {
    static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}

extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
