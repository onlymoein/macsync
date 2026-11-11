import Foundation

/// What applying an incoming Dock layout would change on this Mac.
public struct DockPlan: Equatable, Codable {
    public var sourceMachine: String
    public var currentApps: [DockItem]
    public var targetApps: [DockItem]
    public var currentOthers: [DockItem]
    public var targetOthers: [DockItem]
    public var added: [DockItem]
    public var removed: [DockItem]
    public var moved: [DockItem]
    /// In the incoming layout, but not on this Mac, so they will be left out.
    public var missing: [DockItem]
    public var tileSizeChange: SettingChange<Double>?
    public var orientationChange: SettingChange<String>?
    public var folderOptionsChanged: [DockItem]

    public var hasChanges: Bool {
        currentApps.map(\.key) != targetApps.map(\.key) || currentOthers.map(\.key) != targetOthers.map(\.key)
            || tileSizeChange != nil || orientationChange != nil || !folderOptionsChanged.isEmpty
    }
}

public struct SettingChange<Value: Equatable & Codable>: Equatable, Codable {
    public var from: Value?
    public var to: Value
}

public enum Planner {
    /// Latest wins. On a tie a layout edited on that Mac beats one copied from elsewhere,
    /// then the Mac that joined first beats a newer one, so a fresh Mac never overwrites an established setup.
    public static func winner(among machines: [MachineSnapshot]) -> MachineSnapshot? {
        winner(among: machines) { $0.dock.map { ($0.changedAt, $0.basedOn) } }
    }

    /// The same rule for any section: pass how to read its stamp from a snapshot.
    public static func winner(among machines: [MachineSnapshot],
                              stamp: (MachineSnapshot) -> (changedAt: Date, basedOn: String?)?) -> MachineSnapshot? {
        machines.filter { stamp($0) != nil }.min { a, b in
            let (sa, sb) = (stamp(a)!, stamp(b)!)
            if sa.changedAt != sb.changedAt { return sa.changedAt > sb.changedAt }
            if (sa.basedOn == nil) != (sb.basedOn == nil) { return sa.basedOn == nil }
            if a.firstSeenAt != b.firstSeenAt { return a.firstSeenAt < b.firstSeenAt }
            return a.machineID < b.machineID
        }
    }

    /// The shared Dock: every item that any Mac has, minus items someone deliberately removed.
    /// No Mac is in charge. Order, size and position follow the Mac that changed its Dock last,
    /// and items it doesn't have go in next to their neighbours from the Mac that has them.
    public struct MergedDock: Equatable {
        public var target: DockSection
        public var events: [String: DockEvent]
        public var orderSourceID: String
        public var orderSourceName: String
    }

    public static func mergedDock(among machines: [MachineSnapshot], preferring local: Set<String> = [],
                                  orderFrom chosen: String? = nil) -> MergedDock? {
        let docked = machines.filter { $0.dock != nil }
        let pinned = chosen.flatMap { id in docked.first { $0.machineID == id } }
        guard let order = pinned ?? winner(among: docked), let base = order.dock else { return nil }
        var events: [String: DockEvent] = [:]
        for machine in docked {
            for (key, event) in machine.dock?.events ?? startingEvents(machine.dock!) {
                if let current = events[key], !event.beats(current) { continue }
                events[key] = event
            }
        }
        let present = Set(events.filter { $0.value.present }.keys)
        func keep(_ item: DockItem) -> Bool { item.kind == .spacer || present.contains(item.key) }
        var apps = base.apps.filter(keep)
        var others = base.others.filter(keep)
        var placed = Set((apps + others).filter { $0.kind != .spacer }.map(\.key))

        func insert(_ item: DockItem, after previous: String?, inApps: Bool) {
            var list = inApps ? apps : others
            if let previous, let index = list.lastIndex(where: { $0.key == previous }) {
                list.insert(item, at: index + 1)
            } else if previous == nil {
                list.insert(item, at: 0)
            } else {
                list.append(item)
            }
            if inApps { apps = list } else { others = list }
            placed.insert(item.key)
        }
        // Most recently changed Docks first, so the newest neighbours decide where things go.
        let byRecency = docked.sorted { ($0.dock?.changedAt ?? .distantPast) > ($1.dock?.changedAt ?? .distantPast) }
        for machine in byRecency where machine.machineID != order.machineID {
            for (list, inApps) in [(machine.dock?.apps ?? [], true), (machine.dock?.others ?? [], false)] {
                var previous: String?
                for item in list where item.kind != .spacer {
                    if present.contains(item.key), !placed.contains(item.key) { insert(item, after: previous, inApps: inApps) }
                    if placed.contains(item.key) { previous = item.key }
                }
            }
        }
        // Kept by an event but in no Mac's Dock right now (for example, left out where it isn't installed).
        for (key, event) in events.sorted(by: { $0.key < $1.key }) where event.present && !placed.contains(key) {
            if event.inApps { apps.append(event.item) } else { others.append(event.item) }
            placed.insert(key)
        }
        apps = dedupedByName(apps, preferring: local)
        let target = DockSection(changedAt: base.changedAt, basedOn: base.basedOn, apps: apps, others: others,
                                 tileSize: base.tileSize, orientation: base.orientation)
        return MergedDock(target: target, events: events, orderSourceID: order.machineID, orderSourceName: order.machineName)
    }

    /// A Dock from before events existed, or a Mac's first look at its Dock: a starting point.
    public static func startingEvents(_ section: DockSection, at date: Date = Date(timeIntervalSince1970: 0)) -> [String: DockEvent] {
        var events: [String: DockEvent] = [:]
        for item in section.apps where item.kind != .spacer { events[item.key] = DockEvent(present: true, at: date, item: item, inApps: true) }
        for item in section.others where item.kind != .spacer { events[item.key] = DockEvent(present: true, at: date, item: item, inApps: false) }
        return events
    }

    /// The same app can carry a different bundle ID on two Macs (a store build and a direct
    /// download). Show it once, keeping the copy this Mac already has.
    static func dedupedByName(_ items: [DockItem], preferring local: Set<String>) -> [DockItem] {
        var chosen: [String: String] = [:]
        for item in items where item.kind == .app {
            let name = item.label.lowercased()
            if let current = chosen[name], local.contains(current) || !local.contains(item.key) { continue }
            chosen[name] = item.key
        }
        return items.filter { $0.kind != .app || chosen[$0.label.lowercased()] == $0.key }
    }

    public static func resolve(_ item: DockItem, locator: AppLocating) -> String? {
        switch item.kind {
        case .spacer, .url: return ""
        case .app:
            if let id = item.bundleID, let path = locator.path(forBundleID: id) { return path }
            if let path = item.path, locator.exists(path: path) { return DockCapture.expand(path: path) }
            return nil
        case .file, .folder:
            guard let path = item.path, locator.exists(path: path) else { return nil }
            return DockCapture.expand(path: path)
        }
    }

    public static func dockPlan(current: DockSection, target: DockSection, source: String, locator: AppLocating) -> DockPlan {
        let currentKeys = Set((current.apps + current.others).map(\.key))
        var missing: [DockItem] = []
        func available(_ items: [DockItem]) -> [DockItem] {
            items.filter { item in
                if currentKeys.contains(item.key) || resolve(item, locator: locator) != nil { return true }
                missing.append(item)
                return false
            }
        }
        let targetApps = available(target.apps)
        let targetOthers = available(target.others)
        let targetAll = targetApps + targetOthers
        let targetKeys = Set(targetAll.map(\.key))
        let currentAll = current.apps + current.others
        let added = targetAll.filter { !currentKeys.contains($0.key) && $0.kind != .spacer }
        let removed = currentAll.filter { !targetKeys.contains($0.key) && $0.kind != .spacer }
        let moved = movedItems(from: current.apps, to: targetApps) + movedItems(from: current.others, to: targetOthers)
        let currentByKey = Dictionary(currentAll.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let folderChanged = targetAll.filter { item in
            item.kind == .folder && currentByKey[item.key].map { $0.folder != item.folder } == true
        }
        return DockPlan(
            sourceMachine: source,
            currentApps: current.apps, targetApps: targetApps,
            currentOthers: current.others, targetOthers: targetOthers,
            added: added, removed: removed, moved: moved, missing: missing,
            tileSizeChange: target.tileSize.flatMap { $0 == current.tileSize ? nil : SettingChange(from: current.tileSize, to: $0) },
            orientationChange: target.orientation == current.orientation ? nil
                : SettingChange(from: current.orientation, to: target.orientation),
            folderOptionsChanged: folderChanged)
    }

    /// Items present in both lists that are not part of the longest common order.
    static func movedItems(from old: [DockItem], to new: [DockItem]) -> [DockItem] {
        let newKeys = Set(new.map(\.key))
        let oldKeys = Set(old.map(\.key))
        let a = old.filter { newKeys.contains($0.key) && $0.kind != .spacer }
        let b = new.filter { oldKeys.contains($0.key) && $0.kind != .spacer }
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i].key == b[j].key ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var stable = Set<String>()
        var (i, j) = (0, 0)
        while i < a.count, j < b.count {
            if a[i].key == b[j].key {
                stable.insert(a[i].key)
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return b.filter { !stable.contains($0.key) }
    }

    /// Apps on any other Mac that this one lacks. Additive only: MacSync never uninstalls.
    public static func missingApps(local: Inventory, others: [MachineSnapshot]) -> [MissingApp] {
        var found: [AppRef: Set<String>] = [:]
        var details: [String: AppDetail] = [:]
        var downloads: [String: DirectApp] = [:]
        let casks = Set(local.casks)
        let formulae = Set(local.formulae + (local.allFormulae ?? []))
        let store = Set(local.appStore.map(\.id))
        let direct = Set((local.directApps ?? []).map(\.bundleID))
        for machine in others {
            guard let inventory = machine.inventory else { continue }
            for (token, detail) in inventory.details ?? [:] where details[token] == nil { details[token] = detail.sanitized }
            for name in inventory.casks where !casks.contains(name) {
                found[AppRef(source: .cask, name: name), default: []].insert(machine.machineName)
            }
            for name in inventory.formulae where !formulae.contains(name) {
                found[AppRef(source: .formula, name: name), default: []].insert(machine.machineName)
            }
            for app in inventory.appStore where !store.contains(app.id) {
                found[AppRef(source: .appStore, name: app.name, appStoreID: app.id), default: []].insert(machine.machineName)
            }
            for app in inventory.directApps ?? [] where !direct.contains(app.bundleID) {
                found[AppRef(source: .direct, name: app.bundleID), default: []].insert(machine.machineName)
                let known = downloads[app.bundleID]
                if known == nil || (known?.canDownload == false && app.canDownload) { downloads[app.bundleID] = app.sanitized }
                if details[AppRef(source: .direct, name: app.bundleID).token] == nil {
                    details[AppRef(source: .direct, name: app.bundleID).token] = AppDetail(displayName: app.name, bundleID: app.bundleID)
                }
            }
        }
        let all = found.map { ref, machines in
            MissingApp(app: ref, fromMachines: machines.sorted(), detail: details[ref.token],
                       download: ref.source == .direct ? downloads[ref.name] : nil)
        }
            .filter { $0.app.isSafe }
        return dedupedApps(all, localCasks: casks).sorted { $0.app < $1.app }
    }

    /// One row per app. An app downloaded by hand on one Mac and installed with Homebrew on
    /// another (ArtCraft Launcher, Creative Cloud) shows once, as the Homebrew row, which installs
    /// by itself. It is left out entirely when this Mac already has that cask.
    static func dedupedApps(_ apps: [MissingApp], localCasks: Set<String>) -> [MissingApp] {
        var casks: [String: Int] = [:]
        var caskBundles: [String: Int] = [:]
        var caskNames: [String: Int] = [:]
        for (i, app) in apps.enumerated() where app.app.source == .cask {
            casks[app.app.name] = i
            if let id = app.detail?.bundleID { caskBundles[id] = i }
            caskNames[app.displayName.lowercased()] = i
        }
        var result = apps
        var drop = Set<Int>()
        for (i, app) in apps.enumerated() where app.app.source == .direct {
            if let token = app.download?.cask, localCasks.contains(token) { drop.insert(i); continue }
            let twin = app.download?.cask.flatMap { casks[$0] } ?? caskBundles[app.app.name] ?? caskNames[app.displayName.lowercased()]
            guard let twin else { continue }
            result[twin].fromMachines = Array(Set(result[twin].fromMachines + app.fromMachines)).sorted()
            drop.insert(i)
        }
        return result.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
    }
}

/// A set of apps from one developer that MacSync always offers, even when no Mac has them yet.
public struct AppSuite {
    public struct Member { public let cask: String; public let bundleID: String; public let name: String }
    public let name: String
    public let members: [Member]
    /// Its launcher only finds apps in Applications itself, so they are always installed there.

    public static let all: [AppSuite] = [
        AppSuite(name: "ArtCraft", members: [
            Member(cask: "artcraft-launcher", bundleID: "ai.storyteller.artcraft-launcher", name: "ArtCraft Launcher"),
            Member(cask: "artcraft", bundleID: "ai.storyteller.artcraft", name: "ArtCraft"),
            Member(cask: "cadcraft", bundleID: "ai.storyteller.cadcraft", name: "CADCraft"),
            Member(cask: "figcraft", bundleID: "ai.storyteller.figcraft", name: "FigCraft"),
            Member(cask: "soundcraft", bundleID: "ai.storyteller.soundcraft", name: "SoundCraft"),
            Member(cask: "deckcraft", bundleID: "ai.storyteller.deckcraft", name: "DeckCraft"),
            Member(cask: "designcraft", bundleID: "ai.storyteller.designcraft", name: "DesignCraft"),
            Member(cask: "effectcraft", bundleID: "ai.storyteller.effectcraft", name: "EffectCraft"),
            Member(cask: "filmcraft", bundleID: "ai.storyteller.filmcraft", name: "FilmCraft"),
            Member(cask: "gridcraft", bundleID: "ai.storyteller.gridcraft", name: "GridCraft"),
            Member(cask: "lightcraft", bundleID: "ai.storyteller.lightcraft", name: "LightCraft"),
            Member(cask: "pdfcraft", bundleID: "ai.storyteller.pdfcraft", name: "PdfCraft"),
            Member(cask: "photocraft", bundleID: "ai.storyteller.photocraft", name: "PhotoCraft"),
            Member(cask: "vectorcraft", bundleID: "ai.storyteller.vectorcraft", name: "VectorCraft"),
            Member(cask: "wordcraft", bundleID: "ai.storyteller.wordcraft", name: "WordCraft"),
        ]),
    ]
}

public struct MissingApp: Equatable, Identifiable, Codable {
    public var app: AppRef
    public var fromMachines: [String]
    public var detail: AppDetail?
    /// For a downloaded app: where it is published.
    public var download: DirectApp?
    public var id: String { app.token }

    public init(app: AppRef, fromMachines: [String], detail: AppDetail? = nil, download: DirectApp? = nil) {
        self.app = app
        self.fromMachines = fromMachines
        self.detail = detail
        self.download = download
    }

    /// False for a downloaded app whose source isn't known, which MacSync can't fetch.
    public var canInstall: Bool { app.source != .direct || download?.canDownload == true }

    /// The name people recognize: "Android Studio" rather than the cask token.
    public var displayName: String { detail?.displayName ?? app.name }
}

extension AppDetail {
    /// Details come from another Mac's file, so keep them short and the icon ID a plain hex name.
    var sanitized: AppDetail {
        func clean(_ text: String?, _ limit: Int) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let flat = text.components(separatedBy: .controlCharacters).joined(separator: " ")
            return String(flat.prefix(limit))
        }
        let icon = iconID.flatMap { $0.range(of: "^[0-9a-f]{16,64}$", options: .regularExpression) != nil ? $0 : nil }
        let bundle = bundleID.flatMap { DirectApp.isSafeBundleID($0) ? $0 : nil }
        return AppDetail(displayName: clean(displayName, 80), summary: clean(summary, 160), iconID: icon, bundleID: bundle)
    }
}
