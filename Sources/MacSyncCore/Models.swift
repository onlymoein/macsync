import Foundation

/// One tile in the Dock, in a form that is portable between Macs.
/// Only these allowlisted fields are ever written to iCloud. Bookmark blobs and
/// anything else in the Dock's preferences stay on the Mac they came from.
public struct DockItem: Codable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Codable { case app, folder, file, url, spacer }

    public struct FolderOptions: Codable, Equatable, Hashable {
        public var arrangement: Int?
        public var displayAs: Int?
        public var showAs: Int?
        public var preferredItemSize: Int?
        public init(arrangement: Int? = nil, displayAs: Int? = nil, showAs: Int? = nil, preferredItemSize: Int? = nil) {
            self.arrangement = arrangement
            self.displayAs = displayAs
            self.showAs = showAs
            self.preferredItemSize = preferredItemSize
        }
    }

    public var kind: Kind
    public var label: String
    public var bundleID: String?
    /// Home-relative ("~/Downloads") so it survives different user names.
    public var path: String?
    public var url: String?
    public var spacerStyle: String?
    public var folder: FolderOptions?

    public init(kind: Kind, label: String, bundleID: String? = nil, path: String? = nil, url: String? = nil,
                spacerStyle: String? = nil, folder: FolderOptions? = nil) {
        self.kind = kind
        self.label = label
        self.bundleID = bundleID
        self.path = path
        self.url = url
        self.spacerStyle = spacerStyle
        self.folder = folder
    }

    /// Identity across Macs: apps match on bundle ID because their paths differ.
    public var key: String {
        switch kind {
        case .app: return bundleID.map { "app:\($0)" } ?? "path:\(path ?? label)"
        case .folder, .file: return "path:\(path ?? label)"
        case .url: return "url:\(url ?? label)"
        case .spacer: return "spacer:\(spacerStyle ?? "spacer-tile")"
        }
    }

    public var id: String { key }
}

public struct DockSection: Codable, Equatable {
    public var changedAt: Date
    /// Machine this layout was applied from. Nil means it was edited on this Mac.
    public var basedOn: String?
    public var apps: [DockItem]
    public var others: [DockItem]
    public var tileSize: Double?
    public var orientation: String

    public init(changedAt: Date, basedOn: String? = nil, apps: [DockItem], others: [DockItem],
                tileSize: Double? = nil, orientation: String = "bottom") {
        self.changedAt = changedAt
        self.basedOn = basedOn
        self.apps = apps
        self.others = others
        self.tileSize = tileSize
        self.orientation = orientation
    }

    /// Hash of what the Dock looks like, ignoring when and where it came from.
    public var contentHash: String {
        var copy = self
        copy.changedAt = Date(timeIntervalSince1970: 0)
        copy.basedOn = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(copy)) ?? Data()
        return Hashing.sha256(data)
    }
}

public struct AppStoreApp: Codable, Equatable, Hashable {
    public var id: String
    public var name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Inventory: Codable, Equatable {
    public var brewAvailable: Bool
    public var casks: [String]
    public var formulae: [String]
    public var appStore: [AppStoreApp]
    public init(brewAvailable: Bool = false, casks: [String] = [], formulae: [String] = [], appStore: [AppStoreApp] = []) {
        self.brewAvailable = brewAvailable
        self.casks = casks
        self.formulae = formulae
        self.appStore = appStore
    }
}

public struct MachineSnapshot: Codable, Equatable {
    public var schemaVersion: Int
    public var machineID: String
    public var machineName: String
    public var osVersion: String
    public var appVersion: String
    public var firstSeenAt: Date
    public var savedAt: Date
    public var dock: DockSection?
    public var inventory: Inventory?

    public init(machineID: String, machineName: String, osVersion: String, appVersion: String,
                firstSeenAt: Date, savedAt: Date, dock: DockSection?, inventory: Inventory?) {
        self.schemaVersion = SnapshotCodec.currentVersion
        self.machineID = machineID
        self.machineName = machineName
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.firstSeenAt = firstSeenAt
        self.savedAt = savedAt
        self.dock = dock
        self.inventory = inventory
    }
}

public enum SnapshotError: Error, Equatable, LocalizedError {
    case tooNew(version: Int)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .tooNew(let version):
            return "It was saved by a newer MacSync (format \(version)). Update MacSync on this Mac."
        case .malformed(let why):
            return "It could not be read: \(why)"
        }
    }
}

/// Reads every snapshot format MacSync has shipped.
public enum SnapshotCodec {
    public static let currentVersion = 2
    public static let legacyMachineID = "legacy-v1"

    public static func encode(_ snapshot: MachineSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> MachineSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SnapshotError.malformed("not a JSON object")
        }
        let version = object["schemaVersion"] as? Int ?? 1
        if version > currentVersion { throw SnapshotError.tooNew(version: version) }
        if version == 1 { return try migrateV1(object) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(MachineSnapshot.self, from: data)
        } catch {
            throw SnapshotError.malformed(String(describing: error))
        }
    }

    /// v1 is the Python prototype's snapshot.json: one shared file, apps only in the Dock.
    static func migrateV1(_ object: [String: Any]) throws -> MachineSnapshot {
        guard let host = object["host"] as? String, let dock = object["dock"] as? [[String: Any]] else {
            throw SnapshotError.malformed("v1 snapshot has no host or dock")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let time = (object["time"] as? String).flatMap(formatter.date(from:)) ?? Date(timeIntervalSince1970: 0)
        let items = dock.compactMap { entry -> DockItem? in
            guard let path = entry["path"] as? String else { return nil }
            return DockItem(kind: .app, label: entry["label"] as? String ?? path, path: DockCapture.normalize(path: path))
        }
        let brew = object["brew"] as? [String: Any]
        let appStore = (object["mas"] as? [[String: Any]] ?? []).compactMap { entry -> AppStoreApp? in
            guard let id = entry["id"] as? String else { return nil }
            return AppStoreApp(id: id, name: entry["name"] as? String ?? id)
        }
        return MachineSnapshot(
            machineID: legacyMachineID, machineName: host, osVersion: "unknown", appVersion: "0.1",
            firstSeenAt: time, savedAt: time,
            dock: DockSection(changedAt: time, apps: items, others: []),
            inventory: Inventory(brewAvailable: brew != nil,
                                 casks: brew?["casks"] as? [String] ?? [],
                                 formulae: brew?["formulae"] as? [String] ?? [],
                                 appStore: appStore))
    }
}
