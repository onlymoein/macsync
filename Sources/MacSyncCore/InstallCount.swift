import Foundation

/// Counts how many people have MacSync installed, without knowing who. Macs that sync with each
/// other count as one: they share a random number kept in their iCloud Drive folder. It's sent
/// with MacSync's version and macOS's major version, at most once a day per Mac. Nothing about
/// the person, the Macs, their apps or settings, and no hardware ID. Settings turns it off.
public struct InstallCount {
    public static let url = URL(string: "https://macsync.hindra.studio/api/count")!
    public static let interval: TimeInterval = 24 * 3600
    /// Time for iCloud to bring another Mac's number before this Mac's own is first sent.
    static let settle: TimeInterval = 15 * 60
    /// Without iCloud Drive there's nobody to share with yet: wait longer, then count alone.
    static let alone: TimeInterval = 24 * 3600

    struct Saved: Codable, Equatable {
        /// This Mac's own number, used until the shared one is known.
        var own: String
        /// A hash that tells a copied folder (Migration Assistant) from this Mac. Never sent.
        var mac: String
        var since: Date
        /// What was last sent, so a changed number replaces it rather than adding one.
        var sent: String?
        var sentAt: Date?
    }
    struct Shared: Codable { var id: String }
    struct Message: Codable, Equatable { var id, version, macOS: String; var replaces: String? }

    let env: MacSyncEnvironment
    public init(env: MacSyncEnvironment) { self.env = env }
    var file: URL { env.dataDirectory.appendingPathComponent("install-count.json") }
    var sharedFile: URL { env.syncDirectory.appendingPathComponent("install-id.json") }
    private var macHash: String { Hashing.sha256(Data(("count" + env.machineID).utf8)) }

    func saved() -> Saved? {
        guard let data = try? Data(contentsOf: file), let saved = try? JSONDecoder.iso.decode(Saved.self, from: data),
              saved.mac == macHash else { return nil }
        return saved
    }

    private func save(_ saved: Saved) {
        try? FileManager.default.createDirectory(at: env.dataDirectory, withIntermediateDirectories: true)
        try? JSONEncoder.iso.encode(saved).write(to: file, options: .atomic)
    }

    /// Turned off: this Mac's record is thrown away. The other Macs keep theirs.
    public func forget() { try? FileManager.default.removeItem(at: file) }

    private enum SharedState { case id(String), none, notHereYet }
    private func shared() -> SharedState {
        let fm = FileManager.default
        if fm.fileExists(atPath: sharedFile.path) {
            guard let data = try? Data(contentsOf: sharedFile), let shared = try? JSONDecoder().decode(Shared.self, from: data),
                  let id = UUID(uuidString: shared.id) else { return .notHereYet }
            return .id(id.uuidString.lowercased())
        }
        let placeholder = env.syncDirectory.appendingPathComponent(".install-id.json.icloud")
        if fm.fileExists(atPath: placeholder.path) {
            try? fm.startDownloadingUbiquitousItem(at: sharedFile)
            return .notHereYet
        }
        return .none
    }

    /// What's due to be sent now, or nil. Demos and tests with a pretend Dock are never counted.
    func due(now: Date) -> Message? {
        guard env.dockFile == nil else { return nil }
        let mine: Saved
        if let kept = saved() { mine = kept } else {
            mine = Saved(own: UUID().uuidString.lowercased(), mac: macHash, since: now)
            save(mine)
        }
        let age = now.timeIntervalSince(mine.since)
        // A clock set back must not stop the count for good.
        if let sent = mine.sentAt, sent <= now, now.timeIntervalSince(sent) < Self.interval { return nil }
        let id: String
        switch shared() {
        case .notHereYet: return nil
        case .id(let theirs): id = theirs
        case .none:
            if env.iCloudAvailable {
                // After iCloud has had time to bring another Mac's. If two Macs do this at once,
                // iCloud keeps one file and the other Mac's number is replaced by it.
                guard age < 0 || age >= Self.settle else { return nil }
                try? FileManager.default.createDirectory(at: env.syncDirectory, withIntermediateDirectories: true)
                try? JSONEncoder().encode(Shared(id: mine.own)).write(to: sharedFile, options: .withoutOverwriting)
            } else {
                guard age < 0 || age >= Self.alone else { return nil }
            }
            id = mine.own
        }
        return Message(id: id, version: MacSyncEnvironment.appVersion,
                       macOS: String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
                       replaces: mine.sent == id ? nil : mine.sent)
    }

    func markSent(_ message: Message, now: Date) {
        guard var mine = saved() else { return }
        mine.sent = message.id
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
        markSent(message, now: now)
    }
}
