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
        if !overview.missingApps.isEmpty {
            let count = overview.missingApps.count
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
    func icon(for missing: MissingApp) -> NSImage? {
        guard let id = missing.detail?.iconID else { return nil }
        if let cached = iconCache[id] { return cached }
        guard let url = iconStore.url(for: id), let image = NSImage(contentsOf: url) else { return nil }
        iconCache[id] = image
        return image
    }

    var appsToInstall: [AppRef] {
        (overview?.missingApps ?? []).map(\.app).filter { selectedApps.contains($0.token) }
    }

    var canApply: Bool {
        !isApplying && ((applyDock && (overview?.dockPlan != nil || !dockRemovals.isEmpty)) || (applySettings && overview?.settingsPlan != nil)
                        || !appsToInstall.isEmpty)
    }

    func apply() {
        guard canApply else { return }
        isApplying = true
        lastReport = nil
        undoMessage = nil
        errorMessage = nil
        let request = ApplyRequest(applyDock: applyDock, apps: appsToInstall, applySettings: applySettings,
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
            guard let path = Planner.resolve(item, locator: locator) else { return nil }
            return NSWorkspace.shared.icon(forFile: path)
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
