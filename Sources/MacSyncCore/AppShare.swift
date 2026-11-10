import Foundation

/// An app that came from neither Homebrew nor the App Store (a direct download such as ArtCraft).
/// The only way another Mac can get it is a copy of the app itself.
public struct DirectApp: Codable, Equatable, Hashable {
    public var bundleID: String
    /// The app's file name in Applications, without ".app".
    public var name: String
    public var version: String?
    public init(bundleID: String, name: String, version: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.version = version
    }

    static func isSafeBundleID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]{0,154}$", options: .regularExpression) != nil && !id.contains("..")
    }

    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 120 && !name.contains("/") && !name.hasPrefix(".")
            && name.rangeOfCharacter(from: .controlCharacters) == nil
    }
}

/// Copies direct-download apps between Macs through iCloud Drive, only when a Mac asks:
///
///     apps/requests/<bundle ID>/<machine ID>.json   "this Mac wants it"
///     apps/packages/<bundle ID>.zip (+ .json)       the app, zipped by a Mac that has it
///
/// The Mac that wants an app writes a request. On its next sync, a Mac that has the app zips
/// it once. The Mac that asked unzips it into Applications and withdraws its request; when
/// no requests are left, the Mac that uploaded the package deletes it, so iCloud space is only
/// used while a copy is in flight. Nothing already in Applications is ever replaced.
struct AppShare {
    struct Request: Codable { var machineName: String; var requestedAt: Date }
    struct Package: Codable, Equatable {
        var bundleID: String
        var name: String
        var version: String?
        var fromMachineID: String
        var fromMachine: String
        var uploadedAt: Date
        var bytes: Int64?
    }

    let env: MacSyncEnvironment
    let runner: CommandRunning
    let now: () -> Date
    var fm: FileManager { .default }

    var root: URL { env.syncDirectory.appendingPathComponent("apps", isDirectory: true) }
    var requests: URL { root.appendingPathComponent("requests", isDirectory: true) }
    var packages: URL { root.appendingPathComponent("packages", isDirectory: true) }

    private func zipURL(_ id: String) -> URL { packages.appendingPathComponent(id + ".zip") }
    private func metaURL(_ id: String) -> URL { packages.appendingPathComponent(id + ".json") }
    private func requestURL(_ id: String) -> URL {
        requests.appendingPathComponent(id, isDirectory: true).appendingPathComponent(env.machineID + ".json")
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    // MARK: Asking for an app

    func request(_ bundleID: String) throws {
        guard DirectApp.isSafeBundleID(bundleID) else { return }
        let url = requestURL(bundleID)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(Request(machineName: env.machineName, requestedAt: now())).write(to: url, options: .atomic)
    }

    func withdraw(_ bundleID: String) {
        try? fm.removeItem(at: requestURL(bundleID))
        let folder = requests.appendingPathComponent(bundleID, isDirectory: true)
        if ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter({ !$0.hasPrefix(".") }).isEmpty {
            try? fm.removeItem(at: folder)
        }
    }

    enum Availability: Equatable {
        case ready(Package)
        case downloading(Package)
        case notYet
    }

    func availability(_ bundleID: String) -> Availability {
        guard DirectApp.isSafeBundleID(bundleID),
              let data = try? Data(contentsOf: metaURL(bundleID)),
              let package = try? Self.decoder.decode(Package.self, from: data), package.bundleID == bundleID else { return .notYet }
        let zip = zipURL(bundleID)
        guard fm.fileExists(atPath: zip.path) else { return .notYet }
        if Self.isDownloaded(zip) { return .ready(package) }
        try? fm.startDownloadingUbiquitousItem(at: zip)
        return .downloading(package)
    }

    static func isDownloaded(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey])
        guard values?.isUbiquitousItem == true else { return true }
        return values?.ubiquitousItemDownloadingStatus == .current
    }

    /// Unzips the package into Applications. Returns the app's path, or a reason it didn't work.
    func install(_ package: Package) -> Result<String, EngineError> {
        guard DirectApp.isSafeName(package.name) else { return .failure(.refused("That app's name isn't valid.")) }
        let target = env.applicationsDirectory.appendingPathComponent(package.name + ".app")
        if fm.fileExists(atPath: target.path) {
            withdraw(package.bundleID)
            return .success(target.path)
        }
        // Unzip next to Applications first, then check it is the app that was asked for.
        let staging = env.applicationsDirectory.appendingPathComponent(".macsync-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do { try fm.createDirectory(at: staging, withIntermediateDirectories: true) } catch {
            return .failure(.refused("MacSync can't write to Applications on this Mac."))
        }
        let unzip = runner.run("/usr/bin/ditto", ["-x", "-k", zipURL(package.bundleID).path, staging.path], input: nil, environment: [:])
        let unpacked = staging.appendingPathComponent(package.name + ".app")
        guard unzip.status == 0, fm.fileExists(atPath: unpacked.path) else {
            return .failure(.refused("The copy of \(package.name) couldn't be unpacked."))
        }
        guard Bundle(path: unpacked.path)?.bundleIdentifier == package.bundleID else {
            return .failure(.refused("The copy of \(package.name) isn't the app that was asked for, so it wasn't installed."))
        }
        do { try fm.moveItem(at: unpacked, to: target) } catch {
            return .failure(.refused("\(package.name) couldn't be moved into Applications."))
        }
        withdraw(package.bundleID)
        return .success(target.path)
    }

    // MARK: Answering other Macs

    /// Zips apps other Macs asked for, and clears packages nobody needs any more.
    /// Returns the names of apps it uploaded.
    @discardableResult
    func serve(local: [DirectApp]) -> [String] {
        let mine = Dictionary(local.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        var uploaded: [String] = []
        let asked = ((try? fm.contentsOfDirectory(atPath: requests.path)) ?? []).filter(DirectApp.isSafeBundleID)
        for id in asked {
            let askers = ((try? fm.contentsOfDirectory(atPath: requests.appendingPathComponent(id).path)) ?? [])
                .filter { $0.hasSuffix(".json") && $0 != env.machineID + ".json" }
            guard !askers.isEmpty, let app = mine[id], availability(id) == .notYet else { continue }
            if upload(app) { uploaded.append(app.name) }
        }
        // Packages this Mac uploaded that nobody is waiting for any more.
        let zips = ((try? fm.contentsOfDirectory(atPath: packages.path)) ?? []).filter { $0.hasSuffix(".json") }
        for name in zips {
            let id = String(name.dropLast(5))
            guard let data = try? Data(contentsOf: metaURL(id)),
                  let package = try? Self.decoder.decode(Package.self, from: data),
                  package.fromMachineID == env.machineID else { continue }
            let waiting = ((try? fm.contentsOfDirectory(atPath: requests.appendingPathComponent(id).path)) ?? [])
                .filter { $0.hasSuffix(".json") }
            if waiting.isEmpty {
                try? fm.removeItem(at: zipURL(id))
                try? fm.removeItem(at: metaURL(id))
            }
        }
        return uploaded
    }

    private func upload(_ app: DirectApp) -> Bool {
        let source = env.applicationsDirectory.appendingPathComponent(app.name + ".app")
        guard DirectApp.isSafeName(app.name), fm.fileExists(atPath: source.path) else { return false }
        do { try fm.createDirectory(at: packages, withIntermediateDirectories: true) } catch { return false }
        // Zip under a temporary name so another Mac never sees half a file as the package.
        let temp = packages.appendingPathComponent(".\(app.bundleID)-\(UUID().uuidString.prefix(8)).zip")
        let zip = runner.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, temp.path], input: nil, environment: [:])
        guard zip.status == 0, fm.fileExists(atPath: temp.path) else { try? fm.removeItem(at: temp); return false }
        try? fm.removeItem(at: zipURL(app.bundleID))
        do { try fm.moveItem(at: temp, to: zipURL(app.bundleID)) } catch { try? fm.removeItem(at: temp); return false }
        let bytes = (try? fm.attributesOfItem(atPath: zipURL(app.bundleID).path)[.size] as? NSNumber)?.int64Value
        let package = Package(bundleID: app.bundleID, name: app.name, version: app.version, fromMachineID: env.machineID,
                              fromMachine: env.machineName, uploadedAt: now(), bytes: bytes)
        return (try? Self.encoder.encode(package).write(to: metaURL(app.bundleID), options: .atomic)) != nil
    }
}
