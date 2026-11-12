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

    /// Asks once, naming what goes and what stays, then removes the older versions one by one.
    func removeOlderAdobe() {
        guard adobeBusy == nil, !adobeOlder.isEmpty else { return }
        let names = adobeOlder.map(\.label)
        let open = AdobeApps.running()
        let alert = NSAlert()
        alert.messageText = "Remove \(ListFormatter.localizedString(byJoining: names))?"
        let kept = adobeApps.filter { app in adobeOlder.contains { $0.sapCode == app.sapCode } && !adobeOlder.contains(app) }.map(\.label)
        alert.informativeText = (kept.isEmpty ? "" : "\(ListFormatter.localizedString(byJoining: kept)) stays. ")
            + "Adobe's installer removes the older version and keeps your settings. macOS asks for your password."
            + (open.isEmpty ? "" : "\n\nQuit \(ListFormatter.localizedString(byJoining: open)) first.")
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let older = adobeOlder
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

/// Adobe's apps: older yearly versions to remove, and updates, for personal and company plans alike.
struct AdobeRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if !model.adobeApps.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "paintbrush.pointed").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(detail)
                }
                Spacer(minLength: 6)
                if model.adobeBusy != nil {
                    ProgressView().controlSize(.small)
                } else if !model.adobeOlder.isEmpty {
                    Button("Remove Old") { model.removeOlderAdobe() }
                        .buttonStyle(.borderless).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .help("Remove \(model.adobeOlder.map(\.label).joined(separator: ", ")); the newest version stays")
                } else {
                    Button(model.adobeHasUpdater ? "Update" : "Open") { model.updateAdobe() }
                        .buttonStyle(.borderless).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .help(model.adobeHasUpdater ? "Install every Adobe update with Adobe's updater"
                                                    : "Creative Cloud updates Adobe apps: turn on Auto-update in its settings")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
        }
    }

    private var title: String {
        if let busy = model.adobeBusy { return busy }
        if !model.adobeOlder.isEmpty {
            let n = model.adobeOlder.count
            return "\(n) older Adobe version\(n == 1 ? "" : "s")"
        }
        return "Adobe apps"
    }

    private var detail: String {
        if model.adobeBusy != nil { return "Adobe's installer is working" }
        if let message = model.adobeMessage { return message }
        if !model.adobeOlder.isEmpty { return model.adobeOlder.map(\.label).joined(separator: ", ") + " · newer version installed" }
        return model.adobeHasUpdater ? "\(model.adobeApps.count) apps · updated with Adobe's updater"
                                     : "\(model.adobeApps.count) apps · updated by Creative Cloud"
    }
}
