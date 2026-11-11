import MacSyncCore
import SwiftUI

// MARK: - Glass

extension View {
    /// A Liquid Glass panel on macOS 26 and later, frosted material before that.
    @ViewBuilder func glassPanel(cornerRadius: CGFloat = 18) -> some View {
        if #available(macOS 26.0, *) {
            // Glass behind the content, not around it, so colours (badges, status icons) keep their colour.
            self.background { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius)) }
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.12)))
        }
    }

    @ViewBuilder func primaryGlassButton() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }

    @ViewBuilder func glassButton() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }
}

/// A soft brand-coloured wash behind the glass, so the panels have something to refract.
private struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [Color(red: 0.23, green: 0.17, blue: 0.84).opacity(scheme == .dark ? 0.32 : 0.14),
                                    Color(red: 0.12, green: 0.49, blue: 1.0).opacity(scheme == .dark ? 0.18 : 0.08),
                                    .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Window

struct ReviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Backdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let report = model.lastReport { ResultPanel(report: report) }
                    if let message = model.undoMessage {
                        Label(message, systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(.green).padding(14).frame(maxWidth: .infinity, alignment: .leading).glassPanel()
                    }
                    if let plan = model.overview?.dockPlan { DockPanel(plan: plan, model: model) }
                    if let plan = model.overview?.settingsPlan { SettingsPanel(plan: plan, model: model) }
                    AppsPanel(model: model)
                    if model.overview?.hasPendingChanges != true, model.lastReport == nil {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(.green)
                            Text("Your Macs match").font(.title3.weight(.semibold))
                            Text("Every Mac has the same Dock and apps.").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 34)
                .padding(.bottom, 96)
            }
            footer
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sync your Macs").font(.system(size: 26, weight: .bold, design: .rounded))
            if !chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip).font(.callout.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .glassPanel(cornerRadius: 12)
                    }
                }
            }
        }
    }

    private var chips: [String] {
        var list: [String] = []
        let apps = model.appsToInstall.count
        if apps > 0 { list.append("\(apps) app\(apps == 1 ? "" : "s") to add") }
        if let plan = model.overview?.dockPlan {
            let changes = plan.added.count + plan.removed.count
            list.append(changes == 0 ? "Dock order" : "\(changes) Dock change\(changes == 1 ? "" : "s")")
        }
        if let plan = model.overview?.settingsPlan {
            list.append("\(plan.changes.count) setting\(plan.changes.count == 1 ? "" : "s")")
        }
        return list
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Group {
                if model.isApplying {
                    ProgressView().controlSize(.small)
                    Text(model.progress ?? "Applying…").lineLimit(1)
                } else if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2)
                } else {
                    Label("A restore point is saved first", systemImage: "clock.arrow.circlepath").lineLimit(1)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if model.lastReport != nil, model.overview?.lastRestorePoint != nil {
                Button("Undo") { model.undo() }.glassButton().disabled(model.isApplying)
            }
            Button("Close") { ReviewWindow.shared.close() }.glassButton().keyboardShortcut(.cancelAction)
            Button("Apply") { model.apply() }
                .primaryGlassButton()
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canApply)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 22)
        .padding(14)
    }
}

// MARK: - Panels

private struct PanelHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(LinearGradient(colors: [Color(red: 0.23, green: 0.17, blue: 0.84), Color(red: 0.12, green: 0.49, blue: 1.0)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

private struct DockPanel: View {
    let plan: DockPlan
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(symbol: "dock.rectangle", title: "Dock", subtitle: "Combined from \(plan.sourceMachine)") {
                Toggle("Update Dock", isOn: $model.applyDock).toggleStyle(.switch).labelsHidden()
            }
            DockStrip(items: plan.targetApps + plan.targetOthers, model: model, added: Set(plan.added.map(\.key)))
            Text(model.dockRemovals.isEmpty
                 ? "Click an icon to remove it from the Dock on every Mac."
                 : "\(model.dockRemovals.count) marked to remove from every Mac. Click again to keep.")
                .font(.caption).foregroundStyle(.secondary)
            if !plan.removed.isEmpty {
                IconRow(title: "Removed on another Mac", items: plan.removed, model: model, badge: .removed)
            }
            if !plan.missing.isEmpty {
                IconRow(title: "Added once they're installed", items: plan.missing, model: model, badge: .waiting)
            }
            if let change = plan.tileSizeChange {
                Text("Icon size \(change.from.map { String(format: "%g", $0) } ?? "default") → \(String(format: "%g", change.to))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let change = plan.orientationChange {
                Text("Position \(change.from ?? "bottom") → \(change.to)").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .glassPanel()
        .opacity(model.applyDock ? 1 : 0.55)
    }
}

private enum Badge { case added, removed, waiting }

private struct DockStrip: View {
    let items: [DockItem]
    @ObservedObject var model: AppModel
    let added: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 40, maximum: 40), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let removing = model.dockRemovals.contains(item.key)
                DockIcon(item: item, image: model.icon(for: item),
                         badge: removing ? .removed : (added.contains(item.key) ? .added : nil))
                    .contentShape(Rectangle())
                    .onTapGesture { if item.kind != .spacer { model.toggleDockRemoval(item.key) } }
            }
        }
        .padding(10)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct IconRow: View {
    let title: String
    let items: [DockItem]
    @ObservedObject var model: AppModel
    let badge: Badge

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title).font(.callout).foregroundStyle(.secondary).frame(width: 190, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(items) { item in DockIcon(item: item, image: model.icon(for: item), badge: badge) }
            }
        }
    }
}

private struct DockIcon: View {
    let item: DockItem
    let image: NSImage?
    let badge: Badge?

    var body: some View {
        ZStack {
            if item.kind == .spacer {
                Color.clear
            } else if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "app.dashed").font(.system(size: 24)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .opacity(badge == .removed || badge == .waiting ? 0.45 : 1)
        .overlay(alignment: .bottomTrailing) {
            switch badge {
            case .added: mark("plus", .green)
            case .removed: mark("minus", .red)
            case .waiting: mark("arrow.down", .blue)
            case nil: EmptyView()
            }
        }
        .help(item.label)
        .accessibilityLabel(item.label)
    }

    private func mark(_ symbol: String, _ color: Color) -> some View {
        ZStack {
            Circle().fill(Color.white)
            Circle().fill(color).padding(1.5)
            Image(systemName: symbol).font(.system(size: 8, weight: .heavy)).foregroundColor(.white)
        }
        .frame(width: 16, height: 16)
        .offset(x: 3, y: 3)
    }
}

// MARK: - Apps

private struct AppsPanel: View {
    @ObservedObject var model: AppModel
    @State private var showTools = false

    private var all: [MissingApp] { model.overview?.missingApps ?? [] }
    private var apps: [MissingApp] {
        all.filter { $0.app.source != .formula }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    private var tools: [MissingApp] { all.filter { $0.app.source == .formula } }

    var body: some View {
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PanelHeader(symbol: "square.grid.2x2.fill", title: "Apps from your other Macs",
                            subtitle: "Ticked apps are added to this Mac. Nothing is ever removed.") {
                    selectAll(all)
                }
                if !apps.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(apps) { AppRow(missing: $0, model: model) }
                    }
                }
                if !tools.isEmpty {
                    DisclosureGroup(isExpanded: $showTools) {
                        VStack(spacing: 2) { ForEach(tools) { AppRow(missing: $0, model: model) } }
                            .padding(.top, 6)
                    } label: {
                        HStack {
                            Text("Command-line tools").font(.callout.weight(.medium))
                            Text("\(selected(tools)) of \(tools.count) ticked").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            selectAll(tools)
                        }
                    }
                }
                if model.overview?.brewAvailable == false, all.contains(where: { $0.app.source == .cask || $0.app.source == .formula }) {
                    Label("Homebrew isn't on this Mac yet, so those apps can't be installed. Get it at brew.sh.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .glassPanel()
        }
    }

    private func selected(_ list: [MissingApp]) -> Int { list.filter { model.selectedApps.contains($0.app.token) }.count }

    private func selectAll(_ list: [MissingApp]) -> some View {
        let installable = list.filter(\.canInstall)
        let allOn = selected(installable) == installable.count
        return Button(allOn ? "Untick all" : "Tick all") { model.setSelected(installable.map(\.app.token), !allOn) }
            .glassButton()
            .controlSize(.small)
    }
}

private struct AppRow: View {
    let missing: MissingApp
    @ObservedObject var model: AppModel

    private var isOn: Binding<Bool> {
        Binding(get: { model.selectedApps.contains(missing.app.token) }, set: { model.setSelected(missing.app.token, $0) })
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(missing: missing, image: model.icon(for: missing))
            VStack(alignment: .leading, spacing: 1) {
                Text(missing.displayName).font(.body.weight(.medium)).lineLimit(1)
                if let summary = missing.detail?.summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(sourceLabel).font(.caption).foregroundStyle(.secondary)
                .help(help)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.quaternary.opacity(0.6), in: Capsule())
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
                .disabled(!missing.canInstall)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { if missing.canInstall { isOn.wrappedValue.toggle() } }
        .opacity(missing.canInstall ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }

    private var sourceLabel: String {
        switch missing.app.source {
        case .cask, .formula: return "Homebrew"
        case .appStore: return "App Store"
        case .direct: return missing.canInstall ? "Download" : "No download link"
        }
    }

    private var help: String {
        guard missing.app.source == .direct else { return "" }
        return missing.canInstall
            ? "Downloaded from the developer into Downloads, then opened so you can install it"
            : "MacSync doesn't know where this app is published. Get it from the developer's website."
    }
}

private struct AppIcon: View {
    let missing: MissingApp
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: missing.app.source == .formula ? "terminal.fill" : "app.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(missing.app.source == .formula ? Color(white: 0.18) : Color.accentColor.opacity(0.8),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(2)
            }
        }
        .frame(width: 34, height: 34)
    }
}

// MARK: - Results

private struct ResultPanel: View {
    let report: ApplyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(headline, systemImage: report.hasFailures ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(report.hasFailures ? .orange : .green)
            line("Installed", .installed)
            line("Downloaded from the developer and opened. Finish installing them from Downloads", .downloaded)
            line("Opened in the App Store. Click Get to finish", .openedInAppStore)
            ForEach(report.results.filter { $0.outcome == .failed }) { result in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(result.displayName ?? result.app.name) didn't install").font(.callout.weight(.medium))
                    if let message = result.message {
                        Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            if let error = report.settingsError { Text(error).font(.callout).foregroundStyle(.secondary) }
            if !report.skippedDockItems.isEmpty {
                Text("Added to this Dock once installed: \(report.skippedDockItems.map(\.label).joined(separator: ", "))")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    @ViewBuilder private func line(_ title: String, _ outcome: InstallResult.Outcome) -> some View {
        let names = report.results.filter { $0.outcome == outcome }.map { $0.displayName ?? $0.app.name }
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title):").font(.callout.weight(.medium))
                Text(names.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var headline: String {
        if report.hasFailures { return "Some changes didn't apply" }
        return report.dockChanged || report.settingsChanged || !report.results.isEmpty ? "Changes applied" : "Done"
    }
}

private struct SettingsPanel: View {
    let plan: SettingsPlan
    @ObservedObject var model: AppModel

    private var grouped: [(String, [SettingsChange])] {
        Dictionary(grouping: plan.changes, by: \.category).sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(symbol: "gearshape.fill", title: "Settings",
                        subtitle: "From \(plan.sourceMachine)" + (plan.needsLogout ? " · some need a log out" : "")) {
                Toggle("Update settings", isOn: $model.applySettings).toggleStyle(.switch).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(grouped, id: \.0) { category, changes in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
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
            .opacity(model.applySettings ? 1 : 0.55)
        }
        .padding(18)
        .glassPanel()
    }
}
