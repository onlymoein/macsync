import XCTest
@testable import MacSyncCore

final class DockCaptureTests: XCTestCase {
    func tile(_ url: String, label: String, bundle: String? = nil, type: String = "file-tile") -> [String: Any] {
        var data: [String: Any] = ["file-label": label, "file-data": ["_CFURLString": url, "_CFURLStringType": 15],
                                   "book": Data("SECRET-BOOKMARK".utf8)]
        if let bundle { data["bundle-identifier"] = bundle }
        return ["GUID": 1, "tile-type": type, "tile-data": data]
    }

    func testNormalizesRealWorldPaths() {
        let home = "/Users/studio"
        let safari = DockCapture.item(from: tile("file:///System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/",
                                                 label: "Safari", bundle: "com.apple.Safari"), home: home)
        XCTAssertEqual(safari?.path, "/System/Applications/Safari.app")
        XCTAssertEqual(safari?.key, "app:com.apple.Safari")
        let webApp = DockCapture.item(from: tile("file:///Users/studio/Applications/X.app/", label: "X", bundle: "com.x"), home: home)
        XCTAssertEqual(webApp?.path, "~/Applications/X.app")
        let spaced = DockCapture.item(from: tile("file:///Applications/Google%20Chrome.app/", label: "Chrome", bundle: "c"), home: home)
        XCTAssertEqual(spaced?.path, "/Applications/Google Chrome.app")
    }

    func testFolderKeepsItsDisplayOptions() {
        var raw = tile("file:///Users/studio/Downloads/", label: "Downloads", type: "directory-tile")
        var data = raw["tile-data"] as! [String: Any]
        data["arrangement"] = 2
        data["displayas"] = 0
        data["showas"] = 1
        data["preferreditemsize"] = -1
        raw["tile-data"] = data
        let item = DockCapture.item(from: raw, home: "/Users/studio")
        XCTAssertEqual(item?.kind, .folder)
        XCTAssertEqual(item?.path, "~/Downloads")
        XCTAssertEqual(item?.folder, .init(arrangement: 2, displayAs: 0, showAs: 1, preferredItemSize: -1))
    }

    func testDefaultsWhenDockKeysAreUnset() {
        let section = DockCapture.section(from: ["tilesize": 29.0, "persistent-apps": [tile("file:///A.app/", label: "A", bundle: "a")]],
                                          changedAt: Date(), home: "/h")
        XCTAssertEqual(section.tileSize, 29.0)
        XCTAssertEqual(section.orientation, "bottom")
        XCTAssertEqual(section.apps.count, 1)
    }

    func testSpacersAndUnknownTiles() {
        XCTAssertEqual(DockCapture.item(from: ["tile-type": "small-spacer-tile", "tile-data": [:]])?.kind, .spacer)
        XCTAssertNil(DockCapture.item(from: ["tile-type": "something-new", "tile-data": [:]]))
    }

    func testSecretsNeverReachTheSnapshot() throws {
        var url = tile("", label: "Portal", type: "url-tile")
        url["tile-data"] = ["label": "Portal", "url": ["_CFURLString": "https://me:hunter2@portal.example.com/a?team=1&access_token=abc123&apikey=zzz#frag", "_CFURLStringType": 15]]
        let section = DockCapture.section(
            from: ["persistent-apps": [tile("file:///A.app/", label: "A", bundle: "a")], "persistent-others": [url], "secret-other-key": "hunter2"],
            changedAt: Date(), home: "/h")
        let snapshot = MachineSnapshot(machineID: "m", machineName: "n", osVersion: "o", appVersion: "v", firstSeenAt: Date(),
                                       savedAt: Date(), dock: section, inventory: nil)
        let text = String(decoding: try SnapshotCodec.encode(snapshot), as: UTF8.self)
        for secret in ["hunter2", "abc123", "zzz", "SECRET-BOOKMARK", "U0VDUkVU", "frag"] {
            XCTAssertFalse(text.contains(secret), "\(secret) leaked")
        }
        XCTAssertTrue(text.contains("team=1"))
    }
}
