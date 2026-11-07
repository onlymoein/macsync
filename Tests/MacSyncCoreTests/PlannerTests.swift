import XCTest
@testable import MacSyncCore

final class PlannerTests: XCTestCase {
    func testLatestWins() {
        let old = TestWorld.snapshot(id: "a", apps: [], changedAt: Date(timeIntervalSince1970: 100))
        let new = TestWorld.snapshot(id: "b", apps: [], changedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(Planner.winner(among: [old, new])?.machineID, "b")
    }

    func testFreshMacLosesToEstablishedMac() {
        let epoch = Date(timeIntervalSince1970: 0)
        var established = TestWorld.snapshot(id: "z", apps: [], changedAt: epoch)
        established.firstSeenAt = Date(timeIntervalSince1970: 100)
        var fresh = TestWorld.snapshot(id: "a", apps: [], changedAt: epoch)
        fresh.firstSeenAt = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(Planner.winner(among: [fresh, established])?.machineID, "z")
    }

    func testOriginalBeatsACopyOnATie() {
        let time = Date(timeIntervalSince1970: 500)
        let original = TestWorld.snapshot(id: "z", apps: [], changedAt: time)
        var copy = TestWorld.snapshot(id: "a", apps: [], changedAt: time)
        copy.dock?.basedOn = "z"
        XCTAssertEqual(Planner.winner(among: [copy, original])?.machineID, "z")
    }

    func section(_ ids: [String]) -> DockSection {
        DockSection(changedAt: Date(), apps: ids.map(TestWorld.app), others: [])
    }

    func testMoveIsReportedMinimally() {
        let plan = Planner.dockPlan(current: section(["a", "b", "c", "d"]), target: section(["d", "a", "b", "c"]),
                                    source: "S", locator: TestLocator(apps: ["a", "b", "c", "d"]))
        XCTAssertEqual(plan.moved.map(\.bundleID), ["d"])
        XCTAssertTrue(plan.added.isEmpty)
        XCTAssertTrue(plan.removed.isEmpty)
        XCTAssertTrue(plan.hasChanges)
    }

    func testMissingAppIsLeftOutNotFatal() {
        let plan = Planner.dockPlan(current: section(["a"]), target: section(["a", "ghost", "b"]),
                                    source: "S", locator: TestLocator(apps: ["a", "b"]))
        XCTAssertEqual(plan.missing.map(\.bundleID), ["ghost"])
        XCTAssertEqual(plan.targetApps.map(\.bundleID), ["a", "b"])
        XCTAssertEqual(plan.added.map(\.bundleID), ["b"])
    }

    func testNoChangesWhenOnlyMissingItemsDiffer() {
        let plan = Planner.dockPlan(current: section(["a"]), target: section(["a", "ghost"]),
                                    source: "S", locator: TestLocator(apps: ["a"]))
        XCTAssertFalse(plan.hasChanges)
    }

    func testAppsAreAdditiveAcrossMacs() {
        var other = TestWorld.snapshot(id: "o", apps: [], changedAt: Date())
        other.inventory = Inventory(brewAvailable: true, casks: ["ghostty", "shared"], formulae: ["jq"],
                                    appStore: [AppStoreApp(id: "1", name: "Pages")])
        let local = Inventory(brewAvailable: true, casks: ["shared", "only-here"])
        let tokens = Planner.missingApps(local: local, others: [other]).map(\.app.token)
        XCTAssertEqual(Set(tokens), ["cask:ghostty", "formula:jq", "mas:1"])
    }

    func testUnsafeNamesFromASnapshotAreDropped() {
        var other = TestWorld.snapshot(id: "o", apps: [], changedAt: Date())
        other.inventory = Inventory(casks: ["--force", "a;rm -rf ~", "ok-cask"], appStore: [AppStoreApp(id: "1 && x", name: "Bad")])
        XCTAssertEqual(Planner.missingApps(local: Inventory(), others: [other]).map(\.app.token), ["cask:ok-cask"])
    }
}
