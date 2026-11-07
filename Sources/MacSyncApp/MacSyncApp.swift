import AppKit
import MacSyncCore
import SwiftUI

@main
struct MacSyncApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
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

    func show(model: AppModel) {
        if window == nil {
            let host = NSHostingController(rootView: ReviewView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "Review Changes"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 640, height: 640))
            window.contentMinSize = NSSize(width: 520, height: 420)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}
