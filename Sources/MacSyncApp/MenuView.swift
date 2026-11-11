import MacSyncCore
import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let machines = model.overview?.machines, !machines.isEmpty {
                VStack(spacing: 2) {
                    ForEach(machines) { MachineRow(machine: $0) }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                Divider()
            }
            notices
            actions
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MacSync").font(.headline)
                Text(model.statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.isSyncing || model.isApplying {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
    }

    @ViewBuilder private var notices: some View {
        let messages = [model.actionError, model.errorMessage, model.autoApplyMessage, model.undoMessage, model.updateMessage].compactMap { $0 } + (model.overview?.issues ?? [])
        if let update = model.availableUpdate, !model.isUpdating {
            Button { model.installUpdate(update) } label: {
                Label("Update to MacSync \(update.version)", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(12)
            Divider()
        }
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(messages, id: \.self) { message in
                    Label(message, systemImage: message == model.undoMessage ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            Divider()
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if model.overview?.hasPendingChanges == true {
                Button { ReviewWindow.shared.show(model: model) } label: {
                    Text("Review Changes…").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            HStack(spacing: 8) {
                Button { model.syncNow() } label: {
                    Text(model.isSyncing ? "Syncing…" : "Sync Now").frame(maxWidth: .infinity)
                }
                .disabled(model.isSyncing || model.isApplying)
                Button { model.undo() } label: {
                    Text("Undo Last Apply").frame(maxWidth: .infinity)
                }
                .disabled(model.overview?.lastRestorePoint == nil || model.isApplying)
                .help(model.overview?.lastRestorePoint.map { "Undo \($0.summary) from \($0.sourceMachine)" } ?? "Nothing to undo yet")
            }
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Menu {
                Button("Open Sync Window…") { ReviewWindow.shared.show(model: model) }
                Button("History…") {
                    model.showHistory = true
                    ReviewWindow.shared.show(model: model)
                }
                Divider()
                Toggle("Sync Automatically", isOn: $model.autoSync)
                Toggle("Apply Dock Changes When I Open the Lid", isOn: $model.autoApplyDock)
                Toggle("Open at Login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
                Toggle("Update Automatically", isOn: $model.autoUpdate)
                Toggle("Install Homebrew Updates Automatically", isOn: $model.autoUpgrade)
                Button(model.upgrading ? "Checking Homebrew…" : "Check Homebrew for Updates") { if model.autoUpgrade { model.upgradeAll() } else { model.checkUpgrades() } }
                    .disabled(model.upgrading)
                Button("Check for Updates") { model.checkForUpdates(manual: true) }
                Divider()
                Button("Support MacSync…") { NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/onlymoein")!) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Settings")
            Spacer()
            Text("MacSync \(MacSyncEnvironment.appVersion)").font(.caption).foregroundStyle(.tertiary)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct MachineRow: View {
    let machine: MachineSummary

    private var state: (text: String, color: Color) {
        if machine.isLayoutSource { return ("Latest", .accentColor) }
        return machine.dockMatchesSource ? ("In sync", .green) : ("Behind", Color.warning)
    }

    private var symbol: String {
        let name = machine.name.lowercased()
        if name.contains("book") || name.contains("air") { return "laptopcomputer" }
        if name.contains("studio") { return "macstudio" }
        if name.contains("pro") { return "macpro.gen3" }
        return "desktopcomputer"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(machine.name + (machine.isThisMac ? " (this Mac)" : ""))
                    .lineLimit(1)
                Text("Saved \(machine.savedAt, format: .relative(presentation: .named)) · \(machine.dockItemCount) in Dock · \(machine.appCount) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Group {
                    if machine.isOutdated {
                        Label {
                            Text("MacSync \(machine.appVersion) · update it on that Mac").foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warning)
                        }
                    } else {
                        Text("MacSync \(machine.appVersion)").foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(state.text)
                .font(.caption.weight(.medium))
                .foregroundStyle(state.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
