import AppKit
import Foundation

/// The Dock's preferences as a whole plist, so a backup restores it byte for byte in meaning.
public protocol DockStoring {
    func exportPlist() throws -> Data
    func importPlist(_ data: Data) throws
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

    public func restartDock() {
        _ = runner.run("/usr/bin/killall", ["Dock"], input: nil, environment: [:])
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

    public func importPlist(_ data: Data) throws { try data.write(to: url, options: .atomic) }
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
