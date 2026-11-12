import XCTest
@testable import MacSyncCore

/// Every key and token below is made up.
final class ExtrasTests: XCTestCase {
    func home(_ world: TestWorld, _ mac: String) -> URL { world.root.appendingPathComponent(mac) }

    func write(_ text: String, _ path: String, on mac: String, in world: TestWorld) throws {
        let url = home(world, mac).appendingPathComponent(String(path.dropFirst(2)))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func read(_ path: String, on mac: String, in world: TestWorld) -> String? {
        try? String(contentsOf: home(world, mac).appendingPathComponent(String(path.dropFirst(2))), encoding: .utf8)
    }

    static let fakeHex = String(repeating: "ab12", count: 16)

    func testConfigFileTravelsAndCanBeUndone() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"]), air = try world.mac("air", dock: ["a"])
        try write("alias ll='ls -la'\n", "~/.zshrc", on: "studio", in: world)
        try studio.engine.sync()
        world.tick()
        let overview = try air.engine.sync()
        let change = try XCTUnwrap(overview.extras.files.first { $0.path == "~/.zshrc" })
        XCTAssertTrue(change.isNew)
        XCTAssertEqual(change.sourceMachine, "Studio")
        XCTAssertTrue(overview.hasPendingChanges)

        let report = try air.engine.apply(ApplyRequest(applyDock: false, apps: [], files: ["~/.zshrc"]))
        XCTAssertEqual(report.extras?.filesChanged, ["~/.zshrc"])
        XCTAssertEqual(read("~/.zshrc", on: "air", in: world), "alias ll='ls -la'\n")
        XCTAssertTrue(try air.engine.sync().extras.files.isEmpty, "taken once, not offered again")
        world.tick()
        XCTAssertTrue(try studio.engine.sync().extras.files.isEmpty, "taking it isn't an edit the studio is offered back")

        try air.engine.undoLast()
        XCTAssertNil(read("~/.zshrc", on: "air", in: world), "it didn't exist before, so undo takes it away")
    }

    func testNewerEditOnThisMacIsNotReplaced() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"]), air = try world.mac("air", dock: ["a"])
        try write("one\n", "~/.gitconfig", on: "studio", in: world)
        try studio.engine.sync()
        world.tick()
        try write("two\n", "~/.gitconfig", on: "air", in: world)
        try air.engine.sync()
        world.tick()
        XCTAssertTrue(try air.engine.sync().extras.files.isEmpty)
        let change = try XCTUnwrap(try studio.engine.sync().extras.files.first)
        XCTAssertEqual(change.detail, "+1 −1 lines")
        XCTAssertEqual(Set(change.preview), ["− one", "+ two"])
    }

    func testFileWithASecretStaysOnItsMac() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"]), air = try world.mac("air", dock: ["a"])
        try write("Use the key fc-0123456789abcdef0123456789abcdef here.\n", "~/.claude/CLAUDE.md", on: "studio", in: world)
        try write("export GITHUB_TOKEN=ghp_FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE1234\n", "~/.zprofile", on: "studio", in: world)
        try write("export EDITOR=nvim\n", "~/.zshenv", on: "studio", in: world)
        let mine = try studio.engine.sync()
        XCTAssertEqual(Set(mine.extras.kept.map(\.path)), ["~/.claude/CLAUDE.md", "~/.zprofile"])
        world.tick()
        XCTAssertEqual(try air.engine.sync().extras.files.map(\.path), ["~/.zshenv"])
    }

    func testJSONSettingsKeepEachMacsOwnSecrets() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"]), air = try world.mac("air", dock: ["a"])
        try write(#"{"model": "sonnet", "env": {"EXAMPLE_API_KEY": "airfake999999999abcdef"}}"#,
                  "~/.claude/settings.json", on: "air", in: world)
        try air.engine.sync()
        world.tick()
        try write(#"{"model": "opus", "env": {"EXAMPLE_API_KEY": "studiofake1234567abcdef", "DEBUG": "1"}}"#,
                  "~/.claude/settings.json", on: "studio", in: world)
        try studio.engine.sync()
        let folder = world.sync.appendingPathComponent("files")
        for blob in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
            let text = try String(contentsOf: folder.appendingPathComponent(blob), encoding: .utf8)
            XCTAssertFalse(text.contains("studiofake"), "the key never reaches iCloud")
        }
        world.tick()
        let overview = try air.engine.sync()
        XCTAssertNotNil(overview.extras.files.first { $0.path == "~/.claude/settings.json" })
        try air.engine.apply(ApplyRequest(applyDock: false, apps: [], files: ["~/.claude/settings.json"]))
        let data = try XCTUnwrap(read("~/.claude/settings.json", on: "air", in: world)?.data(using: .utf8))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "opus")
        let env = try XCTUnwrap(json["env"] as? [String: Any])
        XCTAssertEqual(env["EXAMPLE_API_KEY"] as? String, "airfake999999999abcdef")
        XCTAssertEqual(env["DEBUG"] as? String, "1")
    }

    func testRemoveFromAllMacsReachesTheOthers() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"]), air = try world.mac("air", dock: ["a"])
        try write("set -g mouse on\n", "~/.tmux.conf", on: "studio", in: world)
        try write("set -g mouse on\n", "~/.tmux.conf", on: "air", in: world)
        try studio.engine.sync(); try air.engine.sync()
        // Gone from the studio already, so nothing goes to the real Trash.
        try FileManager.default.removeItem(at: home(world, "studio").appendingPathComponent(".tmux.conf"))
        XCTAssertNoThrow(try studio.engine.removeExtra("file:~/.tmux.conf", name: ".tmux.conf", everywhere: true).get())
        world.tick()
        let overview = try air.engine.sync()
        XCTAssertEqual(overview.extras.toRemove.map(\.token), ["file:~/.tmux.conf"])
        XCTAssertTrue(overview.hasPendingChanges)
        try air.engine.keepExtraHere("file:~/.tmux.conf")
        XCTAssertTrue(try air.engine.sync().extras.toRemove.isEmpty)
    }

    func testKeepingAFileToThisMacStopsTakingIt() throws {
        let world = try TestWorld()
        let studio = try world.mac("studio", dock: ["a"]), air = try world.mac("air", dock: ["a"])
        try write("x\n", "~/.vimrc", on: "studio", in: world)
        try studio.engine.sync()
        world.tick()
        XCTAssertFalse(try air.engine.sync().extras.files.isEmpty)
        try air.engine.setFilesLocalOnly(["~/.vimrc"], true)
        let overview = try air.engine.sync()
        XCTAssertTrue(overview.extras.files.isEmpty)
        XCTAssertTrue(overview.extras.shared.contains { $0.path == "~/.vimrc" && $0.localOnly })
    }

    func testNeverSharedPaths() {
        for path in ["~/.ssh/config", "~/.aws/credentials", "~/.zsh_history", "~/.config/gh/hosts.yml", "~/.env", "~/.config/op/config"] {
            XCTAssertTrue(ExtrasCatalog.isNeverShared(path), path)
        }
        XCTAssertFalse(ExtrasCatalog.isNeverShared("~/.zshrc"))
        XCTAssertEqual(ExtrasCatalog.group(for: "~/.claude/skills/foo/SKILL.md")?.id, "skills")
        XCTAssertEqual(ExtrasCatalog.group(for: "~/Library/Application Support/Adobe/Adobe Photoshop 2026/Presets/Brushes/a.abr")?.id, "photoshop")
        XCTAssertNil(ExtrasCatalog.group(for: "~/Documents/notes.txt"))
    }

    func testSecretScan() {
        XCTAssertNotNil(SecretScan.reason(in: "export OPENAI_API_KEY=sk-proj-FAKEFAKEFAKEFAKEFAKE1234"))
        XCTAssertNotNil(SecretScan.reason(in: "    token    " + Self.fakeHex))
        XCTAssertNotNil(SecretScan.reason(in: "-----BEGIN OPENSSH PRIVATE KEY-----"))
        XCTAssertNotNil(SecretScan.reason(in: #"{"apiKey": "fake1fake2fake3fake4"}"#))
        XCTAssertNil(SecretScan.reason(in: #"{"key": "cmd+shift+alt+p", "command": "workbench.action.files.save"}"#))
        XCTAssertNil(SecretScan.reason(in: "[user]\n  signingkey = 3AA5C34371567BD2\n"))
        XCTAssertNil(SecretScan.reason(in: "export GITHUB_TOKEN=$(op read op://dev/github/token)"))
        XCTAssertNil(SecretScan.reason(in: "alias gs='git status'"))
    }

    func testPackageTokens() {
        XCTAssertTrue(Packages.isSafe("tap:onlymoein/tap"))
        XCTAssertTrue(Packages.isSafe("claude-plugin:swift-lsp@claude-plugins-official"))
        XCTAssertTrue(Packages.isSafe("npm:@anthropic-ai/claude-code"))
        XCTAssertFalse(Packages.isSafe("npm:--global"))
        XCTAssertFalse(Packages.isSafe("npm:a;rm -rf"))
        XCTAssertFalse(Packages.isSafe("other:x"))
        XCTAssertEqual(Packages.vdf("name", in: "\"AppState\"\n{\n\t\"appid\"\t\t\"620\"\n\t\"name\"\t\t\"Portal 2\"\n}"), "Portal 2")
    }

    func testHotCornersReadAsNames() {
        XCTAssertEqual(SettingsCatalog.describe("com.apple.dock|wvous-tl-corner", .int(2)), "Mission Control")
        XCTAssertEqual(SettingsCatalog.describe("com.apple.dock|wvous-tl-modifier", .int(1_048_576)), "⌘")
        XCTAssertEqual(SettingsCatalog.describe("x|y", nil), "default")
    }

    func testPkgAppsMatchTheirCaskByBundleID() throws {
        let json = #"[{"token": "microsoft-word", "url": "https://x/word.pkg", "artifacts": [{"pkg": ["Word.pkg"]}, {"uninstall": [{"quit": "com.microsoft.Word", "pkgutil": "com.microsoft.package.Microsoft_Word.app"}]}]}, {"token": "zoom", "url": "https://x/zoom.pkg", "artifacts": [{"uninstall": [{"delete": ["/Applications/zoom.us.app"]}]}]}]"#
        let catalog = try XCTUnwrap(CaskCatalog.parse(Data(json.utf8)))
        XCTAssertEqual(catalog.cask(forBundleID: "com.microsoft.Word"), "microsoft-word")
        XCTAssertEqual(catalog.cask(forApp: "zoom.us.app"), "zoom")
    }
}

final class DependencyFormulaTests: XCTestCase {
    func testAFormulaHereAsADependencyIsNotMissing() {
        var other = TestWorld.snapshot(id: "studio", apps: [], changedAt: Date())
        other.inventory = Inventory(brewAvailable: true, formulae: ["poppler", "jq"])
        let local = Inventory(brewAvailable: true, formulae: [], allFormulae: ["poppler"])
        XCTAssertEqual(Planner.missingApps(local: local, others: [other]).map(\.app.name), ["jq"])
    }
}

final class MovedFormulaTests: XCTestCase {
    func testAFormulaThatMovedToACaskIsNotMissing() {
        var studio = TestWorld.snapshot(id: "studio", apps: [], changedAt: Date())
        studio.inventory = Inventory(brewAvailable: true, formulae: ["vercel"])
        let air = Inventory(brewAvailable: true, casks: ["vercel"])
        XCTAssertTrue(Planner.missingApps(local: air, others: [studio]).isEmpty)
    }
}

final class TerminalInstallTests: XCTestCase {
    func testADevelopersAppPublishedByHomebrewInstallsInTerminal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macsync-term-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let tailscale = MissingApp(app: AppRef(source: .direct, name: "Tailscale"), fromMachines: ["Air"],
                                   detail: AppDetail(displayName: "Tailscale"),
                                   download: DirectApp(bundleID: "io.tailscale.ipn.macsys", name: "Tailscale", cask: "tailscale-app"))
        let docker = MissingApp(app: AppRef(source: .cask, name: "docker-desktop"), fromMachines: ["Air"], detail: AppDetail(displayName: "Docker Desktop"))
        let url = try XCTUnwrap(Engine.terminalInstall([docker, tailscale], in: folder))
        let script = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(script.contains("brew install --cask docker-desktop"))
        XCTAssertTrue(script.contains("brew install --cask tailscale-app"))
        XCTAssertEqual(url.lastPathComponent, "Install 2 apps.command")
        let unknown = MissingApp(app: AppRef(source: .direct, name: "Thing"), fromMachines: [])
        XCTAssertNil(Engine.terminalInstall([unknown], in: folder))
    }

    func testFindsTheDevelopersSetupFilesButNeverProvisioningProfiles() {
        XCTAssertEqual(ExtrasCatalog.group(for: "~/Library/Developer/Xcode/UserData/KeyBindings/Mine.idekeybindings")?.id, "xcode")
        XCTAssertNil(ExtrasCatalog.group(for: "~/Library/Developer/Xcode/UserData/Provisioning Profiles/x.mobileprovision")?.id)
        XCTAssertTrue(Packages.isSafe("android-sdk:platforms/android-36"))
        XCTAssertEqual(Packages.platformName("com.apple.platform.iphonesimulator".components(separatedBy: ".").last!), "iOS")
    }
}

final class PackageClashTests: XCTestCase {
    func testNpmsRealReasonInsteadOfItsLogPath() {
        let stderr = """
        npm error code EEXIST
        npm error path /opt/homebrew/bin/codex
        npm error EEXIST: file already exists
        npm error File exists: /opt/homebrew/bin/codex
        npm error Remove the existing file and try again, or run npm
        npm error A complete log of this run can be found in: /Users/x/.npm/_logs/2026-11-12T21_36_45_688Z-debug-0.log
        """
        let reason = Packages.reason(stderr, name: "@openai/codex") ?? ""
        XCTAssertTrue(reason.hasPrefix("@openai/codex is already on this Mac"), reason)
        XCTAssertFalse(reason.contains("debug-0.log"))
        XCTAssertEqual(Packages.reason("npm error code E404\nnpm error 404 Not Found - GET https://registry.npmjs.org/nope\nnpm error A complete log of this run can be found in: /x-debug-0.log", name: "nope"),
                       "404 Not Found - GET https://registry.npmjs.org/nope")
    }

    func testACommandFromHomebrewMeansThePackageIsntOffered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clash-\(UUID().uuidString.prefix(6))")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin"), cellar = root.appendingPathComponent("Cellar/vercel/63/bin")
        let modules = root.appendingPathComponent("lib/node_modules/thing/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        // Homebrew's vercel is built on npm: its own link goes on into a node_modules folder.
        let inner = root.appendingPathComponent("Cellar/vercel/63/libexec/lib/node_modules/vercel/dist")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: inner.appendingPathComponent("vc.js").path, contents: Data())
        try FileManager.default.createSymbolicLink(atPath: cellar.appendingPathComponent("vercel").path, withDestinationPath: inner.appendingPathComponent("vc.js").path)
        FileManager.default.createFile(atPath: modules.appendingPathComponent("thing").path, contents: Data())
        try FileManager.default.createSymbolicLink(atPath: bin.appendingPathComponent("vercel").path, withDestinationPath: cellar.appendingPathComponent("vercel").path)
        try FileManager.default.createSymbolicLink(atPath: bin.appendingPathComponent("thing").path, withDestinationPath: modules.appendingPathComponent("thing").path)
        let env = MacSyncEnvironment(syncDirectory: root, dataDirectory: root, machineID: "t", machineName: "T", dockFile: nil,
                                     brewPath: bin.appendingPathComponent("brew").path, applicationsDirectory: root, homeDirectory: root.path)
        XCTAssertNotNil(Packages.commandFromElsewhere("npm:vercel", env: env), "Homebrew's vercel")
        XCTAssertNil(Packages.commandFromElsewhere("npm:thing", env: env), "npm's own copy")
        XCTAssertNil(Packages.commandFromElsewhere("npm:@scope/absent", env: env))
    }
}
