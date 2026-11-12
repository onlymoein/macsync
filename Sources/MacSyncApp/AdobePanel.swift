import AppKit
import MacSyncCore
import SwiftUI

extension AppModel {
    /// Reads Adobe's uninstall records again (a file listing, so it's quick).
    func refreshAdobe() {
        guard env_isRealMac else { return }
        let adobe = AdobeApps()
        adobeApps = adobe.installed()
        adobeOlder = adobe.olderVersions()
        adobeHasUpdater = adobe.hasUpdater
    }

    /// A probe or demo Mac has none of this Mac's Adobe apps.
    private var env_isRealMac: Bool { ProcessInfo.processInfo.environment["MACSYNC_DOCK_FILE"] == nil }

    /// Asks once, naming what goes and what stays, then removes the versions one by one.
    func removeOlderAdobe(_ only: [AdobeProduct]? = nil) {
        let older = only ?? adobeOlder
        guard adobeBusy == nil, !older.isEmpty else { return }
        let names = older.map(\.label)
        let open = AdobeApps.running()
        let alert = NSAlert()
        alert.messageText = "Remove \(ListFormatter.localizedString(byJoining: names))?"
        let kept = adobeApps.filter { app in older.contains { $0.sapCode == app.sapCode } && !older.contains(app) }.map(\.label)
        alert.informativeText = (kept.isEmpty ? "" : "\(ListFormatter.localizedString(byJoining: kept)) stays. ")
            + "Adobe's installer removes the older version and keeps your settings. macOS asks for your password."
            + (open.isEmpty ? "" : "\n\nQuit \(ListFormatter.localizedString(byJoining: open)) first.")
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        adobeBusy = "Removing \(older[0].label)…"
        Task { @MainActor in
            var notes: [String] = []
            for product in older {
                adobeBusy = "Removing \(product.label) with Adobe's installer…"
                let result = await Blocking { AdobeApps().remove(product) }.value
                switch result {
                case .success(.removed): notes.append("Removed \(product.label)")
                case .success(.openedAdobesUninstaller): notes.append("Adobe's uninstaller opened for \(product.label)")
                case .failure(let error): notes.append(error.localizedDescription)
                }
                if case .failure = result { break }
            }
            adobeBusy = nil
            adobeMessage = notes.joined(separator: " · ")
            refreshAdobe()
        }
    }

    /// Company installs: Adobe's updater, after one password. Personal plans: Creative Cloud.
    func updateAdobe() {
        guard adobeBusy == nil else { return }
        guard adobeHasUpdater else { AdobeApps.openCreativeCloud(); return }
        let open = AdobeApps.running()
        guard open.isEmpty else { adobeMessage = "Quit \(ListFormatter.localizedString(byJoining: open)) first, then update."; return }
        adobeBusy = "Updating Adobe apps…"
        Task { @MainActor in
            let result = await Blocking { AdobeApps().updateAll() }.value
            adobeBusy = nil
            switch result {
            case .success(let note): adobeMessage = note
            case .failure(let error): adobeMessage = error.localizedDescription
            }
            refreshAdobe()
        }
    }
}

/// The sync window's Adobe section: every Adobe app with its version, Remove on an older yearly
/// version, and Update (Adobe's updater on company installs, Creative Cloud on personal plans).
struct AdobePanel: View {
    @ObservedObject var model: AppModel
    @AppStorage("review.adobe.open") private var open = false

    var body: some View {
        if !model.adobeApps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "paintbrush.pointed.fill", title: "Adobe apps", subtitle: subtitle, isExpanded: $open) {
                    if model.adobeBusy != nil {
                        ProgressView().controlSize(.small)
                    } else {
                        if model.adobeOlder.count > 1 {
                            Button("Remove Older (\(model.adobeOlder.count))") { model.removeOlderAdobe() }.glassButton().controlSize(.small)
                        }
                        Button(model.adobeHasUpdater ? "Update All" : "Update in Creative Cloud") { model.updateAdobe() }
                            .primaryGlassButton().controlSize(.small)
                            .help(model.adobeHasUpdater ? "Install every Adobe update with Adobe's updater; macOS asks for your password once"
                                                        : "On a personal plan, Creative Cloud installs Adobe's updates. Turn on Auto-update in its settings to keep them current.")
                    }
                }
                if open {
                    ForEach(model.adobeApps, id: \.id) { (product: AdobeProduct) in
                        let older = model.adobeOlder.contains(product)
                        HStack(spacing: 12) {
                            if let image = icon(product) { Image(nsImage: image).resizable().frame(width: 28, height: 28) }
                            else { Image(systemName: "app.dashed").font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 28, height: 28) }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(product.label).font(.body.weight(.medium)).lineLimit(1)
                                Text(older ? "\(product.version) · a newer version is installed" : product.version)
                                    .font(.caption).foregroundStyle(older ? Color.warning : .secondary).lineLimit(1)
                            }
                            Spacer()
                            if older, model.adobeBusy == nil {
                                Button("Remove") { model.removeOlderAdobe([product]) }.glassButton().controlSize(.small)
                                    .help("Adobe's installer removes \(product.label) and keeps your settings")
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                    }
                    if !model.adobeHasUpdater {
                        Label("On a personal plan, Creative Cloud installs Adobe's updates; Adobe doesn't let other apps do it. Its Auto-update setting keeps every app current.",
                              systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
            .glassPanel()
        }
    }

    private var subtitle: String {
        if let busy = model.adobeBusy { return busy }
        if let message = model.adobeMessage { return message }
        let n = model.adobeApps.count
        return "\(n) app\(n == 1 ? "" : "s")" + (model.adobeOlder.isEmpty ? "" : " · \(model.adobeOlder.count) older version\(model.adobeOlder.count == 1 ? "" : "s")")
            + (model.adobeHasUpdater ? " · updated with Adobe's updater" : " · updated by Creative Cloud")
    }

    private func icon(_ product: AdobeProduct) -> NSImage? {
        let app = ((try? FileManager.default.contentsOfDirectory(atPath: product.folder.path)) ?? []).first { $0.hasSuffix(".app") && $0.hasPrefix("Adobe") }
        return app.map { NSWorkspace.shared.icon(forFile: product.folder.appendingPathComponent($0).path) }
    }
}
