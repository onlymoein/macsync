import AppKit
import SwiftUI

/// Lets the person pick which apps' preferences sync. Passwords, tokens and keys never do.
struct AppPrefsView: View {
    @ObservedObject var model: AppModel
    @State private var chosen: Set<String> = []
    @State private var available: [String] = []
    @State private var search = ""

    private var shown: [String] {
        let all = Set(available).union(chosen).sorted()
        return search.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("App preferences").font(.headline)
                Text("Tick the apps whose preferences should match on all your Macs. Passwords, tokens, license keys and window positions are never copied.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Search", text: $search).textFieldStyle(.roundedBorder)
            List(shown, id: \.self) { domain in
                Toggle(domain, isOn: Binding(
                    get: { chosen.contains(domain) },
                    set: { isOn in
                        if isOn { chosen.insert(domain) } else { chosen.remove(domain) }
                        model.setAppPrefDomains(Array(chosen))
                    }))
                    .toggleStyle(.checkbox)
            }
            .listStyle(.bordered)
            Text("\(chosen.count) chosen. Review and Apply still ask before anything changes on a Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 420)
        .onAppear {
            chosen = Set(model.appPrefDomains())
            available = model.availableAppPrefDomains()
        }
    }
}

@MainActor
final class AppPrefsWindow {
    static let shared = AppPrefsWindow()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AppPrefsView(model: model)))
            window.title = "App Preferences"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 460, height: 480))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
