import AppKit
import SwiftUI

/// An app whose preferences can sync, as people know it: its name and icon.
private struct PrefApp: Identifiable {
    let domain: String
    let name: String
    let icon: NSImage?
    var id: String { domain }

    /// Only apps people open themselves: those in an Applications folder, not helpers,
    /// updaters and crash reporters that also keep preference files.
    static func find(_ domain: String) -> PrefApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: domain) else { return nil }
        let folders = ["/Applications/", "/System/Applications/", NSHomeDirectory() + "/Applications/"]
        let path = url.path
        guard folders.contains(where: { path.hasPrefix($0) }), !path.contains("/Contents/") else { return nil }
        let info = Bundle(url: url)?.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return PrefApp(domain: domain, name: name, icon: NSWorkspace.shared.icon(forFile: path))
    }
}

/// Lets the person pick which apps' preferences sync. Passwords, tokens and keys never do.
struct AppPrefsView: View {
    @ObservedObject var model: AppModel
    @State private var chosen: Set<String> = []
    @State private var apps: [PrefApp] = []
    @State private var search = ""

    private var shown: [PrefApp] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.domain.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("App settings").font(.title3.weight(.semibold))
                Text("Turn on the apps whose settings should match on all your Macs. Passwords, tokens, license keys and window positions are never copied.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Search apps", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(shown) { app in row(app) }
                }
                .padding(6)
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(chosen.isEmpty ? "None turned on yet. Nothing changes on a Mac until you review and apply."
                 : "\(chosen.count) on. Nothing changes on a Mac until you review and apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 460)
        .onAppear(perform: load)
    }

    private func row(_ app: PrefApp) -> some View {
        let isOn = Binding(
            get: { chosen.contains(app.domain) },
            set: { on in
                if on { chosen.insert(app.domain) } else { chosen.remove(app.domain) }
                model.setAppPrefDomains(Array(chosen))
            })
        return HStack(spacing: 12) {
            Group {
                if let icon = app.icon { Image(nsImage: icon).resizable().scaledToFit() }
                else { Image(systemName: "app.dashed").font(.title2).foregroundStyle(.secondary) }
            }
            .frame(width: 30, height: 30)
            Text(app.name).font(.body).lineLimit(1)
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { isOn.wrappedValue.toggle() }
        .help(app.domain)
    }

    private func load() {
        chosen = Set(model.appPrefDomains())
        let domains = Set(model.availableAppPrefDomains()).union(chosen)
        var found: [PrefApp] = []
        var names = Set<String>()
        for domain in domains.sorted() {
            if let app = PrefApp.find(domain) {
                // One row per app, even if it keeps several preference files.
                guard names.insert(app.name.lowercased()).inserted || chosen.contains(domain) else { continue }
                found.append(app)
            } else if chosen.contains(domain) {
                found.append(PrefApp(domain: domain, name: domain, icon: nil))
            }
        }
        apps = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class AppPrefsWindow {
    static let shared = AppPrefsWindow()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AppPrefsView(model: model)))
            window.title = "App Settings"
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
