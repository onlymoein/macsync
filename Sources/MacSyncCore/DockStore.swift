import AppKit
import Foundation

/// The Dock's preferences as a whole plist, so a backup restores it byte for byte in meaning.
public protocol DockStoring {
    func exportPlist() throws -> Data
    /// Merges into the existing preferences, which is how `defaults import` really behaves.
    func importPlist(_ data: Data) throws
    func removeKeys(_ keys: [String]) throws
    func restartDock()
}

public enum DockStoreError: Error, LocalizedError {
    case failed(String)
    public var errorDescription: String? {
        if case .failed(let why) = self { return why }
        return nil
    }
}

public extension DockStoring {
    /// Makes the preferences exactly this plist, removing keys it doesn't have.
    func replacePlist(_ data: Data) throws {
        guard let incoming = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DockStoreError.failed("That Dock backup is not in the expected format.")
        }
        let extra = Array(Set(try readRaw().keys).subtracting(incoming.keys))
        try importPlist(data)
        if !extra.isEmpty { try removeKeys(extra) }
    }

    func readRaw() throws -> [String: Any] {
        let data = try exportPlist()
        guard let raw = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DockStoreError.failed("The Dock's preferences are not in the expected format.")
        }
        return raw
    }
}

public struct SystemDockStore: DockStoring {
    let runner: CommandRunning
    let settleMicroseconds: UInt32 = 1_500_000
    public init(runner: CommandRunning = SystemCommandRunner()) { self.runner = runner }

    public func exportPlist() throws -> Data {
        let result = runner.run("/usr/bin/defaults", ["export", "com.apple.dock", "-"], input: nil, environment: [:])
        guard result.status == 0, !result.stdout.isEmpty else {
            throw DockStoreError.failed("Could not read the Dock's preferences: \(result.stderr)")
        }
        return result.stdout
    }

    public func importPlist(_ data: Data) throws {
        let result = runner.run("/usr/bin/defaults", ["import", "com.apple.dock", "-"], input: data, environment: [:])
        guard result.status == 0 else {
            throw DockStoreError.failed("Could not write the Dock's preferences: \(result.stderr)")
        }
    }

    public func removeKeys(_ keys: [String]) throws {
        for key in keys {
            let result = runner.run("/usr/bin/defaults", ["delete", "com.apple.dock", key], input: nil, environment: [:])
            guard result.status == 0 else {
                throw DockStoreError.failed("Could not remove \(key) from the Dock's preferences: \(result.stderr)")
            }
        }
    }

    /// Returns once a new Dock is running. It must be SIGKILL: a Dock that restarted recently
    /// saves its in-memory list on SIGTERM, which overwrites what was just written. Verified on
    /// macOS 27.3. launchd relaunches the Dock either way, and it holds no state worth keeping.
    public func restartDock() {
        let before = dockPID()
        _ = runner.run("/usr/bin/killall", ["-KILL", "Dock"], input: nil, environment: [:])
        for _ in 0..<50 {
            usleep(100_000)
            if let now = dockPID(), now != before { break }
        }
        usleep(settleMicroseconds)
    }

    private func dockPID() -> String? {
        let result = runner.run("/usr/bin/pgrep", ["-x", "Dock"], input: nil, environment: [:])
        return result.status == 0 ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
}

/// A Dock kept in a plain file. Used by tests and the simulated second Mac.
public final class FileDockStore: DockStoring {
    let url: URL
    public private(set) var restarts = 0
    public init(url: URL) { self.url = url }

    public func exportPlist() throws -> Data {
        guard let data = try? Data(contentsOf: url) else { throw DockStoreError.failed("No Dock file at \(url.path)") }
        return data
    }

    public func importPlist(_ data: Data) throws {
        var merged = (try? readRaw()) ?? [:]
        let incoming = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
        merged.merge(incoming) { $1 }
        try write(merged)
    }

    public func removeKeys(_ keys: [String]) throws {
        var raw = try readRaw()
        for key in keys { raw[key] = nil }
        try write(raw)
    }

    private func write(_ raw: [String: Any]) throws {
        try PropertyListSerialization.data(fromPropertyList: raw, format: .xml, options: 0).write(to: url, options: .atomic)
    }

    public func restartDock() { restarts += 1 }
}

public struct SystemAppLocator: AppLocating {
    public init() {}

    public func path(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              !url.path.contains("/.Trash/") else { return nil }
        return url.path
    }

    public func exists(path: String) -> Bool {
        FileManager.default.fileExists(atPath: DockCapture.expand(path: path))
    }
}
