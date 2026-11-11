@testable import MacSyncCore
import XCTest

final class SelfUpdateTests: XCTestCase {
    func page(_ tag: String) -> Data { Data("https://github.com/onlymoein/macsync/releases/tag/\(tag)".utf8) }

    func testFindsANewerRelease() throws {
        let runner = FakeRunner()
        runner.web[SelfUpdater.releasesPage] = page("v0.4.0")
        let updater = SelfUpdater(runner: runner, brewPath: nil, appURL: URL(fileURLWithPath: "/Applications/MacSync.app"), currentVersion: "0.3.1")
        let found = try XCTUnwrap(updater.check())
        XCTAssertEqual(found.version, "0.4.0")
        XCTAssertEqual(found.zipURL, "https://github.com/onlymoein/macsync/releases/download/v0.4.0/MacSync-0.4.0.zip")
        XCTAssertEqual(found.checksumURL, found.zipURL + ".sha256")
    }

    func testIgnoresOlderAndOddReleases() {
        let runner = FakeRunner()
        let app = URL(fileURLWithPath: "/Applications/MacSync.app")
        runner.web[SelfUpdater.releasesPage] = page("v0.3.0")
        XCTAssertNil(SelfUpdater(runner: runner, brewPath: nil, appURL: app, currentVersion: "0.3.1").check())
        runner.web[SelfUpdater.releasesPage] = page("v1.0-beta; rm -rf")
        XCTAssertNil(SelfUpdater(runner: runner, brewPath: nil, appURL: app, currentVersion: "0.3.1").check())
        runner.web[SelfUpdater.releasesPage] = Data("https://github.com/onlymoein/macsync/releases".utf8)
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

final class FeedTests: XCTestCase {
    func testTheFeedWinsWhenTheLatestLinkIsStale() {
        let runner = FakeRunner()
        runner.web[SelfUpdater.releasesPage] = Data("https://github.com/onlymoein/macsync/releases/tag/v0.8.0".utf8)
        runner.web[SelfUpdater.releasesFeed] = Data("<feed><entry><link href=\"https://github.com/onlymoein/macsync/releases/tag/v0.8.1\"/></entry><entry><link href=\"https://github.com/onlymoein/macsync/releases/tag/v0.8.0\"/></entry></feed>".utf8)
        let updater = SelfUpdater(runner: runner, brewPath: nil, appURL: URL(fileURLWithPath: "/tmp/x.app"), currentVersion: "0.8.0")
        XCTAssertEqual(updater.check()?.version, "0.8.1")
    }
}
