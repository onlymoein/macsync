import CryptoKit
import Foundation
import IOKit

enum Hashing {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Where MacSync reads and writes. Every location can be overridden so tests, and a
/// simulated second Mac, never touch the real Dock or iCloud Drive.
public struct MacSyncEnvironment {
    public var syncDirectory: URL
    public var dataDirectory: URL
    public var machineID: String
    public var machineName: String
    public var dockFile: URL?
    public var brewPath: String?
    public var applicationsDirectory: URL
    public var homeDirectory: String

    public static let appVersion = "0.3.3"

    public var iCloudAvailable: Bool {
        FileManager.default.fileExists(atPath: syncDirectory.deletingLastPathComponent().path)
    }

    public static func current(_ env: [String: String] = ProcessInfo.processInfo.environment) -> MacSyncEnvironment {
        let home = NSHomeDirectory()
        let sync = env["MACSYNC_SYNC_DIR"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: home).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/MacSync")
        let data = env["MACSYNC_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/MacSync")
        return MacSyncEnvironment(
            syncDirectory: sync,
            dataDirectory: data,
            machineID: env["MACSYNC_MACHINE_ID"] ?? hardwareMachineID(),
            machineName: env["MACSYNC_MACHINE_NAME"] ?? Host.current().localizedName ?? "This Mac",
            dockFile: env["MACSYNC_DOCK_FILE"].map { URL(fileURLWithPath: $0) },
            brewPath: env["MACSYNC_BREW"] ?? ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
                .first { FileManager.default.isExecutableFile(atPath: $0) },
            applicationsDirectory: env["MACSYNC_APPLICATIONS"].map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: "/Applications"),
            homeDirectory: home)
    }

    /// Stable per machine, so restoring a backup onto a new Mac gives it its own identity.
    /// Only a hash leaves the machine, never the hardware UUID itself.
    static func hardwareMachineID() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        let raw = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        return String(Hashing.sha256(Data((raw ?? NSHomeDirectory()).utf8)).prefix(16))
    }
}

/// Runs external tools with no stdin, so nothing can hang waiting for a password.
public protocol CommandRunning {
    func run(_ executable: String, _ arguments: [String], input: Data?, environment: [String: String]) -> CommandResult
}

public struct CommandResult {
    public var status: Int32
    public var stdout: Data
    public var stderr: String
    public var output: String { String(decoding: stdout, as: UTF8.self) }
    public init(status: Int32, stdout: Data = Data(), stderr: String = "") {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct SystemCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], input: Data? = nil,
                    environment: [String: String] = [:]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let inPipe = input == nil ? nil : Pipe()
        process.standardInput = inPipe ?? FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stderr: "Could not run \(executable): \(error.localizedDescription)")
        }
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if let inPipe, let input {
            inPipe.fileHandleForWriting.write(input)
            inPipe.fileHandleForWriting.closeFile()
        }
        group.wait()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, stdout: outData,
                             stderr: String(decoding: errData, as: UTF8.self))
    }
}
