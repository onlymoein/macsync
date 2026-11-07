import XCTest
@testable import MacSyncCore

final class PrefsTests: XCTestCase {
    func testValuesSurviveJSON() throws {
        let value = PrefValue.dict(["a": .array([.bool(true), .int(3), .double(2.5), .string("x")])])
        let back = try JSONDecoder().decode(PrefValue.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(back, value)
        XCTAssertEqual(PrefValue.int(29), PrefValue.double(29.0))
        XCTAssertNotEqual(PrefValue.bool(true), PrefValue.int(1))
    }

    func testSecretsAreNeverCaptured() {
        for key in ["apiToken", "accessToken", "licenseKey", "user_password", "AuthState", "SessionID", "clientSecret", "deviceUUID"] {
            XCTAssertFalse(PrefsCapture.allowed(key: key, value: .string("x")), key)
        }
        XCTAssertFalse(PrefsCapture.allowed(key: "harmless", value: .string("ghp_AbCdEf0123456789AbCdEf0123456789AbCd")))
        XCTAssertFalse(PrefsCapture.allowed(key: "nested", value: .dict(["token": .string("x")])))
        XCTAssertFalse(PrefsCapture.allowed(key: "NSWindow Frame main", value: .string("0 0 10 10")))
        XCTAssertTrue(PrefsCapture.allowed(key: "theme", value: .string("dark")))
        XCTAssertTrue(PrefsCapture.allowed(key: "hotkey", value: .dict(["code": .int(49)])))
    }

    func testCaptureOnlyTakesPickedNonAppleDomains() {
        let prefs = InMemoryPreferences()
        prefs.store["com.raycast.macos"] = ["theme": .string("dark"), "apiToken": .string("secret"), "NSWindow Frame x": .string("1")]
        prefs.store["com.apple.finder"] = ["ShowStatusBar": .bool(true)]
        prefs.store["com.other.app"] = ["a": .int(1)]
        let captured = PrefsCapture.values(prefs: prefs, appDomains: ["com.raycast.macos", "com.apple.mail"], home: "/h")
        XCTAssertEqual(captured.values["com.raycast.macos|theme"], .string("dark"))
        XCTAssertNil(captured.values["com.raycast.macos|apiToken"])
        XCTAssertNil(captured.values["com.other.app|a"])
        XCTAssertEqual(captured.values["com.apple.finder|ShowStatusBar"], .bool(true))
    }

    func section(_ values: [String: PrefValue], domains: [String] = [], covered: [String]? = nil) -> PrefsSection {
        PrefsSection(changedAt: Date(), covered: covered ?? SettingsCatalog.all.map(\.id), values: values, appDomains: domains)
    }

    func testUnsetOnTheOtherMacRemovesTheKey() {
        let prefs = InMemoryPreferences()
        prefs.store["com.apple.finder"] = ["ShowPathbar": .bool(true)]
        let plan = SettingsPlanner.plan(target: section([:]), source: "S", prefs: prefs, home: "/h")
        XCTAssertEqual(plan.changes.map(\.id), ["com.apple.finder|ShowPathbar"])
        XCTAssertNil(plan.changes[0].to)
    }

    func testAKeyTheOtherAppVersionNeverKnewIsLeftAlone() {
        let prefs = InMemoryPreferences()
        prefs.store["com.apple.finder"] = ["ShowPathbar": .bool(true)]
        let plan = SettingsPlanner.plan(target: section([:], covered: []), source: "S", prefs: prefs, home: "/h")
        XCTAssertFalse(plan.hasChanges)
    }

    func testAppPreferencesAreAdditiveAndOnlyForPickedDomains() {
        let prefs = InMemoryPreferences()
        prefs.store["com.raycast.macos"] = ["local-only": .int(1)]
        let target = section(["com.raycast.macos|theme": .string("dark"), "com.evil.app|x": .int(1)], domains: ["com.raycast.macos"])
        let plan = SettingsPlanner.plan(target: target, source: "S", prefs: prefs, home: "/h")
        XCTAssertEqual(plan.changes.map(\.id), ["com.raycast.macos|theme"])
    }

    func testScreenshotFolderMissingHereIsSkippedNotCreated() {
        let prefs = InMemoryPreferences()
        let plan = SettingsPlanner.plan(target: section(["com.apple.screencapture|location": .string("~/NoSuchFolder-\(UUID())")]),
                                        source: "S", prefs: prefs, home: NSHomeDirectory())
        XCTAssertFalse(plan.hasChanges)
        XCTAssertEqual(plan.skipped.count, 1)
    }

    func testSystemPreferencesRoundTripTypesOnARealDomain() {
        let domain = "com.onlymehdi.macsync.tests"
        let prefs = SystemPreferences()
        defer { for key in prefs.allKeys(domain: domain) { prefs.remove(domain: domain, key: key) } }
        prefs.set(domain: domain, key: "f", value: .int(29), type: .float)
        prefs.set(domain: domain, key: "b", value: .bool(true), type: .bool)
        prefs.set(domain: domain, key: "s", value: .string("x"), type: .string)
        prefs.set(domain: domain, key: "i", value: .int(2), type: .int)
        XCTAssertEqual(prefs.value(domain: domain, key: "f"), .double(29))
        XCTAssertEqual(prefs.value(domain: domain, key: "b"), .bool(true))
        XCTAssertEqual(prefs.value(domain: domain, key: "i"), .int(2))
        prefs.remove(domain: domain, key: "s")
        XCTAssertNil(prefs.value(domain: domain, key: "s"))
    }
}

final class ProEngineTests: XCTestCase {
    func twoMacs() throws -> (TestWorld, TestWorld.Mac, TestWorld.Mac) {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"])
        let air = try world.mac("air", dock: ["a"])
        return (world, studio, air)
    }

    func testSettingsApplyThenUndoRestoresEveryKey() throws {
        let (world, studio, air) = try twoMacs()
        studio.prefs.store["com.apple.finder"] = ["ShowPathbar": .bool(true)]
        studio.prefs.store["com.apple.dock"] = ["magnification": .bool(true), "largesize": .int(80)]
        try studio.engine.sync()
        world.tick()
        air.prefs.store["com.apple.finder"] = ["ShowStatusBar": .bool(true)]
        air.prefs.store["com.apple.dock"] = ["largesize": .int(40)]
        let before = air.prefs.store

        let overview = try air.engine.sync()
        XCTAssertEqual(overview.settingsPlan?.sourceMachine, "Studio")
        XCTAssertEqual(Set(overview.settingsPlan?.changes.map(\.id) ?? []),
                       ["com.apple.finder|ShowPathbar", "com.apple.finder|ShowStatusBar", "com.apple.dock|magnification", "com.apple.dock|largesize"])
        XCTAssertEqual(air.prefs.store, before, "sync alone must change nothing")

        let report = try air.engine.apply(ApplyRequest(applyDock: false, apps: []))
        XCTAssertTrue(report.settingsChanged)
        XCTAssertEqual(air.prefs.value(domain: "com.apple.finder", key: "ShowPathbar"), .bool(true))
        XCTAssertNil(air.prefs.value(domain: "com.apple.finder", key: "ShowStatusBar"), "unset on Studio means removed here")
        XCTAssertEqual(air.prefs.value(domain: "com.apple.dock", key: "largesize"), .int(80))
        XCTAssertEqual(Set(air.prefs.restarts), [.finder])
        XCTAssertGreaterThan(air.dockStore.restarts, 0, "Dock keys changed, so the Dock must restart")
        XCTAssertNil(try air.engine.sync().settingsPlan)

        _ = try air.engine.undoLast()
        XCTAssertEqual(air.prefs.store.mapValues { $0.filter { _ in true } }, before)
    }

    func testSettingsOnlyApplyLeavesTheDockAlone() throws {
        let (world, studio, air) = try twoMacs()
        studio.prefs.store["com.apple.finder"] = ["ShowPathbar": .bool(true)]
        try studio.engine.sync()
        world.tick()
        let dockBefore = try air.dockStore.exportPlist()
        _ = try air.engine.apply(ApplyRequest(applyDock: true, apps: []))
        XCTAssertEqual(try air.dockStore.exportPlist(), dockBefore)
        XCTAssertEqual(air.dockStore.restarts, 0)
        try air.dockStore.importPlist(try TestWorld.plist(apps: ["a", "zzz"]))
        _ = try air.engine.undoLast()
        XCTAssertEqual(try DockCapture.section(from: try air.dockStore.readRaw(), changedAt: Date(), home: "/h").apps.count, 2,
                       "undoing a settings-only apply must not roll the Dock back")
    }

    func testSettingsThatDontStickArePutBackAndReported() throws {
        let (world, studio, air) = try twoMacs()
        studio.prefs.store["com.apple.finder"] = ["ShowPathbar": .bool(true)]
        try studio.engine.sync()
        world.tick()
        air.prefs.ignoreWrites = true
        let report = try air.engine.apply(ApplyRequest(applyDock: false, apps: []))
        XCTAssertFalse(report.settingsChanged)
        XCTAssertNotNil(report.settingsError)
        XCTAssertTrue(report.hasFailures)
    }

    func testLatestSettingsEditWins() throws {
        let (world, studio, air) = try twoMacs()
        try studio.engine.sync()
        world.tick()
        try air.engine.sync()
        world.tick()
        studio.prefs.store["com.apple.finder"] = ["ShowPathbar": .bool(true)]
        try studio.engine.sync()
        world.tick()
        air.prefs.store["com.apple.finder"] = ["ShowPathbar": .bool(false)]
        try air.engine.sync()
        world.tick()
        XCTAssertEqual(try studio.engine.sync().settingsPlan?.sourceMachine, "Air")
        XCTAssertNil(try air.engine.sync().settingsPlan)
    }

    func testAnAppliedMacNeverPushesTheSettingsBack() throws {
        let (world, studio, air) = try twoMacs()
        studio.prefs.store["com.apple.finder"] = ["ShowPathbar": .bool(true)]
        try studio.engine.sync()
        world.tick()
        _ = try air.engine.apply(ApplyRequest(applyDock: false, apps: []))
        world.tick()
        XCTAssertNil(try studio.engine.sync().settingsPlan)
    }

    func testWhenProIsLockedNothingIsSavedOrOffered() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"], pro: false)
        studio.prefs.store["com.apple.finder"] = ["ShowPathbar": .bool(true)]
        try studio.engine.sync()
        world.tick()
        let air = try world.mac("air", dock: ["a"], pro: true)
        XCTAssertNil(try SnapshotCodec.decode(Data(contentsOf: world.sync.appendingPathComponent("machines/studio.json"))).settings)
        XCTAssertNil(try air.engine.sync().settingsPlan)
        let locked = try world.mac("locked", dock: ["a"], pro: false)
        XCTAssertFalse(try locked.engine.sync().proEnabled)
    }

    func testPickedAppPreferencesSyncWithoutSecrets() throws {
        let (world, studio, air) = try twoMacs()
        studio.prefs.store["com.raycast.macos"] = ["theme": .string("dark"), "apiToken": .string("nope")]
        try studio.engine.setAppPrefDomains(["com.raycast.macos", "com.apple.mail", "bad domain"])
        XCTAssertEqual(studio.engine.appPrefDomains(), ["com.raycast.macos"])
        try studio.engine.sync()
        world.tick()
        let overview = try air.engine.sync()
        XCTAssertEqual(overview.settingsPlan?.changes.map(\.id), ["com.raycast.macos|theme"])
        _ = try air.engine.apply(ApplyRequest(applyDock: false, apps: []))
        XCTAssertEqual(air.prefs.value(domain: "com.raycast.macos", key: "theme"), .string("dark"))
        XCTAssertNil(air.prefs.value(domain: "com.raycast.macos", key: "apiToken"))
        let text = String(decoding: try Data(contentsOf: world.sync.appendingPathComponent("machines/studio.json")), as: UTF8.self)
        XCTAssertFalse(text.contains("nope"))
    }

    func testSnapshotsFromBeforeProStillLoad() throws {
        let old = #"{"schemaVersion":2,"machineID":"m","machineName":"n","osVersion":"o","appVersion":"0.2.0","firstSeenAt":"2026-11-01T10:00:00Z","savedAt":"2026-11-01T10:00:00Z"}"#
        XCTAssertNil(try SnapshotCodec.decode(Data(old.utf8)).settings)
    }
}
