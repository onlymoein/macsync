import XCTest
@testable import MacSyncCore

final class CraftRecordsTests: XCTestCase {
    /// Pretends to be Homebrew with pdfcraft recorded at 0.20.0 while its cask says 0.21.1.
    final class Brew: CommandRunning {
        var calls: [[String]] = []
        var sha = ""
        var target = ""
        var cache = ""
        var recorded = "0.20.0"
        func run(_ executable: String, _ arguments: [String], input: Data?, environment: [String: String]) -> CommandResult {
            calls.append([executable] + arguments)
            if executable == "/usr/bin/curl" { return CommandResult(status: 1, stderr: "no network in tests") }
            switch (arguments.first ?? "", arguments.dropFirst().first ?? "") {
            case ("outdated", _): return CommandResult(status: 0, stdout: Data(#"{"formulae":[],"casks":[{"name":"pdfcraft","installed_versions":["\#(recorded)"],"current_version":"0.21.1"},{"name":"ghostty"}]}"#.utf8))
            case ("info", _): return CommandResult(status: 0, stdout: Data(#"{"casks":[{"token":"pdfcraft","version":"0.21.1","sha256":"\#(sha)","artifacts":[{"app":["PdfCraft.app"],"target":"\#(target)"}]}]}"#.utf8))
            case ("--cache", _): return CommandResult(status: 0, stdout: Data((cache + "\n").utf8))
            case ("upgrade", _):
                // Homebrew uses the file already in its cache; it would download if it weren't there.
                guard FileManager.default.fileExists(atPath: cache) else { return CommandResult(status: 1, stderr: "would download") }
                recorded = "0.21.1"
                return CommandResult(status: 0)
            case ("list", _): return CommandResult(status: 0, stdout: Data("pdfcraft \(recorded)\n".utf8))
            default: return CommandResult(status: 0)
            }
        }
    }

    func world() throws -> (MacSyncEnvironment, URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("craftrec-\(UUID().uuidString.prefix(6))")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appendingPathComponent("launcher/downloads"), apps = root.appendingPathComponent("Applications/Artcraft")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let contents = apps.appendingPathComponent("PdfCraft.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        (["CFBundleShortVersionString": "0.21.1", "CFBundleIdentifier": "ai.storyteller.pdfcraft"] as NSDictionary)
            .write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        let env = MacSyncEnvironment(syncDirectory: root.appendingPathComponent("sync"), dataDirectory: root.appendingPathComponent("data"),
                                     machineID: "t", machineName: "T", dockFile: nil, brewPath: "/opt/fake/bin/brew",
                                     applicationsDirectory: root.appendingPathComponent("Applications"), homeDirectory: root.path)
        return (env, downloads, apps.appendingPathComponent("PdfCraft.app"), root)
    }

    func testTheLaunchersDownloadFixesHomebrewsRecordWithoutDownloading() throws {
        let (env, downloads, app, root) = try world()
        let brew = Brew()
        brew.target = app.path
        brew.cache = root.appendingPathComponent("brewcache/abc--pdfcraft-0.21.1-macos-universal.dmg").path
        let records = CraftRecords(env: env, runner: brew, launcherDownloads: downloads, isRunning: { _ in false })

        // The launcher downloads the disk image, installs from it and deletes it.
        let dmg = downloads.appendingPathComponent("pdfcraft-0.21.1-macos-universal.dmg")
        try Data("the disk image".utf8).write(to: dmg)
        brew.sha = try XCTUnwrap(AppDownloader.sha256(of: dmg))
        XCTAssertEqual(records.catchDownloads(), ["pdfcraft-0.21.1-macos-universal.dmg"])
        try FileManager.default.removeItem(at: dmg)

        XCTAssertEqual(records.reconcile(), ["pdfcraft"])
        XCTAssertEqual(brew.recorded, "0.21.1")
        XCTAssertTrue(brew.calls.contains(["/opt/fake/bin/brew", "upgrade", "--cask", "--greedy", "pdfcraft"]))
        XCTAssertFalse(brew.calls.contains { $0.first == "/usr/bin/curl" }, "nothing downloaded")
        XCTAssertTrue(records.keptFiles().isEmpty, "the kept link goes once it's used")
    }

    func testNothingHappensWithoutAMatchingFileOrWhenTheAppIsntThatVersion() throws {
        let (env, downloads, app, root) = try world()
        let brew = Brew()
        brew.target = app.path
        brew.cache = root.appendingPathComponent("brewcache/x.dmg").path
        let records = CraftRecords(env: env, runner: brew, launcherDownloads: downloads, isRunning: { _ in false })
        // A file whose checksum isn't the cask's.
        try Data("something else".utf8).write(to: downloads.appendingPathComponent("other.dmg"))
        brew.sha = String(repeating: "0", count: 64)
        records.catchDownloads()
        XCTAssertEqual(records.reconcile(), [])
        XCTAssertFalse(brew.calls.contains { $0.count > 1 && $0[1] == "upgrade" })

        // The right file, but the app on disk is still older: that's a real update, the launcher's to do.
        let dmg = downloads.appendingPathComponent("pdfcraft.dmg")
        try Data("the disk image".utf8).write(to: dmg)
        brew.sha = try XCTUnwrap(AppDownloader.sha256(of: dmg))
        records.catchDownloads()
        (["CFBundleShortVersionString": "0.20.0"] as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        XCTAssertEqual(records.reconcile(), [])
    }

    func testAnOpenAppWaits() throws {
        let (env, downloads, app, root) = try world()
        let brew = Brew()
        brew.target = app.path
        brew.cache = root.appendingPathComponent("brewcache/x.dmg").path
        let dmg = downloads.appendingPathComponent("pdfcraft.dmg")
        try Data("the disk image".utf8).write(to: dmg)
        brew.sha = try XCTUnwrap(AppDownloader.sha256(of: dmg))
        let records = CraftRecords(env: env, runner: brew, launcherDownloads: downloads, isRunning: { $0 == "ai.storyteller.pdfcraft" })
        records.catchDownloads()
        XCTAssertEqual(records.reconcile(), [])
        XCTAssertEqual(records.keptFiles().count, 1, "kept for the next round")
    }
}
