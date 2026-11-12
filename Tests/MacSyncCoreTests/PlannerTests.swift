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

    /// Tailscale from Homebrew on one Mac and downloaded from its website on this one is installed here.
    func testAppDownloadedHereIsNotNeededFromHomebrew() {
        let tailscale = DirectApp(bundleID: "io.tailscale.ipn.macsys", name: "Tailscale", cask: "tailscale-app")
        var pro = TestWorld.snapshot(id: "pro", apps: [], changedAt: Date())
        pro.inventory = Inventory(brewAvailable: true, casks: ["tailscale-app"], directApps: [tailscale])
        let studio = Inventory(brewAvailable: true, directApps: [tailscale])
        XCTAssertTrue(Planner.missingApps(local: studio, others: [pro]).isEmpty)
        // Without the cask link here, the row still carries the bundle ID, so the Applications check can find it.
        let unlinked = Inventory(brewAvailable: true)
        let row = Planner.missingApps(local: unlinked, others: [pro]).first { $0.app.token == "cask:tailscale-app" }
        XCTAssertEqual(row?.detail?.bundleID, "io.tailscale.ipn.macsys")
    }

    /// Same Dock as people see it: a Safari web app with another ID, and an app this Mac doesn't have.
    func testDockMatchesIgnoresWebAppIDsAndAppsNotInstalled() {
        func app(_ id: String, _ label: String, _ path: String? = nil) -> DockItem { DockItem(kind: .app, label: label, bundleID: id, path: path) }
        func dock(_ apps: [DockItem]) -> DockSection { DockSection(changedAt: Date(), apps: apps, others: []) }
        let studio = dock([app("com.apple.Safari", "Safari"), app("com.apple.Safari.WebApp.AAA", "X", "~/Applications/X.app"),
                           app("io.tailscale.ipn.macsys", "Tailscale")])
        let pro = dock([app("com.apple.Safari", "Safari"), app("com.apple.Safari.WebApp.BBB", "X", "~/Applications/X.app"),
                        app("io.tailscale.ipn.macsys", "Tailscale")])
        XCTAssertTrue(Planner.dockMatches(pro, target: studio))
        // The Studio's web app ID is one the Pro doesn't have: it still matches the Pro's own copy.
        XCTAssertTrue(Planner.dockMatches(pro, target: studio, notInstalled: ["com.apple.Safari.WebApp.AAA"]))
        let air = dock([app("com.apple.Safari", "Safari"), app("com.apple.Safari.WebApp.AAA", "X", "~/Applications/X.app")])
        XCTAssertFalse(Planner.dockMatches(air, target: studio))
        XCTAssertTrue(Planner.dockMatches(air, target: studio, notInstalled: ["io.tailscale.ipn.macsys"]))
        // A different web app is still a difference.
        let other = dock([app("com.apple.Safari", "Safari"), app("com.apple.Safari.WebApp.CCC", "YouTube", "~/Applications/YouTube.app"),
                          app("io.tailscale.ipn.macsys", "Tailscale")])
        XCTAssertFalse(Planner.dockMatches(other, target: studio))
    }

    func testBundlesNotOnAMacComeFromTheOthers() {
        var studio = TestWorld.snapshot(id: "studio", apps: [], changedAt: Date())
        studio.inventory = Inventory(directApps: [DirectApp(bundleID: "io.tailscale.ipn.macsys", name: "Tailscale")])
        var air = TestWorld.snapshot(id: "air", apps: [], changedAt: Date())
        air.inventory = Inventory()
        XCTAssertEqual(Planner.bundlesNotOn(air, among: [studio, air]), ["io.tailscale.ipn.macsys"])
        XCTAssertEqual(Planner.bundlesNotOn(studio, among: [studio, air]), [])
    }

    /// The X web app sits at the end on this Mac and near the start on the source Mac, with another ID there.
    func testAWebAppMovesToTheSourceMacsPlaceAsThisMacsOwnCopy() {
        func app(_ id: String, _ label: String, _ path: String? = nil) -> DockItem { DockItem(kind: .app, label: label, bundleID: id, path: path) }
        let theirX = app("com.apple.Safari.WebApp.STUDIO", "X", "~/Applications/X.app")
        let myX = app("com.apple.Safari.WebApp.PRO", "X", "~/Applications/X.app")
        let safari = app("com.apple.Safari", "Safari"), notes = app("com.apple.Notes", "Notes")
        let current = DockSection(changedAt: Date(), apps: [safari, notes, myX], others: [])
        // The merged target holds both copies: the source Mac's near the start, this Mac's at the end.
        let target = DockSection(changedAt: Date(), apps: [safari, theirX, notes, myX], others: [])
        let plan = Planner.dockPlan(current: current, target: target, source: "Studio",
                                    locator: TestLocator(apps: ["com.apple.Safari", "com.apple.Notes", "com.apple.Safari.WebApp.PRO"]))
        XCTAssertEqual(plan.targetApps.map(\.bundleID), ["com.apple.Safari", "com.apple.Safari.WebApp.PRO", "com.apple.Notes"])
        XCTAssertTrue(plan.added.isEmpty)
        XCTAssertTrue(plan.removed.isEmpty)
        XCTAssertFalse(plan.moved.isEmpty, "X moves")
    }
}
