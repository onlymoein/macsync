import Foundation

/// Counts how many Macs have MacSync, without knowing whose. Each Mac makes a random number once
/// and sends it, with MacSync's version and macOS's major version, at most once a day. Nothing
/// about the person, the Mac, its apps or its settings. The number is never put in iCloud, comes
/// from no hardware ID, and is deleted when counting is turned off.
public struct InstallCount {
    public static let url = URL(string: "https://macsync.hindra.studio/api/count")!
    public static let interval: TimeInterval = 24 * 3600

    struct Saved: Codable, Equatable {
        var id: String
        /// A hash that tells a copied folder (Migration Assistant) from this Mac. Never sent.
        var mac: String
        var sentAt: Date?
    }
    struct Message: Codable, Equatable { var id, version, macOS: String }

    let env: MacSyncEnvironment
    public init(env: MacSyncEnvironment) { self.env = env }
    var file: URL { env.dataDirectory.appendingPathComponent("install-count.json") }

    func saved() -> Saved? {
        guard let data = try? Data(contentsOf: file), let saved = try? JSONDecoder.iso.decode(Saved.self, from: data),
              saved.mac == Hashing.sha256(Data(("count" + env.machineID).utf8)) else { return nil }
        return saved
    }

    private func save(_ saved: Saved) {
        try? FileManager.default.createDirectory(at: env.dataDirectory, withIntermediateDirectories: true)
        try? JSONEncoder.iso.encode(saved).write(to: file, options: .atomic)
    }

    /// Turned off: this Mac's number is thrown away.
    public func forget() { try? FileManager.default.removeItem(at: file) }

    /// What's due to be sent now, or nil. Demos and tests with a pretend Dock are never counted.
    func due(now: Date) -> Message? {
        guard env.dockFile == nil else { return nil }
        let mine: Saved
        if let kept = saved() { mine = kept } else {
            mine = Saved(id: UUID().uuidString.lowercased(), mac: Hashing.sha256(Data(("count" + env.machineID).utf8)), sentAt: nil)
            save(mine)
        }
        if let sent = mine.sentAt, now.timeIntervalSince(sent) < Self.interval, sent <= now { return nil }
        return Message(id: mine.id, version: MacSyncEnvironment.appVersion,
                       macOS: String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion))
    }

    func markSent(now: Date) {
        guard var mine = saved() else { return }
        mine.sentAt = now
        save(mine)
    }

    /// Sends it if it's due. No cookies, nothing cached; a failure just tries again next time.
    public func sendIfDue(now: Date = Date()) async {
        guard let message = due(now: now), let body = try? JSONEncoder().encode(message) else { return }
        var request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MacSync", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 204 else { return }
        markSent(now: now)
    }
}
