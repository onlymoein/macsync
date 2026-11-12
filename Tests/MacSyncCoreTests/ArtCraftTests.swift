@testable import MacSyncCore
import XCTest

final class ArtCraftTests: XCTestCase {
    func testCatalogKeepsMacDiskImagesFromArtCraftOnly() {
        let json = Data("""
        {"success":true,"release_info":{"apps":{
          "photocraft":{"name":"PhotoCraft","latest_release":{"version":"0.22.0","prerelease":false,"assets":[
            {"download_url":"https://github.com/storytold/photocraft/releases/download/v0.22.0/p.dmg","sha256":"ABC","size_bytes":10,
             "platform":{"os":"macos","arch":"universal","package_type":"dmg"}},
            {"download_url":"https://github.com/storytold/photocraft/releases/download/v0.22.0/p.zip","platform":{"os":"macos","arch":"universal","package_type":"cli_zip"}}]}},
          "evil":{"name":"Evil","latest_release":{"version":"1.0","assets":[
            {"download_url":"https://example.com/e.dmg","platform":{"os":"macos","arch":"universal","package_type":"dmg"}}]}},
          "winonly":{"name":"WinOnly","latest_release":{"version":"1.0","assets":[
            {"download_url":"https://github.com/storytold/w/w.exe","platform":{"os":"windows","arch":"x86_64","package_type":"exe"}}]}}
        }}}
        """.utf8)
        let apps = ArtCraft.parse(json)
        XCTAssertEqual(apps.map(\.id), ["photocraft"])
        XCTAssertEqual(apps.first?.sha256, "abc")
        XCTAssertEqual(apps.first?.version, "0.22.0")
    }

    func testLauncherCatalogListsEveryAppWithItsDetails() {
        let toml = """
        # ArtCraft Launcher catalog
        [[apps]]
        id = "photocraft"
        mac_bundle_id = "ai.storyteller.photocraft"
        mac_bundle_name = "PhotoCraft"
        mac_team = "DJ6XS33FX8"
        name = "PhotoCraft"
        repo = "storytold/photocraft"
        tagline = "Image editing"
        [apps.details]
        headline = "Not needed"
        [[apps]]
        id = "solidcraft"
        name = "SolidCraft"
        publisher = "Tangency Labs"
        repo = "tangency-labs/solidcraft"
        [[apps]]
        id = "Bad ID!"
        name = "Nope"
        """
        let listings = ArtCraft.parseLauncherCatalog(toml)
        XCTAssertEqual(listings.map(\.id), ["photocraft", "solidcraft"])
        XCTAssertEqual(listings[0].fields["mac_team"], "DJ6XS33FX8")
        XCTAssertNil(listings[0].fields["headline"])
        XCTAssertEqual(listings[1].fields["publisher"], "Tangency Labs")
    }

    func testUpdateIsOfferedOnlyForANewerVersion() {
        var app = CraftApp(id: "x", name: "X", version: "0.20.0", dmgURL: "https://github.com/storytold/x/x.dmg")
        XCTAssertFalse(app.needsUpdate)
        app.installedVersion = "0.19.0"
        XCTAssertTrue(app.needsUpdate)
        app.installedVersion = "0.20.0"
        XCTAssertFalse(app.needsUpdate)
    }

    func testRemoveTrashesTheAppAndTakesItOffTheLaunchersList() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ac-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("Applications/Artcraft")
        let app = folder.appendingPathComponent("PhotoCraft.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: app.appendingPathComponent("Info.plist"))
        let env = MacSyncEnvironment(syncDirectory: home.appendingPathComponent("sync"), dataDirectory: home.appendingPathComponent("data"),
                                     machineID: "t", machineName: "T", dockFile: nil, brewPath: nil,
                                     applicationsDirectory: home.appendingPathComponent("Applications"), homeDirectory: home.path)
        let craft = ArtCraft(env: env, runner: FakeRunner(), now: Date.init)
        try FileManager.default.createDirectory(at: craft.recordsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"apps":{"photocraft":{"path":"x"},"vectorcraft":{"path":"y"}}}"#.utf8).write(to: craft.recordsURL)
        var photo = CraftApp(id: "photocraft", name: "PhotoCraft", version: "1", dmgURL: "https://github.com/storytold/p/p.dmg")
        photo.installedVersion = "1"
        photo.installedPath = folder.appendingPathComponent("PhotoCraft.app").path
        let results = craft.remove([photo])
        if case .failure(let e) = results[0].1 { XCTFail(e.localizedDescription) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: photo.installedPath!))
        XCTAssertEqual(Set(craft.records().keys), ["vectorcraft"])
    }
}

final class SigningTests: XCTestCase {
    func testReadsTheTeamOfARealApp() throws {
        let craft = URL(fileURLWithPath: "/Applications/Artcraft/CADCraft.app")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: craft.path), "needs CADCraft installed")
        guard case .team(let team) = ArtCraft.signingTeam(of: craft, within: 10) else { return XCTFail("no team") }
        XCTAssertEqual(team.count, 10)
        guard case .unsigned = ArtCraft.signingTeam(of: URL(fileURLWithPath: "/tmp"), within: 10) else { return XCTFail("tmp isn't signed") }
    }
}

/// Runs the real download, disk image, signature and copy steps. Off unless MACSYNC_LIVE_CRAFT=1.
final class LiveCraftInstallTests: XCTestCase {
    func testInstallsCADCraftForReal() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MACSYNC_LIVE_CRAFT"] == "1", "live test")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macsync-live-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: root) }
        let apps = root.appendingPathComponent("Applications"), home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let env = MacSyncEnvironment(syncDirectory: root.appendingPathComponent("sync"), dataDirectory: root.appendingPathComponent("data"),
                                     machineID: "t", machineName: "T", dockFile: nil, brewPath: nil, applicationsDirectory: apps,
                                     homeDirectory: home.path)
        var app = CraftApp(id: "cadcraft", name: "CADCraft", version: "0.20.0",
                           dmgURL: "https://github.com/storytold/cadcraft/releases/download/v0.20.0/cadcraft-0.20.0-macos-universal.dmg",
                           sha256: nil, sizeBytes: 84_679_812)
        app.team = "DJ6XS33FX8"
        app.bundleName = "CADCraft"
        var steps: [String] = []
        let started = Date()
        let results = ArtCraft(env: env, runner: SystemCommandRunner(), now: Date.init).install([app], progress: { steps.append($0) })
        let seconds = Date().timeIntervalSince(started)
        print("steps:", Set(steps.map { $0.components(separatedBy: "…")[0] }).sorted(), "seconds:", Int(seconds))
        guard case .success(let path)? = results.first?.1 else { return XCTFail("failed: \(String(describing: results.first?.1))") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + "/Contents/Info.plist"))
        XCTAssertLessThan(seconds, 120)
    }
}

final class UnlistedCraftTests: XCTestCase {
    func testAnInstalledAppMissingFromTheLaunchersListIsAdded() throws {
        let world = try TestWorld()
        let root = world.root
        let home = root.appendingPathComponent("home"), apps = root.appendingPathComponent("Applications"), data = root.appendingPathComponent("data")
        let env = MacSyncEnvironment(syncDirectory: world.sync, dataDirectory: data, machineID: "a", machineName: "A", dockFile: nil,
                                     brewPath: nil, applicationsDirectory: apps, homeDirectory: home.path)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        var ani = CraftApp(id: "anicraft", name: "AniCraft", version: "0.2.0", dmgURL: "https://github.com/storytold/anicraft/a.dmg")
        ani.bundleName = "AniCraft"
        try JSONEncoder().encode([ani]).write(to: data.appendingPathComponent("artcraft-catalog.json"))
        let bundle = apps.appendingPathComponent("Artcraft/AniCraft.app/Contents")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "ai.storyteller.anicraft", "CFBundleShortVersionString": "0.2.0"],
                                           format: .xml, options: 0).write(to: bundle.appendingPathComponent("Info.plist"))
        let craft = ArtCraft(env: env, runner: FakeRunner(), now: Date.init)
        XCTAssertEqual(craft.registerUnlisted(), ["AniCraft"])
        XCTAssertEqual(craft.records()["anicraft"]?["path"] as? String, apps.appendingPathComponent("Artcraft/AniCraft.app").path)
        XCTAssertEqual(craft.registerUnlisted(), [], "listed once")
    }
}

final class LiveCraftIconTests: XCTestCase {
    func testFetchesAnIconFromTheCatalog() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MACSYNC_LIVE_CRAFT"] == "1", "live test")
        let cached = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/MacSync/artcraft-catalog.json")
        let apps = try JSONDecoder().decode([CraftApp].self, from: Data(contentsOf: cached))
        let deck = try XCTUnwrap(apps.first { $0.id == "deckcraft" })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macsync-icon-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: root) }
        let env = MacSyncEnvironment(syncDirectory: root, dataDirectory: root.appendingPathComponent("data"), machineID: "t", machineName: "T",
                                     dockFile: nil, brewPath: nil, applicationsDirectory: root, homeDirectory: root.path)
        let file = ArtCraft(env: env, runner: SystemCommandRunner(), now: Date.init).iconFile(for: deck)
        XCTAssertNotNil(file, "icon \(deck.iconURL ?? "-") sha \(deck.iconSHA256 ?? "-")")
    }
}

final class CraftFolderInventoryTests: XCTestCase {
    func testCraftAppsInTheArtCraftFolderCountAsOnThisMac() throws {
        let world = try TestWorld()
        let apps = world.root.appendingPathComponent("Applications")
        func app(_ path: String, _ id: String) throws {
            let contents = apps.appendingPathComponent(path).appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundleShortVersionString": "1.0"], format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        try app("Artcraft/PhotoCraft.app", "ai.storyteller.photocraft")
        try app("Tools/Helper.app", "com.example.helper")
        try app("Raycast.app", "com.raycast.macos")
        let env = MacSyncEnvironment(syncDirectory: world.sync, dataDirectory: world.root.appendingPathComponent("data"), machineID: "a",
                                     machineName: "A", dockFile: nil, brewPath: nil, applicationsDirectory: apps,
                                     homeDirectory: world.root.path)
        let ids = InventoryReader(runner: FakeRunner(), env: env).directApps(excluding: []).map(\.bundleID)
        XCTAssertEqual(Set(ids), ["ai.storyteller.photocraft", "com.raycast.macos"], "ArtCraft's folder counts; other folders don't")
    }
}
