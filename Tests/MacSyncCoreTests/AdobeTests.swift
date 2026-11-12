import XCTest
@testable import MacSyncCore

final class AdobeTests: XCTestCase {
    /// A pretend Mac: Adobe's uninstall entries and the app folders they belong to.
    func world(_ apps: [(folder: String, app: String, version: String, sap: String, entry: String, base: String)]) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("adobe-\(UUID().uuidString.prefix(6))")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let uninstall = root.appendingPathComponent("Uninstall"), applications = root.appendingPathComponent("Applications")
        for a in apps {
            let contents = applications.appendingPathComponent("\(a.folder)/\(a.app).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            (["CFBundleShortVersionString": a.version] as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
            try FileManager.default.createDirectory(at: uninstall.appendingPathComponent(a.entry + ".app"), withIntermediateDirectories: true)
            let name = a.folder.dropFirst("Adobe ".count).split(separator: " ").dropLast().joined(separator: " ")
            try "--sapCode=\(a.sap)\n--productVersion=\(a.base)\n--productPlatform=macuniversal\n--productName=\(name)\n--mode=2"
                .write(to: uninstall.appendingPathComponent(a.entry + ".adbarg"), atomically: true, encoding: .utf8)
        }
        // A shared part with no app folder of its own.
        try "--sapCode=ACR\n--productVersion=19.0\n--productName=Camera Raw".write(to: uninstall.appendingPathComponent("ACR_19_0.adbarg"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: uninstall.appendingPathComponent("ACR_19_0.app"), withIntermediateDirectories: true)
        return (uninstall, applications)
    }

    func testOlderYearlyVersionsAreFound() throws {
        let (uninstall, applications) = try world([
            ("Adobe InDesign 2026", "Adobe InDesign 2026", "21.6.0.57", "IDSN", "IDSN_21_6_32", "21.6"),
            ("Adobe InDesign 2027", "Adobe InDesign 2027", "22.0.0.104", "IDSN", "IDSN_22_0_32", "22.0"),
            ("Adobe Photoshop 2027", "Adobe Photoshop 2027", "28.0", "PHSP", "PHSP_28_0_32", "28.0"),
        ])
        let adobe = AdobeApps(uninstallFolder: uninstall, applications: applications)
        XCTAssertEqual(adobe.installed().map(\.label), ["InDesign 2026", "InDesign 2027", "Photoshop 2027"])
        XCTAssertEqual(adobe.olderVersions().map(\.label), ["InDesign 2026"])
    }

    func testRemovalUsesAdobesInstallerWithItsOwnValues() throws {
        let (uninstall, applications) = try world([
            ("Adobe InDesign 2026", "Adobe InDesign 2026", "21.6.0.57", "IDSN", "IDSN_21_6_32", "21.6"),
            ("Adobe InDesign 2027", "Adobe InDesign 2027", "22.0.0.104", "IDSN", "IDSN_22_0_32", "22.0"),
        ])
        let adobe = AdobeApps(uninstallFolder: uninstall, applications: applications)
        let old = try XCTUnwrap(adobe.olderVersions().first)
        var ran: [String] = []
        let result = adobe.remove(old) { command, _ in
            ran = command
            try? FileManager.default.removeItem(at: old.folder)  // what Adobe's installer does
            return CommandResult(status: 0)
        }
        guard case .success(.removed) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(ran, [AdobeApps.setup, "--uninstall=1", "--sapCode=IDSN", "--baseVersion=21.6", "--platform=macuniversal",
                             "--deleteUserPreferences=false"])
        // A cancelled password does nothing else.
        let cancelled = adobe.remove(old) { _, _ in CommandResult(status: 1, stderr: "execution error: User canceled. (-128)") }
        guard case .failure(let error) = cancelled else { return XCTFail("should refuse") }
        XCTAssertEqual(error.localizedDescription, "Not removed: the password was cancelled.")
    }

    func testOddValuesNeverReachTheCommandLine() {
        XCTAssertTrue(AdobeApps.isSafe("21.6"))
        XCTAssertFalse(AdobeApps.isSafe("21.6; rm -rf /"))
        XCTAssertEqual(AdobeApps.arguments("--mode=2--sapCode=IDSN\n--productVersion=22.0")["sapCode"], "IDSN")
    }

    /// This Mac's real Adobe apps, read only (nothing is removed).
    func testReadsThisMacsAdobeApps() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: AdobeApps.uninstallFolder.path), "no Adobe apps here")
        let adobe = AdobeApps()
        print("adobe installed:", adobe.installed().map { "\($0.label) (\($0.sapCode) \($0.version))" })
        print("adobe older:", adobe.olderVersions().map(\.label), "updater:", adobe.hasUpdater)
    }
}
