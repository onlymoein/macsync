#if UIPROBE
import AppKit
import MacSyncCore
import SwiftUI

/// Test builds only (UIPROBE=1 scripts/build-app.sh). Walks the app through review, apply and
/// undo, and writes what each screen really renders. Never compiled into a shipped build.
@MainActor
enum UIProbe {
    static func runIfRequested(model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["MACSYNC_UI_PROBE"] else { return }
        let selection = ProcessInfo.processInfo.environment["MACSYNC_UI_PROBE_SELECT"]?.split(separator: ",").map(String.init) ?? []
        Task {
            await settle(model)
            NSApp.appearance = NSAppearance(named: ProcessInfo.processInfo.environment["MACSYNC_UI_PROBE_DARK"] != nil ? .darkAqua : .aqua)
            for token in selection { model.setSelected(token, true) }
            ReviewWindow.shared.show(model: model)
            try? await Task.sleep(nanoseconds: 800_000_000)
            shoot(dir, "1-review", "1-menu", model)
            print("before: canApply=\(model.canApply) status=\(model.statusLine)")
            model.apply()
            await settle(model)
            try? await Task.sleep(nanoseconds: 800_000_000)
            shoot(dir, "2-review-after-apply", "2-menu-after-apply", model)
            print("after apply: report=\(String(describing: model.lastReport?.dockChanged)) status=\(model.statusLine)")
            model.undo()
            await settle(model)
            try? await Task.sleep(nanoseconds: 800_000_000)
            shoot(dir, "3-review-after-undo", "3-menu-after-undo", model)
            print("after undo: \(model.undoMessage ?? "-") status=\(model.statusLine)")
            NSApp.terminate(nil)
        }
    }

    private static func settle(_ model: AppModel) async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        while model.isSyncing || model.isApplying || model.overview == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private static func shoot(_ dir: String, _ review: String, _ menu: String, _ model: AppModel) {
        if let view = NSApp.windows.first(where: { $0.title == "Review Changes" })?.contentView { write(view, dir, review) }
        let host = NSHostingView(rootView: MenuView(model: model))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.appearance = NSApp.appearance
        host.layoutSubtreeIfNeeded()
        write(host, dir, menu)
    }

    private static func write(_ view: NSView, _ dir: String, _ name: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }
}
#endif
