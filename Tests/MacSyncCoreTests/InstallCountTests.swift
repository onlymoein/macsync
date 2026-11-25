import XCTest
@testable import MacSyncCore

final class InstallCountTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)

    func env(_ world: TestWorld, machine: String, sync: URL? = nil, dock: URL? = nil) -> MacSyncEnvironment {
        MacSyncEnvironment(syncDirectory: sync ?? world.sync, dataDirectory: world.root.appendingPathComponent("data-" + machine), machineID: machine,
                           machineName: "Someone's Mac", dockFile: dock, brewPath: nil,
                           applicationsDirectory: world.root, homeDirectory: "/nowhere")
    }

    func testThreeSyncedMacsCountAsOneAtMostOnceADay() throws {
        let world = try TestWorld()
        let macs = ["m1", "m2", "m3"].map { InstallCount(env: env(world, machine: $0)) }
        XCTAssertTrue(macs.allSatisfy { $0.due(now: start) == nil }, "iCloud gets a moment first")
        let later = start.addingTimeInterval(20 * 60)
        let messages = try macs.map { try XCTUnwrap($0.due(now: later)) }
        XCTAssertEqual(Set(messages.map(\.id)).count, 1, "one install")
        XCTAssertTrue(messages.allSatisfy { $0.replaces == nil })
        macs[0].markSent(messages[0], now: later)
        XCTAssertNil(macs[0].due(now: later.addingTimeInterval(3600)))
        XCTAssertEqual(macs[0].due(now: later.addingTimeInterval(25 * 3600)), messages[0])
    }

    func testANumberSentBeforeSharingIsReplaced() throws {
        let world = try TestWorld()
        let offline = world.root.appendingPathComponent("no-icloud/MacSync")
        let alone = InstallCount(env: env(world, machine: "m1", sync: offline))
        XCTAssertNil(alone.due(now: start))
        XCTAssertNil(alone.due(now: start.addingTimeInterval(3600)), "no iCloud yet")
        let next = start.addingTimeInterval(25 * 3600)
        let first = try XCTUnwrap(alone.due(now: next))
        alone.markSent(first, now: next)
        // iCloud is turned on, and another Mac already has a number there.
        let other = InstallCount(env: env(world, machine: "m2"))
        _ = other.due(now: start)
        let theirs = try XCTUnwrap(other.due(now: next))
        let joined = InstallCount(env: env(world, machine: "m1"))
        let message = try XCTUnwrap(joined.due(now: next.addingTimeInterval(25 * 3600)))
        XCTAssertEqual(message.id, theirs.id)
        XCTAssertEqual(message.replaces, first.id)
    }

    func testAnUnreadableSharedNumberIsLeftAlone() throws {
        let world = try TestWorld()
        let count = InstallCount(env: env(world, machine: "m1"))
        _ = count.due(now: start)
        try FileManager.default.createDirectory(at: world.sync, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: count.sharedFile)
        XCTAssertNil(count.due(now: start.addingTimeInterval(99_999)))
        XCTAssertEqual(try String(contentsOf: count.sharedFile, encoding: .utf8), "half")
    }

    func testNothingIdentifyingIsSentAndOffForgets() throws {
        let world = try TestWorld()
        let count = InstallCount(env: env(world, machine: "m1"))
        _ = count.due(now: start)
        let message = try XCTUnwrap(count.due(now: start.addingTimeInterval(99_999)))
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: String])
        XCTAssertEqual(Set(sent.keys), ["id", "version", "macOS"])
        XCTAssertFalse(sent.values.contains { $0.contains("m1") || $0.contains("Someone") })
        count.forget()
        XCTAssertNil(count.saved())
        XCTAssertNil(InstallCount(env: env(world, machine: "d", dock: world.root)).due(now: start.addingTimeInterval(99_999)), "demos aren't counted")
        // A folder copied to another Mac isn't that Mac's.
        _ = count.due(now: start)
        try FileManager.default.copyItem(at: world.root.appendingPathComponent("data-m1"), to: world.root.appendingPathComponent("data-m9"))
        XCTAssertNil(InstallCount(env: env(world, machine: "m9")).saved())
    }
}
