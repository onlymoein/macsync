import MacSyncCore
import SwiftUI

struct ReviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let report = model.lastReport {
                        ResultSection(report: report)
                    }
                    if let message = model.undoMessage {
                        Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    if let plan = model.overview?.dockPlan {
                        DockSectionView(plan: plan, model: model)
                    }
                    if let missing = model.overview?.dockMissing, !missing.isEmpty, model.overview?.dockPlan != nil {
                        Label("Left out because they aren't on this Mac: \(missing.map(\.label).joined(separator: ", "))",
                              systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let plan = model.overview?.settingsPlan {
                        SettingsSectionView(plan: plan, model: model)
                    }
                    AppsSection(model: model)
                    if model.overview?.hasPendingChanges != true, model.lastReport == nil {
                        Text("Nothing to change. This Mac matches your other Macs.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isApplying {
                ProgressView().controlSize(.small)
                Text(model.progress ?? "Applying…").foregroundStyle(.secondary)
            } else if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2)
            } else {
                Text("A restore point is saved first, so you can undo in one click.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.lastReport != nil, model.overview?.lastRestorePoint != nil {
                Button("Undo") { model.undo() }.disabled(model.isApplying)
            }
            Button("Close") { ReviewWindow.shared.close() }.keyboardShortcut(.cancelAction)
            Button("Apply") { model.apply() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canApply)
        }
        .padding(14)
    }
}

private struct DockSectionView: View {
    let plan: DockPlan
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $model.applyDock) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dock layout from \(plan.sourceMachine)").font(.headline)
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            DockStrip(title: "Now", items: plan.currentApps + plan.currentOthers, model: model,
                      marked: Set(plan.removed.map(\.key)), markColor: .red)
            DockStrip(title: "After", items: plan.targetApps + plan.targetOthers, model: model,
                      marked: Set((plan.added + plan.moved).map(\.key)), markColor: .accentColor)

            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(details, id: \.self) { Text($0).font(.callout) }
                }
            }
        }
        .opacity(model.applyDock ? 1 : 0.5)
    }

    private var summary: String {
        var parts: [String] = []
        if !plan.added.isEmpty { parts.append("\(plan.added.count) added") }
        if !plan.removed.isEmpty { parts.append("\(plan.removed.count) removed") }
        if !plan.moved.isEmpty { parts.append("\(plan.moved.count) moved") }
        return parts.isEmpty ? "Dock settings only" : parts.joined(separator: ", ")
    }

    private var details: [String] {
        var lines: [String] = []
        if !plan.added.isEmpty { lines.append("Added: " + plan.added.map(\.label).joined(separator: ", ")) }
        if !plan.removed.isEmpty { lines.append("Removed: " + plan.removed.map(\.label).joined(separator: ", ")) }
        if !plan.moved.isEmpty { lines.append("Moved: " + plan.moved.map(\.label).joined(separator: ", ")) }
        if let change = plan.tileSizeChange {
            lines.append("Size: \(change.from.map { String(format: "%g", $0) } ?? "default") to \(String(format: "%g", change.to))")
        }
        if let change = plan.orientationChange { lines.append("Position: \(change.from ?? "bottom") to \(change.to)") }
        if !plan.folderOptionsChanged.isEmpty {
            lines.append("Folder style: " + plan.folderOptionsChanged.map(\.label).joined(separator: ", "))
        }
        return lines
    }
}

private struct DockStrip: View {
    let title: String
    let items: [DockItem]
    @ObservedObject var model: AppModel
    let marked: Set<String>
    let markColor: Color

    private let columns = [GridItem(.adaptive(minimum: 36, maximum: 36), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    DockIcon(item: item, image: model.icon(for: item), isMarked: marked.contains(item.key), markColor: markColor)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct DockIcon: View {
    let item: DockItem
    let image: NSImage?
    let isMarked: Bool
    let markColor: Color

    var body: some View {
        ZStack {
            if item.kind == .spacer {
                Color.clear
            } else if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(2)
            } else {
                Image(systemName: "questionmark.app.dashed").foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .overlay {
            if isMarked {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(markColor, lineWidth: 2)
            }
        }
        .help(item.label)
        .accessibilityLabel(item.label)
    }
}

private struct AppsSection: View {
    @ObservedObject var model: AppModel

    private func apps(_ source: AppRef.Source) -> [MissingApp] {
        (model.overview?.missingApps ?? []).filter { $0.app.source == source }
    }

    var body: some View {
        if !(model.overview?.missingApps ?? []).isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Apps on your other Macs").font(.headline)
                    Text("Tick what you want here. Nothing is installed unless you tick it, and nothing is ever removed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                group("Apps (Homebrew)", apps(.cask))
                group("Command-line tools (Homebrew)", apps(.formula))
                group("Mac App Store (opens the App Store to finish)", apps(.appStore))
                if model.overview?.brewAvailable == false, !(apps(.cask) + apps(.formula)).isEmpty {
                    Label("Homebrew isn't on this Mac, so Homebrew items can't be installed yet. Get it at brew.sh.",
                          systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func group(_ title: String, _ items: [MissingApp]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ForEach(items) { missing in
                    Toggle(isOn: Binding(
                        get: { model.selectedApps.contains(missing.app.token) },
                        set: { model.setSelected(missing.app.token, $0) })) {
                        HStack(spacing: 6) {
                            Text(missing.app.name)
                            Text(missing.fromMachines.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }
}

private struct ResultSection: View {
    let report: ApplyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(headline, systemImage: report.hasFailures ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(report.hasFailures ? .orange : .green)
            if report.hasFailures, report.dockChanged { Text("Your Dock was updated.") }
            ForEach(report.results) { result in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(result.app.name): \(text(for: result.outcome))")
                    if let message = result.message {
                        Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            if report.settingsChanged { Text("Settings updated.") }
            if let error = report.settingsError { Text(error).font(.callout).foregroundStyle(.secondary) }
            if !report.skippedDockItems.isEmpty {
                Text("Left out of the Dock: \(report.skippedDockItems.map(\.label).joined(separator: ", "))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var headline: String {
        if report.hasFailures { return "Some changes didn't apply" }
        return report.dockChanged || report.settingsChanged ? "Changes applied" : "Done"
    }

    private func text(for outcome: InstallResult.Outcome) -> String {
        switch outcome {
        case .installed: return "installed"
        case .openedInAppStore: return "opened in the App Store"
        case .failed: return "failed"
        }
    }
}

private struct SettingsSectionView: View {
    let plan: SettingsPlan
    @ObservedObject var model: AppModel

    private var grouped: [(String, [SettingsChange])] {
        Dictionary(grouping: plan.changes, by: \.category).sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $model.applySettings) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings from \(plan.sourceMachine)").font(.headline)
                    Text("\(plan.changes.count) change\(plan.changes.count == 1 ? "" : "s")" + (plan.needsLogout ? ", some need a log out" : ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(grouped, id: \.0) { category, changes in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        ForEach(changes) { change in
                            HStack(spacing: 6) {
                                Text(change.label)
                                Spacer(minLength: 8)
                                Text(change.from?.display ?? "default").foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                Text(change.to?.display ?? "default")
                            }
                            .font(.callout)
                        }
                    }
                }
            }
            .opacity(model.applySettings ? 1 : 0.5)
        }
    }
}
