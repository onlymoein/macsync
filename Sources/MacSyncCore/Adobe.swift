import AppKit
import Foundation

/// One installed version of an Adobe app, as Adobe's own uninstaller records it.
public struct AdobeProduct: Equatable, Identifiable, Sendable {
    /// Adobe's product code: IDSN is InDesign, PHSP Photoshop, ILST Illustrator.
    public var sapCode: String
    public var version: String
    public var platform: String
    /// "InDesign 2026": the app's folder name without "Adobe".
    public var label: String
    /// The folder in Applications (Adobe apps live in their own folder).
    public var folder: URL
    /// Adobe's uninstaller for exactly this version.
    public var uninstaller: URL
    public var id: String { sapCode + "#" + version }

    public init(sapCode: String, version: String, platform: String = "macuniversal", label: String, folder: URL, uninstaller: URL) {
        self.sapCode = sapCode; self.version = version; self.platform = platform; self.label = label
        self.folder = folder; self.uninstaller = uninstaller
    }
}

/// Adobe's apps on this Mac: older yearly versions to remove, and updates. Works the same whether
/// Creative Cloud came with a personal plan or a company's Admin Console: both install through
/// Adobe's own installer, which keeps an uninstaller for every version it puts in place.
public struct AdobeApps {
    public static let uninstallFolder = URL(fileURLWithPath: "/Library/Application Support/Adobe/Uninstall")
    static let setup = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup"
    /// Adobe's command-line updater, which comes with company (Admin Console) installs.
    public static let updater = "/usr/local/bin/RemoteUpdateManager"
    public static let creativeCloudBundleID = "com.adobe.acc.AdobeCreativeCloud"

    let uninstallFolder: URL
    let applications: URL
    let runner: CommandRunning

    public init(uninstallFolder: URL = AdobeApps.uninstallFolder, applications: URL = URL(fileURLWithPath: "/Applications"),
                runner: CommandRunning = SystemCommandRunner()) {
        self.uninstallFolder = uninstallFolder; self.applications = applications; self.runner = runner
    }

    /// Every Adobe app version installed here that has its own folder in Applications. Adobe's
    /// shared parts (Camera Raw and the like) have none, so they never show up.
    public func installed() -> [AdobeProduct] {
        let fm = FileManager.default
        let folders = ((try? fm.contentsOfDirectory(atPath: applications.path)) ?? []).filter { $0.hasPrefix("Adobe ") }
        let entries = ((try? fm.contentsOfDirectory(atPath: uninstallFolder.path)) ?? []).filter { $0.hasSuffix(".adbarg") }
        return entries.compactMap { entry -> AdobeProduct? in
            guard let text = try? String(contentsOf: uninstallFolder.appendingPathComponent(entry), encoding: .utf8) else { return nil }
            let values = Self.arguments(text)
            guard let sap = values["sapCode"], let version = values["productVersion"], let name = values["productName"],
                  Self.isSafe(sap), Self.isSafe(version) else { return nil }
            let uninstaller = uninstallFolder.appendingPathComponent(String(entry.dropLast(".adbarg".count)) + ".app")
            guard fm.fileExists(atPath: uninstaller.path) else { return nil }
            // The folder whose app has this major version: "Adobe InDesign 2026" holds InDesign 21.x.
            let major = version.split(separator: ".").first.map(String.init) ?? version
            let folder = folders.first { folder in
                guard folder.hasPrefix("Adobe \(name)") else { return false }
                let dir = applications.appendingPathComponent(folder)
                let app = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).first { $0.hasSuffix(".app") && $0.hasPrefix("Adobe") }
                let short = app.flatMap { NSDictionary(contentsOf: dir.appendingPathComponent($0 + "/Contents/Info.plist"))?["CFBundleShortVersionString"] as? String }
                return short?.split(separator: ".").first.map(String.init) == major
            }
            guard let folder else { return nil }
            return AdobeProduct(sapCode: sap, version: version, platform: values["productPlatform"] ?? "macuniversal",
                                label: String(folder.dropFirst("Adobe ".count)), folder: applications.appendingPathComponent(folder),
                                uninstaller: uninstaller)
        }
        .sorted { ($0.label) < ($1.label) }
    }

    /// Versions with a newer one of the same app installed: InDesign 2026 when 2027 is here.
    public func olderVersions() -> [AdobeProduct] {
        Dictionary(grouping: installed(), by: \.sapCode).values.flatMap { versions -> [AdobeProduct] in
            guard let newest = versions.max(by: { SelfUpdater.isNewer($1.version, than: $0.version) }) else { return [] }
            return versions.filter { $0.id != newest.id }
        }
        .sorted { $0.label < $1.label }
    }

    public var hasUpdater: Bool { FileManager.default.isExecutableFile(atPath: Self.updater) }

    /// "--sapCode=IDSN" lines, as Adobe writes them next to each uninstaller.
    static func arguments(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        // Adobe sometimes runs two lines together ("--mode=2--sapCode=…"), so split on "--".
        for part in text.components(separatedBy: "--") {
            let pair = part.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2, values[pair[0]] == nil { values[pair[0]] = pair[1] }
        }
        return values
    }

    /// Letters, digits and dots only: these go on a command line run as administrator.
    static func isSafe(_ value: String) -> Bool {
        !value.isEmpty && value.count < 40 && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." }
    }

    /// Adobe apps that are open, by name: updating or removing them has to wait until they're closed.
    public static func running() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, id.hasPrefix("com.adobe."), app.activationPolicy == .regular,
                  id != creativeCloudBundleID else { return nil }
            return app.localizedName
        }
    }

    public enum Removal: Equatable { case removed, openedAdobesUninstaller }

    /// Removes one version with Adobe's own installer, quietly, keeping your settings. macOS asks
    /// for the password once. If Adobe's installer doesn't take it, Adobe's uninstaller window for
    /// that version opens instead, so it can always be finished.
    public func remove(_ product: AdobeProduct, askPassword: (_ command: [String], _ prompt: String) -> CommandResult = AdobeApps.runAsAdministrator)
        -> Result<Removal, EngineError> {
        guard Self.isSafe(product.sapCode), Self.isSafe(product.version), Self.isSafe(product.platform) else {
            return .failure(.refused("MacSync couldn't read \(product.label)'s uninstall details."))
        }
        let command = [Self.setup, "--uninstall=1", "--sapCode=\(product.sapCode)", "--baseVersion=\(product.version)",
                       "--platform=\(product.platform)", "--deleteUserPreferences=false"]
        let result = askPassword(command, "MacSync wants to remove \(product.label) with Adobe's installer.")
        if result.status == 0, !FileManager.default.fileExists(atPath: product.folder.path) { return .success(.removed) }
        // Cancelled at the password prompt: nothing else happens.
        if result.stderr.contains("-128") || result.stderr.lowercased().contains("user canceled") {
            return .failure(.refused("Not removed: the password was cancelled."))
        }
        NSWorkspace.shared.open(product.uninstaller)
        return .success(.openedAdobesUninstaller)
    }

    /// Installs every Adobe update with Adobe's updater (company installs), macOS asking for the
    /// password once. Personal plans have no such updater: Creative Cloud updates those apps.
    public func updateAll(askPassword: (_ command: [String], _ prompt: String) -> CommandResult = AdobeApps.runAsAdministrator)
        -> Result<String, EngineError> {
        guard hasUpdater else { return .failure(.refused("Adobe's updater isn't on this Mac.")) }
        let result = askPassword([Self.updater], "MacSync wants to install Adobe's updates.")
        if result.stderr.contains("-128") { return .failure(.refused("Not updated: the password was cancelled.")) }
        // "RemoteUpdateManager exiting with Return Code (0)" is success; 2 means some didn't go in.
        let text = result.output + result.stderr
        if result.status == 0, text.contains("Return Code (0)") || !text.contains("Return Code") { return .success("Adobe apps are up to date") }
        return .failure(.refused("Some Adobe updates didn't go in. Close the Adobe apps and try again, or update in Creative Cloud."))
    }

    public static func openCreativeCloud() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: creativeCloudBundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// macOS's own password window, the one installers use, then the command as administrator.
    public static func runAsAdministrator(_ command: [String], prompt: String) -> CommandResult {
        let script = """
        on run argv
            set cmd to ""
            repeat with i from 2 to count of argv
                set cmd to cmd & quoted form of (item i of argv) & " "
            end repeat
            do shell script cmd with prompt (item 1 of argv) with administrator privileges
        end run
        """
        return SystemCommandRunner().run("/usr/bin/osascript", ["-e", script, prompt] + command, input: nil, environment: [:])
    }
}
