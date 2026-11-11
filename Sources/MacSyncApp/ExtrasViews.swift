import MacSyncCore
import SwiftUI

// Sections for config files, AI setup, app data, login items, packages and signing in.

/// Something that can be removed from this Mac or from every Mac.
struct RemoveTarget: Identifiable, Equatable {
    var token: String
    var name: String
    var id: String { token }
}

extension View {
    /// Asks whether to remove from all Macs or from this Mac only.
    func removeChoices(_ target: Binding<RemoveTarget?>, model: AppModel, what: String = "it") -> some View {
        confirmationDialog("Remove \(target.wrappedValue?.name ?? what)?",
                           isPresented: Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } })) {
            Button("Remove from All Macs", role: .destructive) {
                if let t = target.wrappedValue { model.removeExtra(t.token, name: t.name, everywhere: true) }
            }
            Button("Remove from This Mac Only") {
                if let t = target.wrappedValue { model.removeExtra(t.token, name: t.name, everywhere: false) }
            }
        } message: {
            Text(target.wrappedValue?.token.hasPrefix("file:") == true
                 ? "Files go to the Trash, where you can put them back. All Macs: each other Mac lists it under Removed. This Mac only: it stays on your other Macs and isn't taken here again."
                 : "All Macs: each other Mac lists it under Removed and removes it when you click there. This Mac only: your other Macs keep it, and it isn't offered here again.")
        }
    }
}

private func shortPath(_ path: String) -> String {
    path.replacingOccurrences(of: "~/Library/Application Support/", with: "~/…/")
}

private struct RowIcon: View {
    let symbol: String
    var tint: Color = .accentColor
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct BusyOrError: View {
    @ObservedObject var model: AppModel
    let token: String
    var body: some View {
        if model.extraBusy.contains(token) { ProgressView().controlSize(.small) }
        else if let error = model.extraErrors[token] { Text(error).font(.caption).foregroundStyle(Color.warning).lineLimit(2) }
    }
}

// MARK: Files

struct FilesPanel: View {
    let area: FileArea
    @ObservedObject var model: AppModel
    @AppStorage private var open: Bool
    @State private var expanded: Set<String> = []
    @State private var remove: RemoveTarget?

    init(area: FileArea, model: AppModel) {
        self.area = area
        self.model = model
        _open = AppStorage(wrappedValue: true, "review.files.\(area.rawValue).open")
    }

    private var title: String { ["config": "Config files", "ai": "AI setup", "appData": "App data"][area.rawValue] ?? "" }
    private var symbol: String { ["config": "doc.text.fill", "ai": "sparkles", "appData": "tray.full.fill"][area.rawValue] ?? "doc" }
    private var about: String {
        switch area {
        case .config: return "Shell, Git, editors, terminals, Raycast and your fonts"
        case .ai: return "Skills, agents, rules, CLAUDE.md, settings and MCP servers for Claude, Codex and Cursor"
        case .appData: return "Presets and settings for apps such as Photoshop, Camera Raw and iStat Menus"
        }
    }

    private var changes: [FileChange] { (model.overview?.extras.files ?? []).filter { $0.area == area } }
    private var kept: [KeptFile] { (model.overview?.extras.kept ?? []).filter { $0.area == area } }
    private var shared: [SharedFileInfo] { (model.overview?.extras.shared ?? []).filter { $0.area == area } }
    private var skipped: Set<String> { Set(model.overview?.skippedApps ?? []) }

    var body: some View {
        if !changes.isEmpty || !kept.isEmpty || !shared.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                let on = changes.filter { !skipped.contains($0.token) }.count
                PanelHeader(symbol: symbol, title: title,
                            subtitle: changes.isEmpty ? "\(shared.filter { !$0.localOnly }.count) shared · the same on your Macs · \(about)"
                                : "\(changes.count) from your other Macs · \(about)",
                            isExpanded: $open) {
                    if !changes.isEmpty {
                        AllSwitch(onCount: on, total: changes.count) { model.setSkipped(tokens: changes.map(\.token), !$0) }
                    }
                }
                if open {
                    if !changes.isEmpty {
                        // Many files from one place (a folder of skills) fold into one row.
                        let groups = Dictionary(grouping: changes, by: \.group).sorted { $0.key < $1.key }
                        VStack(spacing: 2) {
                            ForEach(groups, id: \.key) { group, items in
                                if items.count <= 6 {
                                    ForEach(items) { change in changeRow(change) }
                                } else {
                                    changeGroupRow(group, items)
                                    if expanded.contains("changes:" + group) {
                                        ForEach(items.prefix(60)) { change in changeRow(change) }
                                        if items.count > 60 {
                                            Text("and \(items.count - 60) more").font(.caption).foregroundStyle(.secondary).padding(.leading, 48)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if !kept.isEmpty { keptList }
                    if !shared.isEmpty { sharedList }
                }
            }
            .padding(18)
            .glassPanel()
            .removeChoices($remove, model: model)
        }
    }

    private func changeGroupRow(_ group: String, _ items: [FileChange]) -> some View {
        let on = items.filter { !skipped.contains($0.token) }.count
        let sources = Set(items.map(\.sourceMachine)).sorted().joined(separator: ", ")
        let waiting = items.filter(\.waiting).count
        return HStack(spacing: 12) {
            RowIcon(symbol: items[0].symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(group).font(.body.weight(.medium))
                Text("\(items.count) files from \(sources)" + (waiting > 0 ? " · \(waiting) still arriving through iCloud" : ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(expanded.contains("changes:" + group) ? "Hide" : "Show") {
                withAnimation { if expanded.contains("changes:" + group) { expanded.remove("changes:" + group) } else { expanded.insert("changes:" + group) } }
            }
            .buttonStyle(.link).font(.callout)
            AllSwitch(onCount: on, total: items.count) { model.setSkipped(tokens: items.map(\.token), !$0) }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func changeRow(_ change: FileChange) -> some View {
        let on = !skipped.contains(change.token)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                RowIcon(symbol: change.symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(shortPath(change.path)).font(.body.weight(.medium).monospaced()).lineLimit(1).truncationMode(.middle)
                    Text("\(change.group) · \(change.isNew ? "new" : "changed") on \(change.sourceMachine) · \(change.detail)")
                        .font(.caption).foregroundStyle(change.waiting ? Color.warning : Color.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                BusyOrError(model: model, token: change.token)
                if !change.preview.isEmpty {
                    Button { if expanded.contains(change.path) { expanded.remove(change.path) } else { expanded.insert(change.path) } } label: {
                        Image(systemName: expanded.contains(change.path) ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Show what changes")
                }
                Button { remove = RemoveTarget(token: change.token, name: shortPath(change.path)) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from this Mac or all Macs")
                Toggle("", isOn: Binding(get: { on }, set: { model.setSkipped(tokens: [change.token], !$0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .help(on ? "Taken when you press Apply" : "Not taken on this Mac")
            }
            if expanded.contains(change.path) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(change.preview.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                            .foregroundStyle(line.hasPrefix("+") ? Color.green : line.hasPrefix("−") ? Color.red : .secondary)
                            .lineLimit(1)
                    }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 40)
            }
        }
        .opacity(on ? 1 : 0.5)
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private var keptList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Kept on this Mac because they hold a key, token or password", systemImage: "key.slash")
                .font(.callout.weight(.semibold)).foregroundStyle(Color.warning)
            ForEach(kept) { file in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(shortPath(file.path)).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    Text(file.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: NSString(string: file.path).expandingTildeInPath)]) }
                        .buttonStyle(.link).font(.caption)
                }
            }
            Text("To share the rest, move the secret into a file MacSync never copies (like ~/.zshrc.local or ~/.secrets) and load it from there.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var sharedList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shared from this Mac").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                .padding(.top, changes.isEmpty && kept.isEmpty ? 0 : 6)
            let groups = Dictionary(grouping: shared, by: \.group).sorted { $0.key < $1.key }
            ForEach(groups, id: \.key) { group, files in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        RowIcon(symbol: files[0].symbol)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group).font(.body.weight(.medium))
                            Text("\(files.filter { !$0.localOnly }.count) of \(files.count) file\(files.count == 1 ? "" : "s") sent to your other Macs")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(expanded.contains(group) ? "Hide" : "Show") {
                            withAnimation { if expanded.contains(group) { expanded.remove(group) } else { expanded.insert(group) } }
                        }
                        .buttonStyle(.link).font(.callout)
                        AllSwitch(onCount: files.filter { !$0.localOnly }.count, total: files.count) { on in
                            model.setFilesLocalOnly(files.map(\.path), !on)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    if expanded.contains(group) {
                        ForEach(files.prefix(40)) { file in
                            HStack(spacing: 8) {
                                Text(shortPath(file.path)).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                BusyOrError(model: model, token: "file:" + file.path)
                                Button { remove = RemoveTarget(token: "file:" + file.path, name: shortPath(file.path)) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from this Mac or all Macs")
                                Toggle("", isOn: Binding(get: { !file.localOnly }, set: { model.setFilesLocalOnly([file.path], !$0) }))
                                    .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                                    .help(file.localOnly ? "Kept to this Mac" : "Sent to your other Macs")
                            }
                            .opacity(file.localOnly ? 0.5 : 1)
                            .padding(.leading, 46).padding(.trailing, 8)
                        }
                        if files.count > 40 {
                            Text("and \(files.count - 40) more").font(.caption).foregroundStyle(.secondary).padding(.leading, 46)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Removed elsewhere

struct ExtrasRemovedPanel: View {
    @ObservedObject var model: AppModel
    @AppStorage("review.extrasRemoved.open") private var open = true

    private var list: [AppRemoval] { model.overview?.extras.toRemove ?? [] }

    var body: some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "trash.fill", title: "Files and tools removed on your other Macs",
                            subtitle: "\(list.count) still on this Mac · files go to the Trash", isExpanded: $open) {
                    Button("Remove All") { for item in list { model.removeExtra(item.token, name: item.name, everywhere: false) } }
                        .glassButton().controlSize(.small)
                }
                if open {
                    ForEach(list, id: \.token) { item in
                        HStack(spacing: 12) {
                            RowIcon(symbol: item.token.hasPrefix("file:") ? "doc" : item.token.hasPrefix("login:") ? "power" : "shippingbox", tint: .red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                                Text("Removed on \(item.fromMachine)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            BusyOrError(model: model, token: item.token)
                            Button("Keep Here") { model.keepExtraHere(item.token) }.glassButton().controlSize(.small)
                            Button("Remove") { model.removeExtra(item.token, name: item.name, everywhere: false) }.primaryGlassButton().controlSize(.small)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                }
            }
            .padding(18)
            .glassPanel()
        }
    }
}

// MARK: Login items

struct LoginItemsPanel: View {
    @ObservedObject var model: AppModel
    @AppStorage("review.loginItems.open") private var open = true
    @State private var remove: RemoveTarget?

    private var missing: [LoginItem] { model.overview?.extras.loginItems ?? [] }
    private var mine: [LoginItem] { model.overview?.extras.installedLoginItems ?? [] }
    private var skipped: Set<String> { Set(model.overview?.skippedApps ?? []) }
    private var issue: String? { model.overview?.extras.issues.first { $0.hasPrefix("Login items") } }

    var body: some View {
        if !missing.isEmpty || !mine.isEmpty || issue != nil {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "power", title: "Login items",
                            subtitle: missing.isEmpty ? "\(mine.count) open at login · the same on your Macs"
                                : "\(missing.count) open at login on your other Macs · added when you press Apply",
                            isExpanded: $open) {
                    if !missing.isEmpty {
                        AllSwitch(onCount: missing.filter { !skipped.contains($0.token) }.count, total: missing.count) {
                            model.setSkipped(tokens: missing.map(\.token), !$0)
                        }
                    }
                }
                if open {
                    if let issue {
                        Label(issue, systemImage: "lock.shield").font(.caption).foregroundStyle(Color.warning)
                    }
                    ForEach(missing) { item in
                        let on = !skipped.contains(item.token)
                        HStack(spacing: 12) {
                            appIcon(item)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.body.weight(.medium))
                                Text("Opens at login on \((model.overview?.extras.loginItemSources[item.token] ?? []).joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { remove = RemoveTarget(token: item.token, name: item.name) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                            Toggle("", isOn: Binding(get: { on }, set: { model.setSkipped(tokens: [item.token], !$0) }))
                                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        }
                        .opacity(on ? 1 : 0.5)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                    }
                    if !mine.isEmpty {
                        Text("Open at login on this Mac").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .textCase(.uppercase).padding(.top, missing.isEmpty ? 0 : 6)
                        ForEach(mine) { item in
                            HStack(spacing: 10) {
                                appIcon(item)
                                Text(item.name).font(.body)
                                Spacer()
                                BusyOrError(model: model, token: item.token)
                                Button { remove = RemoveTarget(token: item.token, name: item.name) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from this Mac or all Macs")
                            }
                            .padding(.horizontal, 8).padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(18)
            .glassPanel()
            .removeChoices($remove, model: model)
        }
    }

    @ViewBuilder private func appIcon(_ item: LoginItem) -> some View {
        if let image = model.icon(forApp: item.bundleID) {
            Image(nsImage: image).resizable().frame(width: 28, height: 28)
        } else {
            RowIcon(symbol: "power")
        }
    }
}

// MARK: Packages

struct PackagesPanel: View {
    @ObservedObject var model: AppModel
    @AppStorage("review.packages.open") private var open = true
    @State private var shownKinds: Set<String> = []
    @State private var remove: RemoveTarget?

    private var missing: [PackageItem] { model.overview?.extras.packages ?? [] }
    private var mine: [PackageItem] { model.overview?.extras.installedPackages ?? [] }
    private var skipped: Set<String> { Set(model.overview?.skippedApps ?? []) }

    var body: some View {
        if !missing.isEmpty || !mine.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "puzzlepiece.extension.fill", title: "Extensions, plugins and packages",
                            subtitle: missing.isEmpty ? "\(mine.count) on this Mac · the same on your Macs"
                                : "\(missing.count) from your other Macs · Homebrew taps, VS Code and Cursor extensions, npm, uv, Claude Code plugins, Steam",
                            isExpanded: $open) {
                    if !missing.isEmpty {
                        AllSwitch(onCount: missing.filter { !skipped.contains($0.token) }.count, total: missing.count) {
                            model.setSkipped(tokens: missing.map(\.token), !$0)
                        }
                    }
                }
                if open {
                    let groups = Dictionary(grouping: missing, by: \.kind)
                    ForEach(Packages.kinds.filter { groups[$0.kind] != nil }, id: \.kind) { kind in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(kind.label, systemImage: kind.symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(groups[kind.kind] ?? []) { item in packageRow(item, symbol: kind.symbol) }
                        }
                    }
                    if !mine.isEmpty { mineList }
                }
            }
            .padding(18)
            .glassPanel()
            .removeChoices($remove, model: model)
        }
    }

    private func packageRow(_ item: PackageItem, symbol: String) -> some View {
        let on = !skipped.contains(item.token)
        return HStack(spacing: 12) {
            RowIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                Text("On \(item.fromMachines.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { remove = RemoveTarget(token: item.token, name: item.name) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from this Mac or all Macs")
            Toggle("", isOn: Binding(get: { on }, set: { model.setSkipped(tokens: [item.token], !$0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .opacity(on ? 1 : 0.5)
        .padding(.horizontal, 8).padding(.vertical, 3)
    }

    private var mineList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("On this Mac").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                .padding(.top, missing.isEmpty ? 0 : 6)
            let groups = Dictionary(grouping: mine, by: \.kind)
            ForEach(Packages.kinds.filter { groups[$0.kind] != nil }, id: \.kind) { kind in
                let items = groups[kind.kind] ?? []
                HStack(spacing: 10) {
                    RowIcon(symbol: kind.symbol)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(kind.label).font(.body.weight(.medium))
                        Text("\(items.count) on this Mac").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(shownKinds.contains(kind.kind) ? "Hide" : "Show") {
                        withAnimation { if shownKinds.contains(kind.kind) { shownKinds.remove(kind.kind) } else { shownKinds.insert(kind.kind) } }
                    }
                    .buttonStyle(.link).font(.callout)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                if shownKinds.contains(kind.kind) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Text(item.name).font(.callout).lineLimit(1)
                            Spacer()
                            BusyOrError(model: model, token: item.token)
                            Button { remove = RemoveTarget(token: item.token, name: item.name) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from this Mac or all Macs")
                        }
                        .padding(.leading, 46).padding(.trailing, 8)
                    }
                }
            }
        }
    }
}

// MARK: Signing in

struct SignInPanel: View {
    @ObservedObject var model: AppModel
    @AppStorage("review.signIn.open") private var open = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(symbol: "person.badge.key.fill", title: "Sign in to your apps",
                        subtitle: model.signInQueue.isEmpty ? "Apps that need an account show up here after they install"
                            : "\(model.signInQueue.count) to go · password manager first, so it can fill in the rest",
                        isExpanded: $open) {
                Button("Find Apps") { model.findAppsToSignIn() }.glassButton().controlSize(.small)
                    .help("Add every app on this Mac that needs an account or a license")
            }
            if open && !model.signInQueue.isEmpty {
                ForEach(model.signInQueue) { item in
                    HStack(spacing: 12) {
                        if let image = model.icon(forApp: item.bundleID) {
                            Image(nsImage: image).resizable().frame(width: 30, height: 30)
                        } else {
                            RowIcon(symbol: "person.crop.circle")
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.body.weight(.medium))
                            Text(item.hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Open") { model.openForSignIn(item) }.primaryGlassButton().controlSize(.small)
                        Button { model.signInDone(item) } label: { Label("Done", systemImage: "checkmark") }
                            .glassButton().controlSize(.small)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                }
                Text("MacSync never types passwords or license keys. It only opens each app for you.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .glassPanel()
    }
}

// MARK: Updates

struct UpdatesPanel: View {
    @ObservedObject var model: AppModel

    static func kind(_ token: String) -> String {
        switch Packages.kind(token) {
        case "cask": return "Homebrew app"
        case "formula": return "Homebrew tool"
        case "npm": return "npm"
        case "uv": return "uv"
        default: return ""
        }
    }
    @AppStorage("review.updates.open") private var open = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let report = model.upgradeReport
            PanelHeader(symbol: "arrow.triangle.2.circlepath", title: "Updates",
                        subtitle: model.upgrading ? (model.progress ?? "Updating…")
                            : report.map { "\($0.summary) · checked \($0.ranAt.formatted(.relative(presentation: .named)))" }
                            ?? "Homebrew apps and tools, npm and uv, kept on their newest versions",
                        isExpanded: $open) {
                Toggle("Automatic", isOn: $model.autoUpgrade).toggleStyle(.switch).controlSize(.small)
                    .help("Check and update on open and every six hours")
                let outdated = report?.outdated ?? []
                if !outdated.isEmpty {
                    Button("Update All (\(outdated.count))") { model.upgrade(outdated) }
                        .primaryGlassButton().controlSize(.small).disabled(model.upgrading)
                }
                Button(model.upgrading ? "Checking…" : "Check Again") { if model.autoUpgrade { model.upgradeAll() } else { model.checkUpgrades() } }
                    .help(model.autoUpgrade ? "Look for newer versions and install them" : "Look for newer versions")
                    .glassButton().controlSize(.small).disabled(model.upgrading)
            }
            if open, let report {
                let outdated = report.outdated ?? []
                if !outdated.isEmpty {
                    Text("Newer versions are out. Update them one at a time, or all at once.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(outdated) { item in
                        HStack(spacing: 12) {
                            if let image = model.icon(forApp: item.bundleID) { Image(nsImage: image).resizable().frame(width: 28, height: 28) }
                            else { RowIcon(symbol: item.token.hasPrefix("cask:") ? "app.dashed" : "terminal") }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                                Text("\(item.from) → \(item.to) · \(Self.kind(item.token))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if model.upgradeBusy.contains(item.token) { ProgressView().controlSize(.small) }
                            else { Button("Update") { model.upgrade([item]) }.glassButton().controlSize(.small).disabled(model.upgrading) }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                    }
                }
                if !report.waiting.isEmpty {
                    Text("Open right now, so they wait. Quit and Update closes the app, updates it and opens it again.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(report.waiting) { item in
                        HStack(spacing: 12) {
                            if let image = model.icon(forApp: item.bundleID) { Image(nsImage: image).resizable().frame(width: 28, height: 28) }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.body.weight(.medium))
                                Text("\(item.from) → \(item.to)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.upgradeBusy.contains(item.token) { ProgressView().controlSize(.small) }
                            else { Button("Quit and Update") { model.upgradeNow(item) }.primaryGlassButton().controlSize(.small) }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                    }
                }
                if !report.upgraded.isEmpty {
                    Text("Updated: " + report.upgraded.map { "\($0.name) \($0.to)" }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                ForEach(report.failures, id: \.self) { failure in
                    Label(failure, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.warning).lineLimit(2)
                }
            }
        }
        .padding(18)
        .glassPanel()
    }
}
