import Foundation

/// A preference value in a form that survives JSON and compares sensibly across Macs.
public enum PrefValue: Codable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([PrefValue])
    case dict([String: PrefValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([PrefValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: PrefValue].self) { self = .dict(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported preference value") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .dict(let v): try c.encode(v)
        }
    }

    /// JSON can't tell 29 from 29.0, so numbers compare by value.
    public static func == (a: PrefValue, b: PrefValue) -> Bool {
        switch (a, b) {
        case (.bool(let x), .bool(let y)): return x == y
        case (.int(let x), .int(let y)): return x == y
        case (.double(let x), .double(let y)): return x == y
        case (.int(let x), .double(let y)), (.double(let y), .int(let x)): return Double(x) == y
        case (.string(let x), .string(let y)): return x == y
        case (.array(let x), .array(let y)): return x == y
        case (.dict(let x), .dict(let y)): return x == y
        default: return false
        }
    }

    public var display: String {
        switch self {
        case .bool(let v): return v ? "on" : "off"
        case .int(let v): return String(v)
        case .double(let v): return String(format: "%g", v)
        case .string(let v): return v
        case .array(let v): return "\(v.count) items"
        case .dict(let v): return "\(v.count) values"
        }
    }

    /// Foundation form for CFPreferences.
    func foundation(as type: SettingType?) -> Any {
        switch (self, type) {
        case (.int(let v), .float?): return Double(v)
        case (.double(let v), .int?): return Int(v)
        case (.bool(let v), _): return v
        case (.int(let v), _): return v
        case (.double(let v), _): return v
        case (.string(let v), _): return v
        case (.array(let v), _): return v.map { $0.foundation(as: nil) }
        case (.dict(let v), _): return v.mapValues { $0.foundation(as: nil) }
        }
    }
}

public enum SettingType: String, Codable { case bool, int, float, string }

public enum RestartTarget: String, Codable, Hashable { case dock, finder, systemUI }

public struct SettingDefinition: Hashable {
    public var domain: String
    public var key: String
    public var type: SettingType
    public var category: String
    public var label: String
    public var restart: RestartTarget?
    public var needsLogout = false
    /// Stored with the home folder as ~, and skipped if the folder doesn't exist on the target.
    public var isPath = false
    public var id: String { "\(domain)|\(key)" }
}

public enum SettingsCatalog {
    static let global = "NSGlobalDomain"
    static let trackpad = "com.apple.AppleMultitouchTrackpad"
    static let finder = "com.apple.finder"
    static let dock = "com.apple.dock"
    static let capture = "com.apple.screencapture"

    static func d(_ domain: String, _ key: String, _ type: SettingType, _ category: String, _ label: String,
                  restart: RestartTarget? = nil, logout: Bool = false, path: Bool = false) -> SettingDefinition {
        SettingDefinition(domain: domain, key: key, type: type, category: category, label: label,
                          restart: restart, needsLogout: logout, isPath: path)
    }

    /// Dock size and position belong to the free Dock layout, so they are not repeated here.
    public static let all: [SettingDefinition] = [
        d(trackpad, "Clicking", .bool, "Trackpad and mouse", "Tap to click", logout: true),
        d(trackpad, "TrackpadThreeFingerDrag", .bool, "Trackpad and mouse", "Three-finger drag", logout: true),
        d(trackpad, "TrackpadRightClick", .bool, "Trackpad and mouse", "Secondary click", logout: true),
        d("com.apple.driver.AppleBluetoothMultitouch.trackpad", "Clicking", .bool, "Trackpad and mouse", "Tap to click (Magic Trackpad)", logout: true),
        d(global, "com.apple.swipescrolldirection", .bool, "Trackpad and mouse", "Natural scrolling", logout: true),
        d(global, "com.apple.trackpad.scaling", .float, "Trackpad and mouse", "Trackpad tracking speed", logout: true),
        d(global, "com.apple.mouse.scaling", .float, "Trackpad and mouse", "Mouse tracking speed", logout: true),
        d(global, "KeyRepeat", .int, "Keyboard", "Key repeat rate", logout: true),
        d(global, "InitialKeyRepeat", .int, "Keyboard", "Delay until repeat", logout: true),
        d(global, "ApplePressAndHoldEnabled", .bool, "Keyboard", "Accent menu on key hold", logout: true),
        d(global, "NSAutomaticSpellingCorrectionEnabled", .bool, "Keyboard", "Correct spelling automatically"),
        d(global, "NSAutomaticCapitalizationEnabled", .bool, "Keyboard", "Capitalize words automatically"),
        d(global, "NSAutomaticPeriodSubstitutionEnabled", .bool, "Keyboard", "Add period with double space"),
        d(global, "AppleKeyboardUIMode", .int, "Keyboard", "Keyboard navigation", logout: true),
        d(finder, "AppleShowAllFiles", .bool, "Finder", "Show hidden files", restart: .finder),
        d(finder, "ShowPathbar", .bool, "Finder", "Show path bar", restart: .finder),
        d(finder, "ShowStatusBar", .bool, "Finder", "Show status bar", restart: .finder),
        d(finder, "FXPreferredViewStyle", .string, "Finder", "Default view", restart: .finder),
        d(finder, "FXDefaultSearchScope", .string, "Finder", "Search scope", restart: .finder),
        d(finder, "_FXSortFoldersFirst", .bool, "Finder", "Keep folders on top", restart: .finder),
        d(global, "AppleShowAllExtensions", .bool, "Finder", "Show all file extensions", restart: .finder),
        d(dock, "magnification", .bool, "Dock", "Magnification", restart: .dock),
        d(dock, "largesize", .int, "Dock", "Magnified size", restart: .dock),
        d(dock, "autohide", .bool, "Dock", "Hide the Dock automatically", restart: .dock),
        d(dock, "autohide-delay", .float, "Dock", "Hide delay", restart: .dock),
        d(dock, "show-recents", .bool, "Dock", "Show recent apps", restart: .dock),
        d(dock, "minimize-to-application", .bool, "Dock", "Minimize into the app icon", restart: .dock),
        d(dock, "mineffect", .string, "Dock", "Minimize effect", restart: .dock),
        d(global, "AppleInterfaceStyle", .string, "Appearance", "Dark mode", logout: true),
        d(global, "AppleInterfaceStyleSwitchesAutomatically", .bool, "Appearance", "Switch light and dark automatically", logout: true),
        d(global, "AppleShowScrollBars", .string, "Appearance", "Show scroll bars", logout: true),
        d(capture, "location", .string, "Screenshots", "Screenshot folder", path: true),
        d(capture, "type", .string, "Screenshots", "Screenshot format"),
        d(capture, "disable-shadow", .bool, "Screenshots", "No shadow on window shots"),
    ]

    public static func definition(for id: String) -> SettingDefinition? { all.first { $0.id == id } }
}

/// Reads and writes preferences. The real one uses CFPreferences, so types are exact.
public protocol PreferencesStoring: AnyObject {
    func value(domain: String, key: String) -> PrefValue?
    func allKeys(domain: String) -> [String]
    func set(domain: String, key: String, value: PrefValue, type: SettingType?)
    func remove(domain: String, key: String)
    func restart(_ target: RestartTarget)
}

public final class SystemPreferences: PreferencesStoring {
    let runner: CommandRunning
    public init(runner: CommandRunning = SystemCommandRunner()) { self.runner = runner }

    static func app(_ domain: String) -> CFString {
        (domain == "NSGlobalDomain" ? kCFPreferencesAnyApplication : domain as CFString)
    }

    public func value(domain: String, key: String) -> PrefValue? {
        let raw = CFPreferencesCopyValue(key as CFString, Self.app(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return raw.flatMap(Self.convert)
    }

    public func allKeys(domain: String) -> [String] {
        (CFPreferencesCopyKeyList(Self.app(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]) ?? []
    }

    public func set(domain: String, key: String, value: PrefValue, type: SettingType?) {
        CFPreferencesSetValue(key as CFString, value.foundation(as: type) as CFPropertyList, Self.app(domain),
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(Self.app(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    public func remove(domain: String, key: String) {
        CFPreferencesSetValue(key as CFString, nil, Self.app(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(Self.app(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    public func restart(_ target: RestartTarget) {
        switch target {
        case .dock: _ = runner.run("/usr/bin/killall", ["-KILL", "Dock"], input: nil, environment: [:])
        case .finder: _ = runner.run("/usr/bin/killall", ["Finder"], input: nil, environment: [:])
        case .systemUI: _ = runner.run("/usr/bin/killall", ["SystemUIServer"], input: nil, environment: [:])
        }
        usleep(1_200_000)
    }

    static func convert(_ raw: CFTypeRef) -> PrefValue? {
        switch CFGetTypeID(raw) {
        case CFBooleanGetTypeID(): return .bool(CFBooleanGetValue((raw as! CFBoolean)))
        case CFNumberGetTypeID():
            let number = raw as! NSNumber
            return CFNumberIsFloatType(number) ? .double(number.doubleValue) : .int(number.intValue)
        case CFStringGetTypeID(): return .string(raw as! String)
        case CFArrayGetTypeID():
            let items = (raw as! [CFTypeRef]).compactMap(convert)
            return items.count == (raw as! [CFTypeRef]).count ? .array(items) : nil
        case CFDictionaryGetTypeID():
            var out: [String: PrefValue] = [:]
            for (k, v) in raw as! [String: CFTypeRef] { if let value = convert(v) { out[k] = value } }
            return .dict(out)
        default: return nil
        }
    }
}

/// A fake preferences store for tests.
public final class InMemoryPreferences: PreferencesStoring {
    public var store: [String: [String: PrefValue]] = [:]
    public private(set) var restarts: [RestartTarget] = []
    public var ignoreWrites = false

    public init() {}

    public func value(domain: String, key: String) -> PrefValue? { store[domain]?[key] }
    public func allKeys(domain: String) -> [String] { Array(store[domain]?.keys ?? [:].keys) }

    public func set(domain: String, key: String, value: PrefValue, type: SettingType?) {
        guard !ignoreWrites else { return }
        store[domain, default: [:]][key] = value
    }

    public func remove(domain: String, key: String) {
        guard !ignoreWrites else { return }
        store[domain]?[key] = nil
    }

    public func restart(_ target: RestartTarget) { restarts.append(target) }
}

// MARK: Snapshot section

public struct PrefsSection: Codable, Equatable {
    public var changedAt: Date
    public var basedOn: String?
    /// Every setting this app knew about when it was saved. A setting that is covered but
    /// missing from `values` means "unset on that Mac", which is different from "not recorded".
    public var covered: [String]
    public var values: [String: PrefValue]
    /// Apps whose preferences are included, picked by the user.
    public var appDomains: [String]

    public init(changedAt: Date, basedOn: String? = nil, covered: [String], values: [String: PrefValue], appDomains: [String]) {
        self.changedAt = changedAt
        self.basedOn = basedOn
        self.covered = covered
        self.values = values
        self.appDomains = appDomains
    }

    public var contentHash: String {
        var copy = self
        copy.changedAt = Date(timeIntervalSince1970: 0)
        copy.basedOn = nil
        // Adding settings in a newer app version isn't an edit by the person.
        copy.covered = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return Hashing.sha256((try? encoder.encode(copy)) ?? Data())
    }
}

public enum PrefsCapture {
    static let secretKey = try! NSRegularExpression(
        pattern: "(token|secret|passw|passcode|credential|auth|api[-_ ]?key|licen[cs]e|serial|session|cookie|private|bearer|signature|\\bkey$|identifier$|uuid|machine)",
        options: [.caseInsensitive])
    static let looksLikeSecret = try! NSRegularExpression(pattern: "^[A-Za-z0-9+/_=.-]{32,}$")
    static let machineSpecificPrefixes = ["NSWindow", "NSSplitView", "NSTableView", "NSToolbar", "NSStatusItem", "NSNavPanel",
                                          "NSOSPLast", "NSNavLast", "SU", "NSLastOpen", "NSQuitAlwaysKeepsWindows", "WebKit"]

    /// What is safe to copy to another Mac from an app's preferences.
    public static func allowed(key: String, value: PrefValue) -> Bool {
        if machineSpecificPrefixes.contains(where: key.hasPrefix) { return false }
        if secretKey.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil { return false }
        return !containsSecret(value)
    }

    static func containsSecret(_ value: PrefValue) -> Bool {
        switch value {
        case .string(let s): return looksLikeSecret.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        case .array(let items): return items.contains(where: containsSecret)
        case .dict(let map): return map.contains { allowed(key: $0.key, value: $0.value) == false }
        default: return false
        }
    }

    public static func values(prefs: PreferencesStoring, appDomains: [String], home: String) -> (covered: [String], values: [String: PrefValue]) {
        var values: [String: PrefValue] = [:]
        for definition in SettingsCatalog.all {
            guard var value = prefs.value(domain: definition.domain, key: definition.key) else { continue }
            if definition.isPath, case .string(let path) = value { value = .string(DockCapture.normalize(path: path, home: home)) }
            values[definition.id] = value
        }
        for domain in appDomains where !domain.hasPrefix("com.apple.") {
            for key in prefs.allKeys(domain: domain) {
                guard let value = prefs.value(domain: domain, key: key), allowed(key: key, value: value) else { continue }
                values["\(domain)|\(key)"] = value
            }
        }
        return (SettingsCatalog.all.map(\.id), values)
    }
}

// MARK: Plan

public struct SettingsChange: Codable, Equatable, Identifiable {
    public var id: String
    public var domain: String
    public var key: String
    public var label: String
    public var category: String
    public var from: PrefValue?
    /// Nil means the setting is removed, so it goes back to its default.
    public var to: PrefValue?
    public var restart: RestartTarget?
    public var needsLogout: Bool
    public var type: SettingType?
}

public struct SettingsPlan: Codable, Equatable {
    public var sourceMachine: String
    public var sourceMachineID: String
    public var sourceChangedAt: Date
    public var changes: [SettingsChange]
    public var skipped: [String]
    public var hasChanges: Bool { !changes.isEmpty }
    public var needsLogout: Bool { changes.contains { $0.needsLogout } }
}

public enum SettingsPlanner {
    public static func plan(target: PrefsSection, source: String, sourceID: String = "", prefs: PreferencesStoring, home: String) -> SettingsPlan {
        var changes: [SettingsChange] = []
        var skipped: [String] = []
        let covered = Set(target.covered)
        for definition in SettingsCatalog.all where covered.contains(definition.id) {
            var to = target.values[definition.id]
            if definition.isPath, case .string(let path) = to {
                let expanded = DockCapture.expand(path: path, home: home)
                if !FileManager.default.fileExists(atPath: expanded) {
                    skipped.append("\(definition.label) (\(path) isn't on this Mac)")
                    continue
                }
                to = .string(expanded)
            }
            let from = prefs.value(domain: definition.domain, key: definition.key)
            guard from != to else { continue }
            changes.append(SettingsChange(id: definition.id, domain: definition.domain, key: definition.key, label: definition.label,
                                          category: definition.category, from: from, to: to, restart: definition.restart,
                                          needsLogout: definition.needsLogout, type: definition.type))
        }
        // App preferences are additive: a key missing on the other Mac is never deleted here.
        let curated = Set(SettingsCatalog.all.map(\.id))
        for (id, value) in target.values.sorted(by: { $0.key < $1.key }) where !curated.contains(id) {
            let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, target.appDomains.contains(parts[0]), PrefsCapture.allowed(key: parts[1], value: value) else { continue }
            let from = prefs.value(domain: parts[0], key: parts[1])
            guard from != value else { continue }
            changes.append(SettingsChange(id: id, domain: parts[0], key: parts[1], label: parts[1], category: parts[0], from: from,
                                          to: value, restart: nil, needsLogout: false, type: nil))
        }
        return SettingsPlan(sourceMachine: source, sourceMachineID: sourceID, sourceChangedAt: target.changedAt, changes: changes, skipped: skipped)
    }
}
