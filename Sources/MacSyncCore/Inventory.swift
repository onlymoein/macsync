import AppKit
import Foundation

/// What can be installed. Snapshots are input from another machine, so names are checked
/// before they reach a command line.
public struct AppRef: Hashable, Codable, Identifiable, Comparable {
    public enum Source: String, Codable { case cask, formula, appStore, direct }
    public var source: Source
    public var name: String
    public var appStoreID: String?

    public init(source: Source, name: String, appStoreID: String? = nil) {
        self.source = source
        self.name = name
        self.appStoreID = appStoreID
    }

    /// Stable text form, also the CLI's syntax: cask:ghostty, formula:jq, mas:497799835.
    public var token: String {
        switch source {
        case .cask: return "cask:\(name)"
        case .formula: return "formula:\(name)"
        case .appStore: return "mas:\(appStoreID ?? name)"
        case .direct: return "app:\(name)"
        }
    }

    public var id: String { token }
    public static func < (a: AppRef, b: AppRef) -> Bool { a.token < b.token }

    /// A token from another Mac, before it is trusted: cask:x, formula:x, mas:123, app:bundle.id.
    static func isSafeToken(_ token: String) -> Bool {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        switch parts[0] {
        case "cask": return AppRef(source: .cask, name: parts[1]).isSafe
        case "formula": return AppRef(source: .formula, name: parts[1]).isSafe
        case "mas": return AppRef(source: .appStore, name: "", appStoreID: parts[1]).isSafe
        case "app": return AppRef(source: .direct, name: parts[1]).isSafe
        default: return false
        }
    }

    public var isSafe: Bool {
        switch source {
        case .cask, .formula:
            return name.range(of: "^[A-Za-z0-9][A-Za-z0-9@+_./-]*$", options: .regularExpression) != nil
        case .appStore:
            return appStoreID?.range(of: "^[0-9]+$", options: .regularExpression) != nil
        case .direct:
            return DirectApp.isSafeBundleID(name)
        }
    }
}

public struct InventoryReader {
    let runner: CommandRunning
    let env: MacSyncEnvironment

    public init(runner: CommandRunning, env: MacSyncEnvironment) {
        self.runner = runner
        self.env = env
    }

    static func brewEnvironment(_ brew: String) -> [String: String] {
        let prefix = (brew as NSString).deletingLastPathComponent
        return ["PATH": "\(prefix):/usr/bin:/bin:/usr/sbin:/sbin",
                "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1", "NONINTERACTIVE": "1"]
    }

    public func read() -> Inventory {
        var inventory = Inventory(appStore: appStoreApps())
        var details: [String: AppDetail] = [:]
        for app in inventory.appStore {
            let ref = AppRef(source: .appStore, name: app.name, appStoreID: app.id)
            let path = env.applicationsDirectory.appendingPathComponent(app.name + ".app").path
            details[ref.token] = AppDetail(displayName: app.name, iconID: icons.store(appAt: path, for: ref),
                                           bundleID: Self.bundleID(at: path))
        }
        inventory.details = details
        var caskApps: Set<String> = []
        if let brew = env.brewPath {
            let brewEnv = Self.brewEnvironment(brew)
            let casks = runner.run(brew, ["list", "--cask", "-1"], input: nil, environment: brewEnv)
            // Only what the person asked for, not what those formulae pulled in.
            let leaves = runner.run(brew, ["leaves", "--installed-on-request"], input: nil, environment: brewEnv)
            if casks.status == 0, leaves.status == 0 {
                inventory.brewAvailable = true
                inventory.casks = Self.lines(casks.output)
                inventory.formulae = Self.lines(leaves.output)
                let all = runner.run(brew, ["list", "--formula", "-1"], input: nil, environment: brewEnv)
                if all.status == 0 { inventory.allFormulae = Self.lines(all.output) }
                let info = runner.run(brew, ["info", "--json=v2", "--installed"], input: nil, environment: brewEnv)
                if info.status == 0 { caskApps = addBrewDetails(info.output, to: &inventory) }
            }
        }
        let direct = directApps(excluding: caskApps.union(inventory.appStore.map { $0.name + ".app" }))
        for app in direct {
            let ref = AppRef(source: .direct, name: app.bundleID)
            let path = env.applicationsDirectory.appendingPathComponent(app.name + ".app").path
            inventory.details?[ref.token] = AppDetail(displayName: Self.displayName(at: path) ?? app.name,
                                                      iconID: icons.store(appAt: path, for: ref), bundleID: app.bundleID)
        }
        inventory.directApps = withDownloads(direct)
        if inventory.details?.isEmpty == true { inventory.details = nil }
        return inventory
    }

    /// Names, descriptions and icons for what this Mac has, so other Macs can show them
    /// for apps they don't have yet. Icons go to the shared `icons` folder, once each.
    /// Returns the app bundles Homebrew put in Applications.
    @discardableResult
    func addBrewDetails(_ json: String, to inventory: inout Inventory) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var details = inventory.details ?? [:]
        var bundles: Set<String> = []
        let wantedCasks = Set(inventory.casks), wantedFormulae = Set(inventory.formulae)
        for cask in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = cask["token"] as? String else { continue }
            let artifacts = cask["artifacts"] as? [[String: Any]] ?? []
            let appNames = artifacts.compactMap { ($0["app"] as? [Any])?.first as? String }
            bundles.formUnion(appNames.map { ($0 as NSString).lastPathComponent })
            // Apps a .pkg cask installed (no app artifact) are Homebrew's too, not hand-installed.
            if wantedCasks.contains(token) {
                bundles.formUnion(artifacts.flatMap { CaskCatalog.uninstallHints($0).flatMap(\.1) })
            }
            guard wantedCasks.contains(token) else { continue }
            let ref = AppRef(source: .cask, name: token)
            let path = appNames.first.map { env.applicationsDirectory.appendingPathComponent($0).path }
            details[ref.token] = AppDetail(displayName: (cask["name"] as? [String])?.first,
                                           summary: cask["desc"] as? String,
                                           iconID: path.flatMap { icons.store(appAt: $0, for: ref) },
                                           bundleID: path.flatMap(Self.bundleID))
        }
        for formula in root["formulae"] as? [[String: Any]] ?? [] {
            guard let name = formula["name"] as? String, wantedFormulae.contains(name) else { continue }
            details[AppRef(source: .formula, name: name).token] = AppDetail(summary: formula["desc"] as? String)
        }
        inventory.details = details
        return bundles
    }

    /// Apps in Applications that came from neither Homebrew nor the App Store. Apple's own apps
    /// and MacSync itself are left out: every Mac has them, or they can't be copied.
    func directApps(excluding managed: Set<String>) -> [DirectApp] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: env.applicationsDirectory.path)) ?? []
        return names.filter { $0.hasSuffix(".app") && !managed.contains($0) }.sorted().compactMap { file in
            let path = env.applicationsDirectory.appendingPathComponent(file).path
            guard !fm.fileExists(atPath: path + "/Contents/_MASReceipt/receipt"),
                  let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any],
                  let id = info["CFBundleIdentifier"] as? String, DirectApp.isSafeBundleID(id),
                  !id.hasPrefix("com.apple."), id != "com.onlymehdi.macsync" else { return nil }
            let name = String(file.dropLast(4))
            guard DirectApp.isSafeName(name) else { return nil }
            let feed = (info["SUFeedURL"] as? String).flatMap { DirectApp.isSafeFeed($0) ? $0 : nil }
            return DirectApp(bundleID: id, name: name, version: info["CFBundleShortVersionString"] as? String, feed: feed)
        }
    }

    /// Notes which Homebrew cask publishes each app, so other Macs can download it from its source.
    func withDownloads(_ apps: [DirectApp]) -> [DirectApp] {
        guard !apps.isEmpty, let catalog = CaskCatalog.load(env: env, runner: runner, now: Date()) else { return apps }
        return apps.map { app in
            var app = app
            app.cask = catalog.cask(forApp: app.name + ".app") ?? catalog.cask(forBundleID: app.bundleID)
            return app
        }
    }

    static func bundleID(at path: String) -> String? {
        (NSDictionary(contentsOfFile: path + "/Contents/Info.plist")?["CFBundleIdentifier"] as? String)
            .flatMap { DirectApp.isSafeBundleID($0) ? $0 : nil }
    }

    static func displayName(at path: String) -> String? {
        let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
        return (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
    }

    var icons: IconStore { IconStore(directory: env.syncDirectory.appendingPathComponent("icons", isDirectory: true)) }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.sorted()
    }

    /// Apps from the Mac App Store carry a receipt, and Spotlight knows their store ID.
    /// This needs no extra tools, so it works on a Mac that has never seen a terminal.
    func appStoreApps() -> [AppStoreApp] {
        let fm = FileManager.default
        let apps = (try? fm.contentsOfDirectory(atPath: env.applicationsDirectory.path)) ?? []
        return apps.filter { $0.hasSuffix(".app") }.sorted().compactMap { name in
            let path = env.applicationsDirectory.appendingPathComponent(name).path
            guard fm.fileExists(atPath: path + "/Contents/_MASReceipt/receipt") else { return nil }
            let result = runner.run("/usr/bin/mdls", ["-raw", "-name", "kMDItemAppStoreAdamID", path],
                                    input: nil, environment: [:])
            let id = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.status == 0, id.range(of: "^[0-9]+$", options: .regularExpression) != nil else { return nil }
            return AppStoreApp(id: id, name: String(name.dropLast(4)))
        }
    }
}

/// App icons shared through iCloud as small PNGs, named by a hash of the app's token.
/// An icon is only a picture of a public app, so it is safe to sync.
public struct IconStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public static func id(for ref: AppRef) -> String { String(Hashing.sha256(Data(ref.token.utf8)).prefix(24)) }

    public func url(for id: String) -> URL? {
        guard id.range(of: "^[0-9a-f]{16,64}$", options: .regularExpression) != nil else { return nil }
        return directory.appendingPathComponent(id + ".png")
    }

    /// The icon of a Dock app, by bundle ID, so a Mac without the app can still show it.
    public static func id(bundleID: String) -> String { String(Hashing.sha256(Data("bundle:\(bundleID)".utf8)).prefix(24)) }

    /// Writes the icon if it isn't there yet and returns its ID, or nil when the app isn't found.
    func store(appAt path: String, for ref: AppRef) -> String? { store(appAt: path, id: Self.id(for: ref)) }

    func store(appAt path: String, id: String) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }
        guard let target = url(for: id) else { return nil }
        if fm.fileExists(atPath: target.path) { return id }
        guard let png = Self.png(NSWorkspace.shared.icon(forFile: path), side: 128) else { return nil }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return (try? png.write(to: target, options: .atomic)) != nil ? id : nil
    }

    static func png(_ image: NSImage, side: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
