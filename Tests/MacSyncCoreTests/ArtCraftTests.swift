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
