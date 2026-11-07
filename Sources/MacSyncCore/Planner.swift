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
        machines.filter { $0.dock != nil }.min { a, b in
            let (da, db) = (a.dock!, b.dock!)
            if da.changedAt != db.changedAt { return da.changedAt > db.changedAt }
            if (da.basedOn == nil) != (db.basedOn == nil) { return da.basedOn == nil }
            if a.firstSeenAt != b.firstSeenAt { return a.firstSeenAt < b.firstSeenAt }
            return a.machineID < b.machineID
        }
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
        let casks = Set(local.casks)
        let formulae = Set(local.formulae)
        let store = Set(local.appStore.map(\.id))
        for machine in others {
            guard let inventory = machine.inventory else { continue }
            for name in inventory.casks where !casks.contains(name) {
                found[AppRef(source: .cask, name: name), default: []].insert(machine.machineName)
            }
            for name in inventory.formulae where !formulae.contains(name) {
                found[AppRef(source: .formula, name: name), default: []].insert(machine.machineName)
            }
            for app in inventory.appStore where !store.contains(app.id) {
                found[AppRef(source: .appStore, name: app.name, appStoreID: app.id), default: []].insert(machine.machineName)
            }
        }
        return found.map { MissingApp(app: $0.key, fromMachines: $0.value.sorted()) }.filter { $0.app.isSafe }
            .sorted { $0.app < $1.app }
    }
}

public struct MissingApp: Equatable, Identifiable, Codable {
    public var app: AppRef
    public var fromMachines: [String]
    public var id: String { app.token }
}
