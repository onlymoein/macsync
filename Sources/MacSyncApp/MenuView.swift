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
            HomebrewRow(model: model)
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
                Button { ReviewWindow.shared.show(model: model) } label: { Label("Open Sync Window…", systemImage: "macwindow") }
                Button {
                    model.showHistory = true
                    ReviewWindow.shared.show(model: model)
                } label: { Label("History…", systemImage: "clock.arrow.circlepath") }
                Section("Sync") {
                    Toggle("Sync Automatically", isOn: $model.autoSync)
                    Toggle("Apply Dock Changes When I Open the Lid", isOn: $model.autoApplyDock)
                }
                Section("Homebrew") {
                    Toggle("Install Updates Automatically", isOn: $model.autoUpgrade)
                    Button(model.upgrading ? "Checking…" : "Check for Updates Now") {
                        if model.autoUpgrade { model.upgradeAll() } else { model.checkUpgrades() }
                    }
                    .disabled(model.upgrading)
                }
                Section("MacSync \(MacSyncEnvironment.appVersion)") {
                    Toggle("Open at Login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
                    Toggle("Update Automatically", isOn: $model.autoUpdate)
                    Button("Check for Updates Now") { model.checkForUpdates(manual: true) }
                }
                Divider()
                Button { NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/onlymoein")!) } label: {
                    Label("Support MacSync…", systemImage: "cup.and.saucer")
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Settings")
            Spacer()
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
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(machine.name + (machine.isThisMac ? " (this Mac)" : ""))
                    .lineLimit(1)
                Text("Saved \(machine.savedAt, format: .relative(presentation: .named)) · \(machine.dockItemCount) in Dock · \(machine.appCount) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if machine.isOutdated {
                    Label {
                        Text("MacSync \(machine.appVersion) · update it on that Mac").foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warning)
                    }
                    .font(.caption2)
                    .lineLimit(1)
                }
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


/// Homebrew at a glance: how many updates wait, or what was just updated.
private struct HomebrewRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let report = model.upgradeReport ?? (model.upgrading ? UpgradeReport(ranAt: Date()) : nil) {
            let outdated = report.outdated ?? []
            HStack(spacing: 10) {
                Image(systemName: "mug").font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(report, outdated)).font(.body).lineLimit(1)
                    if let detail = detail(report, outdated) {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if model.upgrading { ProgressView().controlSize(.small) }
                else if !outdated.isEmpty {
                    Button("Update All") { model.upgrade(outdated) }.buttonStyle(.borderless).font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { ReviewWindow.shared.show(model: model) }
            Divider()
        }
    }

    private func title(_ report: UpgradeReport, _ outdated: [OutdatedItem]) -> String {
        if model.upgrading { return model.progress ?? "Checking Homebrew…" }
        if !outdated.isEmpty { return "\(outdated.count) Homebrew update\(outdated.count == 1 ? "" : "s")" }
        if !report.upgraded.isEmpty { return "Updated \(report.upgraded.count) with Homebrew" }
        return "Homebrew is up to date"
    }

    private func detail(_ report: UpgradeReport, _ outdated: [OutdatedItem]) -> String? {
        if model.upgrading { return nil }
        let names = (outdated.isEmpty ? report.upgraded : outdated).map(\.name)
        var parts: [String] = []
        if !names.isEmpty { parts.append(names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3)" : "")) }
        if !report.waiting.isEmpty { parts.append("\(report.waiting.count) waiting") }
        if !report.failures.isEmpty { parts.append("\(report.failures.count) failed") }
        if names.isEmpty { parts.append("checked \(report.ranAt.formatted(.relative(presentation: .named)))") }
        return parts.joined(separator: " · ")
    }
}
