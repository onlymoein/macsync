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
            ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let report = model.lastReport { ResultPanel(report: report) }
                    if let message = model.undoMessage {
                        Label(message, systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(.green).padding(14).frame(maxWidth: .infinity, alignment: .leading).glassPanel()
                    }
                    ToRemovePanel(model: model)
                    if let plan = model.overview?.dockPlan ?? model.overview?.dockPreview {
                        DockPanel(plan: plan, model: model, matches: model.overview?.dockPlan == nil)
                        if !plan.missing.isEmpty { NotInstalledPanel(items: plan.missing, model: model) }
                    }
                    ForEach(AppSuite.all, id: \.name) { suite in SuitePanel(suite: suite, model: model) }
                    AppsPanel(kind: .apps, model: model)
                    AppsPanel(kind: .appStore, model: model)
                    AppsPanel(kind: .tools, model: model)
                    ThisMacPanel(kind: .apps, model: model)
                    ThisMacPanel(kind: .tools, model: model)
                    // Settings sit lower down: Dock and apps first, then settings, then history.
                    if let plan = model.overview?.settingsPlan {
                        SettingsPanel(plan: plan, model: model)
                    } else if model.proEnabled {
                        // Always there, like the Dock, so it's clear what's in sync.
                        SettingsMatchPanel(model: model)
                    }
                    if model.proEnabled { AppSettingsPanel(model: model) }
                    HistoryPanel(model: model).id("history")
                    if let overview = model.overview, !overview.hasPendingChanges, !model.canApply, model.lastReport == nil {
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
            .onAppear { jumpToHistory(scroller) }
            .onChange(of: model.showHistory) { _ in jumpToHistory(scroller) }
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

    private func jumpToHistory(_ scroller: ScrollViewProxy) {
        guard model.showHistory else { return }
        UserDefaults.standard.set(true, forKey: "review.history.open")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation { scroller.scrollTo("history", anchor: .top) }
            model.showHistory = false
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
                } else if let error = model.actionError ?? model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2)
                } else if model.canApply {
                    Label("A restore point is saved first", systemImage: "clock.arrow.circlepath").lineLimit(1)
                } else {
                    Label("Nothing to apply on this Mac.", systemImage: "checkmark.circle")
                        .lineLimit(2)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if model.lastReport?.restorePoint != nil, model.overview?.lastRestorePoint != nil {
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
    /// Nothing to change: this Mac's Dock already is the combined one.
    var matches = false
    @AppStorage("review.dock.open") private var open = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(symbol: "dock.rectangle", title: "Dock",
                        subtitle: matches ? "Matches your other Macs" : "Combined from \(plan.sourceMachine)", isExpanded: $open) {
                Toggle("Update Dock", isOn: $model.applyDock).toggleStyle(.switch).labelsHidden()
            }
            if open { content }
        }
        .padding(18)
        .glassPanel()
        .opacity(model.applyDock ? 1 : 0.55)
    }

    private var orderLabel: String {
        guard let id = model.overview?.dockOrderFrom,
              let mac = model.overview?.machines.first(where: { $0.id == id }) else { return "Whichever Mac changed last" }
        return mac.name + (mac.isThisMac ? " (this Mac)" : "")
    }

    @ViewBuilder private var content: some View {
            HStack(spacing: 8) {
                Text("Order on every Mac").font(.callout).foregroundStyle(.secondary)
                Menu {
                    Button("Whichever Mac changed last") { model.setDockOrder(nil) }
                    Divider()
                    ForEach(model.overview?.machines ?? []) { mac in
                        Button(mac.name + (mac.isThisMac ? " (this Mac)" : "")) { model.setDockOrder(mac.id) }
                    }
                } label: {
                    Text(orderLabel).font(.callout.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Every Mac's Dock keeps this order. Apps the other Macs add go next to their neighbours.")
                Spacer()
            }
            DockStrip(items: plan.targetApps + plan.targetOthers, model: model, added: Set(plan.added.map(\.key)), apps: plan.targetApps)
            Text((model.dockArrangement != nil ? "New order: press Apply to use it on every Mac. " : "Drag icons to rearrange. ")
                 + (model.dockRemovals.isEmpty
                    ? "Click an icon, or its ×, to remove it from the Dock on every Mac."
                    : "\(model.dockRemovals.count) marked to remove from every Mac. Press Apply, or click again to keep."))
                .font(.caption).foregroundStyle(.secondary)
            if model.dockArrangement != nil {
                Button("Reset Order") { model.dockArrangement = nil }.glassButton().controlSize(.small)
            }
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

/// One switch for a whole section: on when every item in it is on.
private struct AllSwitch: View {
    let onCount: Int
    let total: Int
    let set: (Bool) -> Void

    var body: some View {
        let allOn = onCount == total
        Toggle(isOn: Binding(get: { allOn }, set: { set($0) })) {
            Text(allOn ? "All on" : onCount == 0 ? "All off" : "\(onCount) on").font(.caption).foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(total == 0)
        .help(allOn ? "Turn all off" : "Turn all on")
        .accessibilityLabel(allOn ? "Turn all off" : "Turn all on")
    }
}

private struct DockStrip: View {
    let items: [DockItem]
    @ObservedObject var model: AppModel
    let added: Set<String>
    /// The apps part of the Dock, which can be dragged into a new order.
    let apps: [DockItem]
    @State private var dragging: String?

    private let columns = [GridItem(.adaptive(minimum: 40, maximum: 40), spacing: 6)]

    private var arrangedApps: [DockItem] {
        guard let order = model.dockArrangement else { return apps }
        let byKey = Dictionary(apps.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        return order.compactMap { byKey[$0] } + apps.filter { !order.contains($0.key) }
    }

    var body: some View {
        let others = items.filter { item in !apps.contains { $0.key == item.key } }
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(Array(arrangedApps.enumerated()), id: \.offset) { _, item in
                icon(item)
                    .opacity(dragging == item.key ? 0.3 : 1)
                    .onDrag {
                        dragging = item.key
                        return NSItemProvider(object: item.key as NSString)
                    }
                    .onDrop(of: [.text], delegate: DockDrop(target: item.key, apps: apps, model: model, dragging: $dragging))
            }
            ForEach(Array(others.enumerated()), id: \.offset) { _, item in icon(item) }
        }
        .padding(10)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: model.dockArrangement)
        // A drag let go anywhere in the strip, or abandoned: no icon stays dimmed.
        .onDrop(of: [.text], isTargeted: nil) { _ in dragging = nil; return true }
        .onHover { inside in if inside, NSEvent.pressedMouseButtons == 0 { dragging = nil } }
    }

    private func icon(_ item: DockItem) -> some View {
        DockStripIcon(item: item, model: model, added: added.contains(item.key))
    }
}

/// One Dock icon in the preview: drag to move it, click it or its × to remove it from every Mac.
private struct DockStripIcon: View {
    let item: DockItem
    @ObservedObject var model: AppModel
    let added: Bool
    @State private var hovering = false

    var body: some View {
        let removing = model.dockRemovals.contains(item.key)
        DockIcon(item: item, image: model.icon(for: item), badge: removing ? .removed : (added ? .added : nil))
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { toggle() })
            .overlay(alignment: .topLeading) {
                if hovering && !removing && item.kind != .spacer {
                    Button(action: toggle) {
                        ZStack {
                            Circle().fill(Color(white: 0.25))
                            Image(systemName: "xmark").font(.system(size: 7, weight: .heavy)).foregroundColor(.white)
                        }
                        .frame(width: 15, height: 15)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -4, y: -4)
                    .help("Remove \(item.label) from the Dock on every Mac")
                }
            }
            .onHover { hovering = $0 }
            .contextMenu {
                if item.kind != .spacer {
                    Button(removing ? "Keep in the Dock" : "Remove from Dock on Every Mac") { toggle() }
                }
            }
            .help(removing ? "\(item.label) will be removed from every Mac's Dock. Click to keep it." : item.label)
    }

    private func toggle() { if item.kind != .spacer { model.toggleDockRemoval(item.key) } }
}

/// Moves the dragged icon in front of the one it's over, as the Dock itself does.
private struct DockDrop: DropDelegate {
    let target: String
    let apps: [DockItem]
    let model: AppModel
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        model.moveDockItem(dragging, before: target, in: apps)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
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
            PanelHeader(symbol: "arrow.down.app.fill", title: "Dock apps to install",
                        subtitle: "\(needed) of \(items.count) needed · in your other Mac's Dock, missing on this one", isExpanded: $open) {
                AllSwitch(onCount: needed, total: items.count) { on in
                    model.setSkipped(tokens: items.map { model.skipToken(for: $0) }, !on)
                }
            }
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
                        Text(skipped ? "Not needed on this Mac"
                             : model.missingApp(for: item)?.app.source == .appStore ? "Open in App Store" : "Open download page")
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

extension AppSuite {
    public func member(for app: MissingApp) -> Member? {
        members.first { m in app.app.name == m.cask || app.detail?.bundleID == m.bundleID || app.app.name == m.bundleID }
    }
    public static func contains(_ app: MissingApp) -> Bool { all.contains { $0.member(for: app) != nil } }
}

/// A suite MacSync always offers (ArtCraft), in a section of its own.
private struct SuitePanel: View {
    let suite: AppSuite
    @ObservedObject var model: AppModel
    @AppStorage private var open: Bool

    init(suite: AppSuite, model: AppModel) {
        self.suite = suite
        self.model = model
        _open = AppStorage(wrappedValue: true, "review.suite.\(suite.name).open")
    }

    private var missing: [MissingApp] {
        (model.overview?.missingApps ?? []).filter { suite.member(for: $0) != nil }
            .sorted { a, b in
                (a.displayName.hasSuffix(" Launcher") ? 0 : 1, a.displayName) < (b.displayName.hasSuffix(" Launcher") ? 0 : 1, b.displayName)
            }
    }
    private var skipped: Set<String> { Set(model.overview?.skippedApps ?? []) }
    private var wanted: [MissingApp] { missing.filter { !skipped.contains($0.app.token) } }
    private var left: [MissingApp] {
        wanted.filter { $0.canInstall && model.gotten[$0.app.token] == nil && !model.getting.contains($0.app.token) }
    }

    var body: some View {
        if !missing.isEmpty {
            let onMac = suite.members.count - missing.count
            VStack(alignment: .leading, spacing: 14) {
                PanelHeader(symbol: "paintpalette.fill", title: suite.name,
                            subtitle: "\(onMac) of \(suite.members.count) apps on this Mac · Homebrew installs the rest into Applications",
                            isExpanded: $open) {
                    HStack(spacing: 12) {
                        // Straight into Applications: ArtCraft Launcher doesn't look in subfolders.
                        Button(left.isEmpty ? "Get All" : "Get All \(left.count)") { model.get(left) }
                            .glassButton().controlSize(.small).disabled(left.isEmpty)
                            .help("Install them all into Applications with Homebrew, where ArtCraft Launcher finds them")
                        AllSwitch(onCount: wanted.count, total: missing.count) { on in
                            model.setSkipped(tokens: missing.map(\.app.token), !on)
                        }
                    }
                }
                if open {
                    VStack(spacing: 2) { ForEach(missing) { AppRow(missing: $0, model: model) } }
                }
            }
            .padding(18)
            .glassPanel()
        }
    }
}

/// Several apps from one developer (the ArtCraft suite) shown as one row.
struct AppFamily: Identifiable {
    let id: String
    let name: String
    let apps: [MissingApp]

    enum Entry: Identifiable {
        case single(MissingApp)
        case family(AppFamily)
        var id: String {
            switch self { case .single(let app): return app.id; case .family(let family): return "family:" + family.id }
        }
    }

    /// Apps sharing a developer's bundle ID prefix (ai.storyteller.photocraft, ai.storyteller.vectorcraft)
    /// form one family when there are three or more. The family is named after its launcher
    /// app when there is one ("ArtCraft Launcher" → "ArtCraft"), otherwise after the developer.
    static func group(_ apps: [MissingApp]) -> [Entry] {
        func key(_ app: MissingApp) -> String? {
            guard let id = app.detail?.bundleID ?? (app.app.source == .direct ? app.app.name : nil) else { return nil }
            let parts = id.split(separator: ".")
            guard parts.count >= 3 else { return nil }
            let prefix = parts.prefix(2).joined(separator: ".").lowercased()
            // Big developers ship unrelated apps under one prefix; only group small suites.
            return ["com.apple", "com.google", "com.microsoft", "com.adobe"].contains(prefix) ? nil : prefix
        }
        let byKey = Dictionary(grouping: apps.filter { key($0) != nil }, by: { key($0)! }).filter { $0.value.count >= 3 }
        var seen = Set<String>()
        var entries: [Entry] = []
        for app in apps {
            if let k = key(app), let members = byKey[k] {
                guard seen.insert(k).inserted else { continue }
                let launcher = members.first { $0.displayName.hasSuffix(" Launcher") }
                let suite = AppSuite.all.first { suite in suite.members.contains { $0.bundleID.lowercased().hasPrefix(k + ".") } }
                let name = suite?.name ?? launcher.map { String($0.displayName.dropLast(" Launcher".count)) }
                    ?? k.split(separator: ".").reversed().joined(separator: ".")
                let sorted = members.sorted { a, b in
                    (a.displayName.hasSuffix(" Launcher") ? 0 : 1, a.displayName) < (b.displayName.hasSuffix(" Launcher") ? 0 : 1, b.displayName)
                }
                entries.append(.family(AppFamily(id: k, name: name, apps: sorted)))
            } else {
                entries.append(.single(app))
            }
        }
        return entries
    }
}

private struct FamilyRow: View {
    let family: AppFamily
    @ObservedObject var model: AppModel
    @State private var expanded = false

    private var skipped: Set<String> { Set(model.overview?.skippedApps ?? []) }
    private var wanted: [MissingApp] { family.apps.filter { !skipped.contains($0.app.token) } }
    private var left: [MissingApp] {
        wanted.filter { $0.canInstall && model.gotten[$0.app.token] == nil && !model.getting.contains($0.app.token) }
    }
    private var busy: Bool { family.apps.contains { model.getting.contains($0.app.token) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                AppIcon(missing: family.apps[0], image: model.icon(for: family.apps[0]))
                Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(family.name).font(.body.weight(.medium))
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                        Text("\(family.apps.count) apps · \(family.apps.map(\.displayName).prefix(4).joined(separator: ", "))\(family.apps.count > 4 ? "…" : "")")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                if busy {
                    ProgressView().controlSize(.small)
                } else if left.isEmpty {
                    Text(wanted.isEmpty ? "Not needed" : "Done").font(.callout).foregroundStyle(.secondary)
                } else {
                    Button("Get All \(left.count)…") {
                        if let folder = model.chooseFolder(for: family.id, name: family.name) { model.get(left, into: folder) }
                    }
                    .primaryGlassButton().controlSize(.small)
                    .help("Choose a folder, then install all \(left.count) apps there")
                }
                Toggle("", isOn: Binding(get: { !wanted.isEmpty }, set: { on in model.setSkipped(tokens: family.apps.map(\.app.token), !on) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .help(wanted.isEmpty ? "Not needed on this Mac. Switch on to get them." : "Switch off if this Mac doesn't need any of them.")
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .opacity(wanted.isEmpty ? 0.5 : 1)
            if expanded {
                VStack(spacing: 2) { ForEach(family.apps) { AppRow(missing: $0, model: model) } }
                    .padding(.leading, 28)
            }
        }
    }
}

/// Apps, or command-line tools, from the other Macs: each in its own section.
/// Apps removed on another Mac that are still here: uninstall them in one click, or keep them.
private struct ToRemovePanel: View {
    @ObservedObject var model: AppModel
    @AppStorage("review.toRemove.open") private var open = true
    @State private var confirmAll = false

    private var list: [MissingApp] { model.overview?.toRemove ?? [] }

    var body: some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "trash.fill", title: "Removed on your other Macs",
                            subtitle: "\(list.count) still on this Mac · Homebrew uninstalls them, others go to the Trash",
                            isExpanded: $open) {
                    Button("Uninstall All") { confirmAll = true }
                        .glassButton().controlSize(.small)
                        .disabled(!model.removing.isEmpty)
                }
                if open {
                    VStack(spacing: 2) {
                        ForEach(list) { app in
                            HStack(spacing: 12) {
                                AppIcon(missing: app, image: model.icon(for: app))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.displayName).font(.body.weight(.medium)).lineLimit(1)
                                    Text("Removed on \(app.fromMachines.first ?? "another Mac")").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.removing.contains(app.app.token) {
                                    ProgressView().controlSize(.small)
                                } else if let result = model.removeResults[app.app.token], result.outcome == .failed {
                                    Text(result.message ?? "Didn't uninstall").font(.caption).foregroundStyle(.orange).lineLimit(2)
                                    Button("Keep Here") { model.keepHere(app) }.glassButton().controlSize(.small)
                                    Button("Try Again") { model.uninstallHere([app]) }.primaryGlassButton().controlSize(.small)
                                } else {
                                    Button("Keep Here") { model.keepHere(app) }.glassButton().controlSize(.small)
                                    Button("Uninstall") { model.uninstallHere([app]) }.primaryGlassButton().controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                        }
                    }
                }
            }
            .padding(18)
            .glassPanel()
            .confirmationDialog("Uninstall \(list.count) app\(list.count == 1 ? "" : "s") from this Mac?", isPresented: $confirmAll) {
                Button("Uninstall All", role: .destructive) { model.uninstallHere(list) }
            } message: {
                Text("Homebrew apps are uninstalled. Other apps are moved to the Trash, where you can put them back.")
            }
        }
    }
}

/// What this Mac offers the others. Switch an app off to stop sending it; remove an app to take
/// it off every Mac.
private struct ThisMacPanel: View {
    enum Kind { case apps, tools }
    let kind: Kind
    @ObservedObject var model: AppModel
    @AppStorage private var open: Bool
    @State private var search = ""
    @State private var confirm: MissingApp?

    init(kind: Kind, model: AppModel) {
        self.kind = kind
        self.model = model
        _open = AppStorage(wrappedValue: false, kind == .apps ? "review.thisMac.open" : "review.thisMacTools.open")
    }

    private var list: [MissingApp] {
        (model.overview?.installedApps ?? [])
            .filter { ($0.app.source == .formula) == (kind == .tools) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    private var hidden: Set<String> { Set(model.overview?.unshared ?? []) }
    private var shown: [MissingApp] { search.isEmpty ? list : list.filter { $0.displayName.localizedCaseInsensitiveContains(search) } }

    var body: some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                let shared = list.filter { !hidden.contains($0.app.token) }.count
                PanelHeader(symbol: kind == .apps ? "arrow.up.circle.fill" : "terminal",
                            title: kind == .apps ? "Shared from this Mac" : "Command-line tools shared from this Mac",
                            subtitle: "\(shared) of \(list.count) sent to your other Macs", isExpanded: $open) {
                    AllSwitch(onCount: shared, total: list.count) { on in model.setShared(list.map(\.app.token), on) }
                }
                if open {
                    Text("Switch off what your other Macs shouldn't get. Remove one to take it off every Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder)
                    VStack(spacing: 2) { ForEach(shown) { row($0) } }
                    if kind == .apps, let removed = model.overview?.removed, !removed.isEmpty {
                        Divider().padding(.vertical, 4)
                        Text("Removed from all Macs").font(.callout.weight(.medium))
                        ForEach(removed, id: \.token) { removal in
                            HStack {
                                Text(removal.name).foregroundStyle(.secondary)
                                Text("by \(removal.fromMachine)").font(.caption).foregroundStyle(.tertiary)
                                Spacer()
                                Button("Bring Back") { model.cancelRemoval(removal.token) }.glassButton().controlSize(.small)
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }
            .padding(18)
            .glassPanel()
            .confirmationDialog("Remove \(confirm?.displayName ?? "this app") from all your Macs?",
                                isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
                Button("Remove from All Macs", role: .destructive) { if let app = confirm { model.removeEverywhere(app) } }
            } message: {
                Text("It's removed from this Mac now. Each other Mac lists it under Removed and uninstalls it when you click there. Homebrew apps are uninstalled; others go to the Trash.")
            }
        }
    }

    private func row(_ app: MissingApp) -> some View {
        let token = app.app.token
        let isShared = !hidden.contains(token)
        return HStack(spacing: 12) {
            AppIcon(missing: app, image: model.icon(for: app))
            VStack(alignment: .leading, spacing: 1) {
                Text(app.displayName).font(.body.weight(.medium)).lineLimit(1)
                Text(isShared ? "Sent to your other Macs" : "Only on this Mac").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if model.removing.contains(token) {
                ProgressView().controlSize(.small)
            } else if let result = model.removeResults[token], result.outcome == .failed {
                Text(result.message ?? "Didn't uninstall").font(.caption).foregroundStyle(.orange).lineLimit(2).frame(maxWidth: 220)
                Button("Try Again") { model.removeEverywhere(app) }.glassButton().controlSize(.small)
            } else {
                Button { confirm = app } label: { Label("Remove", systemImage: "trash") }
                    .glassButton().controlSize(.small)
                    .help("Remove from this Mac and all your other Macs")
            }
            Toggle("", isOn: Binding(get: { isShared }, set: { model.setShared([token], $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .help(isShared ? "Switch off to stop sending it to your other Macs" : "Switch on to send it to your other Macs")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .opacity(isShared ? 1 : 0.6)
    }
}

/// Every Apply on this Mac, newest first. Restore goes back to just before any of them.
private struct HistoryPanel: View {
    @ObservedObject var model: AppModel
    @AppStorage("review.history.open") private var open = false
    @State private var confirm: RestorePointInfo?

    private var points: [RestorePointInfo] { model.overview?.history ?? [] }

    var body: some View {
        do {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "clock.arrow.circlepath", title: "History",
                            subtitle: points.isEmpty ? "Nothing applied on this Mac yet"
                                : "\(points.count) saved on this Mac · go back to before any of them", isExpanded: $open) { EmptyView() }
                if open && points.isEmpty {
                    Text("Each time you press Apply, MacSync saves how this Mac was first. They show up here, and Restore goes back to any of them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if open && !points.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(points) { point in
                            HStack(spacing: 12) {
                                Image(systemName: point.undoneAt == nil ? "circle.fill" : "arrow.uturn.backward.circle")
                                    .font(.caption).foregroundStyle(point.undoneAt == nil ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(point.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.body.weight(.medium))
                                    Text("\(point.summary.prefix(1).uppercased() + point.summary.dropFirst()), from \(point.sourceMachine)"
                                         + (point.undoneAt != nil ? " · undone" : ""))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Button("Restore") { confirm = point }
                                    .glassButton().controlSize(.small)
                                    .disabled(model.isApplying)
                                    .help("Put this Mac's Dock and settings back to just before this")
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .opacity(point.undoneAt == nil ? 1 : 0.6)
                        }
                    }
                    Text("Each Apply saves one. Restoring puts this Mac's Dock and settings back to just before it, undoing it and anything applied after it. Installed apps stay installed. The last 20 are kept.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .glassPanel()
            .confirmationDialog("Go back to before \(confirm?.createdAt.formatted(date: .abbreviated, time: .shortened) ?? "")?",
                                isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
                Button("Restore") { if let point = confirm { model.restore(point) } }
            } message: {
                Text("This Mac's Dock and settings go back to how they were then. Your other Macs follow this Dock next time you apply there.")
            }
        }
    }
}

/// Which apps' own settings match on every Mac. Passwords, tokens and keys never sync.
private struct AppSettingsPanel: View {
    @ObservedObject var model: AppModel
    @AppStorage("review.appSettings.open") private var open = true
    @State private var chosen: Set<String> = []
    @State private var apps: [PrefApp] = []
    @State private var search = ""
    @State private var loaded = false

    private var shown: [PrefApp] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(symbol: "slider.horizontal.3", title: "App settings",
                        subtitle: model.pendingAppPrefs != nil ? "Changed · press Apply to save"
                            : "\(apps.filter { model.appPrefsChosen.contains($0.domain) }.count) of \(apps.count) apps match on all your Macs",
                        isExpanded: $open) {
                AllSwitch(onCount: apps.filter { model.appPrefsChosen.contains($0.domain) }.count, total: apps.count) { on in
                    model.setAppPref(apps.map(\.domain), on)
                }
            }
            if open {
                Text("Turn on the apps whose settings should match on all your Macs, then press Apply. Your other Macs then show these settings to apply. Passwords, tokens, license keys and window positions are never copied.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Search apps", text: $search).textFieldStyle(.roundedBorder)
                VStack(spacing: 2) { ForEach(shown) { row($0) } }
            }
        }
        .padding(18)
        .glassPanel()
        .onAppear { load(); loaded = true }
        .onChange(of: model.overview?.appPrefDomains ?? []) { domains in
            // Settings applied from another Mac can bring more apps: show them, don't overwrite them.
            let fresh = Set(domains)
            guard fresh != chosen else { return }
            chosen = fresh
            for domain in fresh where !apps.contains(where: { $0.domain == domain }) && domain != "com.onlymehdi.macsync" {
                if let app = PrefApp.find(domain) { apps.append(app) }
            }
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func row(_ app: PrefApp) -> some View {
        let isOn = Binding(
            get: { model.appPrefsChosen.contains(app.domain) },
            set: { on in model.setAppPref([app.domain], on) })
        return HStack(spacing: 12) {
            Group {
                if let icon = app.icon { Image(nsImage: icon).resizable().scaledToFit() }
                else { Image(systemName: "app.dashed").font(.title2).foregroundStyle(.secondary) }
            }
            .frame(width: 30, height: 30)
            Text(app.name).lineLimit(1)
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func load() {
        chosen = Set(model.appPrefDomains())
        let domains = Set(model.availableAppPrefDomains()).union(chosen)
        var found: [PrefApp] = []
        var names = Set<String>()
        for domain in domains.sorted() {
            if domain == "com.onlymehdi.macsync" { continue }
            if let app = PrefApp.find(domain) {
                guard names.insert(app.name.lowercased()).inserted || chosen.contains(domain) else { continue }
                found.append(app)
            } else if chosen.contains(domain) {
                found.append(PrefApp(domain: domain, name: domain, icon: nil))
            }
        }
        apps = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct AppsPanel: View {
    enum Kind { case apps, appStore, tools }
    let kind: Kind
    @ObservedObject var model: AppModel
    @AppStorage private var open: Bool

    init(kind: Kind, model: AppModel) {
        self.kind = kind
        self.model = model
        // Apps start open; the long list of tools starts closed.
        _open = AppStorage(wrappedValue: kind != .tools,
                           kind == .apps ? "review.apps.open" : kind == .appStore ? "review.appStore.open" : "review.tools.open")
    }

    private var list: [MissingApp] {
        (model.overview?.missingApps ?? [])
            .filter { app in
                switch kind {
                case .apps: return (app.app.source == .cask || app.app.source == .direct) && !AppSuite.contains(app)
                case .appStore: return app.app.source == .appStore
                case .tools: return app.app.source == .formula
                }
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    private var skippedTokens: Set<String> { Set(model.overview?.skippedApps ?? []) }
    private var wanted: Int { list.filter { !skippedTokens.contains($0.app.token) }.count }

    var body: some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PanelHeader(symbol: kind == .apps ? "square.grid.2x2.fill" : kind == .appStore ? "bag.fill" : "terminal.fill",
                            title: kind == .apps ? "Apps on your other Macs" : kind == .appStore ? "App Store apps" : "Command-line tools",
                            subtitle: "\(wanted) of \(list.count) needed" + (kind == .apps ? " · Homebrew installs them, others download from the developer"
                                : kind == .appStore ? " · each opens its App Store page, click Get there" : " · installed with Homebrew"),
                            isExpanded: $open) {
                    HStack(spacing: 12) {
                        getAll(list, label: kind == .tools ? "Install All" : "Get All")
                        switchAll(list)
                    }
                }
                if open {
                    VStack(spacing: 2) {
                        ForEach(AppFamily.group(list)) { entry in
                            switch entry {
                            case .single(let app): AppRow(missing: app, model: model)
                            case .family(let family): FamilyRow(family: family, model: model)
                            }
                        }
                    }
                    if model.overview?.brewAvailable == false, list.contains(where: { $0.app.source == .cask || $0.app.source == .formula }) {
                        Label("Homebrew isn't on this Mac yet, so Homebrew apps can't be installed. Get it at brew.sh.", systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18)
            .glassPanel()
        }
    }

    private func switchAll(_ list: [MissingApp]) -> some View {
        AllSwitch(onCount: list.filter { !skippedTokens.contains($0.app.token) }.count, total: list.count) { on in
            model.setSkipped(tokens: list.map(\.app.token), !on)
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
    @State private var confirmRemove = false

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
            Button { confirmRemove = true } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(model.getting.contains(token) || model.removing.contains(token))
                .help("Uninstall \(missing.displayName) from all your Macs")
                .accessibilityLabel("Uninstall from all Macs")
            Toggle("", isOn: Binding(get: { !isSkipped }, set: { model.setSkipped(missing, !$0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .disabled(model.getting.contains(token))
                .help(isSkipped ? "Not needed on this Mac. Switch on to get it." : "Switch off if this Mac doesn't need it. MacSync remembers.")
        }
        .opacity(isSkipped ? 0.5 : 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .help(help)
        .confirmationDialog("Uninstall \(missing.displayName) from all your Macs?", isPresented: $confirmRemove) {
            Button("Uninstall from All Macs", role: .destructive) { model.removeEverywhere(missing) }
        } message: {
            Text(missing.fromMachines.isEmpty ? "Each Mac that has it lists it under Removed and uninstalls it when you click there."
                 : "It's on \(missing.fromMachines.joined(separator: ", ")). Each of those Macs lists it under Removed and uninstalls it when you click there. MacSync stops offering it here.")
        }
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
            case .removed:
                Label("Removed", systemImage: "trash").font(.callout).foregroundStyle(.secondary)
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
        case .appStore: return "Open in App Store"
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
        case .cask, .formula: return missing.fromMachines.isEmpty ? "Installs with Homebrew. Suggested by MacSync."
            : "Installs with Homebrew. On \(missing.fromMachines.joined(separator: ", "))."
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

/// The settings that match on every Mac, with their values here, when nothing needs applying.
private struct SettingsMatchPanel: View {
    @ObservedObject var model: AppModel
    @AppStorage("review.settings.open") private var open = true
    @State private var settings: [SettingsChange] = []

    private var grouped: [(String, [SettingsChange])] {
        Dictionary(grouping: settings, by: \.category).sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let synced = settings.filter { !model.excludedSettingsChosen.contains($0.id) }.count
            PanelHeader(symbol: "gearshape.fill", title: "Settings",
                        subtitle: model.pendingExcludedSettings != nil ? "Changed · press Apply to save"
                            : "\(synced) of \(settings.count) kept the same on your Macs · trackpad, keyboard, Finder, Dock and screenshots",
                        isExpanded: $open) {
                AllSwitch(onCount: synced, total: settings.count) { on in model.setSettingSynced(settings.map(\.id), on) }
            }
            if open {
                Text("Switch off a setting to keep it to this Mac, then press Apply. Change a setting in System Settings on any Mac and the others offer it here.")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(grouped, id: \.0) { category, items in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                            ForEach(items) { item in
                                let on = !model.excludedSettingsChosen.contains(item.id)
                                HStack {
                                    Text(item.label)
                                    Spacer(minLength: 8)
                                    Text(item.to?.display ?? "default").foregroundStyle(.secondary)
                                    Toggle("", isOn: Binding(get: { on }, set: { model.setSettingSynced([item.id], $0) }))
                                        .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                                        .help(on ? "Kept the same on all your Macs" : "Only on this Mac")
                                }
                                .font(.callout)
                                .opacity(on ? 1 : 0.5)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .glassPanel()
        .onAppear { settings = model.currentSettings() }
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
