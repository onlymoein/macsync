import Foundation

// Share My Setup: a .macsync file a friend opens to get the same apps, tools, settings and
// config. It holds only what this Mac already shares with its own Macs, so nothing that looks
// like a secret is in it, and never fonts or app data (those are licensed to you).

public enum ShareSection: String, Codable, CaseIterable, Identifiable {
    case apps, appStore, tools, packages, settings, config, ai, loginItems
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .apps: return "Apps"
        case .appStore: return "App Store apps"
        case .tools: return "Command-line tools"
        case .packages: return "Extensions, plugins and packages"
        case .settings: return "Settings"
        case .config: return "Config files"
        case .ai: return "AI setup"
        case .loginItems: return "Login items"
        }
    }
    public var detail: String {
        switch self {
        case .apps: return "Homebrew apps and apps from their developers"
        case .appStore: return "Opens each one's App Store page"
        case .tools: return "Homebrew command-line tools and taps"
        case .packages: return "VS Code and Cursor extensions, npm, uv, Claude Code plugins"
        case .settings: return "Trackpad, keyboard, Finder, Dock behaviour, hot corners, screenshots"
        case .config: return "Shell, Git, editors, terminals (fonts stay with you)"
        case .ai: return "Skills, rules, CLAUDE.md, MCP servers, with keys taken out"
        case .loginItems: return "Apps that open at login"
        }
    }
    public var symbol: String {
        switch self {
        case .apps: return "square.grid.2x2.fill"
        case .appStore: return "bag.fill"
        case .tools: return "terminal.fill"
        case .packages: return "puzzlepiece.extension.fill"
        case .settings: return "gearshape.fill"
        case .config: return "doc.text.fill"
        case .ai: return "sparkles"
        case .loginItems: return "power"
        }
    }
    /// Login items are personal, so they start off.
    public static var defaults: Set<ShareSection> { Set(allCases).subtracting([.loginItems]) }
}

public struct SharedSetup: Codable {
    public static let format = "macsync-setup"
    /// The start of a compressed setup file. Older files are plain JSON and still open.
    static let packedMagic = Data("MSZ1".utf8)

    /// The file as written: zlib-compressed, about a third of the JSON's size.
    public static func pack(_ json: Data) -> Data {
        guard let small = try? (json as NSData).compressed(using: .zlib) as Data else { return json }
        return packedMagic + small
    }

    /// The JSON inside a setup file, compressed or not.
    public static func unpack(_ file: Data) -> Data {
        guard file.starts(with: packedMagic),
              let json = try? (file.dropFirst(packedMagic.count) as NSData).decompressed(using: .zlib) as Data else { return file }
        return json
    }
    public var format = SharedSetup.format
    public var version = 1
    public var name: String
    public var createdAt: Date
    public var sections: [ShareSection]
    public var snapshot: MachineSnapshot
    /// File contents by SHA-256, base64.
    public var blobs: [String: String]
}

/// A setup a friend shared with this Mac.
public struct ImportedSetup: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var importedAt: Date
    public var sections: [ShareSection]
    public var machineID: String { "shared:" + id }
}

extension Engine {
    var importedDirectory: URL { env.dataDirectory.appendingPathComponent("shared-setups", isDirectory: true) }

    /// A .macsync file with the chosen sections of this Mac's setup.
    public func exportSetup(name: String, sections: Set<ShareSection>) throws -> Data {
        let snapshot = try sync(refreshInventory: false)
        _ = snapshot
        guard let mine = store.load().machines.first(where: { $0.machineID == env.machineID }) else {
            throw EngineError.refused("This Mac's setup hasn't been saved yet. Try again in a moment.")
        }
        var shared = MachineSnapshot(machineID: "shared", machineName: name, osVersion: mine.osVersion, appVersion: mine.appVersion,
                                     firstSeenAt: now(), savedAt: now(), dock: nil, inventory: nil)
        if var inventory = mine.inventory {
            if !sections.contains(.apps) { inventory.casks = []; inventory.directApps = nil }
            if !sections.contains(.appStore) { inventory.appStore = [] }
            if !sections.contains(.tools) { inventory.formulae = [] }
            inventory.allFormulae = nil
            // Icons live in this person's iCloud, which a friend can't reach.
            inventory.details = inventory.details?.mapValues { var d = $0; d.iconID = nil; return d }
            shared.inventory = inventory
        }
        if sections.contains(.settings), var settings = mine.settings {
            // System settings only: an app's own preferences can hold things about you.
            let curated = Set(SettingsCatalog.all.map(\.id))
            settings.values = settings.values.filter { curated.contains($0.key) && !$0.key.hasSuffix("|location") }
            settings.covered = settings.covered.filter { curated.contains($0) && !$0.hasSuffix("|location") }
            settings.appDomains = []
            settings.changedAt = now()
            settings.basedOn = nil
            shared.settings = settings
        }
        var blobs: [String: String] = [:]
        if var extras = mine.extras {
            let areas = Set([sections.contains(.config) ? FileArea.config : nil, sections.contains(.ai) ? FileArea.ai : nil].compactMap { $0 })
            extras.files = extras.files.filter { path, _ in
                guard let group = ExtrasCatalog.group(for: path) else { return false }
                return areas.contains(group.area) && group.id != "fonts"
            }
            for (path, entry) in extras.files {
                guard let sha = entry.sha else { continue }
                guard let data = FileManager.default.contents(atPath: self.extras.blobs.appendingPathComponent(sha).path),
                      AppDownloader.sha256Hex(data) == sha else { extras.files[path] = nil; continue }
                blobs[sha] = data.base64EncodedString()
            }
            if !sections.contains(.loginItems) { extras.loginItems = [] }
            extras.packages = extras.packages.filter { token in
                let kind = Packages.kind(token)
                if kind == "tap" { return sections.contains(.tools) }
                if kind == "steam" { return false }
                return sections.contains(.packages)
            }
            if !sections.contains(.packages) { extras.marketplaces = nil }
            extras.removals = nil
            shared.extras = extras
        }
        let setup = SharedSetup(name: name, createdAt: now(), sections: ShareSection.allCases.filter(sections.contains),
                                snapshot: shared, blobs: blobs)
        let encoder = JSONEncoder.iso
        encoder.outputFormatting = [.sortedKeys]
        return SharedSetup.pack(try encoder.encode(setup))
    }

    /// Reads a .macsync file. What it holds is offered here like another Mac's setup, under its name.
    @discardableResult
    public func importSetup(_ data: Data) throws -> ImportedSetup {
        guard data.count < 200_000_000,
              let setup = try? JSONDecoder.iso.decode(SharedSetup.self, from: SharedSetup.unpack(data)), setup.format == SharedSetup.format else {
            throw EngineError.refused("That isn't a MacSync setup file.")
        }
        guard setup.version <= 1 else { throw EngineError.refused("That setup was made by a newer MacSync. Update MacSync first.") }
        let fm = FileManager.default
        // Only content that matches its name is kept.
        try? fm.createDirectory(at: extras.blobs, withIntermediateDirectories: true)
        for (sha, encoded) in setup.blobs where sha.count == 64 {
            guard let blob = Data(base64Encoded: encoded), AppDownloader.sha256Hex(blob) == sha else { continue }
            let url = extras.blobs.appendingPathComponent(sha)
            if !fm.fileExists(atPath: url.path) { try? blob.write(to: url, options: .atomic) }
        }
        let name = String(setup.name.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        let id = String(Hashing.sha256(data).prefix(12))
        var snapshot = setup.snapshot
        snapshot.machineID = "shared:" + id
        snapshot.machineName = (name.isEmpty ? "A friend" : name) + "'s setup"
        snapshot.dock = nil
        snapshot.removals = nil
        snapshot.dockOrder = nil
        // Files and settings from the setup count as new here, so they are offered.
        snapshot.settings?.changedAt = now()
        if var files = snapshot.extras?.files {
            for key in files.keys { files[key]?.changedAt = now() }
            snapshot.extras?.files = files
        }
        let info = ImportedSetup(id: id, name: snapshot.machineName, importedAt: now(), sections: setup.sections)
        try fm.createDirectory(at: importedDirectory, withIntermediateDirectories: true)
        try SnapshotCodec.encode(snapshot).write(to: importedDirectory.appendingPathComponent(id + ".json"), options: .atomic)
        try JSONEncoder.iso.encode(info).write(to: importedDirectory.appendingPathComponent(id + ".info"), options: .atomic)
        _ = try? sync(refreshInventory: false)
        return info
    }

    public func importedSetups() -> [ImportedSetup] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: importedDirectory.path)) ?? []
        return names.filter { $0.hasSuffix(".info") }.compactMap { name in
            (try? Data(contentsOf: importedDirectory.appendingPathComponent(name))).flatMap { try? JSONDecoder.iso.decode(ImportedSetup.self, from: $0) }
        }.sorted { $0.importedAt > $1.importedAt }
    }

    /// Stops offering what a shared setup had. Nothing already applied changes.
    public func removeImportedSetup(_ id: String) throws {
        for ext in ["json", "info"] { try? FileManager.default.removeItem(at: importedDirectory.appendingPathComponent("\(id).\(ext)")) }
        try sync(refreshInventory: false)
    }

    /// Setups friends shared, as if they were other Macs. Never published to iCloud.
    func importedSnapshots() -> [MachineSnapshot] {
        importedSetups().compactMap { info in
            (try? Data(contentsOf: importedDirectory.appendingPathComponent(info.id + ".json"))).flatMap { try? SnapshotCodec.decode($0) }
        }
    }
}
