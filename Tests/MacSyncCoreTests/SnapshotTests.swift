import XCTest
@testable import MacSyncCore

final class SnapshotTests: XCTestCase {
    func testRoundTrip() throws {
        let snapshot = TestWorld.snapshot(id: "a", apps: ["com.a"], changedAt: Date(timeIntervalSince1970: 1000))
        let decoded = try SnapshotCodec.decode(try SnapshotCodec.encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.schemaVersion, SnapshotCodec.currentVersion)
    }

    func testNewerVersionIsRefusedNotCrashed() {
        let data = Data(#"{"schemaVersion": 99, "machineID": "x"}"#.utf8)
        XCTAssertThrowsError(try SnapshotCodec.decode(data)) { error in
            XCTAssertEqual(error as? SnapshotError, .tooNew(version: 99))
        }
    }

    func testGarbageIsRefused() {
        XCTAssertThrowsError(try SnapshotCodec.decode(Data("nope".utf8)))
    }

    func testUnknownFieldsFromSameVersionAreIgnored() throws {
        var object = try JSONSerialization.jsonObject(with: try SnapshotCodec.encode(
            TestWorld.snapshot(id: "a", apps: [], changedAt: Date(timeIntervalSince1970: 0)))) as! [String: Any]
        object["somethingNew"] = 1
        XCTAssertNoThrow(try SnapshotCodec.decode(try JSONSerialization.data(withJSONObject: object)))
    }

    func testMigratesPrototypeSnapshot() throws {
        let v1 = #"""
        {"host":"air.local","time":"2026-11-01T10:00:00",
         "dock":[{"label":"Safari","path":"/Applications/Safari.app"}],
         "brew":{"casks":["ghostty"],"formulae":["jq"]},
         "mas":[{"id":"497799835","name":"Xcode"}]}
        """#
        let snapshot = try SnapshotCodec.decode(Data(v1.utf8))
        XCTAssertEqual(snapshot.schemaVersion, SnapshotCodec.currentVersion)
        XCTAssertEqual(snapshot.machineName, "air.local")
        XCTAssertEqual(snapshot.dock?.apps.first?.path, "/Applications/Safari.app")
        XCTAssertEqual(snapshot.inventory?.casks, ["ghostty"])
        XCTAssertEqual(snapshot.inventory?.appStore.first?.id, "497799835")
    }
}
