@testable import MacSyncCore
import XCTest

final class SelfUpdateTests: XCTestCase {
    func release(_ tag: String, assets: [String], prerelease: Bool = false) -> Data {
        let list = assets.map { #"{"name":"\#($0)","browser_download_url":"https://github.com/onlymehdi/macsync/releases/download/\#(tag)/\#($0)"}"# }
        return Data(#"{"tag_name":"\#(tag)","prerelease":\#(prerelease),"assets":[\#(list.joined(separator: ","))]}"#.utf8)
    }

    func testFindsANewerRelease() throws {
        let runner = FakeRunner()
        runner.web[SelfUpdater.releasesAPI] = release("v0.4.0", assets: ["MacSync-0.4.0.zip", "MacSync-0.4.0.zip.sha256"])
        let updater = SelfUpdater(runner: runner, brewPath: nil, appURL: URL(fileURLWithPath: "/Applications/MacSync.app"), currentVersion: "0.3.1")
        let found = try XCTUnwrap(updater.check())
        XCTAssertEqual(found.version, "0.4.0")
        XCTAssertNotNil(found.checksumURL)
    }

    func testIgnoresOlderPrereleaseAndForeignAssets() {
        let runner = FakeRunner()
        let app = URL(fileURLWithPath: "/Applications/MacSync.app")
        runner.web[SelfUpdater.releasesAPI] = release("v0.3.0", assets: ["MacSync-0.3.0.zip"])
        XCTAssertNil(SelfUpdater(runner: runner, brewPath: nil, appURL: app, currentVersion: "0.3.1").check())
        runner.web[SelfUpdater.releasesAPI] = release("v0.9.0", assets: ["MacSync-0.9.0.zip"], prerelease: true)
        XCTAssertNil(SelfUpdater(runner: runner, brewPath: nil, appURL: app, currentVersion: "0.3.1").check())
        runner.web[SelfUpdater.releasesAPI] = Data(#"{"tag_name":"v0.9.0","assets":[{"name":"MacSync-0.9.0.zip","browser_download_url":"https://evil.example/MacSync.zip"}]}"#.utf8)
        XCTAssertNil(SelfUpdater(runner: runner, brewPath: nil, appURL: app, currentVersion: "0.3.1").check())
    }

    func testVersionOrder() {
        XCTAssertTrue(SelfUpdater.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertTrue(SelfUpdater.isNewer("1.0", than: "0.9"))
        XCTAssertFalse(SelfUpdater.isNewer("0.3.0", than: "0.3"))
    }

    func testHomebrewCopyUpdatesThroughBrew() {
        let runner = FakeRunner()
        runner.casks = ["macsync"]
        let updater = SelfUpdater(runner: runner, brewPath: "/fake/brew", appURL: URL(fileURLWithPath: "/Applications/MacSync.app"), currentVersion: "0.3.1")
        let release = SelfUpdater.Release(version: "0.4.0", zipURL: "https://github.com/x.zip", checksumURL: nil)
        XCTAssertNoThrow(try updater.install(release).get())
        XCTAssertTrue(runner.calls.contains(["/fake/brew", "upgrade", "--cask", "macsync"]))
    }

    func testUpdateWithWrongChecksumIsRefused() {
        let runner = FakeRunner()
        runner.web["https://github.com/z.zip"] = Data("zip".utf8)
        runner.web["https://github.com/z.zip.sha256"] = Data((String(repeating: "0", count: 64) + "  MacSync-0.4.0.zip").utf8)
        let updater = SelfUpdater(runner: runner, brewPath: nil, appURL: URL(fileURLWithPath: "/nonexistent/MacSync.app"), currentVersion: "0.3.1")
        let result = updater.install(.init(version: "0.4.0", zipURL: "https://github.com/z.zip", checksumURL: "https://github.com/z.zip.sha256"))
        guard case .failure = result else { return XCTFail("should refuse") }
    }
}
