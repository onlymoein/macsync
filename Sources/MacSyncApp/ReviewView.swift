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
                    if let plan = model.overview?.dockPlan {
                        DockPanel(plan: plan, model: model)
                        if !plan.missing.isEmpty { NotInstalledPanel(items: plan.missing, model: model) }
                    }
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
        let apps = (model.overview?.wantedApps ?? []).filter { model.gotten[$0.app.token] == nil }.count
        if apps > 0 { list.append("\(apps) app\(apps == 1 ? "" : "s") to get") }
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
    /// When given, the header opens and closes its panel.
    var isExpanded: Binding<Bool>? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let isExpanded {
                Button { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.wrappedValue.toggle() } } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                            .frame(width: 12)
                        label
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isExpanded.wrappedValue ? "Collapse" : "Expand") \(title)")
            } else {
                label
                Spacer(minLength: 8)
            }
            trailing
        }
    }

    private var label: some View {
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
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
            }
        }
    }
}

private struct DockPanel: View {
    let plan: DockPlan
    @ObservedObject var model: AppModel
    @AppStorage("review.dock.open") private var open = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(symbol: "dock.rectangle", title: "Dock", subtitle: "Combined from \(plan.sourceMachine)", isExpanded: $open) {
                Toggle("Update Dock", isOn: $model.applyDock).toggleStyle(.switch).labelsHidden()
            }
            if open { content }
        }
        .padding(18)
        .glassPanel()
        .opacity(model.applyDock ? 1 : 0.55)
    }

    @ViewBuilder private var content: some View {
            DockStrip(items: plan.targetApps + plan.targetOthers, model: model, added: Set(plan.added.map(\.key)))
            Text(model.dockRemovals.isEmpty
                 ? "Click an icon to remove it from the Dock on every Mac."
                 : "\(model.dockRemovals.count) marked to remove from every Mac. Click again to keep.")
                .font(.caption).foregroundStyle(.secondary)
            if !plan.removed.isEmpty {
                IconRow(title: "Removed on another Mac", items: plan.removed, model: model, badge: .removed)
            }
            if let change = plan.tileSizeChange {
                Text("Icon size \(change.from.map { String(format: "%g", $0) } ?? "default") → \(String(format: "%g", change.to))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let change = plan.orientationChange {
                Text("Position \(change.from ?? "bottom") → \(change.to)").font(.callout).foregroundStyle(.secondary)
            }
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

/// Dock items from another Mac whose apps aren't on this one yet: their icon and name, a link to
/// where to get each one, and a switch for the ones this Mac doesn't need (remembered).
struct NotInstalledPanel: View {
    let items: [DockItem]
    @ObservedObject var model: AppModel
    @AppStorage("review.notInstalled.open") private var open = true

    private var needed: Int { items.filter { !model.isSkipped($0) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(symbol: "arrow.down.app.fill", title: "Not installed here",
                        subtitle: "\(needed) of \(items.count) needed · in the Dock on your other Mac", isExpanded: $open) { EmptyView() }
            if open {
                Text("Click one to open its download page. Switch off what this Mac doesn't need. Each one joins this Dock once it's installed.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 2) {
                    ForEach(items) { item in WaitingItem(item: item, model: model) }
                }
            }
        }
        .padding(18)
        .glassPanel()
    }
}

private struct WaitingItem: View {
    let item: DockItem
    @ObservedObject var model: AppModel

    var body: some View {
        let skipped = model.isSkipped(item)
        HStack(spacing: 12) {
            Button { model.openDownloadPage(for: item) } label: {
                HStack(spacing: 12) {
                    Group {
                        if let image = model.icon(for: item) { Image(nsImage: image).resizable().scaledToFit() }
                        else {
                            Image(systemName: "app.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.accentColor.opacity(0.8), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.name(for: item)).font(.body.weight(.medium)).lineLimit(1)
                        Text(skipped ? "Not needed on this Mac" : "Open download page")
                            .font(.caption).foregroundStyle(skipped ? Color.secondary : Color.accentColor)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(skipped)
            .help("Open the page where you can get \(model.name(for: item))")
            if !skipped {
                Button { model.openDownloadPage(for: item) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open download page")
            }
            Toggle("", isOn: Binding(get: { !skipped }, set: { model.setSkipped(token: model.skipToken(for: item), !$0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .help(skipped ? "Switch on if this Mac needs it" : "Switch off if this Mac doesn't need it. MacSync remembers.")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .opacity(skipped ? 0.5 : 1)
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
        .opacity(badge == .removed ? 0.45 : badge == .waiting ? 0.7 : 1)
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
    @AppStorage("review.apps.open") private var open = true

    private var everything: [MissingApp] {
        (model.overview?.missingApps ?? []).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    private var skippedTokens: Set<String> { Set(model.overview?.skippedApps ?? []) }
    private var all: [MissingApp] { everything }
    private var wanted: Int { everything.filter { !skippedTokens.contains($0.app.token) }.count }
    private var apps: [MissingApp] { all.filter { $0.app.source != .formula } }
    private var tools: [MissingApp] { all.filter { $0.app.source == .formula } }

    var body: some View {
        if !everything.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PanelHeader(symbol: "square.grid.2x2.fill", title: "Apps on your other Macs",
                            subtitle: "\(wanted) of \(everything.count) needed · switch off what this Mac doesn't need",
                            isExpanded: $open) {
                    getAll(apps, label: "Get All")
                }
                if open {
                if !apps.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(apps) { AppRow(missing: $0, model: model) }
                    }
                }
                if !tools.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            // The whole label opens the list, not just the small arrow.
                            Button { withAnimation(.easeInOut(duration: 0.2)) { showTools.toggle() } } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                                        .rotationEffect(.degrees(showTools ? 90 : 0))
                                    Text("Command-line tools").font(.callout.weight(.medium))
                                    Text("\(tools.count)").font(.callout).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showTools ? "Hide command-line tools" : "Show command-line tools")
                            Spacer()
                            getAll(tools, label: "Install All")
                        }
                        if showTools {
                            VStack(spacing: 2) { ForEach(tools) { AppRow(missing: $0, model: model) } }
                        }
                    }
                }
                if model.overview?.brewAvailable == false, all.contains(where: { $0.app.source == .cask || $0.app.source == .formula }) {
                    Label("Homebrew isn't on this Mac yet, so Homebrew apps can't be installed. Get it at brew.sh.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                }
            }
            .padding(18)
            .glassPanel()
        }
    }

    private func getAll(_ list: [MissingApp], label: String) -> some View {
        let skipped = skippedTokens
        let left = list.filter { $0.canInstall && !skipped.contains($0.app.token) && model.gotten[$0.app.token] == nil && !model.getting.contains($0.app.token) }
        return Button(label) { model.get(left) }
            .glassButton()
            .controlSize(.small)
            .disabled(left.isEmpty)
    }
}

private struct AppRow: View {
    let missing: MissingApp
    @ObservedObject var model: AppModel

    private var token: String { missing.app.token }
    private var isSkipped: Bool { model.overview?.skippedApps.contains(token) == true }
    private var result: InstallResult? { model.gotten[token] }

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(missing: missing, image: model.icon(for: missing))
            VStack(alignment: .leading, spacing: 1) {
                Text(missing.displayName).font(.body.weight(.medium)).lineLimit(1)
                if let result, result.outcome == .failed, let message = result.message {
                    Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
                } else if let summary = missing.detail?.summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(sourceLabel).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.quaternary.opacity(0.6), in: Capsule())
            action.frame(minWidth: 92, alignment: .trailing)
            Toggle("", isOn: Binding(get: { !isSkipped }, set: { model.setSkipped(missing, !$0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .disabled(model.getting.contains(token))
                .help(isSkipped ? "Not needed on this Mac. Switch on to get it." : "Switch off if this Mac doesn't need it. MacSync remembers.")
        }
        .opacity(isSkipped ? 0.5 : 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .help(help)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var action: some View {
        if model.getting.contains(token) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(missing.app.source == .direct ? "Downloading" : "Installing").font(.caption).foregroundStyle(.secondary)
            }
        } else if let result {
            switch result.outcome {
            case .installed:
                Label("Installed", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
            case .downloaded:
                Button("Open") { model.openDownload(result) }.glassButton().controlSize(.small)
                    .help("Open the installer in Downloads")
            case .openedInAppStore:
                Label("In App Store", systemImage: "bag").font(.callout).foregroundStyle(.secondary)
            case .failed:
                Button("Try Again") { model.get([missing]) }.glassButton().controlSize(.small)
            }
        } else if isSkipped {
            Text("Not needed").font(.callout).foregroundStyle(.secondary)
        } else if !missing.canInstall {
            Text("No link").font(.callout).foregroundStyle(.secondary)
        } else {
            Button(buttonTitle) { model.get([missing]) }.primaryGlassButton().controlSize(.small)
        }
    }

    private var buttonTitle: String {
        switch missing.app.source {
        case .cask, .formula: return "Install"
        case .appStore: return "Get"
        case .direct: return "Download"
        }
    }

    private var sourceLabel: String {
        switch missing.app.source {
        case .cask, .formula: return "Homebrew"
        case .appStore: return "App Store"
        case .direct: return "Developer"
        }
    }

    private var help: String {
        switch missing.app.source {
        case .cask, .formula: return "Installs with Homebrew. On \(missing.fromMachines.joined(separator: ", "))."
        case .appStore: return "Opens its App Store page. Click Get there."
        case .direct:
            return missing.canInstall
                ? "Downloads the installer from the developer into Downloads and opens it, so you can finish installing it."
                : "MacSync doesn't know where this app is published. Get it from the developer's website."
        }
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
    @AppStorage("review.settings.open") private var open = true

    private var grouped: [(String, [SettingsChange])] {
        Dictionary(grouping: plan.changes, by: \.category).sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(symbol: "gearshape.fill", title: "Settings",
                        subtitle: "\(plan.changes.count) from \(plan.sourceMachine)" + (plan.needsLogout ? " · some need a log out" : ""),
                        isExpanded: $open) {
                Toggle("Update settings", isOn: $model.applySettings).toggleStyle(.switch).labelsHidden()
            }
            if open {
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
        }
        .padding(18)
        .glassPanel()
    }
}
