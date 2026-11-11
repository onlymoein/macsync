import AppKit
import MacSyncCore
import SwiftUI

/// Choose what to share with a friend, then save the file or send it.
struct ShareSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("share.name") private var name = NSFullUserName().components(separatedBy: " ").first ?? ""
    @State private var chosen: Set<ShareSection> = ShareSheet.savedSections()
    @State private var working = false
    @State private var error: String?
    /// For the website's picture only.
    var demoName: String? = nil

    static func savedSections() -> Set<ShareSection> {
        guard let raw = UserDefaults.standard.array(forKey: "share.sections") as? [String] else { return ShareSection.defaults }
        return Set(raw.compactMap(ShareSection.init(rawValue:)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(LinearGradient(colors: [Color(red: 0.23, green: 0.17, blue: 0.84), Color(red: 0.12, green: 0.49, blue: 1.0)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share your setup").font(.title2.weight(.bold))
                    Text("Your friend opens the file in MacSync and picks what they want.").foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Your name").foregroundStyle(.secondary)
                TextField("Name", text: demoName.map { .constant($0) } ?? $name).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Text("They'll see \"\((demoName ?? name).isEmpty ? "A friend" : (demoName ?? name))'s setup\"").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(ShareSection.allCases) { section in
                    Toggle(isOn: Binding(get: { chosen.contains(section) },
                                         set: { if $0 { chosen.insert(section) } else { chosen.remove(section) } })) {
                        HStack(spacing: 12) {
                            Image(systemName: section.symbol).foregroundStyle(Color.accentColor).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(section.label).font(.body.weight(.medium))
                                Text(section.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 7).padding(.horizontal, 12)
                    if section != ShareSection.allCases.last { Divider().padding(.leading, 48) }
                }
            }
            .glassPanel(cornerRadius: 14)
            Label("Never in it: passwords, keys, tokens or any file with one in it, your fonts, app data, your Dock and your history.",
                  systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.warning) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Save File…") { make(send: false) }.disabled(chosen.isEmpty || working)
                Button("Share…") { make(send: true) }.keyboardShortcut(.defaultAction).disabled(chosen.isEmpty || working)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func make(send: Bool) {
        working = true
        error = nil
        UserDefaults.standard.set(chosen.map(\.rawValue), forKey: "share.sections")
        Task {
            let result = await model.makeSetupFile(name: name, sections: chosen)
            working = false
            switch result {
            case .failure(let failure): error = failure.localizedDescription
            case .success(let url):
                if send {
                    // The usual share menu: AirDrop, Messages, Mail.
                    guard let view = NSApp.keyWindow?.contentView else { return }
                    let picker = NSSharingServicePicker(items: [url])
                    picker.show(relativeTo: NSRect(x: view.bounds.maxX - 90, y: 30, width: 1, height: 1), of: view, preferredEdge: .minY)
                } else {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = url.lastPathComponent
                    panel.allowedContentTypes = [.init(filenameExtension: "macsync") ?? .data]
                    if panel.runModal() == .OK, let target = panel.url {
                        try? FileManager.default.removeItem(at: target)
                        do { try FileManager.default.copyItem(at: url, to: target); dismiss() }
                        catch { self.error = "It couldn't be saved there." }
                    }
                }
            }
        }
    }
}

/// A setup a friend shared: what's in it shows up in the sections below.
struct SharedSetupsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if !model.importedSetups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader(symbol: "person.2.fill", title: "Shared with you",
                            subtitle: "What's in these is offered in the sections below, marked with their name") { EmptyView() }
                ForEach(model.importedSetups) { setup in
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 26)).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(setup.name).font(.body.weight(.medium))
                            Text(setup.sections.map(\.label).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button("Remove") { model.removeImportedSetup(setup) }.glassButton().controlSize(.small)
                            .help("Stop offering what's in it. Anything you already took stays.")
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                }
            }
            .padding(18)
            .glassPanel()
        }
    }
}
