import XCTest
@testable import MacSyncCore

final class EngineTests: XCTestCase {
    func dockBundleIDs(_ mac: TestWorld.Mac) throws -> [String] {
        try DockCapture.section(from: try mac.dockStore.readRaw(), changedAt: Date(), home: "/Users/test").apps.compactMap(\.bundleID)
    }

    func testFirstRunNeverOverwritesAnEstablishedMac() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["x"], locate: ["a", "b", "x"])
        let overview = try air.engine.sync()
        XCTAssertEqual(overview.dockPlan?.sourceMachine, "Studio")
        XCTAssertNil(try studio.engine.sync().dockPlan, "the established Mac must not be offered the new Mac's default Dock")
    }

    func testSyncChangesNothingOnThisMac() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["x"], locate: ["a", "b", "x"])
        let before = try air.dockStore.exportPlist()
        try air.engine.sync()
        XCTAssertEqual(try air.dockStore.exportPlist(), before)
        XCTAssertEqual(air.dockStore.restarts, 0)
    }

    func testApplyThenUndoRestoresExactly() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b", "c"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["c", "x"], locate: ["a", "b", "c", "x"])
        let original = try air.dockStore.exportPlist()

        let report = try air.engine.apply(ApplyRequest(applyDock: true, apps: []))
        XCTAssertTrue(report.dockChanged)
        XCTAssertNotNil(report.restorePoint)
        XCTAssertEqual(try dockBundleIDs(air), ["a", "b", "c"])
        XCTAssertEqual(air.dockStore.restarts, 1)

        let undone = try air.engine.undoLast()
        XCTAssertNotNil(undone.undoneAt)
        XCTAssertEqual(try air.dockStore.exportPlist(), original)
        XCTAssertThrowsError(try air.engine.undoLast())
    }

    func testApplyKeepsLocalTileDataAndRecentApps() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["b", "a"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a", "b"])
        _ = try air.engine.apply(ApplyRequest(applyDock: true, apps: []))
        let raw = try air.dockStore.readRaw()
        let first = (raw["persistent-apps"] as! [[String: Any]])[0]
        XCTAssertEqual((first["tile-data"] as! [String: Any])["book"] as? Data, Data("local-bookmark-b".utf8))
        XCTAssertEqual((raw["recent-apps"] as! [[String: Any]]).count, 1)
    }

    func testUnknownLocalTilesAreKept() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["b", "a"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a", "b"])
        var raw = try air.dockStore.readRaw()
        var apps = raw["persistent-apps"] as! [[String: Any]]
        apps.append(["tile-type": "future-tile", "tile-data": ["x": 1]])
        raw["persistent-apps"] = apps
        try air.dockStore.importPlist(try PropertyListSerialization.data(fromPropertyList: raw, format: .xml, options: 0))
        // That edit is newer than Studio's, so edit Studio afterwards to make it the latest.
        try air.engine.sync()
        world.tick()
        try studio.dockStore.importPlist(try TestWorld.plist(apps: ["b", "a", "b2"]))
        try studio.engine.sync()
        world.tick()
        _ = try air.engine.apply(ApplyRequest(applyDock: true, apps: []))
        let tiles = try air.dockStore.readRaw()["persistent-apps"] as! [[String: Any]]
        XCTAssertTrue(tiles.contains { $0["tile-type"] as? String == "future-tile" })
    }

    func testAfterApplyBothMacsSettleInSync() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["x"], locate: ["a", "x"])
        let report = try air.engine.apply(ApplyRequest(applyDock: true, apps: []))
        XCTAssertEqual(report.skippedDockItems.map(\.bundleID), ["b"])
        world.tick()
        let airAfter = try air.engine.sync()
        XCTAssertNil(airAfter.dockPlan, "a Mac lacking one app must not be offered the same change forever")
        XCTAssertEqual(airAfter.dockMissing.map(\.bundleID), ["b"])
        let studioAfter = try studio.engine.sync()
        XCTAssertNil(studioAfter.dockPlan, "a partial copy must not flow back and remove Studio's app")
        XCTAssertEqual(studioAfter.machines.first { $0.id == "air" }?.dockMatchesSource, true)
    }

    func testLatestEditWinsAcrossMacsWithARestorePoint() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b"], locate: ["a", "b", "c"])
        let air = try world.mac("air", dock: ["a", "b"], locate: ["a", "b", "c"])
        try studio.engine.sync()
        world.tick()
        try air.engine.sync()
        world.tick()
        try studio.dockStore.importPlist(try TestWorld.plist(apps: ["b", "a"]))
        try studio.engine.sync()
        world.tick()
        try air.dockStore.importPlist(try TestWorld.plist(apps: ["a", "b", "c"]))
        try air.engine.sync()
        world.tick()
        let conflict = try studio.engine.sync()
        XCTAssertEqual(conflict.dockPlan?.sourceMachine, "Air")
        XCTAssertNil(try air.engine.sync().dockPlan)
        let report = try studio.engine.apply(ApplyRequest(applyDock: true, apps: []))
        XCTAssertEqual(try dockBundleIDs(studio), ["a", "b", "c"])
        XCTAssertEqual(report.restorePoint?.sourceMachine, "Air")
    }

    func testUndoBeatsTheLayoutItCameFrom() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["b", "a"])
        _ = try air.engine.apply(ApplyRequest(applyDock: true, apps: []))
        world.tick()
        _ = try air.engine.undoLast()
        XCTAssertNil(try air.engine.sync().dockPlan, "undo must stick on the Mac that undid")
        world.tick()
        XCTAssertEqual(try studio.engine.sync().dockPlan?.sourceMachine, "Air")
    }

    func testFailedInstallIsReportedAndOthersContinue() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"])
        studio.runner.casks = ["good", "bad"]
        studio.runner.formulae = ["jq"]
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a"])
        air.runner.failing = ["bad"]
        let overview = try air.engine.sync()
        let report = try air.engine.apply(ApplyRequest(applyDock: false, apps: overview.missingApps.map(\.app)))
        XCTAssertTrue(report.hasFailures)
        XCTAssertEqual(report.results.first { $0.app.name == "bad" }?.outcome, .failed)
        XCTAssertEqual(report.results.first { $0.app.name == "bad" }?.message, "Error: bad needs a password")
        XCTAssertEqual(report.results.first { $0.app.name == "good" }?.outcome, .installed)
        XCTAssertEqual(report.results.first { $0.app.name == "jq" }?.outcome, .installed)
        XCTAssertNotNil(report.restorePoint)
    }

    func testOnlyAppsFromOtherMacsCanBeInstalled() throws {
        let world = try TestWorld()
        let air = try world.mac("air", dock: ["a"])
        let report = try air.engine.apply(ApplyRequest(applyDock: false, apps: [AppRef(source: .cask, name: "evil")]))
        XCTAssertTrue(report.results.isEmpty)
        XCTAssertFalse(air.runner.calls.contains { $0.contains("install") })
    }

    func testNoHomebrewIsAClearFailure() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"])
        studio.runner.casks = ["ghostty"]
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a"], brew: nil)
        let overview = try air.engine.sync()
        XCTAssertFalse(overview.brewAvailable)
        let report = try air.engine.apply(ApplyRequest(applyDock: false, apps: overview.missingApps.map(\.app)))
        XCTAssertEqual(report.results.first?.outcome, .failed)
        XCTAssertTrue(report.results.first?.message?.contains("Homebrew") == true)
    }

    func testAppStoreAppOpensItsPage() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"])
        try studio.engine.sync()
        let air = try world.mac("air", dock: ["a"])
        var other = try SnapshotCodec.decode(try Data(contentsOf: world.sync.appendingPathComponent("machines/studio.json")))
        other.inventory?.appStore = [AppStoreApp(id: "497799835", name: "Xcode")]
        try SnapshotCodec.encode(other).write(to: world.sync.appendingPathComponent("machines/studio.json"))
        let overview = try air.engine.sync()
        let report = try air.engine.apply(ApplyRequest(applyDock: false, apps: overview.missingApps.map(\.app)))
        XCTAssertEqual(report.results.first?.outcome, .openedInAppStore)
        XCTAssertTrue(air.runner.calls.contains { $0.last == "macappstore://apps.apple.com/app/id497799835" })
    }

    func testICloudOffIsAnIssueNotACrash() throws {
        let world = try TestWorld()
        try FileManager.default.removeItem(at: world.root.appendingPathComponent("iCloud"))
        let air = try world.mac("air", dock: ["a"])
        let overview = try air.engine.sync()
        XCTAssertFalse(overview.iCloudAvailable)
        XCTAssertTrue(overview.issues.contains { $0.contains("iCloud") })
    }

    func testBadAndNewerSnapshotsAreSkipped() throws {
        let world = try TestWorld()
        let air = try world.mac("air", dock: ["a"])
        try air.engine.sync()
        let machines = world.sync.appendingPathComponent("machines")
        try Data("garbage".utf8).write(to: machines.appendingPathComponent("bad.json"))
        try Data(#"{"schemaVersion":99}"#.utf8).write(to: machines.appendingPathComponent("future.json"))
        try Data("x".utf8).write(to: machines.appendingPathComponent("air 2.json"))
        let overview = try air.engine.sync()
        XCTAssertEqual(overview.machines.count, 1)
        XCTAssertEqual(overview.issues.count, 2)
        XCTAssertTrue(overview.issues.contains { $0.contains("newer MacSync") })
    }

    func testRestorePointsArePruned() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a", "b"])
        for round in 0..<(Engine.maxRestorePoints + 3) {
            try studio.dockStore.importPlist(try TestWorld.plist(apps: round % 2 == 0 ? ["b", "a"] : ["a", "b"]))
            try studio.engine.sync()
            world.tick()
            _ = try air.engine.apply(ApplyRequest(applyDock: true, apps: []))
            world.tick()
        }
        XCTAssertEqual(air.engine.restorePoints().count, Engine.maxRestorePoints)
    }

    func testUndoRemovesKeysTheApplyAdded() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b"])
        try studio.dockStore.importPlist(try TestWorld.plist(apps: ["a", "b"], orientation: "left"))
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a", "b"])
        XCTAssertNil(try air.dockStore.readRaw()["orientation"])
        _ = try air.engine.apply(ApplyRequest(applyDock: true, apps: []))
        XCTAssertEqual(try air.dockStore.readRaw()["orientation"] as? String, "left")
        _ = try air.engine.undoLast()
        XCTAssertNil(try air.dockStore.readRaw()["orientation"], "the backup had no such key, so undo must remove it")
    }

    func testApplyDoesNotAddAnUnsetDefaultPosition() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["b", "a"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a", "b"])
        _ = try air.engine.apply(ApplyRequest(applyDock: true, apps: []))
        XCTAssertNil(try air.dockStore.readRaw()["orientation"])
    }

    func testApplyAndUndoSurviveADockThatOverwritesThem() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["b", "a"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a", "b"])
        let stubborn = StubbornDock(inner: air.dockStore, overwrites: 2)
        let engine = world.engine(for: air, dock: stubborn, locate: ["a", "b"])
        XCTAssertTrue(try engine.apply(ApplyRequest(applyDock: true, apps: [])).dockChanged)
        XCTAssertEqual(try dockBundleIDs(air), ["b", "a"])
        XCTAssertEqual(stubborn.restarts, 3)
        stubborn.overwritesLeft = 2
        _ = try engine.undoLast()
        XCTAssertEqual(try dockBundleIDs(air), ["a", "b"], "undo must not report success while the Dock kept the old list")
    }

    func testDockThatNeverAcceptsIsAFailureAndUndoStaysAvailable() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["b", "a"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a", "b"])
        let stubborn = StubbornDock(inner: air.dockStore, overwrites: 1000)
        let engine = world.engine(for: air, dock: stubborn, locate: ["a", "b"])
        XCTAssertThrowsError(try engine.apply(ApplyRequest(applyDock: true, apps: [])))
        XCTAssertEqual(try dockBundleIDs(air), ["a", "b"])
    }

    func testAMacWithAPendingChangeIsNotInSync() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a"], locate: ["a", "b"])
        let overview = try air.engine.sync()
        XCTAssertNotNil(overview.dockPlan)
        XCTAssertEqual(overview.machines.first { $0.isThisMac }?.dockMatchesSource, false)
    }

    func testSelectionPersists() throws {
        let world = try TestWorld()
        let air = try world.mac("air", dock: ["a"])
        try air.engine.setSelectedApps(["cask:ghostty"])
        XCTAssertEqual(try air.engine.sync().selectedApps, ["cask:ghostty"])
    }
}
