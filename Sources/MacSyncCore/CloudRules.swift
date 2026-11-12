import CryptoKit
import Foundation

/// Fixes that reach every Mac without a new version: which apps are the same, Homebrew renames,
/// apps never to offer, a note in the menu, and switches that turn an automatic action off.
///
/// Only data, never code. The file is signed with a key that stays on the developer's Mac; MacSync
/// checks the signature against the public key below and ignores anything else, so whoever could
/// change the website still couldn't change what MacSync does. See docs/RELEASING.md.
public struct CloudRules: Codable, Equatable {
    /// Goes up with each file published. A file with a lower number than the one kept here is
    /// refused, so an old file can't be served again to undo a fix.
    public var version: Int
    public var issued: Date?
    /// The same app under a Homebrew cask and the bundle IDs it can have (downloaded by hand, say).
    public var sameApps: [SameApp]?
    /// Homebrew casks that changed name: old name to new one.
    public var caskRenames: [String: String]?
    /// Apps never offered from other Macs, by token ("cask:name", "app:bundle.id", "mas:123").
    public var neverOffer: [String]?
    /// Notes shown in the menu.
    public var notices: [Notice]?
    /// Switches turned off for everyone (see `CloudSwitch`).
    public var off: [String]?

    public struct SameApp: Codable, Equatable {
        public var cask: String
        public var bundleIDs: [String]
        public init(cask: String, bundleIDs: [String]) { self.cask = cask; self.bundleIDs = bundleIDs }
    }

    public struct Notice: Codable, Equatable {
        public var id: String
        public var text: String
        /// Shown from this version (included) and below that one (not included). Either may be left out.
        public var from: String?
        public var below: String?
        public init(id: String, text: String, from: String? = nil, below: String? = nil) {
            self.id = id; self.text = text; self.from = from; self.below = below
        }
    }

    public init(version: Int, issued: Date? = nil, sameApps: [SameApp]? = nil, caskRenames: [String: String]? = nil,
                neverOffer: [String]? = nil, notices: [Notice]? = nil, off: [String]? = nil) {
        self.version = version; self.issued = issued; self.sameApps = sameApps; self.caskRenames = caskRenames
        self.neverOffer = neverOffer; self.notices = notices; self.off = off
    }

    public static let none = CloudRules(version: 0)

    public func isOff(_ name: CloudSwitch) -> Bool { (off ?? []).contains(name.rawValue) }

    /// The cask's current name.
    public func cask(_ name: String) -> String { caskRenames?[name] ?? name }

    /// The cask a bundle ID belongs to, from `sameApps`.
    public func cask(forBundleID bundleID: String) -> String? {
        sameApps?.first { $0.bundleIDs.contains(bundleID) }.map { cask($0.cask) }
    }

    public func bundleIDs(forCask name: String) -> [String] {
        let name = cask(name)
        return sameApps?.first { cask($0.cask) == name }?.bundleIDs ?? []
    }

    /// The notes for this version of MacSync, at most three and each shortened, so a mistake in the
    /// file can't fill the menu.
    public func notices(forVersion version: String) -> [String] {
        (notices ?? []).filter { n in
            (n.from.map { !SelfUpdater.isNewer($0, than: version) } ?? true)
                && (n.below.map { SelfUpdater.isNewer($0, than: version) } ?? true)
        }
        .prefix(3).map { String($0.text.prefix(200)) }
    }
}

/// Automatic actions the rules file can turn off on every Mac while a fix is on its way. Turning
/// one off never does anything by itself: it only stops MacSync starting it on its own.
public enum CloudSwitch: String, CaseIterable {
    /// Applying the Dock by itself when the lid opens.
    case autoApplyDock
    /// Updating Homebrew apps and tools by itself.
    case autoUpgrade
}

/// Downloads, checks and keeps the rules file.
public struct CloudRulesStore {
    public static let url = "https://onlymoein.github.io/macsync/rules.json"
    /// The public half of the key the rules file is signed with.
    public static let publicKey = "emqJDnYxcACvg4Lt0lQ8K8wcgmkLkWCK8SxHYEOqvzY="
    static let maxSize = 256 * 1024

    let folder: URL
    let runner: CommandRunning
    let url: String
    let publicKey: String
    let now: () -> Date

    public init(folder: URL, runner: CommandRunning, url: String = CloudRulesStore.url,
                publicKey: String = CloudRulesStore.publicKey, now: @escaping () -> Date = Date.init) {
        self.folder = folder; self.runner = runner; self.url = url; self.publicKey = publicKey; self.now = now
    }

    var rulesFile: URL { folder.appendingPathComponent("rules.json") }
    var signatureFile: URL { folder.appendingPathComponent("rules.json.sig") }
    var checkedFile: URL { folder.appendingPathComponent("rules.checked") }

    /// The rules kept here, checked again each time they're read. Nothing, if there are none or they don't check out.
    public func current() -> CloudRules {
        guard let data = try? Data(contentsOf: rulesFile), let signature = try? Data(contentsOf: signatureFile) else { return .none }
        return Self.verified(data, signature: signature, publicKey: publicKey) ?? .none
    }

    /// The rules in `data`, if `signature` (base64 text) is a valid signature of exactly those bytes.
    public static func verified(_ data: Data, signature: Data, publicKey: String) -> CloudRules? {
        guard data.count <= maxSize,
              let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let sig = Data(base64Encoded: String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
              key.isValidSignature(sig, for: data) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CloudRules.self, from: data)
    }

    /// Fetches the file at most once every few hours. Keeps it only if it's signed and not older
    /// than the one already here. Says what happened, for the log.
    @discardableResult
    public func refresh(force: Bool = false) -> String {
        let fm = FileManager.default
        if !force, let at = (try? fm.attributesOfItem(atPath: checkedFile.path)[.modificationDate]) as? Date,
           now().timeIntervalSince(at) < 6 * 3600 { return "checked recently" }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        fm.createFile(atPath: checkedFile.path, contents: Data())
        func get(_ address: String) -> Data? {
            let r = runner.run("/usr/bin/curl", ["-fsSL", "--proto", "=https", "--proto-redir", "=https", "--max-time", "20",
                                                 "--max-filesize", "\(Self.maxSize)", address], input: nil, environment: [:])
            return r.status == 0 && !r.stdout.isEmpty ? r.stdout : nil
        }
        guard let data = get(url), let signature = get(url + ".sig") else { return "couldn't download" }
        guard let rules = Self.verified(data, signature: signature, publicKey: publicKey) else { return "signature didn't check out: ignored" }
        let kept = current()
        guard rules.version >= kept.version else { return "older than the rules here: ignored" }
        guard rules.version > kept.version || rules != kept else { return "unchanged" }
        do {
            try data.write(to: rulesFile, options: .atomic)
            try signature.write(to: signatureFile, options: .atomic)
        } catch { return "couldn't save" }
        return "updated to \(rules.version)"
    }
}
