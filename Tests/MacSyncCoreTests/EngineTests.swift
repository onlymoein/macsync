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
        let keys = overview.dockPlan?.targetApps.compactMap(\.bundleID) ?? []
        XCTAssertEqual(Set(keys), ["a", "b", "x"], "the new Mac keeps its own app and gains Studio's")
        XCTAssertLessThan(keys.firstIndex(of: "a")!, keys.firstIndex(of: "b")!, "Studio's order is kept")
        let studioPlan = try studio.engine.sync().dockPlan
        XCTAssertNil(studioPlan?.removed.first, "a new Mac must never remove anything from an established one")
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
        XCTAssertEqual(Set(try dockBundleIDs(air)), ["a", "b", "c", "x"])
        XCTAssertEqual(air.dockStore.restarts, 1)

        let undone = try air.engine.undoLast()
        XCTAssertNotNil(undone.undoneAt)
        XCTAssertEqual(try air.dockStore.exportPlist(), original)
        XCTAssertThrowsError(try air.engine.undoLast())
        world.tick()
        try air.engine.sync()
        XCTAssertEqual(try studio.engine.sync().dockPlan?.removed ?? [], [], "undo on one Mac must not remove apps from another")
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
        XCTAssertEqual(conflict.dockPlan?.targetApps.compactMap(\.bundleID), ["a", "b", "c"])
        XCTAssertNil(try air.engine.sync().dockPlan)
        let report = try studio.engine.apply(ApplyRequest(applyDock: true, apps: []))
        XCTAssertEqual(try dockBundleIDs(studio), ["a", "b", "c"])
        XCTAssertNotNil(report.restorePoint)
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
        XCTAssertEqual(try studio.engine.sync().dockPlan?.targetApps.compactMap(\.bundleID), ["b", "a"])
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

    func testAppsStartTickedAndUntickingPersists() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"])
        studio.runner.casks = ["ghostty", "rectangle"]
        try studio.engine.sync()
        let air = try world.mac("air", dock: ["a"])
        XCTAssertEqual(try air.engine.sync().selectedApps, ["cask:ghostty", "cask:rectangle"], "everything from the other Macs starts ticked")
        try air.engine.setSelectedApps(["cask:rectangle"])
        XCTAssertEqual(try air.engine.sync().selectedApps, ["cask:rectangle"])
        studio.runner.casks.append("raycast")
        try studio.engine.sync()
        XCTAssertEqual(try air.engine.sync().selectedApps, ["cask:raycast", "cask:rectangle"], "a new app starts ticked, the unticked one stays unticked")
    }

    func testDocksCombineSoEveryMacGetsEveryApp() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b"], locate: ["a", "b", "raycast"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a", "raycast", "b"], locate: ["a", "b", "raycast"])
        try air.engine.sync()
        world.tick()
        let plan = try XCTUnwrap(try studio.engine.sync().dockPlan)
        XCTAssertEqual(plan.added.compactMap(\.bundleID), ["raycast"])
        XCTAssertEqual(plan.removed, [])
        XCTAssertEqual(plan.targetApps.compactMap(\.bundleID), ["a", "raycast", "b"], "it goes in next to its neighbours")
        XCTAssertNil(try air.engine.sync().dockPlan?.removed.first, "the Mac that has it is never told to remove it")
    }

    func testRemovingOnOneMacRemovesEverywhereAndAddingBackRestores() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b", "c"])
        let air = try world.mac("air", dock: ["a", "b", "c"])
        try studio.engine.sync()
        try air.engine.sync()
        world.tick()
        try studio.dockStore.importPlist(try TestWorld.plist(apps: ["a", "b"]))
        try studio.engine.sync()
        world.tick()
        let plan = try XCTUnwrap(try air.engine.sync().dockPlan)
        XCTAssertEqual(plan.removed.compactMap(\.bundleID), ["c"])
        _ = try air.engine.apply(ApplyRequest(applyDock: true, apps: []))
        XCTAssertEqual(try dockBundleIDs(air), ["a", "b"])
        world.tick()
        try air.dockStore.importPlist(try TestWorld.plist(apps: ["a", "b", "c"]))
        try air.engine.sync()
        world.tick()
        XCTAssertEqual(try studio.engine.sync().dockPlan?.added.compactMap(\.bundleID), ["c"])
    }

    static let catalog = Data("""
    [{"token":"photocraft","url":"https://example.com/PhotoCraft.dmg","sha256":"SUM",
      "artifacts":[{"app":["PhotoCraft.app"]},{"zap":{}}]},
     {"token":"photocraft@beta","url":"https://example.com/beta.dmg","sha256":"no_check","artifacts":[{"app":["PhotoCraft.app"]}]}]
    """.utf8)

    func testDownloadedAppComesFromWhereItIsPublishedNotICloud() throws {
        let world = try TestWorld()
        let installer = Data("installer".utf8)
        let sum = AppDownloader.sha256Hex(installer)
        let catalog = Data(String(decoding: Self.catalog, as: UTF8.self).replacingOccurrences(of: "SUM", with: sum).utf8)
        let studio = try world.mac("studio", dock: ["a"])
        studio.runner.web[CaskCatalog.address] = catalog
        try world.installDirectApp("PhotoCraft", bundleID: "ai.storyteller.photocraft", on: "studio")
        try studio.engine.sync()

        let air = try world.mac("air", dock: ["a"])
        air.runner.web[CaskCatalog.address] = catalog
        air.runner.web["https://example.com/PhotoCraft.dmg"] = installer
        let offered = try air.engine.sync()
        let photo = try XCTUnwrap(offered.missingApps.first { $0.app.source == .direct })
        XCTAssertEqual(photo.download?.cask, "photocraft")
        XCTAssertTrue(photo.canInstall)
        XCTAssertTrue(offered.selectedApps.contains(photo.app.token))

        let report = try air.engine.apply(ApplyRequest(applyDock: false, apps: [photo.app]))
        XCTAssertEqual(report.results.first?.outcome, .downloaded, report.results.first?.message ?? "")
        let saved = world.root.appendingPathComponent("air/Downloads/PhotoCraft.dmg")
        XCTAssertEqual(try Data(contentsOf: saved), installer)
        XCTAssertTrue(air.runner.calls.contains(["/usr/bin/open", saved.path]))
        // Nothing but sync files goes to iCloud.
        XCTAssertFalse(FileManager.default.fileExists(atPath: world.sync.appendingPathComponent("apps").path))
        let synced = FileManager.default.enumerator(atPath: world.sync.path)?.allObjects as? [String] ?? []
        XCTAssertFalse(synced.contains { $0.hasSuffix(".dmg") || $0.hasSuffix(".zip") })
    }

    func testDownloadThatDoesNotMatchItsChecksumIsDeleted() throws {
        let world = try TestWorld()
        let catalog = Data(String(decoding: Self.catalog, as: UTF8.self).replacingOccurrences(of: "SUM", with: String(repeating: "0", count: 64)).utf8)
        let studio = try world.mac("studio", dock: ["a"])
        studio.runner.web[CaskCatalog.address] = catalog
        try world.installDirectApp("PhotoCraft", bundleID: "ai.storyteller.photocraft", on: "studio")
        try studio.engine.sync()
        let air = try world.mac("air", dock: ["a"])
        air.runner.web[CaskCatalog.address] = catalog
        air.runner.web["https://example.com/PhotoCraft.dmg"] = Data("tampered".utf8)
        let photo = try XCTUnwrap(try air.engine.sync().missingApps.first { $0.app.source == .direct })
        let report = try air.engine.apply(ApplyRequest(applyDock: false, apps: [photo.app]))
        XCTAssertEqual(report.results.first?.outcome, .failed)
        let downloads = (try? FileManager.default.contentsOfDirectory(atPath: world.root.appendingPathComponent("air/Downloads").path)) ?? []
        XCTAssertEqual(downloads, [])
        XCTAssertFalse(air.runner.calls.contains { $0.first == "/usr/bin/open" })
    }

    func testAppWithOnlyAnUpdateFeedDownloadsItsLatestRelease() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"])
        try world.installDirectApp("Tool", bundleID: "com.example.tool", on: "studio", feed: "https://example.com/appcast.xml")
        try studio.engine.sync()
        let air = try world.mac("air", dock: ["a"])
        air.runner.web["https://example.com/appcast.xml"] = Data("""
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><title>2.0</title><enclosure url="https://example.com/Tool-2.0.zip" sparkle:version="2"/></item>
        <item><title>1.0</title><enclosure url="https://example.com/Tool-1.0.zip" sparkle:version="1"/></item>
        </channel></rss>
        """.utf8)
        air.runner.web["https://example.com/Tool-2.0.zip"] = Data("PK zip".utf8)
        let tool = try XCTUnwrap(try air.engine.sync().missingApps.first { $0.app.source == .direct })
        let report = try air.engine.apply(ApplyRequest(applyDock: false, apps: [tool.app]))
        XCTAssertEqual(report.results.first?.outcome, .downloaded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: world.root.appendingPathComponent("air/Downloads/Tool.zip").path))
    }

    func testAppWithNoKnownSourceIsShownButNotTicked() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"])
        try world.installDirectApp("Mystery", bundleID: "com.example.mystery", on: "studio")
        try studio.engine.sync()
        let air = try world.mac("air", dock: ["a"])
        let overview = try air.engine.sync()
        let app = try XCTUnwrap(overview.missingApps.first { $0.app.source == .direct })
        XCTAssertFalse(app.canInstall)
        XCTAssertFalse(overview.selectedApps.contains(app.app.token))
    }

    func testAppNotNeededIsRememberedAndCanComeBack() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"])
        studio.runner.casks = ["ghostty"]
        try studio.engine.sync()
        let air = try world.mac("air", dock: ["a"])
        XCTAssertTrue(try air.engine.sync().hasPendingChanges)
        try air.engine.setSkipped("cask:ghostty", true)
        let after = try air.engine.sync()
        XCTAssertEqual(after.skippedApps, ["cask:ghostty"])
        XCTAssertTrue(after.wantedApps.isEmpty)
        XCTAssertFalse(after.hasPendingChanges)
        try air.engine.setSkipped("cask:ghostty", false)
        XCTAssertEqual(try air.engine.sync().wantedApps.map(\.app.token), ["cask:ghostty"])
    }

    func testRemoveFromAllMacsUninstallsHereAndAsksTheOthers() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"])
        studio.runner.casks = ["blender"]
        try studio.engine.sync()
        let air = try world.mac("air", dock: ["a"])
        air.runner.casks = ["blender"]
        try air.engine.sync()
        world.tick()

        let blender = try XCTUnwrap(try studio.engine.sync().installedApps.first { $0.app.token == "cask:blender" })
        let results = studio.engine.removeEverywhere([blender])
        XCTAssertEqual(results.first?.outcome, .removed)
        XCTAssertTrue(studio.runner.calls.contains(["/fake/brew", "uninstall", "--cask", "blender"]))

        world.tick()
        let onAir = try air.engine.sync()
        XCTAssertEqual(onAir.toRemove.map(\.app.token), ["cask:blender"])
        XCTAssertTrue(onAir.hasPendingChanges)
        _ = air.engine.uninstallHere(onAir.toRemove)
        XCTAssertTrue(air.runner.calls.contains(["/fake/brew", "uninstall", "--cask", "blender"]))
    }

    func testRemovedAppIsNotOfferedAndCanBeBroughtBack() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"])
        studio.runner.casks = ["blender"]
        try studio.engine.sync()
        let air = try world.mac("air", dock: ["a"])
        try air.engine.sync()
        world.tick()
        // Removed from all Macs on the Air, which never had it: the Studio is asked, the Air stops offering it.
        let offered = try XCTUnwrap(try air.engine.sync().missingApps.first { $0.app.token == "cask:blender" })
        _ = air.engine.removeEverywhere([offered])
        world.tick()
        XCTAssertFalse(try air.engine.sync().missingApps.contains { $0.app.token == "cask:blender" })
        XCTAssertEqual(try studio.engine.sync().toRemove.map(\.app.token), ["cask:blender"])
        world.tick()
        try air.engine.cancelRemoval("cask:blender")
        world.tick()
        XCTAssertTrue(try studio.engine.sync().toRemove.isEmpty)
        XCTAssertTrue(try air.engine.sync().missingApps.contains { $0.app.token == "cask:blender" })
    }

    func testAppSwitchedOffIsNotSentToOtherMacs() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"])
        studio.runner.casks = ["blender", "ghostty"]
        try studio.engine.sync()
        try studio.engine.setShared(["cask:blender"], false)
        let air = try world.mac("air", dock: ["a"])
        let offered = try air.engine.sync().missingApps.map(\.app.token)
        XCTAssertEqual(offered, ["cask:ghostty"])
        try studio.engine.setShared(["cask:blender"], true)
        XCTAssertEqual(try air.engine.sync().missingApps.map(\.app.token), ["cask:blender", "cask:ghostty"])
    }

    func testChosenMacsDockOrderIsKeptEvenWhenAnotherChangesLater() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b", "c"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["c", "b", "a"])
        try air.engine.sync()
        world.tick()
        try air.engine.setDockOrder(machineID: "studio")
        world.tick()
        let plan = try XCTUnwrap(try air.engine.sync().dockPlan)
        XCTAssertEqual(plan.targetApps.compactMap(\.bundleID), ["a", "b", "c"])
        // The choice reaches the other Macs too.
        XCTAssertEqual(try studio.engine.sync().dockOrderFrom, "studio")
    }

    func testDockArrangedInMacSyncIsWrittenAndFollowedByOtherMacs() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b", "c"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a", "b", "c"])
        try air.engine.sync()
        world.tick()
        let keys = try XCTUnwrap(try air.engine.sync().dockPreview).targetApps.map(\.key)
        let report = try air.engine.apply(ApplyRequest(applyDock: true, apps: [], dockOrder: [keys[2], keys[0], keys[1]]))
        XCTAssertTrue(report.dockChanged)
        XCTAssertEqual(try dockBundleIDs(air), ["c", "a", "b"])
        world.tick()
        let plan = try XCTUnwrap(try studio.engine.sync().dockPlan)
        XCTAssertEqual(plan.targetApps.compactMap(\.bundleID), ["c", "a", "b"])
    }

    func testRemovingFromADockThatAlreadyMatchesWorks() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "b", "c"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a", "b", "c"])
        let overview = try air.engine.sync()
        XCTAssertNil(overview.dockPlan)
        let key = try XCTUnwrap(overview.dockPreview?.targetApps.first { $0.bundleID == "b" }).key
        world.tick()
        let report = try air.engine.apply(ApplyRequest(applyDock: true, apps: [], removeFromDock: [key]))
        XCTAssertTrue(report.dockChanged)
        XCTAssertEqual(try dockBundleIDs(air), ["a", "c"])
        world.tick()
        XCTAssertEqual(try studio.engine.sync().dockPlan?.removed.compactMap(\.bundleID), ["b"])
    }

    func testOldICloudCopiesAreDeleted() throws {
        let world = try TestWorld()
        let old = world.sync.appendingPathComponent("apps/packages")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("big".utf8).write(to: old.appendingPathComponent("com.example.zip"))
        let studio = try world.mac("studio", dock: ["a"])
        try studio.engine.sync()
        XCTAssertFalse(FileManager.default.fileExists(atPath: world.sync.appendingPathComponent("apps").path))
    }

    func testRemovingInReviewRemovesFromEveryMac() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a", "junk"], locate: ["a", "junk", "x"])
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a", "x"], locate: ["a", "junk", "x"])
        let plan = try XCTUnwrap(try air.engine.sync().dockPlan)
        let junk = try XCTUnwrap(plan.targetApps.first { $0.bundleID == "junk" })
        _ = try air.engine.apply(ApplyRequest(applyDock: true, apps: [], removeFromDock: [junk.key]))
        XCTAssertEqual(Set(try dockBundleIDs(air)), ["a", "x"], "the marked item is left out here")
        world.tick()
        let studioPlan = try XCTUnwrap(try studio.engine.sync().dockPlan)
        XCTAssertEqual(studioPlan.removed.compactMap(\.bundleID), ["junk"], "and removed from the other Mac")
        XCTAssertEqual(studioPlan.added.compactMap(\.bundleID), ["x"])
    }
}
