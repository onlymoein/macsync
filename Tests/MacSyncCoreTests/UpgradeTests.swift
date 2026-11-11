import XCTest
@testable import MacSyncCore

final class UpgradeTests: XCTestCase {
    final class BrewRunner: CommandRunning {
        var calls: [[String]] = []
        func run(_ executable: String, _ arguments: [String], input: Data?, environment: [String: String]) -> CommandResult {
            calls.append(arguments)
            if arguments.first == "outdated" {
                let json = #"{"formulae": [{"name": "jq", "installed_versions": ["1.6"], "current_version": "1.7"}], "casks": [{"name": "deckcraft", "installed_versions": ["0.1"], "current_version": "0.2"}, {"name": "raycast", "installed_versions": ["1.0"], "current_version": "1.1"}, {"name": "ghostty", "installed_versions": ["1.0"], "current_version": "1.2"}, {"name": "macsync", "installed_versions": ["0.6"], "current_version": "0.7"}]}"#
                return CommandResult(status: 0, stdout: Data(json.utf8))
            }
            if arguments.first == "info" {
                let json = #"{"casks": [{"token": "raycast", "name": ["Raycast"], "artifacts": [{"app": ["Raycast.app"]}]}, {"token": "ghostty", "name": ["Ghostty"], "artifacts": [{"app": ["Ghostty.app"]}]}]}"#
                return CommandResult(status: 0, stdout: Data(json.utf8))
            }
            return CommandResult(status: 0)
        }
    }

    func testUpdatesEverythingExceptOpenAppsAndItself() throws {
        let world = try TestWorld()
        try world.installDirectApp("Raycast", bundleID: "com.raycast.macos", on: "studio")
        try world.installDirectApp("Ghostty", bundleID: "com.mitchellh.ghostty", on: "studio")
        let env = MacSyncEnvironment(syncDirectory: world.sync, dataDirectory: world.root.appendingPathComponent("data"), machineID: "s",
                                     machineName: "S", dockFile: nil, brewPath: "/fake/brew",
                                     applicationsDirectory: world.root.appendingPathComponent("studio/Applications"), homeDirectory: "/nowhere")
        let runner = BrewRunner()
        var upgrader = Upgrader(env: env, runner: runner)
        upgrader.isRunning = { $0 == "com.raycast.macos" }
        XCTAssertTrue(upgrader.isDue())
        let report = upgrader.upgradeAll(now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(Set(report.upgraded.map(\.token)), ["formula:jq", "cask:ghostty"])
        XCTAssertEqual(report.waiting.map(\.name), ["Raycast"], "open apps wait")
        XCTAssertFalse(runner.calls.contains { $0.contains("macsync") && $0.first == "upgrade" }, "MacSync updates itself")
        XCTAssertTrue(runner.calls.contains(["upgrade", "--cask", "--greedy", "ghostty"]))
        XCTAssertFalse(upgrader.isDue(now: Date(timeIntervalSince1970: 2000)))
        XCTAssertTrue(upgrader.isDue(now: Date(timeIntervalSince1970: 1000 + 7 * 3600)))
    }

    func testCheckListsWithoutInstallingThenUpdateOne() throws {
        let world = try TestWorld()
        let env = MacSyncEnvironment(syncDirectory: world.sync, dataDirectory: world.root.appendingPathComponent("data"), machineID: "s",
                                     machineName: "S", dockFile: nil, brewPath: "/fake/brew",
                                     applicationsDirectory: world.root.appendingPathComponent("studio/Applications"), homeDirectory: "/nowhere")
        let runner = BrewRunner()
        var upgrader = Upgrader(env: env, runner: runner)
        upgrader.isRunning = { _ in false }
        let found = upgrader.check()
        XCTAssertEqual(Set((found.outdated ?? []).map(\.token)), ["formula:jq", "cask:raycast", "cask:ghostty"])
        XCTAssertFalse(runner.calls.contains { $0.first == "upgrade" }, "checking installs nothing")
        let jq = try XCTUnwrap(found.outdated?.first { $0.token == "formula:jq" })
        let after = upgrader.upgrade([jq])
        XCTAssertEqual(after.upgraded.map(\.token), ["formula:jq"])
        XCTAssertEqual(Set((after.outdated ?? []).map(\.token)), ["cask:raycast", "cask:ghostty"], "the rest are still listed")
    }
}

final class StreamTests: XCTestCase {
    func testLinesArriveAsTheyArePrintedAndSilenceStopsIt() {
        var lines: [String] = []
        let ok = SystemCommandRunner().stream("/bin/sh", ["-c", "echo '==> Downloading x'; sleep 0.3; echo '==> Pouring x'"],
                                              input: nil, environment: [:], idleTimeout: 5) { lines.append($0) }
        XCTAssertEqual(ok.status, 0)
        XCTAssertEqual(lines, ["==> Downloading x", "==> Pouring x"])
        let quiet = SystemCommandRunner().stream("/bin/sh", ["-c", "echo start; sleep 30"], input: nil, environment: [:], idleTimeout: 1) { _ in }
        XCTAssertEqual(quiet.status, -2)
        XCTAssertTrue(quiet.stderr.contains("printed nothing"))
        XCTAssertEqual(Engine.brewStatus("Password:", name: "x")?.contains("password"), true)
        XCTAssertEqual(Engine.brewStatus("==> Pouring btop--1.4.tar.gz", name: "btop"), "Installing btop…")
    }
}

final class SelfUpdatingAppTests: XCTestCase {
    func testAnAppThatUpdatesItselfIsOfferedOnlyWhenHomebrewIsAhead() throws {
        let world = try TestWorld()
        let data = world.root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let casks = #"[{"token": "claude", "url": "https://x/c.zip", "version": "5.1232.0,abcdef", "artifacts": [{"app": ["Claude.app"]}]}, {"token": "chatgpt", "url": "https://x/g.zip", "version": "26.1103.60933", "artifacts": [{"app": ["ChatGPT.app"]}]}]"#
        try Data(casks.utf8).write(to: data.appendingPathComponent("cask-catalog.json"))
        let env = MacSyncEnvironment(syncDirectory: world.sync, dataDirectory: data, machineID: "s", machineName: "S", dockFile: nil,
                                     brewPath: "/fake/brew", applicationsDirectory: world.root.appendingPathComponent("Applications"),
                                     homeDirectory: "/nowhere")
        var upgrader = Upgrader(env: env, runner: FakeRunner())
        upgrader.directApps = [DirectApp(bundleID: "com.anthropic.claudefordesktop", name: "Claude", version: "5.1231.2", feed: nil),
                               DirectApp(bundleID: "com.openai.codex", name: "ChatGPT", version: "26.1103.60933", feed: nil)]
        let found = upgrader.directOutdated()
        XCTAssertEqual(found.map(\.token), ["adopt:claude"], "ChatGPT is already as new as Homebrew's")
        XCTAssertEqual(found.first?.to, "5.1232.0")
    }
}
