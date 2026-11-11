#if UIPROBE
import AppKit
import MacSyncCore
import SwiftUI

/// Test builds only (UIPROBE=1 scripts/build-app.sh). Drives the real views through review, apply
/// and undo, and writes what each renders as 2x images. Never compiled into a shipped build.
@MainActor
enum UIProbe {
    static func runIfRequested(model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        if env["MACSYNC_UI_PROBE_WAKE"] != nil {
            // Pretend the lid was just opened, then report what the Dock looks like a bit later.
            Task {
                await settle(model)
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await settle(model)
                print("after wake: \(model.autoApplyMessage ?? "no auto apply") error=\(model.actionError ?? "-")")
                NSApp.terminate(nil)
            }
            return
        }
        guard let dir = env["MACSYNC_UI_PROBE"] else { return }
        let suffix = env["MACSYNC_UI_PROBE_DARK"] != nil ? "dark" : "light"
        let height = CGFloat(Double(env["MACSYNC_UI_PROBE_HEIGHT"] ?? "") ?? 900)
        Task {
            await settle(model)
            NSApp.appearance = NSAppearance(named: suffix == "dark" ? .darkAqua : .aqua)
            let wanted = env["MACSYNC_UI_PROBE_SELECT"] ?? ""
            let tokens = wanted == "all" ? (model.overview?.missingApps.map(\.app.token) ?? []) : wanted.split(separator: ",").map(String.init)
            for token in tokens { model.setSelected(token, true) }
            try? await Task.sleep(nanoseconds: 500_000_000)
            shoot(dir, "review-\(suffix)", "menu-\(suffix)", model, height)
            print("before: canApply=\(model.canApply) status=\(model.statusLine)")
            if env["MACSYNC_UI_PROBE_NOAPPLY"] == nil {
                model.apply()
                await settle(model)
                try? await Task.sleep(nanoseconds: 800_000_000)
                shoot(dir, "applied-\(suffix)", "menu-applied-\(suffix)", model, height)
                print("after apply: dock=\(String(describing: model.lastReport?.dockChanged)) settings=\(String(describing: model.lastReport?.settingsChanged)) status=\(model.statusLine)")
                model.undo()
                await settle(model)
                print("after undo: \(model.undoMessage ?? "-") status=\(model.statusLine)")
            }
            NSApp.terminate(nil)
        }
    }

    private static func settle(_ model: AppModel) async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        while model.isSyncing || model.isApplying || model.overview == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private static func shoot(_ dir: String, _ review: String, _ menu: String, _ model: AppModel, _ height: CGFloat) {
        let background = Color(nsColor: .windowBackgroundColor)
        write(ReviewView(model: model).frame(width: 680, height: height).background(background), dir, review)
        write(MenuView(model: model).background(background), dir, menu)
        write(AppPrefsView(model: model).frame(width: 460, height: 560).background(background), dir, "appsettings-" + menu)
    }

    private static func write<V: View>(_ view: V, _ dir: String, _ name: String) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.appearance = NSApp.appearance
        host.layoutSubtreeIfNeeded()
        let bounds = host.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = bounds.size
        host.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }
}
#endif
