import CryptoKit
import XCTest
@testable import MacSyncCore

final class CloudRulesTests: XCTestCase {
    // A key made for these tests only, not the one MacSync trusts.
    let key = Curve25519.Signing.PrivateKey()
    var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }
    let url = "https://example.test/rules.json"

    func signed(_ json: String, with signer: Curve25519.Signing.PrivateKey? = nil) -> (Data, Data) {
        let data = Data(json.utf8)
        let sig = try! (signer ?? key).signature(for: data).base64EncodedString()
        return (data, Data((sig + "\n").utf8))
    }

    func store(_ runner: FakeRunner, folder: URL) -> CloudRulesStore {
        CloudRulesStore(folder: folder, runner: runner, url: url, publicKey: publicKey)
    }

    func tempFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rules-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testOnlyASignedFileIsBelieved() {
        let (data, sig) = signed(#"{"version": 3, "off": ["autoUpgrade"]}"#)
        XCTAssertEqual(CloudRulesStore.verified(data, signature: sig, publicKey: publicKey)?.version, 3)
        // One changed byte, or a file signed with another key, is ignored.
        var tampered = data
        tampered[tampered.count - 3] = UInt8(ascii: "X")
        XCTAssertNil(CloudRulesStore.verified(tampered, signature: sig, publicKey: publicKey))
        let (other, otherSig) = signed(#"{"version": 3}"#, with: Curve25519.Signing.PrivateKey())
        XCTAssertNil(CloudRulesStore.verified(other, signature: otherSig, publicKey: publicKey))
        XCTAssertNil(CloudRulesStore.verified(data, signature: Data("not base64".utf8), publicKey: publicKey))
    }

    func testRefreshKeepsNewerFilesAndRefusesOlderOrForgedOnes() {
        let runner = FakeRunner()
        let folder = tempFolder()
        let rules = store(runner, folder: folder)
        XCTAssertEqual(rules.current(), .none)

        (runner.web[url], runner.web[url + ".sig"]) = signed(#"{"version": 2, "off": ["autoApplyDock"]}"#)
        XCTAssertEqual(rules.refresh(force: true), "updated to 2")
        XCTAssertTrue(rules.current().isOff(.autoApplyDock))

        // An older file served again can't undo a fix.
        (runner.web[url], runner.web[url + ".sig"]) = signed(#"{"version": 1}"#)
        XCTAssertEqual(rules.refresh(force: true), "older than the rules here: ignored")
        XCTAssertEqual(rules.current().version, 2)

        // A forged file is ignored and the good one stays.
        (runner.web[url], runner.web[url + ".sig"]) = signed(#"{"version": 9}"#, with: Curve25519.Signing.PrivateKey())
        XCTAssertEqual(rules.refresh(force: true), "signature didn't check out: ignored")
        XCTAssertEqual(rules.current().version, 2)

        // A file changed on disk afterwards no longer counts.
        try? Data(#"{"version": 50}"#.utf8).write(to: folder.appendingPathComponent("rules.json"))
        XCTAssertEqual(rules.current(), .none)
    }

    func testRefreshWaitsBetweenChecks() {
        let runner = FakeRunner()
        let rules = store(runner, folder: tempFolder())
        (runner.web[url], runner.web[url + ".sig"]) = signed(#"{"version": 1}"#)
        XCTAssertEqual(rules.refresh(), "updated to 1")
        XCTAssertEqual(rules.refresh(), "checked recently")
        XCTAssertEqual(runner.calls.filter { $0.first == "/usr/bin/curl" }.count, 2)
    }

    func testNoticesFollowTheVersion() {
        let rules = CloudRules(version: 1, notices: [
            .init(id: "a", text: "Everyone"),
            .init(id: "b", text: "Before 0.8.21", below: "0.8.21"),
            .init(id: "c", text: "From 0.9", from: "0.9.0"),
        ])
        XCTAssertEqual(rules.notices(forVersion: "0.8.20"), ["Everyone", "Before 0.8.21"])
        XCTAssertEqual(rules.notices(forVersion: "0.9.1"), ["Everyone", "From 0.9"])
    }

    func testRulesDecideWhichAppsAreTheSame() {
        let rules = CloudRules(version: 1, sameApps: [.init(cask: "anydesk", bundleIDs: ["com.philandro.anydesk"])],
                               caskRenames: ["old-name": "new-name"], neverOffer: ["cask:noisy"])
        var other = TestWorld.snapshot(id: "o", apps: [], changedAt: Date())
        other.inventory = Inventory(brewAvailable: true, casks: ["anydesk", "old-name", "noisy", "ghostty"])
        let here = Inventory(brewAvailable: true, casks: ["new-name"],
                             directApps: [DirectApp(bundleID: "com.philandro.anydesk", name: "AnyDesk")])
        XCTAssertEqual(Planner.missingApps(local: here, others: [other], rules: rules).map(\.app.token), ["cask:ghostty"])
        // Without rules, all of them look missing.
        XCTAssertEqual(Planner.missingApps(local: here, others: [other]).count, 4)
    }

    /// The file on the website is signed with the key MacSync trusts.
    func testThePublishedFileChecksOut() throws {
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs")
        let data = try Data(contentsOf: docs.appendingPathComponent("rules.json"))
        let sig = try Data(contentsOf: docs.appendingPathComponent("rules.json.sig"))
        let rules = try XCTUnwrap(CloudRulesStore.verified(data, signature: sig, publicKey: CloudRulesStore.publicKey))
        XCTAssertEqual(rules.cask(forBundleID: "io.tailscale.ipn.macsys"), "tailscale-app")
    }
}
