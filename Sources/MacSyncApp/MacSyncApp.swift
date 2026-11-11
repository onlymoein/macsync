import AppKit
import MacSyncCore
import SwiftUI

@main
struct MacSyncApp: App {
    @StateObject private var model = AppModel()

    /// The copy that draws the website's pictures stays out of the menu bar.
    @State private var inMenuBar = ProcessInfo.processInfo.environment["MACSYNC_UI_PROBE"] == nil

    var body: some Scene {
        MenuBarExtra(isInserted: $inMenuBar) {
            MenuView(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel("MacSync")
        }
        .menuBarExtraStyle(.window)
    }
}

/// The review window lives in AppKit because a SwiftUI Window scene would open itself at launch.
@MainActor
final class ReviewWindow {
    static let shared = ReviewWindow()
    private var window: NSWindow?
    var isVisible: Bool { window?.isVisible == true }

    func show(model: AppModel) {
        // Every section starts folded each time the window opens; you open what you want.
        if window?.isVisible != true {
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("review.") && key.hasSuffix(".open") {
                defaults.set(false, forKey: key)
            }
            for key in ReviewWindow.sectionKeys { defaults.set(false, forKey: key) }
        }
        if window == nil {
            let host = NSHostingController(rootView: ReviewView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "Sync"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // Off: dragging Dock icons in the window must not move the window.
            window.isMovableByWindowBackground = false
            window.setContentSize(NSSize(width: 680, height: 720))
            window.contentMinSize = NSSize(width: 560, height: 460)
            window.isReleasedWhenClosed = false
            window.center()
            // Closing the window lets an update that was waiting for it go in.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak model] _ in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    model?.syncWindowClosed()
                }
            }
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    static let sectionKeys = ["dock", "notInstalled", "artcraft", "apps", "appStore", "tools", "thisMac", "thisMacTools", "toRemove",
                              "extrasRemoved", "settings", "appSettings", "history", "homebrew", "signIn", "loginItems", "packages",
                              "files.config", "files.ai", "files.appData"].map { "review.\($0).open" }
}
