import AppKit
import MacSyncCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var overview: SyncOverview?
    @Published var isSyncing = false
    @Published var isApplying = false
    @Published var progress: String?
    @Published var errorMessage: String?
    @Published var lastReport: ApplyReport?
    @Published var undoMessage: String?
    @Published var applyDock = true
    @Published var applySettings = true
    @Published var selectedApps: Set<String> = []
    /// Dock items marked in the review window to be removed from every Mac.
    @Published var dockRemovals: Set<String> = []
    /// A new order for the Dock's apps, dragged into place in the review window.
    @Published var dockArrangement: [String]?

    /// Moves a Dock app to sit before another one, in the review window's preview.
    func moveDockItem(_ key: String, before target: String, in current: [DockItem]) {
        var keys = dockArrangement ?? current.map(\.key)
        guard key != target, let from = keys.firstIndex(of: key) else { return }
        guard let targetIndex = keys.firstIndex(of: target) else { return }
        keys.remove(at: from)
        // Moving right lands after the icon it's over; moving left lands before it, as in the Dock.
        keys.insert(key, at: min(targetIndex, keys.count))
        dockArrangement = keys == current.map(\.key) ? nil : keys
    }
    @Published var autoSync: Bool {
        didSet {
            UserDefaults.standard.set(autoSync, forKey: "autoSync")
            scheduleTimer()
        }
    }
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    /// A newer MacSync release, when one is out.
    @Published var availableUpdate: SelfUpdater.Release?
    @Published var updateMessage: String?
    @Published var isUpdating = false
    /// On by default: opening the lid applies Dock changes from the other Macs without
    /// asking. A restore point is saved first, and Undo is in the menu.
    @Published var autoApplyDock: Bool {
        didSet { UserDefaults.standard.set(autoApplyDock, forKey: "autoApplyDock") }
    }
    /// Until this time after a wake, a sync that finds Dock changes applies them. iCloud can take
    /// a minute to bring in what the other Macs saved, so it isn't only the first sync.
    private var applyDockUntil: Date?
    @Published var autoApplyMessage: String?

    @Published var autoUpdate: Bool {
        didSet { UserDefaults.standard.set(autoUpdate, forKey: "autoUpdate") }
    }
    private var lastUpdateCheck = Date.distantPast
    /// At most this often; checks also happen whenever the Mac wakes, unlocks or a login session
    /// becomes active, so a new version arrives soon after you sit down.
    private static let updateInterval: TimeInterval = 30 * 60

    private let engine = Engine.live()
    private let locator = SystemAppLocator()
    private let iconStore = IconStore(directory: MacSyncEnvironment.current().syncDirectory.appendingPathComponent("icons"))
    private var iconCache: [String: NSImage] = [:]
    private var timer: Timer?
    private var lastInventoryRefresh = Date.distantPast
    private var wakeObserver: NSObjectProtocol?
    private var dockWatcher: DockWatcher?
    /// Checks the live Dock every few seconds, so a moved icon shows up and syncs right away
    /// even before macOS writes the Dock's file.
    private var dockPoll: Timer?
    private var replacedCheck: Timer?

    /// Restarts into the new version once the app on disk has been replaced, unless something
    /// is in the middle of changing the Mac. The version in Info.plist on disk tells.
    func relaunchIfReplaced() {
        let plist = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist), let onDisk = info["CFBundleShortVersionString"] as? String,
              onDisk != MacSyncEnvironment.appVersion,
              !isApplying, !isSyncing, getting.isEmpty, removing.isEmpty, !isUpdating else { return }
        // Once per new version, so a mismatched copy can't restart over and over.
        guard UserDefaults.standard.string(forKey: "relaunchedFor") != onDisk else { return }
        UserDefaults.standard.set(onDisk, forKey: "relaunchedFor")
        Self.relaunch()
    }
    private var lastDockFingerprint: String?

    private static let syncInterval: TimeInterval = 5 * 60
    private static let inventoryInterval: TimeInterval = 30 * 60

    init() {
        autoSync = UserDefaults.standard.object(forKey: "autoSync") as? Bool ?? true
        autoUpdate = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
        autoApplyDock = UserDefaults.standard.object(forKey: "autoApplyDock") as? Bool ?? true
        scheduleTimer()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.autoApplyDock { self.applyDockUntil = Date().addingTimeInterval(180) }
                self.backgroundSync()
                // iCloud may still be bringing in the other Macs' saves: look again shortly.
                for delay in [20.0, 60.0, 150.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.backgroundSync() }
                }
            }
        }
        let env = MacSyncEnvironment.current()
        let dockFile = env.dockFile ?? URL(fileURLWithPath: env.homeDirectory)
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
        dockWatcher = DockWatcher(file: dockFile) { [weak self] in
            Task { @MainActor in
                guard let self, self.autoSync, !self.isApplying else { return }
                self.runSync(refreshInventory: false)
            }
        }
        dockPoll = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollDock() }
        }
        // Homebrew, a manual drag or an update may replace the app while it runs: restart into it.
        replacedCheck = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.relaunchIfReplaced() }
        }
        // Starting to use the Mac (wake, screen on, unlock, switching back to this login): look for an update.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            updateObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.checkForUpdatesSoon() }
            })
        }
        updateObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdatesSoon() }
        })
        URLHandler.shared.model = self
        NSAppleEventManager.shared().setEventHandler(URLHandler.shared, andSelector: #selector(URLHandler.handle(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        syncNow()
        checkForUpdates()
        if CommandLine.arguments.contains("--review") {
            // This init runs inside a SwiftUI update, and opening a window there aborts the app.
            DispatchQueue.main.async { [self] in ReviewWindow.shared.show(model: self) }
        }
        #if UIPROBE
        DispatchQueue.main.async { [self] in UIProbe.runIfRequested(model: self) }
        #endif
    }

    var menuBarSymbol: String {
        if errorMessage != nil { return "exclamationmark.arrow.triangle.2.circlepath" }
        return overview?.hasPendingChanges == true ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath"
    }

    var thisMac: MachineSummary? { overview?.machines.first { $0.isThisMac } }

    var statusLine: String {
        if isApplying { return progress ?? "Applying…" }
        if isSyncing && overview == nil { return "Checking your Macs…" }
        guard let overview else { return errorMessage ?? "Not synced yet" }
        if !overview.iCloudAvailable { return "iCloud Drive is off" }
        if let plan = overview.dockPlan {
            return "Dock changes from \(plan.sourceMachine)"
        }
        if let plan = overview.settingsPlan {
            return "New settings from \(plan.sourceMachine)"
        }
        if overview.wantedApps.contains(where: { !$0.fromMachines.isEmpty }) {
            let count = overview.wantedApps.filter { !$0.fromMachines.isEmpty }.count
            return "\(count) app\(count == 1 ? "" : "s") on your other Macs"
        }
        return overview.machines.count > 1 ? "Your Macs match" : "This Mac is saved. Add another Mac to sync."
    }

    func syncNow() { runSync(refreshInventory: true) }

    private func backgroundSync() {
        checkForUpdates()
        guard autoSync, !isApplying else { return }
        runSync(refreshInventory: Date().timeIntervalSince(lastInventoryRefresh) > Self.inventoryInterval)
    }

    private var pollingDock = false
    private var pollTicks = 0
    private func pollDock() {
        guard autoSync, !isApplying, !pollingDock else { return }
        // Every 3 seconds with the sync window open, every 15 otherwise.
        pollTicks += 1
        if !ReviewWindow.shared.isVisible, pollTicks % 5 != 0 { return }
        pollingDock = true
        let engine = engine
        Task {
            let print = await Task.detached { engine.dockFingerprintNow() }.value
            pollingDock = false
            guard let print else { return }
            if let last = lastDockFingerprint, last != print { runSync(refreshInventory: false) }
            lastDockFingerprint = print
        }
    }

    /// A sync asked for while one was running; it runs as soon as that one ends, so the result
    /// shows what the person just changed.
    private var resyncWanted = false
    private var resyncInventory = false

    private func runSync(refreshInventory: Bool) {
        guard !isSyncing else {
            resyncWanted = true
            resyncInventory = resyncInventory || refreshInventory
            return
        }
        isSyncing = true
        let engine = engine
        Task {
            let result = await Task.detached { Result { try engine.sync(refreshInventory: refreshInventory) } }.value
            isSyncing = false
            switch result {
            case .success(let overview):
                self.overview = overview
                self.selectedApps = Set(overview.selectedApps)
                self.errorMessage = nil
                if refreshInventory { lastInventoryRefresh = Date() }
                trimDockEdits(overview)
                applyDockAfterWakeIfWanted(overview)
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
            if resyncWanted {
                let inventory = resyncInventory
                resyncWanted = false
                resyncInventory = false
                runSync(refreshInventory: inventory)
            }
        }
    }

    /// After a wake, with the setting on: applies Dock changes from the other Macs by itself.
    /// Only the Dock. Settings and apps still wait for the person, and so does anything they
    /// were arranging in the sync window.
    private func applyDockAfterWakeIfWanted(_ overview: SyncOverview) {
        guard autoApplyDock, let until = applyDockUntil, Date() < until, let plan = overview.dockPlan,
              !isApplying, dockArrangement == nil, dockRemovals.isEmpty, getting.isEmpty, removing.isEmpty else { return }
        applyDockUntil = nil
        isApplying = true
        let engine = engine
        Task {
            let result = await Task.detached {
                Result { try engine.apply(ApplyRequest(applyDock: true, apps: [], applySettings: false)) }
            }.value
            isApplying = false
            switch result {
            case .success(let report) where report.dockChanged:
                autoApplyMessage = "Dock updated from \(plan.sourceMachine) when you opened the lid. Undo Last Apply puts it back."
            case .success: break
            case .failure(let error): actionError = error.localizedDescription
            }
            runSync(refreshInventory: false)
        }
    }

    /// Drops marks for Dock items that are no longer in the combined Dock.
    private func trimDockEdits(_ overview: SyncOverview) {
        let plan = overview.dockPlan ?? overview.dockPreview
        let keys = Set(((plan?.targetApps ?? []) + (plan?.targetOthers ?? [])).map(\.key))
        dockRemovals = dockRemovals.intersection(keys)
        if let order = dockArrangement {
            let apps = (plan?.targetApps ?? []).map(\.key)
            let kept = order.filter { apps.contains($0) }
            dockArrangement = kept.isEmpty || kept == apps ? nil : kept
        }
    }

    /// A failed Apply, Undo or setting. Kept until the next action, so a sync doesn't wipe it.
    @Published var actionError: String?

    func setSelected(_ token: String, _ selected: Bool) {
        if selected { selectedApps.insert(token) } else { selectedApps.remove(token) }
        let engine = engine, chosen = selectedApps
        Task.detached { try? engine.setSelectedApps(chosen) }
    }

    func toggleDockRemoval(_ key: String) {
        if dockRemovals.contains(key) { dockRemovals.remove(key) } else { dockRemovals.insert(key) }
    }

    /// Ticks or unticks several apps at once (a whole group).
    func setSelected(_ tokens: [String], _ selected: Bool) {
        if selected { selectedApps.formUnion(tokens) } else { selectedApps.subtract(tokens) }
        let engine = engine, chosen = selectedApps
        Task.detached { try? engine.setSelectedApps(chosen) }
    }

    /// The app's own icon, shared through iCloud by the Mac that has it.
    /// The app on another Mac that a Dock item stands for, matched by bundle ID.
    func missingApp(for item: DockItem) -> MissingApp? {
        let apps = overview?.missingApps ?? []
        if let id = item.bundleID,
           let match = apps.first(where: { $0.detail?.bundleID == id || ($0.app.source == .direct && $0.app.name == id) }) {
            return match
        }
        // A Mac on an older MacSync sends no bundle IDs: match by name, so Xcode in the Dock is
        // the Xcode in the App Store list.
        let label = item.label.lowercased()
        return apps.first { $0.displayName.lowercased() == label || ($0.app.source == .appStore && $0.app.name.lowercased() == label) }
    }

    func name(for item: DockItem) -> String {
        missingApp(for: item)?.displayName ?? item.label
    }

    func icon(for missing: MissingApp) -> NSImage? {
        if let id = missing.detail?.iconID, let image = cachedIcon(id) { return image }
        if let image = missing.detail?.bundleID.flatMap({ cachedIcon(IconStore.id(bundleID: $0)) }) { return image }
        // The icon a Mac saved when it had the app as a download (the Craft apps, by bundle ID).
        if let id = missing.detail?.bundleID, let image = cachedIcon(IconStore.id(for: AppRef(source: .direct, name: id))) { return image }
        guard missing.app.source != .formula else { return nil }
        return webIcon(bundleID: missing.detail?.bundleID, name: missing.displayName, missing: missing)
    }

    /// Logos fetched from the App Store or the developer, by app, while the other Mac hasn't shared one.
    @Published private var webIcons: [String: NSImage] = [:]
    private var webIconsAsked: Set<String> = []

    private func webIcon(bundleID: String?, name: String, missing: MissingApp?) -> NSImage? {
        let key = bundleID ?? name
        if let image = webIcons[key] { return image }
        guard !webIconsAsked.contains(key) else { return nil }
        webIconsAsked.insert(key)
        let engine = engine
        Task {
            let url = await Task.detached { engine.webIcon(bundleID: bundleID, name: name, missing: missing) }.value
            if let url, let image = NSImage(contentsOf: url) { webIcons[key] = image }
        }
        return nil
    }

    private func cachedIcon(_ id: String) -> NSImage? {
        if let cached = iconCache[id] { return cached }
        guard let url = iconStore.url(for: id) else { return nil }
        guard let image = NSImage(contentsOf: url) else {
            // Still in iCloud only: fetch it, and it shows on the next refresh.
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return nil
        }
        iconCache[id] = image
        return image
    }

    var appsToInstall: [AppRef] {
        (overview?.missingApps ?? []).map(\.app).filter { selectedApps.contains($0.token) }
    }

    var canApply: Bool {
        !isApplying && getting.isEmpty && removing.isEmpty && (pendingAppPrefs != nil || pendingExcludedSettings != nil || (applyDock && (overview?.dockPlan != nil || !dockRemovals.isEmpty || dockArrangement != nil)) || (applySettings && overview?.settingsPlan != nil)
)
    }

    /// Apps being fetched one at a time from the list, and how each one went.
    @Published var getting: Set<String> = []
    @Published var gotten: [String: InstallResult] = [:]
    private var getQueue: [MissingApp] = []

    /// Hides an app this Mac doesn't need, or brings it back. Remembered across syncs.
    func setSkipped(_ app: MissingApp, _ skipped: Bool) { setSkipped(token: app.app.token, skipped) }

    func setSkipped(token: String, _ skipped: Bool) { setSkipped(tokens: [token], skipped) }

    func setSkipped(tokens: [String], _ skipped: Bool) {
        let engine = engine
        Task { _ = await Task.detached { try? engine.setSkipped(tokens, skipped) }.value; runSync(refreshInventory: false) }
        skippedDock = skipped ? skippedDock.union(tokens) : skippedDock.subtracting(tokens)
        guard var current = overview else { return }
        current.skippedApps.removeAll { tokens.contains($0) }
        if skipped { current.skippedApps += tokens }
        overview = current
    }

    /// A Dock item's key for "not needed": its app's when MacSync knows it, else its bundle ID.
    func skipToken(for item: DockItem) -> String {
        missingApp(for: item)?.app.token ?? "dock:\(item.bundleID ?? item.label)"
    }

    func isSkipped(_ item: DockItem) -> Bool {
        let token = skipToken(for: item)
        return overview?.skippedApps.contains(token) == true || skippedDock.contains(token)
    }

    @Published private var skippedDock: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "skippedDock") ?? []) {
        didSet { UserDefaults.standard.set(Array(skippedDock), forKey: "skippedDock") }
    }

    /// Opens where the person can get a Dock app this Mac doesn't have.
    func openDownloadPage(for item: DockItem) {
        let engine = engine
        let missing = missingApp(for: item)
        let name = name(for: item)
        Task {
            let url = await Task.detached { engine.downloadPage(bundleID: item.bundleID, name: name, missing: missing) }.value
            if let url { NSWorkspace.shared.open(url) }
        }
    }

    /// Where each app goes, when the person chose a folder for it (by app token).
    private var installFolders: [String: URL] = [:]

    /// Asks where a group of apps should go, remembering the answer for that group.
    func chooseFolder(for familyID: String, name: String) -> URL? {
        let key = "installFolder." + familyID
        let panel = NSOpenPanel()
        panel.title = "Where should the \(name) apps go?"
        panel.message = "Choose a folder for the \(name) apps. You can make a new one, like Applications/\(name)."
        panel.prompt = "Install Here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = UserDefaults.standard.url(forKey: key) ?? URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        UserDefaults.standard.set(url, forKey: key)
        return url
    }

    // MARK: ArtCraft

    @Published var craftApps: [CraftApp] = []
    @Published var craftLoading = false
    @Published var craftBusy: Set<String> = []
    @Published var craftErrors: [String: String] = [:]

    /// A Craft app's icon: from the app when it's installed, otherwise the one a Mac saved to iCloud.
    func craftIcon(_ app: CraftApp) -> NSImage? {
        if let path = app.installedPath { return NSWorkspace.shared.icon(forFile: path) }
        if let image = craftIcons[app.id] { return image }
        guard app.iconURL != nil, !craftIconsAsked.contains(app.id) else { return nil }
        craftIconsAsked.insert(app.id)
        let engine = engine
        Task {
            let url = await Task.detached { engine.craftIconFile(app) }.value
            if let url, let image = NSImage(contentsOf: url) { craftIcons[app.id] = image }
        }
        return nil
    }

    @Published private var craftIcons: [String: NSImage] = [:]
    private var craftIconsAsked: Set<String> = []

    func loadCraft(refresh: Bool = false) {
        guard !craftLoading else { return }
        craftLoading = true
        let engine = engine
        Task {
            let apps = await Task.detached { engine.craftApps(refresh: refresh) }.value
            craftLoading = false
            if !apps.isEmpty { craftApps = apps }
        }
    }

    /// Installs or updates Craft apps from ArtCraft's downloads, then refreshes the list.
    func installCraft(_ apps: [CraftApp]) {
        let fresh = apps.filter { !craftBusy.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for app in fresh { craftBusy.insert(app.id); craftErrors[app.id] = nil }
        let engine = engine
        Task {
            let results = await Task.detached { () -> [(CraftApp, Result<String, EngineError>)] in
                engine.installCraftAgain(fresh)
                return engine.installCraft(fresh)
            }.value
            for (app, result) in results {
                craftBusy.remove(app.id)
                if case .failure(let error) = result { craftErrors[app.id] = error.localizedDescription }
            }
            craftLoading = false
            loadCraft()
            syncNow()
        }
    }

    func removeCraft(_ apps: [CraftApp], everywhere: Bool = false) {
        let fresh = apps.filter { !craftBusy.contains($0.id) && $0.isInstalled }
        guard !fresh.isEmpty else { return }
        for app in fresh { craftBusy.insert(app.id); craftErrors[app.id] = nil }
        let engine = engine
        Task {
            let results = await Task.detached { engine.removeCraft(fresh, everywhere: everywhere) }.value
            for (app, result) in results {
                craftBusy.remove(app.id)
                if case .failure(let error) = result { craftErrors[app.id] = error.localizedDescription }
            }
            loadCraft()
            syncNow()
        }
    }

    /// Apps to open once they are installed (ArtCraft Launcher, so it can install the rest).
    private var openAfter: [String: String] = [:]

    func get(_ apps: [MissingApp], thenOpen bundleID: String) {
        for app in apps { openAfter[app.app.token] = bundleID }
        get(apps)
    }

    func openApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func get(_ apps: [MissingApp], into folder: URL) {
        for app in apps { installFolders[app.app.token] = folder }
        get(apps)
    }

    func get(_ apps: [MissingApp]) {
        let fresh = apps.filter { $0.canInstall && !getting.contains($0.app.token) && gotten[$0.app.token]?.outcome != .installed
                                  && gotten[$0.app.token]?.outcome != .downloaded }
        guard !fresh.isEmpty else { return }
        for app in fresh { getting.insert(app.app.token); gotten[app.app.token] = nil }
        let wasIdle = getQueue.isEmpty
        getQueue += fresh
        if wasIdle { getNext() }
    }

    private func getNext() {
        guard let next = getQueue.first else { syncNow(); return }
        let engine = engine
        progress = "Getting \(next.displayName)…"
        Task {
            let folder = installFolders.removeValue(forKey: next.app.token)
            let result = await Task.detached { engine.getApp(next, into: folder) }.value
            getQueue.removeFirst()
            getting.remove(next.app.token)
            gotten[next.app.token] = result
            if result.outcome == .installed, let bundleID = openAfter.removeValue(forKey: next.app.token) {
                // LaunchServices may need a moment to notice the new app.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.openApp(bundleID: bundleID) }
            }
            progress = nil
            getNext()
        }
    }

    /// Set to open the sync window at its History section.
    @Published var showHistory = false

    func setDockOrder(_ machineID: String?) {
        let engine = engine
        Task { _ = await Task.detached { try? engine.setDockOrder(machineID: machineID) }.value; syncNow() }
    }

    // MARK: Removing and sharing

    @Published var removing: Set<String> = []
    @Published var removeResults: [String: InstallResult] = [:]

    func removeEverywhere(_ app: MissingApp) { runRemoval([app]) { engine, apps in engine.removeEverywhere(apps) } }
    func uninstallHere(_ apps: [MissingApp]) { runRemoval(apps) { engine, apps in engine.uninstallHere(apps) } }

    private func runRemoval(_ apps: [MissingApp], _ work: @escaping @Sendable (Engine, [MissingApp]) -> [InstallResult]) {
        let fresh = apps.filter { !removing.contains($0.app.token) }
        guard !fresh.isEmpty else { return }
        for app in fresh { removing.insert(app.app.token); removeResults[app.app.token] = nil }
        let engine = engine
        Task {
            let results = await Task.detached { work(engine, fresh) }.value
            for result in results { removeResults[result.app.token] = result }
            for app in fresh { removing.remove(app.app.token) }
            syncNow()
        }
    }

    func keepHere(_ app: MissingApp) {
        let engine = engine, token = app.app.token
        if var current = overview { current.toRemove.removeAll { $0.app.token == token }; overview = current }
        Task { _ = await Task.detached { try? engine.keepHere(token) }.value; runSync(refreshInventory: false) }
    }

    func cancelRemoval(_ token: String) {
        let engine = engine
        Task { _ = await Task.detached { try? engine.cancelRemoval(token) }.value; syncNow() }
    }

    func setShared(_ tokens: [String], _ shared: Bool) {
        if var current = overview {
            current.unshared.removeAll { tokens.contains($0) }
            if !shared { current.unshared += tokens }
            overview = current
        }
        let engine = engine
        Task { _ = await Task.detached { try? engine.setShared(tokens, shared) }.value; runSync(refreshInventory: false) }
    }

    /// Opens a downloaded installer again, or shows it in Finder if it's gone from where it was.
    func openDownload(_ result: InstallResult) {
        guard let path = result.path else { return }
        if FileManager.default.fileExists(atPath: path) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        else { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) }
    }

    func apply() {
        guard canApply else { return }
        isApplying = true
        lastReport = nil
        undoMessage = nil
        actionError = nil
        let request = ApplyRequest(applyDock: applyDock, apps: [], applySettings: applySettings,
                                   removeFromDock: Array(dockRemovals), dockOrder: dockArrangement)
        let wantsMore = (applyDock && (overview?.dockPlan != nil || !dockRemovals.isEmpty || dockArrangement != nil))
            || (applySettings && overview?.settingsPlan != nil)
        let appPrefs = pendingAppPrefs.map { Array($0).sorted() }
        let excluded = pendingExcludedSettings.map { Array($0).sorted() }
        let engine = engine
        Task {
            let result: Result<ApplyReport, Error> = await Task.detached {
                Result {
                    // App settings first: which apps' settings this Mac shares with the others.
                    if let appPrefs { try engine.setAppPrefDomains(appPrefs) }
                    if let excluded { try engine.setExcludedSettings(excluded) }
                    guard wantsMore else {
                        return ApplyReport(restorePoint: nil, dockChanged: false, skippedDockItems: [], results: [])
                    }
                    return try engine.apply(request) { message in
                        Task { @MainActor [weak self] in self?.progress = message }
                    }
                }
            }.value
            if case .success = result { pendingAppPrefs = nil; pendingExcludedSettings = nil }
            isApplying = false
            progress = nil
            switch result {
            case .success(let report): lastReport = report; dockRemovals = []; dockArrangement = nil
            case .failure(let error): actionError = error.localizedDescription
            }
            syncNow()
        }
    }

    /// Puts this Mac back to just before a past Apply.
    func restore(_ point: RestorePointInfo) {
        let engine = engine
        actionError = nil
        autoApplyMessage = nil
        isApplying = true
        progress = "Restoring…"
        Task {
            let result = await Task.detached { Result { try engine.restore(point.id) } }.value
            isApplying = false
            progress = nil
            switch result {
            case .success:
                lastReport = nil
                undoMessage = "Back to how this Mac was before \(point.createdAt.formatted(date: .abbreviated, time: .shortened)). Installed apps stay installed."
            case .failure(let error):
                actionError = error.localizedDescription
            }
            syncNow()
        }
    }

    func undo() {
        let engine = engine
        actionError = nil
        autoApplyMessage = nil
        isApplying = true
        progress = "Undoing…"
        Task {
            let result = await Task.detached { Result { try engine.undoLast() } }.value
            isApplying = false
            progress = nil
            switch result {
            case .success(let point):
                lastReport = nil
                let restored = point.touchedSettings == true && point.touchedDock == false ? "Your settings are back as they were."
                    : (point.touchedSettings == true ? "Your Dock and settings are back as they were." : "Your Dock is back as it was.")
                undoMessage = point.installed.isEmpty
                    ? restored
                    : "\(restored) Installed apps stay installed: \(point.installed.joined(separator: ", "))."
            case .failure(let error):
                actionError = error.localizedDescription
            }
            syncNow()
        }
    }

    func appPrefDomains() -> [String] { engine.appPrefDomains() }
    func currentSettings() -> [SettingsChange] { engine.currentSettings() }
    func availableAppPrefDomains() -> [String] { engine.availableAppPrefDomains() }
    /// System settings switched off (kept to this Mac) in the window, not applied yet.
    @Published var pendingExcludedSettings: Set<String>?

    var excludedSettingsChosen: Set<String> { pendingExcludedSettings ?? Set(overview?.excludedSettings ?? []) }

    func setSettingSynced(_ ids: [String], _ on: Bool) {
        var next = excludedSettingsChosen
        if on { next.subtract(ids) } else { next.formUnion(ids) }
        pendingExcludedSettings = next == Set(overview?.excludedSettings ?? []) ? nil : next
    }

    /// App settings switches flipped in the window but not applied yet.
    @Published var pendingAppPrefs: Set<String>?

    var appPrefsChosen: Set<String> { pendingAppPrefs ?? Set(overview?.appPrefDomains ?? appPrefDomains()) }

    func setAppPref(_ domains: [String], _ on: Bool) {
        var next = appPrefsChosen
        if on { next.formUnion(domains) } else { next.subtract(domains) }
        pendingAppPrefs = next == Set(overview?.appPrefDomains ?? appPrefDomains()) ? nil : next
    }

    func setAppPrefDomains(_ domains: [String]) {
        if var current = overview { current.appPrefDomains = domains.sorted(); overview = current }
        let engine = engine
        Task { _ = await Task.detached { try? engine.setAppPrefDomains(domains) }.value; runSync(refreshInventory: false) }
    }
    var proEnabled: Bool { overview?.proEnabled ?? ProLicense.isUnlocked }

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            actionError = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    func icon(for item: DockItem) -> NSImage? {
        switch item.kind {
        case .spacer: return nil
        case .url: return NSImage(systemSymbolName: "globe", accessibilityDescription: item.label)
        case .app, .file, .folder:
            if let path = Planner.resolve(item, locator: locator) { return NSWorkspace.shared.icon(forFile: path) }
            // Not on this Mac: use the icon the other Mac synced for that app.
            if let image = missingApp(for: item).flatMap({ icon(for: $0) }) { return image }
            if let image = item.bundleID.flatMap({ cachedIcon(IconStore.id(bundleID: $0)) }) { return image }
            return webIcon(bundleID: item.bundleID, name: name(for: item), missing: missingApp(for: item))
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard autoSync else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.backgroundSync() }
        }
    }

    // MARK: Updates

    private var updater: SelfUpdater {
        SelfUpdater(runner: SystemCommandRunner(), brewPath: MacSyncEnvironment.current().brewPath, appURL: Bundle.main.bundleURL)
    }

    /// Looks for a new release once a day, or now when asked. With automatic updates on, a
    /// release is installed straight away unless a MacSync window is open.
    private var updateObservers: [NSObjectProtocol] = []

    /// A few seconds after the Mac comes back, once the network is up again.
    private func checkForUpdatesSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.checkForUpdates() }
    }

    /// The sync window closed: an update that waited for it can go in now.
    func syncWindowClosed() {
        if let update = availableUpdate, autoUpdate, !isUpdating, !isApplying { installUpdate(update) }
    }

    func checkForUpdates(manual: Bool = false) {
        guard !isUpdating, manual || Date().timeIntervalSince(lastUpdateCheck) > Self.updateInterval else { return }
        // A build run from the project folder isn't an installed copy, so it never replaces itself.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        lastUpdateCheck = Date()
        let updater = updater
        Task.detached {
            let release = updater.check()
            await MainActor.run {
                self.availableUpdate = release
                if manual { self.updateMessage = release == nil ? "MacSync \(MacSyncEnvironment.appVersion) is the latest version." : nil }
                if let release, self.autoUpdate, !NSApp.windows.contains(where: { $0.isVisible && $0.level == .normal }) {
                    self.installUpdate(release)
                }
            }
        }
    }

    func installUpdate(_ release: SelfUpdater.Release) {
        guard !isUpdating else { return }
        isUpdating = true
        updateMessage = "Updating to MacSync \(release.version)…"
        let updater = updater
        Task.detached {
            let result = updater.install(release)
            await MainActor.run {
                self.isUpdating = false
                switch result {
                case .success: Self.relaunch()
                case .failure(let error): self.updateMessage = error.localizedDescription
                }
            }
        }
    }

    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // A moment's wait, so whatever is replacing the app has finished.
        task.arguments = ["-c", "sleep 3; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}


/// Opens MacSync's windows from links, for Raycast and the command line:
/// macsync://review (or macsync://open), macsync://history, macsync://sync.
@MainActor
final class URLHandler: NSObject {
    static let shared = URLHandler()
    weak var model: AppModel?

    @objc func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text), url.scheme == "macsync", let model else { return }
        switch url.host ?? url.path {
        case "history":
            model.showHistory = true
            ReviewWindow.shared.show(model: model)
        case "sync":
            model.syncNow()
        default:
            ReviewWindow.shared.show(model: model)
        }
    }
}
