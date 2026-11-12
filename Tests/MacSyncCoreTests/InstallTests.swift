@testable import MacSyncCore
import XCTest

final class InstallLocationTests: XCTestCase {
    func testKnowsWhereItRuns() {
        let home = "/Users/someone"
        XCTAssertTrue(AppInstallLocation(appURL: URL(fileURLWithPath: "/Applications/MacSync.app"), home: home).isInApplications)
        XCTAssertTrue(AppInstallLocation(appURL: URL(fileURLWithPath: "/Users/someone/Applications/MacSync.app"), home: home).isInApplications)
        XCTAssertFalse(AppInstallLocation(appURL: URL(fileURLWithPath: "/Users/someone/Downloads/MacSync.app"), home: home).isInApplications)
        XCTAssertFalse(AppInstallLocation(appURL: URL(fileURLWithPath: "/Applications/Tools/MacSync.app"), home: home).isInApplications)
        let hidden = AppInstallLocation(appURL: URL(fileURLWithPath: "/private/var/folders/x/T/AppTranslocation/ABC/d/MacSync.app"), home: home)
        XCTAssertTrue(hidden.isTranslocated)
        XCTAssertFalse(hidden.isInApplications)
        XCTAssertTrue(AppInstallLocation(appURL: URL(fileURLWithPath: "/Volumes/MacSync/MacSync.app"), home: home).isOnDiskImage)
    }

    func testMovesItselfAndReplacesAnOlderCopy() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("macsync-move-\(UUID().uuidString.prefix(6))")
        defer { try? fm.removeItem(at: root) }
        func makeApp(_ url: URL, version: String) throws {
            let contents = url.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        let downloaded = root.appendingPathComponent("Downloads/MacSync.app")
        let installed = root.appendingPathComponent("Applications/MacSync.app")
        try makeApp(downloaded, version: "0.9.0")
        try makeApp(installed, version: "0.8.0")
        let result = AppInstallLocation(appURL: downloaded).move(to: installed, runner: SystemCommandRunner())
        XCTAssertEqual(try result.get(), installed)
        let version = NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(version, "0.9.0")
        XCTAssertFalse(fm.fileExists(atPath: downloaded.path), "the downloaded copy goes to the Trash")
    }
}
