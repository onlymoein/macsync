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
    @Published var autoUpdate: Bool {
        didSet { UserDefaults.standard.set(autoUpdate, forKey: "autoUpdate") }
    }
    private var lastUpdateCheck = Date.distantPast
    private static let updateInterval: TimeInterval = 24 * 3600

    private let engine = Engine.live()
    private let locator = SystemAppLocator()
    private let iconStore = IconStore(directory: MacSyncEnvironment.current().syncDirectory.appendingPathComponent("icons"))
    private var iconCache: [String: NSImage] = [:]
    private var timer: Timer?
    private var lastInventoryRefresh = Date.distantPast
    private var wakeObserver: NSObjectProtocol?

    private static let syncInterval: TimeInterval = 5 * 60
    private static let inventoryInterval: TimeInterval = 30 * 60

    init() {
        autoSync = UserDefaults.standard.object(forKey: "autoSync") as? Bool ?? true
        autoUpdate = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
        scheduleTimer()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.backgroundSync() }
        }
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
        if !overview.wantedApps.isEmpty {
            let count = overview.wantedApps.count
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

    private func runSync(refreshInventory: Bool) {
        guard !isSyncing else { return }
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
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func setSelected(_ token: String, _ selected: Bool) {
        if selected { selectedApps.insert(token) } else { selectedApps.remove(token) }
        try? engine.setSelectedApps(selectedApps)
    }

    func toggleDockRemoval(_ key: String) {
        if dockRemovals.contains(key) { dockRemovals.remove(key) } else { dockRemovals.insert(key) }
    }

    /// Ticks or unticks several apps at once (a whole group).
    func setSelected(_ tokens: [String], _ selected: Bool) {
        if selected { selectedApps.formUnion(tokens) } else { selectedApps.subtract(tokens) }
        try? engine.setSelectedApps(selectedApps)
    }

    /// The app's own icon, shared through iCloud by the Mac that has it.
    /// The app on another Mac that a Dock item stands for, matched by bundle ID.
    func missingApp(for item: DockItem) -> MissingApp? {
        guard let id = item.bundleID else { return nil }
        return overview?.missingApps.first { $0.detail?.bundleID == id || ($0.app.source == .direct && $0.app.name == id) }
    }

    func name(for item: DockItem) -> String {
        missingApp(for: item)?.displayName ?? item.label
    }

    func icon(for missing: MissingApp) -> NSImage? {
        if let id = missing.detail?.iconID, let image = cachedIcon(id) { return image }
        if let image = missing.detail?.bundleID.flatMap({ cachedIcon(IconStore.id(bundleID: $0)) }) { return image }
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
        !isApplying && ((applyDock && (overview?.dockPlan != nil || !dockRemovals.isEmpty)) || (applySettings && overview?.settingsPlan != nil)
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
        try? engine.setSkipped(tokens, skipped)
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
            let result = await Task.detached { engine.getApp(next) }.value
            getQueue.removeFirst()
            getting.remove(next.app.token)
            gotten[next.app.token] = result
            progress = nil
            getNext()
        }
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
        errorMessage = nil
        let request = ApplyRequest(applyDock: applyDock, apps: [], applySettings: applySettings,
                                   removeFromDock: Array(dockRemovals))
        let engine = engine
        Task {
            let result: Result<ApplyReport, Error> = await Task.detached {
                Result {
                    try engine.apply(request) { message in
                        Task { @MainActor [weak self] in self?.progress = message }
                    }
                }
            }.value
            isApplying = false
            progress = nil
            switch result {
            case .success(let report): lastReport = report; dockRemovals = []
            case .failure(let error): errorMessage = error.localizedDescription
            }
            syncNow()
        }
    }

    func undo() {
        let engine = engine
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
                errorMessage = error.localizedDescription
            }
            syncNow()
        }
    }

    func appPrefDomains() -> [String] { engine.appPrefDomains() }
    func availableAppPrefDomains() -> [String] { engine.availableAppPrefDomains() }
    func setAppPrefDomains(_ domains: [String]) {
        try? engine.setAppPrefDomains(domains)
        syncNow()
    }
    var proEnabled: Bool { overview?.proEnabled ?? ProLicense.isUnlocked }

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "Couldn't change Open at Login: \(error.localizedDescription)"
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

    private static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
