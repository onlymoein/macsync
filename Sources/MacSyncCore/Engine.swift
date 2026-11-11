import AppKit
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
    /// The MacSync version that Mac runs.
    public var appVersion: String = ""
    /// Older than this Mac's MacSync, so it may miss newer features.
    public var isOutdated: Bool { !appVersion.isEmpty && SelfUpdater.isNewer(MacSyncEnvironment.appVersion, than: appVersion) }
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
    /// Every saved restore point, newest first, so the person can go back to any of them.
    public var history: [RestorePointInfo] = []
    public var proEnabled: Bool
    public var settingsPlan: SettingsPlan?
    public var settingsSkipped: [String]
    public var appPrefDomains: [String]
    /// Apps from other Macs the person said this Mac doesn't need. Remembered on this Mac only.
    public var skippedApps: [String] = []
    /// Apps on this Mac that MacSync can remove from every Mac.
    public var installedApps: [MissingApp] = []
    /// Apps removed on another Mac that are still on this one.
    public var toRemove: [MissingApp] = []
    /// Apps removed from all Macs, newest first, so a removal can be taken back.
    public var removed: [AppRemoval] = []
    /// This Mac's apps it doesn't offer the other Macs.
    public var unshared: [String] = []
    /// The Mac whose Dock order every Mac follows; nil means whichever changed last.
    public var dockOrderFrom: String?
    /// The combined Dock even when it already matches this Mac, so it can always be shown.
    public var dockPreview: DockPlan?
    /// Settings this Mac keeps to itself.
    public var excludedSettings: [String] = []

    /// Suggested suites (ArtCraft) are offered in the window but don't count as something to do.
    public var hasPendingChanges: Bool {
        dockPlan != nil || settingsPlan != nil || wantedApps.contains { !$0.fromMachines.isEmpty } || !toRemove.isEmpty
    }
    /// Missing apps, minus the ones this Mac doesn't need.
    public var wantedApps: [MissingApp] { missingApps.filter { !skippedApps.contains($0.app.token) } }
}

public struct InstallResult: Codable, Equatable, Identifiable {
    public enum Outcome: String, Codable { case installed, openedInAppStore, downloaded, removed, failed }
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
    /// A new order for the Dock's apps (by key), arranged in MacSync. Every Mac follows it.
    public var dockOrder: [String]?
    public init(applyDock: Bool, apps: [AppRef], applySettings: Bool = true, removeFromDock: [String] = [], dockOrder: [String]? = nil) {
        self.applyDock = applyDock
        self.apps = apps
        self.applySettings = applySettings
        self.removeFromDock = removeFromDock
        self.dockOrder = dockOrder
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

    public init(restorePoint: RestorePointInfo?, dockChanged: Bool, skippedDockItems: [DockItem], results: [InstallResult],
                settingsChanged: Bool = false, settingsSkipped: [String] = [], settingsError: String? = nil) {
        self.restorePoint = restorePoint
        self.dockChanged = dockChanged
        self.skippedDockItems = skippedDockItems
        self.results = results
        self.settingsChanged = settingsChanged
        self.settingsSkipped = settingsSkipped
        self.settingsError = settingsError
    }
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
        /// Every Mac's "remove from all Macs" requests, by app token, merged.
        var removals: [String: AppRemoval]?
        /// Apps removed elsewhere that this Mac keeps anyway.
        var keptHere: [String]?
        /// This Mac's apps that it doesn't offer to the other Macs.
        var unshared: [String]?
        var dockOrder: DockOrderChoice?
        /// Settings this Mac keeps to itself: not sent to the other Macs, and not taken from them.
        var excludedSettings: [String]?
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
    /// One change to this Mac's saved state at a time: a sync reads the state, works, then writes
    /// it back, so a switch flipped in between would otherwise be lost. Recursive because one
    /// action can run others (Apply ends with a sync).
    private let stateLock = NSRecursiveLock()
    private var missingDownloads: [String: DirectApp] = [:]
    /// Where apps go for the install in progress, when the person chose a folder.
    private var installFolder: URL?

    /// A folder apps can be installed into: one that exists and can be written to.
    static func isUsableFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return url.isFileURL && FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            && FileManager.default.isWritableFile(atPath: url.path)
    }

    /// Suites always offered (ArtCraft). Tests pass none.
    let suites: [AppSuite]

    public init(env: MacSyncEnvironment, dock: DockStoring, locator: AppLocating, runner: CommandRunning,
                prefs: PreferencesStoring = InMemoryPreferences(), proUnlocked: Bool = ProLicense.isUnlocked,
                suites: [AppSuite] = AppSuite.all, now: @escaping () -> Date = Date.init) {
        self.suites = suites
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
        stateLock.lock(); defer { stateLock.unlock() }
        var state = loadState()
        let local = try captureDock(&state)
        if env.iCloudAvailable { storeDockIcons(local) }
        if refreshInventory || state.inventory == nil {
            state.inventory = InventoryReader(runner: runner, env: env).read()
            state.inventoryAt = now()
        }
        let settings = capturePrefs(&state)
        mergeRemovals(&state)
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

    // MARK: Removing from all Macs, and what this Mac shares

    /// Puts items in the order given by their keys. Items the order doesn't name keep their place
    /// after the ones it does.
    static func arrange(_ items: [DockItem], by order: [String]) -> [DockItem] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return items.enumerated().sorted { a, b in
            let ra = rank[a.element.key] ?? order.count + a.offset, rb = rank[b.element.key] ?? order.count + b.offset
            return ra < rb
        }.map(\.element)
    }

    /// The latest "follow this Mac's Dock order" choice made on any Mac.
    private func dockOrder(_ state: LocalState, _ everyone: [MachineSnapshot]) -> DockOrderChoice? {
        (everyone.compactMap(\.dockOrder) + [state.dockOrder].compactMap { $0 }).max { $0.at < $1.at }
    }

    /// Makes every Mac's Dock follow one Mac's order, or nil for whichever Dock changed last.
    public func setDockOrder(machineID: String?) throws {
        stateLock.lock(); defer { stateLock.unlock() }
        var state = loadState()
        state.dockOrder = DockOrderChoice(machineID: machineID, at: now())
        try saveState(state)
        try sync(refreshInventory: false)
    }

    /// Takes in every other Mac's removal requests. The newest request for an app wins.
    private func mergeRemovals(_ state: inout LocalState) {
        var merged = state.removals ?? [:]
        for machine in store.load().machines where machine.machineID != env.machineID {
            for removal in machine.removals ?? [] where AppRef.isSafeToken(removal.token) {
                if let mine = merged[removal.token], mine.at >= removal.at { continue }
                var clean = removal
                clean.name = String(removal.name.prefix(80))
                clean.fromMachine = String(removal.fromMachine.prefix(80))
                merged[removal.token] = clean
            }
        }
        state.removals = merged.isEmpty ? nil : merged
    }

    /// The apps this Mac offers the others: everything, minus what the person switched off.
    private func sharedInventory(_ state: LocalState) -> Inventory? {
        guard var inventory = state.inventory else { return nil }
        let hidden = Set(state.unshared ?? [])
        guard !hidden.isEmpty else { return inventory }
        inventory.casks.removeAll { hidden.contains(AppRef(source: .cask, name: $0).token) }
        inventory.formulae.removeAll { hidden.contains(AppRef(source: .formula, name: $0).token) }
        inventory.appStore.removeAll { hidden.contains(AppRef(source: .appStore, name: $0.name, appStoreID: $0.id).token) }
        inventory.directApps?.removeAll { hidden.contains(AppRef(source: .direct, name: $0.bundleID).token) }
        inventory.details = inventory.details?.filter { !hidden.contains($0.key) }
        return inventory
    }

    /// This Mac's apps as rows, with their names and icons.
    private func localApps(_ state: LocalState) -> [MissingApp] {
        guard let inventory = state.inventory else { return [] }
        var refs: [AppRef] = inventory.casks.map { AppRef(source: .cask, name: $0) }
            + inventory.appStore.map { AppRef(source: .appStore, name: $0.name, appStoreID: $0.id) }
            + (inventory.directApps ?? []).map { AppRef(source: .direct, name: $0.bundleID) }
        refs += inventory.formulae.map { AppRef(source: .formula, name: $0) }
        let direct = Dictionary((inventory.directApps ?? []).map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        return refs.filter(\.isSafe).map { ref in
            var detail = inventory.details?[ref.token]
            if detail == nil, ref.source == .direct { detail = AppDetail(displayName: direct[ref.name]?.name, bundleID: ref.name) }
            return MissingApp(app: ref, fromMachines: [env.machineName], detail: detail,
                              download: ref.source == .direct ? direct[ref.name] : nil)
        }
    }

    /// Stops offering an app to the other Macs, or starts again.
    public func setShared(_ tokens: [String], _ shared: Bool) throws {
        stateLock.lock(); defer { stateLock.unlock() }
        var state = loadState()
        var set = Set(state.unshared ?? [])
        if shared { set.subtract(tokens) } else { set.formUnion(tokens) }
        state.unshared = set.isEmpty ? nil : set.sorted()
        try saveState(state)
        try sync(refreshInventory: false)
    }

    /// Removes apps from this Mac now, and asks every other Mac to remove them too.
    public func removeEverywhere(_ apps: [MissingApp], progress: (String) -> Void = { _ in }) -> [InstallResult] {
        stateLock.lock(); defer { stateLock.unlock() }
        let installed = Set(localApps(loadState()).map(\.app.token))
        // Uninstall here first. Only an app that is really gone from this Mac (or was never on it)
        // is recorded as removed, so a failed uninstall doesn't hide the app or ask the others.
        let results = uninstallHere(apps.filter { installed.contains($0.app.token) }, progress: progress)
        let failed = Set(results.filter { $0.outcome == .failed }.map(\.app.token))
        var state = loadState()
        var removals = state.removals ?? [:]
        for app in apps where app.app.isSafe && !failed.contains(app.app.token) {
            removals[app.app.token] = AppRemoval(token: app.app.token, name: app.displayName, bundleID: app.detail?.bundleID,
                                                 at: now(), active: true, fromMachine: env.machineName)
        }
        state.removals = removals.isEmpty ? nil : removals
        try? saveState(state)
        _ = try? sync(refreshInventory: false)
        return results
    }

    /// Takes back a removal, so the app is offered to Macs that lack it again.
    public func cancelRemoval(_ token: String) throws {
        stateLock.lock(); defer { stateLock.unlock() }
        var state = loadState()
        guard var removal = state.removals?[token] else { return }
        removal.active = false
        removal.at = now()
        removal.fromMachine = env.machineName
        state.removals?[token] = removal
        state.keptHere = (state.keptHere ?? []).filter { $0 != token }
        try saveState(state)
        try sync(refreshInventory: false)
    }

    /// Leaves an app removed elsewhere on this Mac, and stops asking.
    public func keepHere(_ token: String) throws {
        stateLock.lock(); defer { stateLock.unlock() }
        var state = loadState()
        state.keptHere = Array(Set(state.keptHere ?? []).union([token])).sorted()
        try saveState(state)
    }

    /// Uninstalls apps from this Mac: Homebrew uninstalls its own, anything else goes to the Trash,
    /// where it can be put back. The app also leaves this Mac's Dock.
    public func uninstallHere(_ apps: [MissingApp], progress: (String) -> Void = { _ in }) -> [InstallResult] {
        stateLock.lock(); defer { stateLock.unlock() }
        var results: [InstallResult] = []
        for app in apps where app.app.isSafe {
            progress("Removing \(app.displayName)…")
            var result = uninstall(app)
            result.displayName = app.displayName
            results.append(result)
            if result.outcome == .removed, let id = app.detail?.bundleID ?? (app.app.source == .direct ? app.app.name : nil) {
                removeDockTiles(bundleID: id)
            }
        }
        var state = loadState()
        state.inventory = InventoryReader(runner: runner, env: env).read()
        state.inventoryAt = now()
        try? saveState(state)
        _ = try? sync(refreshInventory: false)
        return results
    }

    private func uninstall(_ app: MissingApp) -> InstallResult {
        let ref = app.app
        switch ref.source {
        case .cask, .formula:
            guard let brew = env.brewPath else { return InstallResult(app: ref, outcome: .failed, message: "Homebrew isn't installed.") }
            let args = ref.source == .cask ? ["uninstall", "--cask", ref.name] : ["uninstall", ref.name]
            let result = runner.run(brew, args, input: nil, environment: InventoryReader.brewEnvironment(brew))
            if result.status == 0 { return InstallResult(app: ref, outcome: .removed, message: nil) }
            return InstallResult(app: ref, outcome: .failed,
                                 message: result.stderr.split(whereSeparator: \.isNewline).last.map(String.init) ?? "brew exited with \(result.status).")
        case .appStore, .direct:
            let file: String? = ref.source == .appStore ? ref.name : (app.download?.name ?? loadState().inventory?.directApps?.first { $0.bundleID == ref.name }?.name)
            guard let file, DirectApp.isSafeName(file) else {
                return InstallResult(app: ref, outcome: .failed, message: "MacSync couldn't find \(app.displayName) in Applications.")
            }
            let url = env.applicationsDirectory.appendingPathComponent(file + ".app")
            guard FileManager.default.fileExists(atPath: url.path) else { return InstallResult(app: ref, outcome: .removed, message: "It was already gone.") }
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                return InstallResult(app: ref, outcome: .removed, message: "Moved to the Trash.")
            }
            // App Store apps belong to the system: macOS asks for your password, as when you drag
            // one to the Trash in Finder.
            if Self.recycleAskingForPassword(url) {
                return InstallResult(app: ref, outcome: .removed, message: "Moved to the Trash.")
            }
            return InstallResult(app: ref, outcome: .failed,
                                 message: "\(app.displayName) wasn't moved to the Trash. App Store apps need your Mac's password: press Try Again and enter it.")
        }
    }

    /// Moves a file to the Trash the way Finder does, which asks for an administrator's
    /// password when the file belongs to the system. Waits for the answer.
    static func recycleAskingForPassword(_ url: URL) -> Bool {
        // macOS's own password window, the one installers use. The app goes to this person's
        // Trash, where it can still be put back.
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        var target = trash.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = trash.appendingPathComponent(url.deletingPathExtension().lastPathComponent + " \(n)." + url.pathExtension)
            n += 1
        }
        let script = """
        on run argv
            do shell script "/bin/mv " & quoted form of (item 1 of argv) & " " & quoted form of (item 2 of argv) with prompt "MacSync wants to move " & (item 3 of argv) & " to the Trash." with administrator privileges
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, url.path, target.path, url.deletingPathExtension().lastPathComponent]
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0 && !FileManager.default.fileExists(atPath: url.path)
    }

    /// Takes an uninstalled app's tile out of this Mac's Dock. The next sync records it as
    /// removed, so the other Macs drop it too.
    private func removeDockTiles(bundleID: String) {
        guard var raw = try? dock.readRaw(), let tiles = raw["persistent-apps"] as? [[String: Any]] else { return }
        let kept = tiles.filter { (($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String) != bundleID }
        guard kept.count != tiles.count else { return }
        raw["persistent-apps"] = kept
        guard let data = try? PropertyListSerialization.data(fromPropertyList: raw, format: .xml, options: 0) else { return }
        try? commit(data, expecting: fingerprint(of: data))
    }

    /// Shares the icon of every app in this Dock, so other Macs can show apps they don't have yet.
    private func storeDockIcons(_ dock: DockSection) {
        let icons = IconStore(directory: env.syncDirectory.appendingPathComponent("icons", isDirectory: true))
        for item in dock.apps where item.kind == .app {
            guard let id = item.bundleID, DirectApp.isSafeBundleID(id), let path = locator.path(forBundleID: id) ?? item.path else { continue }
            _ = icons.store(appAt: path, id: IconStore.id(bundleID: id))
        }
    }

    /// Where a person can get an app this Mac doesn't have: its App Store page, or the
    /// developer's site as Homebrew lists it, or the App Store found by its bundle ID.
    /// Uses the network, so call it off the main thread.
    public func downloadPage(bundleID: String?, name: String, missing: MissingApp?) -> URL? {
        if let missing, missing.app.source == .appStore, let id = missing.app.appStoreID {
            return URL(string: "macappstore://apps.apple.com/app/id\(id)")
        }
        let catalog = CaskCatalog.load(env: env, runner: runner, now: now())
        let token: String? = {
            if let missing, missing.app.source == .cask { return missing.app.name }
            if let cask = missing?.download?.cask { return cask }
            return catalog?.cask(forApp: name + ".app")
        }()
        if let token, let page = catalog?.entries[token]?.homepage, DirectApp.isSafeURL(page) { return URL(string: page) }
        if let bundleID, DirectApp.isSafeBundleID(bundleID) {
            let lookup = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--max-time", "15",
                                                      "https://itunes.apple.com/lookup?entity=macSoftware&bundleId=\(bundleID)"],
                                    input: nil, environment: [:])
            if lookup.status == 0,
               let root = try? JSONSerialization.jsonObject(with: lookup.stdout) as? [String: Any],
               let first = (root["results"] as? [[String: Any]])?.first, let id = first["trackId"] as? Int {
                return URL(string: "macappstore://apps.apple.com/app/id\(id)")
            }
        }
        if let feed = missing?.download?.feed, let url = URL(string: feed), let host = url.host {
            return URL(string: "https://\(host)")
        }
        var search = URLComponents(string: "https://duckduckgo.com/")!
        search.queryItems = [URLQueryItem(name: "q", value: "\(name) Mac app download")]
        return search.url
    }

    /// A logo for an app this Mac doesn't have, from the App Store or the developer's site, for
    /// when the Mac that has it hasn't shared one yet. Saved on this Mac only. Uses the network.
    public func webIcon(bundleID: String?, name: String, missing: MissingApp?) -> URL? {
        let key = String(Hashing.sha256(Data("web:\(bundleID ?? missing?.app.token ?? name)".utf8)).prefix(24))
        let folder = env.dataDirectory.appendingPathComponent("web-icons", isDirectory: true)
        let file = folder.appendingPathComponent(key + ".png")
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) { return file }
        // Don't ask again for a day after nothing was found.
        let miss = folder.appendingPathComponent(key + ".none")
        if let at = (try? fm.attributesOfItem(atPath: miss.path)[.modificationDate]) as? Date, now().timeIntervalSince(at) < 86_400 { return nil }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        func fetch(_ url: String) -> Data? {
            let r = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--max-time", "15", url], input: nil, environment: [:])
            return r.status == 0 && !r.stdout.isEmpty ? r.stdout : nil
        }
        var candidates: [String] = []
        let lookup: String? = {
            if let id = missing?.app.appStoreID, missing?.app.source == .appStore, missing?.app.isSafe == true {
                return "https://itunes.apple.com/lookup?entity=macSoftware&id=\(id)"
            }
            if let bundleID, DirectApp.isSafeBundleID(bundleID) { return "https://itunes.apple.com/lookup?entity=macSoftware&bundleId=\(bundleID)" }
            return nil
        }()
        if let lookup, let data = fetch(lookup),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let art = (root["results"] as? [[String: Any]])?.first?["artworkUrl512"] as? String {
            candidates.append(art)
        }
        let catalog = CaskCatalog.load(env: env, runner: runner, now: now())
        let guess = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let token = missing?.app.source == .cask ? missing?.app.name
            : (missing?.download?.cask ?? catalog?.cask(forApp: name + ".app")
               ?? [guess, guess + "-app"].first { catalog?.entries[$0] != nil })
        if let token, let page = catalog?.entries[token]?.homepage, let base = URL(string: page), let host = base.host {
            candidates += ["https://\(host)/apple-touch-icon.png"]
            // Icons the developer's page names, largest first: apple-touch-icon, then other icons.
            if DirectApp.isSafeURL(page), let html = fetch(page).map({ String(decoding: $0.prefix(400_000), as: UTF8.self) }) {
                candidates += Self.pageIcons(html, base: base)
            }
            candidates.append("https://\(host)/favicon.ico")
        }
        for url in candidates where DirectApp.isSafeURL(url) {
            guard let data = fetch(url), let image = NSImage(data: data), image.isValid,
                  let png = IconStore.png(image, side: 128) else { continue }
            if (try? png.write(to: file, options: .atomic)) != nil { return file }
        }
        try? Data().write(to: miss)
        return nil
    }

    static func pageIcons(_ html: String, base: URL) -> [String] {
        guard let tag = try? NSRegularExpression(pattern: "<link[^>]+>", options: .caseInsensitive) else { return [] }
        var found: [(rank: Int, url: String)] = []
        for match in tag.matches(in: html, range: NSRange(html.startIndex..., in: html)).prefix(200) {
            let link = String(html[Range(match.range, in: html)!])
            func attr(_ name: String) -> String? {
                guard let re = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*[\"']([^\"']+)[\"']", options: .caseInsensitive),
                      let m = re.firstMatch(in: link, range: NSRange(link.startIndex..., in: link)),
                      let r = Range(m.range(at: 1), in: link) else { return nil }
                return String(link[r])
            }
            guard let rel = attr("rel")?.lowercased(), rel.contains("icon"), !rel.contains("mask"),
                  let href = attr("href"), let url = URL(string: href, relativeTo: base)?.absoluteURL, url.scheme == "https" else { continue }
            let size = attr("sizes").flatMap { Int($0.split(separator: "x").first ?? "") } ?? 0
            found.append((rel.contains("apple-touch") ? 10_000 + size : size, url.absoluteString))
        }
        return found.sorted { $0.rank > $1.rank }.map(\.url).filter { !$0.hasSuffix(".svg") }
    }

    /// Marks an app as not needed on this Mac, or brings it back. Kept even after it stops being
    /// offered, so it stays hidden if another Mac installs it again later.
    public func setSkipped(_ token: String, _ skipped: Bool) throws { try setSkipped([token], skipped) }

    public func setSkipped(_ tokens: [String], _ skipped: Bool) throws {
        stateLock.lock(); defer { stateLock.unlock() }
        var state = loadState()
        var set = Set(state.deselectedApps ?? [])
        if skipped { set.formUnion(tokens) } else { set.subtract(tokens) }
        state.deselectedApps = set.sorted()
        try saveState(state)
    }

    /// Records the choice as what was unticked, so apps that turn up later start ticked.
    public func setSelectedApps(_ tokens: Set<String>) throws {
        stateLock.lock(); defer { stateLock.unlock() }
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
        let captured = capture(state)
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

    /// This Mac's settings as they are sent, without the ones it keeps to itself.
    private func capture(_ state: LocalState) -> (covered: [String], values: [String: PrefValue]) {
        let domains = (state.appPrefDomains ?? []).sorted()
        var captured = PrefsCapture.values(prefs: prefs, appDomains: domains, home: env.homeDirectory)
        let excluded = Set(state.excludedSettings ?? [])
        guard !excluded.isEmpty else { return captured }
        captured.covered.removeAll { excluded.contains($0) }
        captured.values = captured.values.filter { !excluded.contains($0.key) }
        return captured
    }

    /// Chooses which settings this Mac keeps to itself.
    public func setExcludedSettings(_ ids: [String]) throws {
        stateLock.lock(); defer { stateLock.unlock() }
        var state = loadState()
        state.excludedSettings = ids.isEmpty ? nil : Array(Set(ids)).sorted()
        try saveState(state)
        try sync(refreshInventory: false)
    }

    private func currentPrefsHash(_ state: LocalState) -> String {
        let domains = (state.appPrefDomains ?? []).sorted()
        let captured = capture(state)
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
                        savedAt: now(), dock: dock, inventory: sharedInventory(state), settings: settings,
                        removals: state.removals.map { Array($0.values).sorted { $0.token < $1.token } },
                        dockOrder: state.dockOrder)
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
           let merged = Planner.mergedDock(among: everyone, preferring: Set((local.apps + local.others).map(\.key)),
                                                orderFrom: dockOrder(state, everyone)?.machineID) {
            mergedTarget = merged.target
            plan = Planner.dockPlan(current: local, target: merged.target, source: Self.sourceLabel(merged, everyone: everyone),
                                    locator: locator)
        }
        var settingsPlan: SettingsPlan?
        if let sw = settingsWinner(everyone), sw.machineID != env.machineID, let target = sw.settings {
            settingsPlan = SettingsPlanner.plan(target: target, source: sw.machineName, sourceID: sw.machineID,
                                                prefs: prefs, home: env.homeDirectory)
            let excluded = Set(state.excludedSettings ?? [])
            settingsPlan?.changes.removeAll { excluded.contains($0.id) }
        }
        let active = Set((state.removals ?? [:]).values.filter(\.active).map(\.token))
        let missing = missingApps(state, others: others).filter { !active.contains($0.app.token) }
        let deselected = Set(state.deselectedApps ?? [])
        let local = localApps(state)
        let kept = Set(state.keptHere ?? [])
        let toRemove = local.filter { active.contains($0.app.token) && !kept.contains($0.app.token) }
            .map { app -> MissingApp in
                var copy = app
                if let from = state.removals?[app.app.token]?.fromMachine { copy.fromMachines = [from] }
                return copy
            }
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
                appCount: (inventory?.casks.count ?? 0) + (inventory?.formulae.count ?? 0) + (inventory?.appStore.count ?? 0),
                appVersion: machine.appVersion)
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
            history: restorePoints(),
            proEnabled: proUnlocked,
            settingsPlan: settingsPlan?.hasChanges == true ? settingsPlan : nil,
            settingsSkipped: settingsPlan?.skipped ?? [],
            appPrefDomains: state.appPrefDomains ?? [],
            skippedApps: missing.map(\.app.token).filter { deselected.contains($0) },
            installedApps: local.filter { !active.contains($0.app.token) },
            toRemove: toRemove,
            removed: (state.removals ?? [:]).values.filter(\.active).sorted { $0.at > $1.at },
            unshared: state.unshared ?? [],
            dockOrderFrom: dockOrder(state, everyone)?.machineID,
            dockPreview: plan,
            excludedSettings: state.excludedSettings ?? [])
    }

    /// Apps on other Macs that this one lacks, leaving out any this Mac already has under another
    /// name or source (AnyDesk from Homebrew on one Mac, downloaded on another).
    private func missingApps(_ state: LocalState, others: [MachineSnapshot]) -> [MissingApp] {
        var found = Planner.missingApps(local: state.inventory ?? Inventory(), others: others)
        // Suites MacSync always offers (ArtCraft): any member this Mac lacks, from Homebrew.
        let inventory = state.inventory ?? Inventory()
        let have = Set(inventory.casks)
        let haveBundles = Set((inventory.directApps ?? []).map(\.bundleID))
        let offered = Set(found.compactMap { $0.detail?.bundleID } + found.map(\.app.name))
        for suite in suites {
            for member in suite.members where !have.contains(member.cask) && !haveBundles.contains(member.bundleID)
                && !offered.contains(member.bundleID) && !offered.contains(member.cask) {
                found.append(MissingApp(app: AppRef(source: .cask, name: member.cask), fromMachines: [],
                                        detail: AppDetail(displayName: member.name, bundleID: member.bundleID)))
            }
        }
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
        stateLock.lock(); defer { stateLock.unlock() }
        let lock = try acquireLock()
        defer { close(lock) }
        let before = try sync(refreshInventory: false)
        let allowed = Set(before.missingApps.map(\.app))
        let apps = request.apps.filter { allowed.contains($0) && $0.isSafe }
        // The combined Dock, whether or not it differs from this Mac's.
        let shown = before.dockPlan ?? before.dockPreview
        let removals = request.applyDock ? Set(request.removeFromDock).intersection(
            ((shown?.targetApps ?? []) + (shown?.targetOthers ?? [])).map(\.key)) : []
        let rearranged = request.applyDock ? request.dockOrder.flatMap { $0.isEmpty ? nil : $0 } : nil
        let wantsDock = request.applyDock && (before.dockPlan != nil || !removals.isEmpty || rearranged != nil)
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
                // Take on that Mac's choice of apps whose settings sync, so both Macs show it.
                if let theirs = store.load().machines.first(where: { $0.machineID == plan.sourceMachineID })?.settings?.appDomains {
                    let mine = Set(state.appPrefDomains ?? [])
                    state.appPrefDomains = mine.union(theirs.filter { $0.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
                        && !$0.hasPrefix("com.apple.") }).sorted()
                }
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
                let known = state.dockEvents?[key] ?? shown.flatMap { plan in
                    (plan.targetApps.map { ($0, true) } + plan.targetOthers.map { ($0, false) }).first { $0.0.key == key }
                        .map { DockEvent(present: true, at: Self.epoch, item: $0.0, inApps: $0.1) }
                }
                if let known { state.dockEvents?[key] = DockEvent(present: false, at: now(), item: known.item, inApps: known.inApps) }
            }
            snapshotDock.events = state.dockEvents
            let everyone = store.load().machines.filter { $0.machineID != env.machineID }
                + [makeSnapshot(state: state, dock: snapshotDock)]
            let localKeys = Set((snapshotDock.apps + snapshotDock.others).map(\.key))
            if rearranged != nil, let pinned = dockOrder(state, everyone)?.machineID, pinned != env.machineID {
                // Arranged here on purpose: this Mac's order becomes the one every Mac follows.
                state.dockOrder = DockOrderChoice(machineID: env.machineID, at: now())
            }
            if let merged = Planner.mergedDock(among: everyone, preferring: localKeys, orderFrom: dockOrder(state, everyone)?.machineID) {
                var target = merged.target
                if let rearranged { target.apps = Self.arrange(target.apps, by: rearranged) }
                let plan = Planner.dockPlan(current: snapshotDock, target: target, source: Self.sourceLabel(merged, everyone: everyone),
                                            locator: locator)
                skipped = plan.missing
                if plan.hasChanges {
                    try write(plan: plan, target: target, backup: point)
                    dockChanged = true
                    if rearranged != nil {
                        // A change made on this Mac: it is now the newest Dock.
                        state.dockChangedAt = now()
                        state.dockBasedOn = nil
                    } else if merged.orderSourceID != env.machineID {
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

    /// Homebrew's error in plain words: "Homebrew no longer has tldr. Did you mean tldx?"
    static func brewProblem(_ stderr: String, name: String, status: Int32) -> String {
        let lines = stderr.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        if let line = lines.first(where: { $0.contains("No available formula") || $0.contains("No available cask") || $0.contains("No casks found") }) {
            let hint = line.range(of: "Did you mean")
                .map { " " + line[$0.lowerBound...].trimmingCharacters(in: .whitespaces) } ?? ""
            return "Homebrew no longer has \(name), so it can't be installed.\(hint) Switch it off if you don't need it."
        }
        let last = lines.last { !$0.isEmpty } ?? "brew exited with \(status)."
        return last.replacingOccurrences(of: "^(Error|Warning): ", with: "", options: .regularExpression)
    }

    /// Gets one app straight away, outside Apply: installs it with Homebrew, opens its App Store
    /// page, or downloads its installer from the developer. Nothing else on the Mac changes.
    public func getApp(_ missing: MissingApp, into folder: URL? = nil) -> InstallResult {
        stateLock.lock(); defer { stateLock.unlock() }
        guard missing.app.isSafe else { return InstallResult(app: missing.app, outcome: .failed, message: "That app's name isn't valid.") }
        missingNames[missing.app.token] = missing.displayName
        if let download = missing.download { missingDownloads[missing.app.token] = download.sanitized }
        installFolder = folder.flatMap { Self.isUsableFolder($0) ? $0 : nil }
        defer { installFolder = nil }
        var result = install(missing.app)
        result.displayName = missing.displayName
        // Gone from Homebrew: nothing to install, so stop offering it on this Mac.
        if result.outcome == .failed, result.message?.hasPrefix("Homebrew no longer has") == true {
            var state = loadState()
            state.deselectedApps = Array(Set(state.deselectedApps ?? []).union([missing.app.token])).sorted()
            try? saveState(state)
        }
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
            // Published as a Homebrew cask: install it fully instead of opening its installer.
            if let token = missingDownloads[app.token]?.cask, DirectApp.isSafeCask(token), env.brewPath != nil {
                return install(AppRef(source: .cask, name: token))
            }
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
            var args = app.source == .cask ? ["install", "--cask", app.name] : ["install", app.name]
            if app.source == .cask, let folder = installFolder { args.insert("--appdir=\(folder.path)", at: 2) }
            let result = runner.run(brew, args, input: nil, environment: InventoryReader.brewEnvironment(brew))
            guard result.status != 0 else { return InstallResult(app: app, outcome: .installed, message: nil) }
            // Installed another way (a download, npm, another formula): it's here, so it's done.
            if result.stderr.range(of: "already an App at|already a Binary at|is already installed", options: .regularExpression) != nil {
                return InstallResult(app: app, outcome: .installed, message: "Already on this Mac, installed another way.")
            }
            return InstallResult(app: app, outcome: .failed, message: Self.brewProblem(result.stderr, name: app.name, status: result.status))
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
        stateLock.lock(); defer { stateLock.unlock() }
        var state = loadState()
        let valid = domains.filter { $0.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
            && !$0.hasPrefix("com.apple.") && $0 != "NSGlobalDomain" && $0 != SelfUpdater.bundleID }
        state.appPrefDomains = Array(Set(valid)).sorted()
        try saveState(state)
    }

    /// A short fingerprint of the Dock as it is right now, read through macOS rather than the
    /// file on disk (which macOS may write late). Cheap enough to check every few seconds.
    public func dockFingerprintNow() -> String? {
        guard let raw = try? dock.readRaw() else { return nil }
        let section = DockCapture.section(from: raw, changedAt: Self.epoch, home: env.homeDirectory)
        return section.contentHash
    }

    /// Every setting MacSync keeps the same on all Macs, with its value on this Mac.
    public func currentSettings() -> [SettingsChange] {
        SettingsCatalog.all.map { d in
            let value = prefs.value(domain: d.domain, key: d.key)
            return SettingsChange(id: d.id, domain: d.domain, key: d.key, label: d.label, category: d.category,
                                  from: value, to: value, restart: d.restart, needsLogout: d.needsLogout, type: d.type)
        }
    }

    /// Apps that have saved preferences on this Mac, for the person to choose from.
    public func availableAppPrefDomains() -> [String] {
        let folder = URL(fileURLWithPath: env.homeDirectory).appendingPathComponent("Library/Preferences")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".plist") }.map { String($0.dropLast(6)) }
            .filter { !$0.hasPrefix("com.apple.") && !$0.hasPrefix(".") && $0.contains(".") && $0 != SelfUpdater.bundleID }.sorted()
    }

    // MARK: Undo

    /// Puts the Dock back exactly as it was. Installed apps stay installed, and the result says so.
    public func undoLast() throws -> RestorePointInfo {
        stateLock.lock(); defer { stateLock.unlock() }
        guard let point = restorePoints().first(where: { $0.undoneAt == nil }) else { throw EngineError.nothingToUndo }
        return try restore(point.id)
    }

    /// Puts this Mac back to how it was just before that Apply: its Dock and settings. Every
    /// Apply made after it is rolled back too. Installed apps stay installed.
    @discardableResult
    public func restore(_ id: String) throws -> RestorePointInfo {
        stateLock.lock(); defer { stateLock.unlock() }
        let lock = try acquireLock()
        defer { close(lock) }
        let all = restorePoints()
        guard var point = all.first(where: { $0.id == id }) else { throw EngineError.nothingToUndo }
        if point.touchedDock != false {
            let backup = try Data(contentsOf: restoreDirectory(point.id).appendingPathComponent("dock.plist"))
            try commit(backup, expecting: try fingerprint(of: backup))
        }
        // Settings come back newest first, so each one ends as it was before this Apply.
        for later in all.filter({ $0.id >= id && $0.undoneAt == nil && $0.touchedSettings == true }) {
            try restoreSettings(from: later)
        }
        if let data = try? Data(contentsOf: restoreDirectory(point.id).appendingPathComponent("dock-history.json")),
           let history = try? JSONDecoder.iso.decode(DockHistory.self, from: data) {
            var state = loadState()
            state.dockKeys = history.keys
            state.dockEvents = history.events
            try saveState(state)
        }
        for var later in all where later.id > id && later.undoneAt == nil {
            later.undoneAt = now()
            try writeRestoreInfo(later)
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
