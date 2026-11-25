import XCTest
@testable import MacSyncCore

final class InstallCountTests: XCTestCase {
    func env(_ world: TestWorld, machine: String = "m1", dock: URL? = nil) -> MacSyncEnvironment {
        MacSyncEnvironment(syncDirectory: world.sync, dataDirectory: world.root.appendingPathComponent("data"), machineID: machine,
                           machineName: "Someone's Mac", dockFile: dock, brewPath: nil,
                           applicationsDirectory: world.root, homeDirectory: "/nowhere")
    }

    func testOneNumberPerMacAtMostOnceADay() throws {
        let world = try TestWorld()
        let count = InstallCount(env: env(world))
        let now = Date(timeIntervalSince1970: 1_000_000)
        let first = try XCTUnwrap(count.due(now: now))
        XCTAssertEqual(count.due(now: now), first, "the same number until it's sent")
        count.markSent(now: now)
        XCTAssertNil(count.due(now: now.addingTimeInterval(3600)))
        XCTAssertEqual(count.due(now: now.addingTimeInterval(25 * 3600))?.id, first.id)
        // Copied to a new Mac: a number of its own.
        XCTAssertNotEqual(InstallCount(env: env(world, machine: "m2")).due(now: now)?.id, first.id)
    }

    func testNothingIdentifyingIsSentAndOffForgets() throws {
        let world = try TestWorld()
        let count = InstallCount(env: env(world))
        let message = try XCTUnwrap(count.due(now: Date()))
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: String])
        XCTAssertEqual(Set(sent.keys), ["id", "version", "macOS"])
        XCTAssertNotNil(UUID(uuidString: message.id))
        XCTAssertFalse(sent.values.contains { $0.contains("m1") || $0.contains("Someone") })
        count.forget()
        XCTAssertNil(count.saved())
        XCTAssertNil(InstallCount(env: env(world, dock: world.root)).due(now: Date()), "demos aren't counted")
    }
}
