import MacSyncCore
import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.overview?.hasPendingChanges == true {
                Button { ReviewWindow.shared.show(model: model) } label: {
                    Text("Review Changes…").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
            notices
            if let machines = model.overview?.machines, !machines.isEmpty {
                MenuSection(title: "Your Macs") {
                    ForEach(machines) { MachineRow(machine: $0) }
                }
            }
            MenuSection(title: "Updates") {
                HomebrewRow(model: model)
                MacSyncUpdateRow(model: model)
            }
            Divider().padding(.top, 4)
            toolbar
            // What's running, at the very bottom: a bar, and a line on what it's doing.
            if model.isBusy { Divider() }
            ActivityBar(model: model)
        }
        .animation(.easeInOut(duration: 0.2), value: model.isBusy)
        .frame(width: 340)
        // The menu's window follows the content's height, so no empty glass is left above it.
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.menuOpened() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.menuBarSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text("MacSync").font(.headline)
                Text(model.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
    }

    @ViewBuilder private var notices: some View {
        let messages = [model.actionError, model.errorMessage, model.autoApplyMessage, model.undoMessage].compactMap { $0 } + (model.overview?.issues ?? [])
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(messages, id: \.self) { message in
                    Label(message, systemImage: message == model.undoMessage ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 10)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            ToolbarButton(title: model.isSyncing ? "Syncing" : "Sync", symbol: "arrow.triangle.2.circlepath",
                          help: "Save this Mac and check your other Macs now") { model.syncNow() }
                .disabled(model.isSyncing || model.isApplying)
            ToolbarButton(title: "History", symbol: "clock.arrow.circlepath", help: "What changed and when") {
                model.showHistory = true
                ReviewWindow.shared.show(model: model)
            }
            ToolbarButton(title: "Share", symbol: "square.and.arrow.up", help: "Share your setup with a friend") {
                ReviewWindow.shared.show(model: model)
                model.requestShare = true
            }
            ToolbarButton(title: "Import", symbol: "square.and.arrow.down", help: "Open a setup a friend shared with you") {
                model.chooseSharedSetup()
            }
            ToolbarButton(title: "Coffee", symbol: "cup.and.saucer", help: "Buy me a coffee: MacSync is free") {
                NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/onlymoein")!)
            }
            // A menu's label is drawn in one line, so the word sits under it separately.
            VStack(spacing: 3) {
                settingsMenu
                Text("Settings").font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var settingsMenu: some View {
        Menu {
            Button { ReviewWindow.shared.show(model: model) } label: { Label("Open Sync Window…", systemImage: "macwindow") }
            Button { model.chooseSharedSetup() } label: { Label("Open a Shared Setup…", systemImage: "tray.and.arrow.down") }
            Button { OnboardingWindow.shared.show(model: model) } label: { Label("Welcome and Install…", systemImage: "hand.wave") }
            Section("Sync") {
                Toggle("Sync Automatically", isOn: $model.autoSync)
                Toggle("Apply Dock Changes When I Open the Lid", isOn: $model.autoApplyDock)
            }
            Section("Updates") {
                Toggle("Update Apps and Tools Automatically", isOn: $model.autoUpgrade)
                Toggle("Update MacSync Automatically", isOn: $model.autoUpdate)
                Picker("MacSync Versions", selection: $model.updateChannel) {
                    ForEach(UpdateChannel.allCases) { Text($0 == .stable ? "Stable (Notarized by Apple)" : "New (Before Apple Checks)").tag($0) }
                }
            }
            Section("MacSync \(MacSyncEnvironment.appVersion)") {
                Toggle("Open at Login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
            }
            Divider()
            Button("Quit MacSync") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape").font(.system(size: 15))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}

/// A titled group in the menu.
private struct MenuSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 2)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 6)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
    }
}

/// An icon over a short word, like Control Center.
private struct ToolbarButton: View {
    let title: String
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovering && isEnabled ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .primary : .tertiary)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(title)
    }
}

/// MacSync's own version: up to date, a check, or an Update button when one is ready.
private struct MacSyncUpdateRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.availableUpdate != nil ? "arrow.down.circle.fill" : "checkmark.seal")
                .font(.system(size: 16))
                .foregroundStyle(model.availableUpdate != nil ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(model.availableUpdate.map { "MacSync \($0.version) is ready" } ?? "MacSync \(MacSyncEnvironment.appVersion)")
                        .lineLimit(1)
                    if model.updateChannel == .new { ChannelTag() }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(detail)
            }
            Spacer(minLength: 6)
            if model.isUpdating {
                ProgressView().controlSize(.small)
            } else if let update = model.availableUpdate {
                Button("Update") { model.installUpdate(update) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .help("Installs MacSync \(update.version) and reopens it")
            } else {
                Button {
                    model.checkForUpdates(manual: true)
                    if model.autoUpgrade { model.upgradeAll() } else { model.checkUpgrades() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(model.upgrading)
                .help("Check for updates to MacSync, apps and tools")
                .accessibilityLabel("Check for Updates")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private var detail: String {
        if let message = model.updateMessage { return message }
        if model.availableUpdate != nil { return model.autoUpdate ? "Installs on its own when MacSync is idle" : "You're on \(MacSyncEnvironment.appVersion)" }
        return "Up to date"
    }
}

/// Marks the New channel: versions that may not be notarized yet.
struct ChannelTag: View {
    var body: some View {
        Text("NEW CHANNEL")
            .font(.system(size: 8.5, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .foregroundStyle(Color.orange)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .help("You get each MacSync version as soon as it's out, before Apple has finished checking it. Change this in Settings.")
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
                HStack(spacing: 5) {
                    Text(machine.name).lineLimit(1)
                    if machine.isThisMac {
                        Text("This Mac").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
                Text("Saved \(machine.savedAt, format: .relative(presentation: .named)) · \(machine.dockItemCount) in Dock · \(machine.appCount) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if machine.isOutdated {
                    Label {
                        Text("Needs a MacSync update (has \(machine.appVersion))").foregroundStyle(.secondary)
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
        .padding(.horizontal, 8)
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
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture { ReviewWindow.shared.show(model: model) }
        }
    }

    private func title(_ report: UpgradeReport, _ outdated: [OutdatedItem]) -> String {
        if model.upgrading { return model.work["brew"]?.current.map { "Updating \($0)…" } ?? "Checking Homebrew…" }
        if !outdated.isEmpty { return "\(outdated.count) update\(outdated.count == 1 ? "" : "s") for apps and tools" }
        if !report.upgraded.isEmpty { return "Updated \(report.upgraded.count) with Homebrew" }
        return "Apps and tools are up to date"
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
