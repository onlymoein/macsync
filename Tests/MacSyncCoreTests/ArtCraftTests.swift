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
}
