import Foundation

public enum SyncStoreError: Error, LocalizedError {
    case iCloudUnavailable
    public var errorDescription: String? {
        "iCloud Drive isn't available. Turn it on in System Settings, under your Apple Account, then iCloud."
    }
}

/// One file per Mac, each with a single writer, so iCloud never has to merge anything.
public struct SyncStore {
    public struct Loaded {
        public var machines: [MachineSnapshot] = []
        public var issues: [String] = []
    }

    let env: MacSyncEnvironment
    var machinesDirectory: URL { env.syncDirectory.appendingPathComponent("machines", isDirectory: true) }

    public init(env: MacSyncEnvironment) { self.env = env }

    public func save(_ snapshot: MachineSnapshot) throws {
        guard env.iCloudAvailable else { throw SyncStoreError.iCloudUnavailable }
        try FileManager.default.createDirectory(at: machinesDirectory, withIntermediateDirectories: true)
        let url = machinesDirectory.appendingPathComponent("\(snapshot.machineID).json")
        let data = try SnapshotCodec.encode(snapshot)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    public func load() -> Loaded {
        var loaded = Loaded()
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: machinesDirectory.path)) ?? []
        for name in names.sorted() {
            let url = machinesDirectory.appendingPathComponent(name)
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                // Older macOS keeps a placeholder until the file is downloaded.
                try? fm.startDownloadingUbiquitousItem(at: url)
                loaded.issues.append("Waiting for iCloud to download another Mac's setup.")
                continue
            }
            // iCloud conflict copies ("id 2.json") are ignored: the original is authoritative.
            guard name.hasSuffix(".json"), !name.contains(" ") else { continue }
            read(url, expectedID: String(name.dropLast(5)), into: &loaded)
        }
        let legacy = env.syncDirectory.appendingPathComponent("snapshot.json")
        if fm.fileExists(atPath: legacy.path) { read(legacy, expectedID: nil, into: &loaded) }
        return loaded
    }

    private func read(_ url: URL, expectedID: String?, into loaded: inout Loaded) {
        var coordinationError: NSError?
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            data = try? Data(contentsOf: target)
        }
        guard let data else {
            loaded.issues.append("Couldn't read \(url.lastPathComponent) from iCloud yet.")
            return
        }
        do {
            let snapshot = try SnapshotCodec.decode(data)
            if let expectedID, snapshot.machineID != expectedID {
                loaded.issues.append("Ignored \(url.lastPathComponent): its contents belong to another Mac.")
            } else {
                loaded.machines.append(snapshot)
            }
        } catch {
            loaded.issues.append("Skipped \(url.lastPathComponent). \(error.localizedDescription)")
        }
    }
}
