import XCTest
@testable import MacSyncCore

final class ShareTests: XCTestCase {
    func testAFriendGetsOnlyTheChosenSectionsAndNoSecrets() throws {
        let mine = try TestWorld(), theirs = try TestWorld()
        let me = try mine.mac("studio", dock: ["a"])
        me.runner.casks = ["ghostty"]
        me.runner.formulae = ["jq"]
        let home = mine.root.appendingPathComponent("studio")
        try Data("alias ll='ls -la'\n".utf8).write(to: home.appendingPathComponent(".zshrc"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try Data("Use the key fc-0123456789abcdef0123456789abcdef.\n".utf8).write(to: home.appendingPathComponent(".claude/CLAUDE.md"))
        try me.engine.sync()

        let file = try me.engine.exportSetup(name: "Mehdi", sections: [.apps, .config, .ai])
        let text = String(decoding: file, as: UTF8.self)
        XCTAssertFalse(text.contains("fc-0123456789abcdef"), "a file with a secret is never shared")
        XCTAssertFalse(text.contains("\"jq\""), "command-line tools weren't chosen")

        let friend = try theirs.mac("friend", dock: ["a"])
        let info = try friend.engine.importSetup(file)
        XCTAssertEqual(info.name, "Mehdi's setup")
        let overview = try friend.engine.sync()
        XCTAssertEqual(overview.missingApps.map(\.app.name), ["ghostty"])
        XCTAssertEqual(overview.missingApps.first?.fromMachines, ["Mehdi's setup"])
        XCTAssertEqual(overview.extras.files.map(\.path), ["~/.zshrc"])
        XCTAssertFalse(overview.machines.contains { $0.name.contains("setup") }, "a shared setup isn't one of your Macs")

        try friend.engine.apply(ApplyRequest(applyDock: false, apps: [], files: ["~/.zshrc"]))
        XCTAssertEqual(try String(contentsOf: theirs.root.appendingPathComponent("friend/.zshrc"), encoding: .utf8), "alias ll='ls -la'\n")

        try friend.engine.removeImportedSetup(info.id)
        XCTAssertTrue(try friend.engine.sync().missingApps.isEmpty)
        XCTAssertThrowsError(try friend.engine.importSetup(Data("{}".utf8)))
    }
}
