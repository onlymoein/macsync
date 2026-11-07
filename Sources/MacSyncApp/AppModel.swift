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
    @Published var selectedApps: Set<String> = []
    @Published var autoSync: Bool {
        didSet {
            UserDefaults.standard.set(autoSync, forKey: "autoSync")
            scheduleTimer()
        }
    }
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled

    private let engine = Engine.live()
    private let locator = SystemAppLocator()
    private var timer: Timer?
    private var lastInventoryRefresh = Date.distantPast
    private var wakeObserver: NSObjectProtocol?

    private static let syncInterval: TimeInterval = 5 * 60
    private static let inventoryInterval: TimeInterval = 30 * 60

    init() {
        autoSync = UserDefaults.standard.object(forKey: "autoSync") as? Bool ?? true
        scheduleTimer()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.backgroundSync() }
        }
        syncNow()
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
            return "New Dock layout from \(plan.sourceMachine)"
        }
        if !overview.missingApps.isEmpty {
            let count = overview.missingApps.count
            return "\(count) app\(count == 1 ? "" : "s") on your other Macs"
        }
        return overview.machines.count > 1 ? "Your Macs match" : "This Mac is saved. Add another Mac to sync."
    }

    func syncNow() { runSync(refreshInventory: true) }

    private func backgroundSync() {
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

    var appsToInstall: [AppRef] {
        (overview?.missingApps ?? []).map(\.app).filter { selectedApps.contains($0.token) }
    }

    var canApply: Bool {
        !isApplying && ((applyDock && overview?.dockPlan != nil) || !appsToInstall.isEmpty)
    }

    func apply() {
        guard canApply else { return }
        isApplying = true
        lastReport = nil
        undoMessage = nil
        errorMessage = nil
        let request = ApplyRequest(applyDock: applyDock, apps: appsToInstall)
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
            case .success(let report): lastReport = report
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
                undoMessage = point.installed.isEmpty
                    ? "Your Dock is back as it was."
                    : "Your Dock is back as it was. Installed apps stay installed: \(point.installed.joined(separator: ", "))."
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            syncNow()
        }
    }

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
}
