import Foundation

// Everything beyond the Dock, apps and system settings: config files, AI setup, app data,
// login items and extra packages. Files travel through iCloud as content-addressed blobs in
// `MacSync/files/`. Anything that looks like a secret stays on its own Mac.

// MARK: Shared data

public struct SharedFile: Codable, Equatable, Hashable {
    /// SHA-256 of what is shared (for JSON files, the copy with secrets taken out). Nil for a link.
    public var sha: String?
    public var size: Int
    /// When this content was made, on whichever Mac made it. The newest wins.
    public var changedAt: Date
    /// Home-relative target, for a symbolic link (the links `npx skills` makes).
    public var link: String?
    public var executable: Bool?
    public init(sha: String?, size: Int, changedAt: Date, link: String? = nil, executable: Bool? = nil) {
        self.sha = sha; self.size = size; self.changedAt = changedAt; self.link = link; self.executable = executable
    }
    func sameContent(as other: SharedFile?) -> Bool { other.map { $0.sha == sha && $0.link == link } ?? false }
}

public struct LoginItem: Codable, Equatable, Hashable, Identifiable {
    public var name: String
    public var bundleID: String?
    /// Home-relative path of the app.
    public var path: String
    public var token: String { "login:" + (bundleID ?? path) }
    public var id: String { token }
    public init(name: String, bundleID: String?, path: String) { self.name = name; self.bundleID = bundleID; self.path = path }
}

public struct ExtrasSection: Codable, Equatable {
    /// By home-relative path ("~/.zshrc").
    public var files: [String: SharedFile]
    public var loginItems: [LoginItem]
    /// Package tokens: "tap:owner/repo", "vscode:publisher.ext", "cursor:…", "npm:…", "uv:…",
    /// "claude-plugin:name@marketplace", "steam:appid".
    public var packages: [String]
    public var packageNames: [String: String]?
    /// Claude Code marketplaces this Mac uses, by name: "owner/repo" or a URL.
    public var marketplaces: [String: String]?
    /// "Remove from all my Macs" for files, login items and packages, by token. The latest wins.
    public var removals: [AppRemoval]?
    public init(files: [String: SharedFile] = [:], loginItems: [LoginItem] = [], packages: [String] = [],
                packageNames: [String: String]? = nil, marketplaces: [String: String]? = nil, removals: [AppRemoval]? = nil) {
        self.files = files; self.loginItems = loginItems; self.packages = packages
        self.packageNames = packageNames; self.marketplaces = marketplaces; self.removals = removals
    }
}

// MARK: What is synced

public enum FileArea: String, Codable, CaseIterable { case config, ai, appData }

public enum FileMode: Equatable {
    /// Text, shared only if nothing in it looks like a secret.
    case text
    /// Fonts and other binary files.
    case binary
    /// JSON with secret-looking values taken out; this Mac's own secrets are kept when it's updated.
    case json
    /// Only one key of a JSON file (Claude Code's MCP servers in ~/.claude.json), with secrets taken out.
    case jsonKey(String)
}

public struct FileGroup {
    public var id: String
    public var area: FileArea
    public var label: String
    public var symbol: String
    /// Home-relative patterns. `*` matches within one folder name, a trailing `/**` takes everything below.
    public var patterns: [String]
    public var mode: FileMode = .text
    /// App data is only taken when one of these apps is on the Mac.
    public var needsApp: [String] = []
}

public enum ExtrasCatalog {
    static func g(_ id: String, _ area: FileArea, _ label: String, _ symbol: String, _ patterns: [String],
                  _ mode: FileMode = .text, needs: [String] = []) -> FileGroup {
        FileGroup(id: id, area: area, label: label, symbol: symbol, patterns: patterns, mode: mode, needsApp: needs)
    }

    public static let groups: [FileGroup] = [
        g("shell", .config, "Shell", "terminal", ["~/.zshrc", "~/.zprofile", "~/.zshenv", "~/.bashrc", "~/.bash_profile", "~/.profile",
                                                  "~/.inputrc", "~/.config/fish/config.fish", "~/.config/fish/functions/**",
                                                  "~/.config/fish/conf.d/**", "~/.config/starship.toml", "~/.p10k.zsh"]),
        g("git", .config, "Git", "arrow.triangle.branch", ["~/.gitconfig", "~/.gitignore_global", "~/.gitignore", "~/.config/git/config",
                                                           "~/.config/git/ignore", "~/.config/git/attributes"]),
        g("editors", .config, "Editors", "chevron.left.forwardslash.chevron.right", [
            "~/.vimrc", "~/.config/nvim/**", "~/.editorconfig", "~/.config/zed/settings.json", "~/.config/zed/keymap.json",
            "~/Library/Application Support/Code/User/settings.json", "~/Library/Application Support/Code/User/keybindings.json",
            "~/Library/Application Support/Code/User/snippets/**",
            "~/Library/Application Support/Cursor/User/settings.json", "~/Library/Application Support/Cursor/User/keybindings.json",
            "~/Library/Application Support/Cursor/User/snippets/**"]),
        g("terminals", .config, "Terminals", "macwindow", ["~/.config/ghostty/config", "~/.config/kitty/**", "~/.config/alacritty/**",
                                                           "~/.wezterm.lua", "~/.config/wezterm/**", "~/.tmux.conf", "~/.config/tmux/**"]),
        g("raycast", .config, "Raycast", "command", ["~/.config/raycast/**"]),
        g("fonts", .config, "Fonts", "textformat", ["~/Library/Fonts/*"], .binary),

        g("skills", .ai, "Skills", "sparkles", ["~/.agents/**", "~/.claude/skills/**", "~/.codex/skills/**", "~/.cursor/skills/**"]),
        g("claude", .ai, "Claude Code", "brain", ["~/.claude/CLAUDE.md", "~/.claude/agents/**", "~/.claude/commands/**",
                                                   "~/.claude/rules/**", "~/.claude/output-styles/**"]),
        g("claude-settings", .ai, "Claude Code settings", "slider.horizontal.3", ["~/.claude/settings.json"], .json),
        g("claude-mcp", .ai, "Claude Code MCP servers", "server.rack", ["~/.claude.json"], .jsonKey("mcpServers")),
        g("claude-desktop", .ai, "Claude app MCP servers", "server.rack",
          ["~/Library/Application Support/Claude/claude_desktop_config.json"], .json),
        g("codex", .ai, "Codex", "chevron.left.forwardslash.chevron.right", ["~/.codex/AGENTS.md", "~/.codex/prompts/**",
                                                                               "~/.codex/rules/**", "~/.codex/config.toml"]),
        g("cursor", .ai, "Cursor", "cursorarrow.rays", ["~/.cursor/rules/**"]),
        g("cursor-mcp", .ai, "Cursor MCP servers", "server.rack", ["~/.cursor/mcp.json"], .json),

        g("photoshop", .appData, "Photoshop presets", "paintbrush", ["~/Library/Application Support/Adobe/Adobe Photoshop */Presets/**"],
          .binary, needs: ["com.adobe.Photoshop"]),
        g("cameraraw", .appData, "Camera Raw presets", "camera.aperture", ["~/Library/Application Support/Adobe/CameraRaw/Settings/**",
                                                                            "~/Library/Application Support/Adobe/CameraRaw/Defaults/**",
                                                                            "~/Library/Application Support/Adobe/CameraRaw/Curves/**"],
          .binary, needs: ["com.adobe.Photoshop", "com.adobe.LightroomClassicCC7", "com.adobe.bridge14", "com.adobe.bridge15"]),
    ]

    /// Preference domains of apps whose settings travel as app data, through the App settings
    /// filter (license keys and other secrets are left out).
    public static let appDataDomains: [(bundleID: String, domains: [String], label: String)] = [
        ("com.bjango.istatmenus", ["com.bjango.istatmenus", "com.bjango.istatmenus7", "com.bjango.istatmenus.status"], "iStat Menus"),
        ("com.bjango.istatmenus7", ["com.bjango.istatmenus7", "com.bjango.istatmenus.status"], "iStat Menus"),
    ]

    public static func group(for path: String) -> FileGroup? {
        groups.first { group in group.patterns.contains { ExtrasFiles.matches(path, pattern: $0) } }
    }

    /// Never shared, whatever the pattern says.
    static let neverPrefixes = ["~/.ssh", "~/.aws", "~/.gnupg", "~/.config/op", "~/.netrc", "~/.docker", "~/.kube",
                                "~/.config/gh", "~/.claude/.credentials", "~/.codex/auth.json", "~/.config/raycast/extensions"]
    static let neverNames = try! NSRegularExpression(pattern:
        "(history|\\.env($|\\.)|secret|credential|token|password|id_rsa|id_ed25519|\\.pem$|\\.key$|\\.p12$|\\.p8$|keychain|\\.sqlite|\\.db$|\\.log$|cookies)",
        options: [.caseInsensitive])
    static let skippedFolders: Set<String> = [".git", "node_modules", "__pycache__", ".venv", "cache", "Cache", "logs", ".system"]
    static let maxFileSize = 25 * 1024 * 1024
    static let maxFilesPerGroup = 3000
    static let maxBytesPerGroup = 300_000_000

    static func isNeverShared(_ path: String) -> Bool {
        if neverPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        let name = (path as NSString).lastPathComponent
        if name == ".DS_Store" { return true }
        return neverNames.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }
}

// MARK: Secrets

public enum SecretScan {
    static let patterns: [NSRegularExpression] = [
        "-----BEGIN [A-Z ]*PRIVATE KEY-----",
        "\\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}", "github_pat_[A-Za-z0-9_]{30,}", "\\bsk-[A-Za-z0-9_-]{20,}",
        "\\bxox[abprs]-[A-Za-z0-9-]{10,}", "\\bAKIA[0-9A-Z]{16}\\b", "\\bAIza[0-9A-Za-z_-]{30,}", "\\bglpat-[A-Za-z0-9_-]{20,}",
        "\\bnpm_[A-Za-z0-9]{30,}", "\\bfc-[0-9a-f]{32}\\b", "\\bpk_(live|test)_[A-Za-z0-9]{20,}", "\\b(sk|rk)_live_[A-Za-z0-9]{20,}",
        "[Bb]earer\\s+[A-Za-z0-9._~+/-]{20,}",
    ].map { try! NSRegularExpression(pattern: $0) }
    /// `API_KEY=…`, `"token": "…"`, `password = …`, `token    73e5…`.
    static let assignment = try! NSRegularExpression(pattern:
        "([A-Za-z0-9_-]*(key|token|secret|passw(or)?d|pwd|auth|credential|bearer)[A-Za-z0-9_-]*)[\"']?(\\s*[:=]\\s*|\\s{2,})[\"']?([A-Za-z0-9_\\-./+=]{16,})",
        options: [.caseInsensitive])
    static let harmlessKeys: Set<String> = ["signingkey", "key", "keybindings", "keymap", "keyboard", "hotkey", "monkey"]

    /// Why a text looks like it holds a secret, with the line, or nil.
    public static func reason(in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() where line.count < 4000 {
            let range = NSRange(line.startIndex..., in: line)
            if patterns.contains(where: { $0.firstMatch(in: line, range: range) != nil }) {
                return "line \(index + 1) looks like a key or token"
            }
            for match in assignment.matches(in: line, range: range) {
                guard let nameRange = Range(match.range(at: 1), in: line), let valueRange = Range(match.range(at: 5), in: line) else { continue }
                let name = line[nameRange].lowercased(), value = String(line[valueRange])
                if harmlessKeys.contains(name) || value.hasPrefix("$") || value.hasPrefix("/") || value.hasPrefix("~") || value.contains("${") { continue }
                if value.rangeOfCharacter(from: .decimalDigits) != nil, value.rangeOfCharacter(from: .letters) != nil {
                    return "line \(index + 1) sets \(line[nameRange])"
                }
            }
        }
        return nil
    }

    static func isSecret(key: String, value: Any) -> Bool {
        guard let text = value as? String else { return false }
        let range = NSRange(key.startIndex..., in: key)
        let keyLooksSecret = PrefsCapture.secretKey.firstMatch(in: key, range: range) != nil
            && !["model", "theme"].contains(key.lowercased())
        if keyLooksSecret && !text.isEmpty && !text.hasPrefix("$") { return true }
        return reason(in: text) != nil || (text.count >= 32 && PrefsCapture.looksLikeSecret.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            && text.rangeOfCharacter(from: .decimalDigits) != nil && !text.contains("/"))
    }

    /// The JSON with every secret-looking value taken out, and how many were.
    static func sanitize(_ value: Any) -> (Any, Int) {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:], removed = 0
            for (key, item) in dict {
                if isSecret(key: key, value: item) { removed += 1; continue }
                let (clean, count) = sanitize(item)
                out[key] = clean; removed += count
            }
            return (out, removed)
        }
        if let array = value as? [Any] {
            var removed = 0
            let clean = array.compactMap { item -> Any? in
                if let text = item as? String, reason(in: text) != nil { removed += 1; return nil }
                let (c, n) = sanitize(item); removed += n; return c
            }
            return (clean, removed)
        }
        return (value, 0)
    }

    /// Puts this Mac's own secrets back into JSON that came from another Mac.
    static func keepSecrets(_ incoming: Any, local: Any?) -> Any {
        guard var incoming = incoming as? [String: Any], let local = local as? [String: Any] else { return incoming }
        for (key, value) in local {
            if incoming[key] == nil {
                if isSecret(key: key, value: value) { incoming[key] = value }
            } else if value is [String: Any] {
                incoming[key] = keepSecrets(incoming[key]!, local: value)
            }
        }
        return incoming
    }
}

// MARK: Files

public struct LocalFile {
    public var path: String
    public var group: FileGroup
    public var entry: SharedFile
    public var data: Data?
    public var isLink: Bool
}

public struct Why: Error { public var text: String; init(_ text: String) { self.text = text } }

public enum ExtrasFiles {
    static func expand(_ path: String, home: String) -> String { DockCapture.expand(path: path, home: home) }

    static func matches(_ path: String, pattern: String) -> Bool {
        let p = pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let s = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if p.last == "**" {
            let base = Array(p.dropLast())
            return s.count > base.count && zip(base, s).allSatisfy(componentMatches)
        }
        return p.count == s.count && zip(p, s).allSatisfy(componentMatches)
    }

    static func componentMatches(_ pattern: String, _ name: String) -> Bool {
        guard pattern.contains("*") else { return pattern == name }
        let parts = pattern.components(separatedBy: "*")
        guard name.hasPrefix(parts.first!), name.hasSuffix(parts.last!), name.count >= parts.first!.count + parts.last!.count else { return false }
        return true
    }

    /// Every existing file the patterns name, home-relative, links reported as links.
    static func list(_ group: FileGroup, home: String) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for pattern in group.patterns {
            var comps = pattern.split(separator: "/").map(String.init)
            let recursive = comps.last == "**"
            if recursive { comps.removeLast() }
            // Expand wildcards one folder at a time.
            var bases = ["~"]
            for comp in comps.dropFirst() {
                bases = bases.flatMap { base -> [String] in
                    guard comp.contains("*") else { return [base + "/" + comp] }
                    let names = (try? fm.contentsOfDirectory(atPath: expand(base, home: home))) ?? []
                    return names.filter { componentMatches(comp, $0) }.sorted().map { base + "/" + $0 }
                }
            }
            for base in bases {
                let full = expand(base, home: home)
                var isDir: ObjCBool = false
                let isLink = (try? fm.destinationOfSymbolicLink(atPath: full)) != nil
                guard isLink || fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
                if !recursive || isLink || !isDir.boolValue {
                    if !isDir.boolValue || isLink { out.append(base) }
                    continue
                }
                walk(base, home: home, into: &out, limit: ExtrasCatalog.maxFilesPerGroup)
            }
        }
        return Array(Set(out)).filter { !ExtrasCatalog.isNeverShared($0) }.sorted()
    }

    private static func walk(_ dir: String, home: String, into out: inout [String], limit: Int) {
        let fm = FileManager.default
        for name in ((try? fm.contentsOfDirectory(atPath: expand(dir, home: home))) ?? []).sorted() where out.count < limit {
            let path = dir + "/" + name
            if ExtrasCatalog.isNeverShared(path) { continue }
            let full = expand(path, home: home)
            if (try? fm.destinationOfSymbolicLink(atPath: full)) != nil { out.append(path); continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if !ExtrasCatalog.skippedFolders.contains(name) && !name.lowercased().contains("cache") && !name.hasSuffix(".app") {
                    walk(path, home: home, into: &out, limit: limit)
                }
            } else {
                out.append(path)
            }
        }
    }

    /// What this Mac would share for one file: its bytes (sanitized for JSON), or why it can't.
    static func read(_ path: String, group: FileGroup, home: String) -> Result<(data: Data?, link: String?, executable: Bool), Why> {
        let fm = FileManager.default
        let full = expand(path, home: home)
        if let target = try? fm.destinationOfSymbolicLink(atPath: full) {
            let absolute = target.hasPrefix("/") ? target : ((full as NSString).deletingLastPathComponent as NSString).appendingPathComponent(target)
            let normalized = DockCapture.normalize(path: (absolute as NSString).standardizingPath, home: home)
            guard normalized.hasPrefix("~/") else { return .failure(Why("links outside your home folder")) }
            return .success((nil, normalized, false))
        }
        let attributes = try? fm.attributesOfItem(atPath: full)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size <= ExtrasCatalog.maxFileSize else { return .failure(Why("is larger than 25 MB")) }
        guard let data = fm.contents(atPath: full) else { return .failure(Why("can't be read")) }
        let executable = ((attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o100 != 0
        switch group.mode {
        case .binary:
            return .success((data, nil, executable))
        case .text:
            guard let text = String(data: data, encoding: .utf8) else {
                // Skills can carry images and the like; they are shared as they are.
                return group.area == .ai ? .success((data, nil, executable)) : .failure(Why("isn't a text file"))
            }
            if let why = SecretScan.reason(in: text) { return .failure(Why("has a secret in it: \(why)")) }
            return .success((data, nil, executable))
        case .json:
            guard let object = try? JSONSerialization.jsonObject(with: data) else { return .failure(Why("isn't valid JSON")) }
            return checked(canonical(SecretScan.sanitize(object).0))
        case .jsonKey(let key):
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(Why("isn't valid JSON")) }
            let part = object[key] ?? [String: Any]()
            return checked(canonical([key: SecretScan.sanitize(part).0]))
        }
    }

    /// The cleaned copy is scanned again, so a secret the cleaning missed still keeps the file home.
    static func checked(_ data: Data) -> Result<(data: Data?, link: String?, executable: Bool), Why> {
        if let text = String(data: data, encoding: .utf8), let why = SecretScan.reason(in: text) {
            return .failure(Why("has a secret in it: \(why)"))
        }
        return .success((data, nil, false))
    }

    static func canonical(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    static func modified(_ path: String, home: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: expand(path, home: home))[.modificationDate]) as? Date
    }
}

// MARK: Plan

public struct FileChange: Codable, Equatable, Identifiable {
    public var path: String
    public var area: FileArea
    public var group: String
    public var symbol: String
    public var isNew: Bool
    public var sourceMachine: String
    public var entry: SharedFile
    /// "+12 −3 lines", "font", "link".
    public var detail: String
    /// A few changed lines, for text files.
    public var preview: [String]
    /// The blob hasn't arrived through iCloud yet.
    public var waiting: Bool
    public var token: String { "file:" + path }
    public var id: String { path }
}

public struct KeptFile: Codable, Equatable, Identifiable {
    public var path: String
    public var area: FileArea
    public var reason: String
    public var id: String { path }
}

public struct SharedFileInfo: Codable, Equatable, Identifiable {
    public var path: String
    public var area: FileArea
    public var group: String
    public var symbol: String
    public var localOnly: Bool
    public var id: String { path }
}

public struct PackageItem: Codable, Equatable, Identifiable {
    public var token: String
    public var kind: String
    public var name: String
    public var fromMachines: [String]
    public var id: String { token }
}

public struct ExtrasPlan: Codable, Equatable {
    public var files: [FileChange] = []
    public var kept: [KeptFile] = []
    public var shared: [SharedFileInfo] = []
    public var loginItems: [LoginItem] = []
    public var loginItemSources: [String: [String]] = [:]
    public var packages: [PackageItem] = []
    public var issues: [String] = []
    /// Removed on another Mac and still on this one.
    public var toRemove: [AppRemoval] = []
    public var removed: [AppRemoval] = []
    public var installedPackages: [PackageItem] = []
    public var installedLoginItems: [LoginItem] = []
    public var isEmpty: Bool { files.isEmpty && loginItems.isEmpty && packages.isEmpty }
}

public struct ExtrasReport: Codable, Equatable {
    public var filesChanged: [String] = []
    public var loginItemsAdded: [String] = []
    public var packagesInstalled: [String] = []
    public var failures: [String] = []
}

// MARK: Engine part

final class Extras {
    struct State: Codable {
        /// What this Mac last shared or took, by path.
        var known: [String: SharedFile] = [:]
        /// Paths this Mac keeps to itself.
        var localOnly: [String] = []
        var packages: [String]?
        var packageNames: [String: String]?
        var marketplaces: [String: String]?
        var packagesAt: Date?
        var loginItems: [LoginItem]?
        var loginItemsAt: Date?
        var loginItemsIssue: String?
        var removals: [String: AppRemoval]?
        var keptHere: [String]?
        /// Modification date and size at the last read, so unchanged files aren't read again.
        var stamps: [String: String]?
    }

    let env: MacSyncEnvironment
    let runner: CommandRunning
    let locator: AppLocating
    let now: () -> Date
    private(set) var kept: [KeptFile] = []

    init(env: MacSyncEnvironment, runner: CommandRunning, locator: AppLocating, now: @escaping () -> Date) {
        self.env = env; self.runner = runner; self.locator = locator; self.now = now
    }

    /// A simulated Mac in the real home folder (the website's demo) must not read or write real files.
    var enabled: Bool {
        FileManager.default.fileExists(atPath: env.homeDirectory) && (env.dockFile == nil || env.homeDirectory != NSHomeDirectory())
    }
    var live: Bool { env.dockFile == nil }

    var blobs: URL { env.syncDirectory.appendingPathComponent("files", isDirectory: true) }
    private var stateURL: URL { env.dataDirectory.appendingPathComponent("extras-state.json") }

    func loadState() -> State {
        (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder.iso.decode(State.self, from: $0) } ?? State()
    }

    func saveState(_ state: State) {
        try? FileManager.default.createDirectory(at: env.dataDirectory, withIntermediateDirectories: true)
        try? JSONEncoder.iso.encode(state).write(to: stateURL, options: .atomic)
    }

    // MARK: Capture

    func capture(refresh: Bool) -> ExtrasSection? {
        guard enabled else { return nil }
        var state = loadState()
        var files: [String: SharedFile] = [:]
        var kept: [KeptFile] = []
        let localOnly = Set(state.localOnly)
        for group in ExtrasCatalog.groups {
            if !group.needsApp.isEmpty && !group.needsApp.contains(where: appInstalled) { continue }
            var groupBytes = 0
            for path in ExtrasFiles.list(group, home: env.homeDirectory) where files[path] == nil {
                if localOnly.contains(path) { continue }
                // A folder that grew huge (presets, fonts) stops being copied past the limit.
                groupBytes += ((try? FileManager.default.attributesOfItem(atPath: ExtrasFiles.expand(path, home: env.homeDirectory))[.size]) as? NSNumber)?.intValue ?? 0
                if groupBytes > ExtrasCatalog.maxBytesPerGroup {
                    kept.append(KeptFile(path: path, area: group.area, reason: "\(group.label) is over \(ExtrasCatalog.maxBytesPerGroup / 1_000_000) MB, so the rest stays here"))
                    continue
                }
                let stamp = Self.stamp(path, home: env.homeDirectory)
                if let known = state.known[path], let stamp, state.stamps?[path] == stamp,
                   known.sha.map({ FileManager.default.fileExists(atPath: blobs.appendingPathComponent($0).path) }) ?? true {
                    files[path] = known
                    continue
                }
                switch ExtrasFiles.read(path, group: group, home: env.homeDirectory) {
                case .failure(let why):
                    kept.append(KeptFile(path: path, area: group.area, reason: why.text))
                case .success(let read):
                    let sha = read.data.map { AppDownloader.sha256Hex($0) }
                    var entry = SharedFile(sha: sha, size: read.data?.count ?? 0, changedAt: now(), link: read.link,
                                           executable: read.executable ? true : nil)
                    if let known = state.known[path], known.sha == sha, known.link == read.link {
                        entry = known
                    } else if state.known[path] == nil {
                        // First time seen: it was last edited when the file says.
                        entry.changedAt = min(now(), ExtrasFiles.modified(path, home: env.homeDirectory) ?? now())
                    }
                    if let data = read.data, let sha, env.iCloudAvailable { storeBlob(data, sha: sha) }
                    files[path] = entry
                    if let stamp { state.stamps = (state.stamps ?? [:]).merging([path: stamp]) { $1 } }
                }
            }
        }
        state.known = state.known.filter { files[$0.key] != nil || !FileManager.default.fileExists(atPath: ExtrasFiles.expand($0.key, home: env.homeDirectory)) }
        for (path, entry) in files { state.known[path] = entry }
        self.kept = kept
        if live {
            if refresh || state.packages == nil { readPackages(&state) }
            if refresh || state.loginItems == nil || (state.loginItemsAt.map { now().timeIntervalSince($0) > 600 } ?? true) {
                readLoginItems(&state)
            }
        }
        saveState(state)
        return ExtrasSection(files: files, loginItems: state.loginItems ?? [], packages: state.packages ?? [],
                             packageNames: state.packageNames, marketplaces: state.marketplaces,
                             removals: state.removals.map { Array($0.values).sorted { $0.token < $1.token } })
    }

    /// What this Mac would share and keep, without saving or uploading anything.
    func scan() -> (shared: [SharedFileInfo], kept: [KeptFile]) {
        var shared: [SharedFileInfo] = [], kept: [KeptFile] = []
        let localOnly = Set(loadState().localOnly)
        for group in ExtrasCatalog.groups {
            if !group.needsApp.isEmpty && !group.needsApp.contains(where: appInstalled) { continue }
            for path in ExtrasFiles.list(group, home: env.homeDirectory) where !shared.contains(where: { $0.path == path }) {
                switch ExtrasFiles.read(path, group: group, home: env.homeDirectory) {
                case .failure(let why): kept.append(KeptFile(path: path, area: group.area, reason: why.text))
                case .success: shared.append(SharedFileInfo(path: path, area: group.area, group: group.label, symbol: group.symbol,
                                                            localOnly: localOnly.contains(path)))
                }
            }
        }
        return (shared, kept)
    }

    static func stamp(_ path: String, home: String) -> String? {
        let full = ExtrasFiles.expand(path, home: home)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: full),
              (attributes[.type] as? FileAttributeType) != .typeSymbolicLink,
              let date = attributes[.modificationDate] as? Date, let size = attributes[.size] as? NSNumber else { return nil }
        return "\(date.timeIntervalSince1970)|\(size)"
    }

    func appInstalled(_ bundleID: String) -> Bool { locator.path(forBundleID: bundleID) != nil }

    private func storeBlob(_ data: Data, sha: String) {
        let url = blobs.appendingPathComponent(sha)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Plan

    func plan(others: [MachineSnapshot], skipped: Set<String>) -> ExtrasPlan {
        var plan = ExtrasPlan()
        guard enabled else { return plan }
        var state = loadState()
        // Every Mac's removals, merged: the latest word on each token wins.
        var merged = state.removals ?? [:]
        for removal in others.flatMap({ $0.extras?.removals ?? [] }) where Self.isRemovableToken(removal.token) {
            if let current = merged[removal.token], current.at >= removal.at { continue }
            merged[removal.token] = removal
        }
        if merged != (state.removals ?? [:]) { state.removals = merged; saveState(state) }
        let removed = Set(merged.values.filter(\.active).map(\.token))
        let localOnly = Set(state.localOnly)
        let home = env.homeDirectory
        // Newest version of each path on the other Macs.
        var newest: [String: (SharedFile, String)] = [:]
        for machine in others {
            for (path, entry) in machine.extras?.files ?? [:] where ExtrasFiles.matches(path, pattern: "~/**") {
                if let current = newest[path], current.0.changedAt >= entry.changedAt { continue }
                newest[path] = (entry, machine.machineName)
            }
        }
        let fm = FileManager.default
        for (path, (entry, source)) in newest.sorted(by: { $0.key < $1.key }) {
            guard !localOnly.contains(path), !removed.contains("file:" + path), !ExtrasCatalog.isNeverShared(path), !path.contains("/../"),
                  let group = ExtrasCatalog.group(for: path) else { continue }
            if !group.needsApp.isEmpty && !group.needsApp.contains(where: appInstalled) { continue }
            let full = ExtrasFiles.expand(path, home: home)
            let localIsLink = (try? fm.destinationOfSymbolicLink(atPath: full)) != nil
            let exists = localIsLink || fm.fileExists(atPath: full)
            let known = state.known[path]
            if exists, entry.sameContent(as: known) { continue }
            if exists, let known, known.changedAt >= entry.changedAt { continue }
            // A file kept here because of a secret is never replaced.
            if kept.contains(where: { $0.path == path }) { continue }
            // A file that is a link on this Mac (a dotfiles folder) is left to whatever manages it.
            if localIsLink && entry.link == nil { continue }
            if let link = entry.link, !fm.fileExists(atPath: ExtrasFiles.expand(link, home: home)) { continue }
            var change = FileChange(path: path, area: group.area, group: group.label, symbol: group.symbol, isNew: !exists,
                                    sourceMachine: source, entry: entry, detail: "", preview: [], waiting: false)
            if let link = entry.link {
                change.detail = "link to \(link)"
            } else if let sha = entry.sha, blobReady(sha), let data = fm.contents(atPath: blobs.appendingPathComponent(sha).path) {
                describe(&change, new: data, oldPath: exists ? full : nil, group: group)
            } else {
                change.waiting = true
                change.detail = "still arriving through iCloud"
            }
            plan.files.append(change)
        }
        plan.kept = kept
        plan.shared = (state.known.keys.map { $0 } + state.localOnly).sorted().compactMap { path in
            guard let group = ExtrasCatalog.group(for: path) else { return nil }
            return SharedFileInfo(path: path, area: group.area, group: group.label, symbol: group.symbol, localOnly: localOnly.contains(path))
        }
        // Login items whose app this Mac has.
        let mine = Set((state.loginItems ?? []).map(\.token))
        let mineByName = Set((state.loginItems ?? []).map { $0.name.lowercased() })
        var seen: [String: LoginItem] = [:]
        for machine in others {
            for item in machine.extras?.loginItems ?? [] where !mine.contains(item.token) && !mineByName.contains(item.name.lowercased())
                && !removed.contains(item.token) {
                guard localAppPath(item) != nil else { continue }
                seen[item.token] = item
                plan.loginItemSources[item.token, default: []].append(machine.machineName)
            }
        }
        plan.loginItems = live ? seen.values.sorted { $0.name < $1.name } : []
        // Packages.
        let have = Set(state.packages ?? [])
        var packages: [String: PackageItem] = [:]
        for machine in others {
            for token in machine.extras?.packages ?? [] where !have.contains(token) && Packages.isSafe(token) && !removed.contains(token) {
                guard Packages.canInstall(token, env: env, locator: locator) else { continue }
                let kind = Packages.kind(token)
                let name = machine.extras?.packageNames?[token] ?? String(token.dropFirst(kind.count + 1))
                packages[token, default: PackageItem(token: token, kind: kind, name: name, fromMachines: [])].fromMachines.append(machine.machineName)
            }
        }
        plan.packages = live ? packages.values.sorted { ($0.kind, $0.name) < ($1.kind, $1.name) } : []
        if let issue = state.loginItemsIssue { plan.issues.append(issue) }
        // Removed on another Mac, still here.
        let keptHere = Set(state.keptHere ?? [])
        for removal in merged.values.filter(\.active).sorted(by: { $0.at > $1.at }) where !keptHere.contains(removal.token) {
            if has(removal.token, state) { plan.toRemove.append(removal) }
        }
        plan.removed = merged.values.filter(\.active).sorted { $0.at > $1.at }
        plan.installedPackages = (state.packages ?? []).map { token in
            let kind = Packages.kind(token)
            return PackageItem(token: token, kind: kind, name: state.packageNames?[token] ?? String(token.dropFirst(kind.count + 1)), fromMachines: [])
        }
        plan.installedLoginItems = state.loginItems ?? []
        _ = skipped
        return plan
    }

    /// Whether a shared file's copy is on this Mac. One still in iCloud is asked for in the
    /// background: reading it here would wait for the download, once per file.
    func blobReady(_ sha: String) -> Bool {
        let url = blobs.appendingPathComponent(sha)
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values?.isUbiquitousItem == true, values?.ubiquitousItemDownloadingStatus != .current {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func describe(_ change: inout FileChange, new: Data, oldPath: String?, group: FileGroup) {
        let newText: String?
        switch group.mode {
        case .jsonKey, .json: newText = String(data: new, encoding: .utf8)
        default: newText = String(data: new, encoding: .utf8)
        }
        guard let newText, group.mode != .binary else {
            change.detail = ByteCountFormatter.string(fromByteCount: Int64(new.count), countStyle: .file)
            return
        }
        var oldText = ""
        if let oldPath, let data = FileManager.default.contents(atPath: oldPath) {
            if case .text = group.mode { oldText = String(data: data, encoding: .utf8) ?? "" }
            else if let read = try? ExtrasFiles.read(DockCapture.normalize(path: oldPath, home: env.homeDirectory), group: group,
                                                     home: env.homeDirectory).get(), let d = read.data {
                oldText = String(data: d, encoding: .utf8) ?? ""
            }
        }
        let diff = newText.components(separatedBy: "\n").difference(from: oldText.isEmpty ? [] : oldText.components(separatedBy: "\n"))
        let added = diff.insertions.count, removed = diff.removals.count
        change.detail = oldPath == nil ? "\(added) line\(added == 1 ? "" : "s")" : "+\(added) −\(removed) lines"
        change.preview = diff.prefix(6).map { step in
            switch step {
            case .insert(_, let line, _): return "+ " + String(line.prefix(120))
            case .remove(_, let line, _): return "− " + String(line.prefix(120))
            }
        }
    }

    func localAppPath(_ item: LoginItem) -> String? {
        if let bundle = item.bundleID, let path = locator.path(forBundleID: bundle) { return path }
        let full = ExtrasFiles.expand(item.path, home: env.homeDirectory)
        return FileManager.default.fileExists(atPath: full) ? full : nil
    }

    // MARK: Apply

    struct FileBackup: Codable { var path: String; var existed: Bool; var backup: String? }

    func apply(files: [FileChange], loginItems: [LoginItem], packages: [PackageItem], marketplaces: [String: String],
               backupDir: URL, progress: (String) -> Void) -> ExtrasReport {
        var report = ExtrasReport()
        var state = loadState()
        let fm = FileManager.default
        let home = env.homeDirectory
        var backups: [FileBackup] = []
        let folder = backupDir.appendingPathComponent("files", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for change in files where !change.waiting {
            guard let group = ExtrasCatalog.group(for: change.path) else { continue }
            progress("Updating \(change.path)…")
            let full = ExtrasFiles.expand(change.path, home: home)
            let isLink = (try? fm.destinationOfSymbolicLink(atPath: full)) != nil
            var backup = FileBackup(path: change.path, existed: isLink || fm.fileExists(atPath: full), backup: nil)
            if backup.existed {
                let name = "\(backups.count)-" + (change.path as NSString).lastPathComponent
                if (try? fm.copyItem(atPath: full, toPath: folder.appendingPathComponent(name).path)) != nil { backup.backup = name }
                else { report.failures.append("\(change.path): couldn't back it up, so it was left alone"); continue }
            }
            backups.append(backup)
            do {
                try fm.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                if let link = change.entry.link {
                    if backup.existed { try fm.removeItem(atPath: full) }
                    try fm.createSymbolicLink(atPath: full, withDestinationPath: ExtrasFiles.expand(link, home: home))
                } else {
                    guard let sha = change.entry.sha else { throw EngineError.refused("its copy in iCloud is incomplete") }
                    guard blobReady(sha) else { throw EngineError.refused("it's still arriving through iCloud; try again in a minute") }
                    guard let blob = fm.contents(atPath: blobs.appendingPathComponent(sha).path),
                          AppDownloader.sha256Hex(blob) == sha else { throw EngineError.refused("its copy in iCloud is incomplete") }
                    var data = blob
                    switch group.mode {
                    case .json:
                        let incoming = try JSONSerialization.jsonObject(with: blob)
                        let local = fm.contents(atPath: full).flatMap { try? JSONSerialization.jsonObject(with: $0) }
                        data = try JSONSerialization.data(withJSONObject: SecretScan.keepSecrets(incoming, local: local),
                                                          options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    case .jsonKey(let key):
                        let incoming = (try JSONSerialization.jsonObject(with: blob) as? [String: Any])?[key] ?? [String: Any]()
                        var whole = fm.contents(atPath: full).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                        whole[key] = SecretScan.keepSecrets(incoming, local: whole[key])
                        data = try JSONSerialization.data(withJSONObject: whole, options: [.prettyPrinted, .withoutEscapingSlashes])
                    default: break
                    }
                    if isLink { try fm.removeItem(atPath: full) }
                    try data.write(to: URL(fileURLWithPath: full), options: .atomic)
                    if change.entry.executable == true { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: full) }
                }
                state.known[change.path] = change.entry
                state.stamps?[change.path] = nil
                report.filesChanged.append(change.path)
            } catch {
                report.failures.append("\(change.path): \(error.localizedDescription)")
            }
        }
        try? JSONEncoder().encode(backups).write(to: backupDir.appendingPathComponent("files.json"), options: .atomic)
        for item in loginItems {
            guard let path = localAppPath(item) else { continue }
            progress("Adding \(item.name) to login items…")
            let result = runner.run("/usr/bin/osascript", ["-e", "on run argv", "-e",
                "tell application \"System Events\" to make login item at end with properties {path:(item 1 of argv), hidden:false}",
                "-e", "end run", path], input: nil, environment: [:])
            if result.status == 0 { report.loginItemsAdded.append(item.name); state.loginItems?.append(item) }
            else { report.failures.append("\(item.name) wasn't added to login items: \(Self.automationProblem(result.stderr))") }
        }
        for package in packages where Packages.isSafe(package.token) {
            progress("Installing \(package.name)…")
            switch Packages.install(package.token, env: env, runner: runner, marketplaces: marketplaces, localMarketplaces: state.marketplaces ?? [:]) {
            case .success: report.packagesInstalled.append(package.name); state.packages?.append(package.token)
            case .failure(let error): report.failures.append("\(package.name): \(error.localizedDescription)")
            }
        }
        saveState(state)
        return report
    }

    /// Puts files back as they were before an Apply.
    func restore(from backupDir: URL) {
        guard let data = try? Data(contentsOf: backupDir.appendingPathComponent("files.json")),
              let backups = try? JSONDecoder().decode([FileBackup].self, from: data) else { return }
        let fm = FileManager.default
        var state = loadState()
        for backup in backups.reversed() {
            let full = ExtrasFiles.expand(backup.path, home: env.homeDirectory)
            try? fm.removeItem(atPath: full)
            if let name = backup.backup {
                try? fm.copyItem(atPath: backupDir.appendingPathComponent("files").appendingPathComponent(name).path, toPath: full)
            }
            // Counts as an edit made here, so the restored file is what this Mac shares.
            state.known[backup.path] = nil
            state.stamps?[backup.path] = nil
        }
        saveState(state)
    }

    func setLocalOnly(_ paths: [String], _ localOnly: Bool) {
        var state = loadState()
        var set = Set(state.localOnly)
        if localOnly { set.formUnion(paths) } else { set.subtract(paths) }
        state.localOnly = set.sorted()
        saveState(state)
    }

    // MARK: Removing

    static func isRemovableToken(_ token: String) -> Bool {
        if token.hasPrefix("file:") { let path = String(token.dropFirst(5)); return path.hasPrefix("~/") && !path.contains("/../") }
        if token.hasPrefix("login:") { return token.count < 300 }
        return Packages.isSafe(token)
    }

    private func has(_ token: String, _ state: State) -> Bool {
        if token.hasPrefix("file:") {
            let full = ExtrasFiles.expand(String(token.dropFirst(5)), home: env.homeDirectory)
            return FileManager.default.fileExists(atPath: full) || (try? FileManager.default.destinationOfSymbolicLink(atPath: full)) != nil
        }
        if token.hasPrefix("login:") { return (state.loginItems ?? []).contains { $0.token == token } }
        return (state.packages ?? []).contains(token)
    }

    /// Takes something off this Mac: a file to the Trash, a login item out of the list, a package uninstalled.
    /// With `everywhere`, every other Mac is asked to do the same.
    func remove(_ token: String, name: String, everywhere: Bool) -> Result<Void, EngineError> {
        guard Self.isRemovableToken(token) else { return .failure(.refused("That item's name isn't valid.")) }
        var state = loadState()
        var result: Result<Void, EngineError> = .success(())
        if token.hasPrefix("file:") {
            let path = String(token.dropFirst(5))
            let url = URL(fileURLWithPath: ExtrasFiles.expand(path, home: env.homeDirectory))
            if FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
                do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
                catch { result = .failure(.refused("It couldn't be moved to the Trash.")) }
            }
            if case .success = result {
                state.known[path] = nil
                if !everywhere { state.localOnly = Array(Set(state.localOnly + [path])).sorted() }
            }
        } else if token.hasPrefix("login:") {
            let item = (state.loginItems ?? []).first { $0.token == token }
            if let item, live {
                let r = runner.run("/usr/bin/osascript", ["-e", "on run argv", "-e",
                    "tell application \"System Events\" to delete (every login item whose name is (item 1 of argv))", "-e", "end run", item.name],
                    input: nil, environment: [:])
                if r.status != 0 { result = .failure(.refused(Self.automationProblem(r.stderr))) }
            }
            if case .success = result { state.loginItems?.removeAll { $0.token == token } }
        } else if (state.packages ?? []).contains(token) {
            result = Packages.uninstall(token, env: env, runner: runner)
            if case .success = result { state.packages?.removeAll { $0 == token } }
        }
        if case .success = result {
            var removals = state.removals ?? [:]
            if everywhere {
                removals[token] = AppRemoval(token: token, name: name, bundleID: nil, at: now(), active: true, fromMachine: env.machineName)
            } else if removals[token]?.active == true {
                // Removed here because another Mac asked: nothing more to do.
            }
            state.removals = removals
            if !everywhere { state.keptHere?.removeAll { $0 == token } }
        }
        saveState(state)
        return result
    }

    /// Takes back a "remove from all Macs", or keeps an item on this Mac anyway.
    func cancelRemoval(_ token: String) {
        var state = loadState()
        if var removal = state.removals?[token] {
            removal.active = false
            removal.at = now()
            removal.fromMachine = env.machineName
            state.removals?[token] = removal
        }
        saveState(state)
    }

    func keepHere(_ token: String) {
        var state = loadState()
        state.keptHere = Array(Set((state.keptHere ?? []) + [token])).sorted()
        saveState(state)
    }

    // MARK: Login items

    private func readLoginItems(_ state: inout State) {
        let script = "JSON.stringify(Application('System Events').loginItems().map(i => ({name: i.name(), path: i.path()})))"
        let result = runner.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", script], input: nil, environment: [:])
        state.loginItemsAt = now()
        guard result.status == 0 else {
            if !result.stderr.isEmpty { state.loginItemsIssue = "Login items: \(Self.automationProblem(result.stderr))" }
            return
        }
        state.loginItemsIssue = nil
        guard let data = result.output.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        state.loginItems = list.compactMap { entry in
            guard let name = entry["name"] as? String, let path = entry["path"] as? String, path.hasSuffix(".app"),
                  DirectApp.isSafeName(name) else { return nil }
            return LoginItem(name: name, bundleID: InventoryReader.bundleID(at: path),
                             path: DockCapture.normalize(path: path, home: env.homeDirectory))
        }.sorted { $0.name < $1.name }
    }

    static func automationProblem(_ stderr: String) -> String {
        stderr.contains("-1743") || stderr.contains("Not authorized")
            ? "allow MacSync to control System Events in System Settings → Privacy & Security → Automation"
            : stderr.split(whereSeparator: \.isNewline).last.map(String.init) ?? "it didn't work"
    }

    // MARK: Packages

    private func readPackages(_ state: inout State) {
        var tokens: [String] = []
        var names: [String: String] = [:]
        if let brew = env.brewPath {
            let result = runner.run(brew, ["tap"], input: nil, environment: InventoryReader.brewEnvironment(brew))
            if result.status == 0 {
                tokens += InventoryReader.lines(result.output).filter { !["homebrew/core", "homebrew/cask", "homebrew/bundle", "homebrew/services"].contains($0) }
                    .map { "tap:" + $0 }
            }
        }
        for (kind, cli) in [("vscode", Packages.code), ("cursor", Packages.cursor)] {
            guard let path = cli.first(where: FileManager.default.isExecutableFile) else { continue }
            let result = runner.run(path, ["--list-extensions"], input: nil, environment: Packages.toolEnv)
            if result.status == 0 { tokens += InventoryReader.lines(result.output).map { "\(kind):\($0.lowercased())" } }
        }
        if let npm = Packages.npm.first(where: FileManager.default.isExecutableFile) {
            let result = runner.run(npm, ["ls", "-g", "--depth=0", "--json"], input: nil, environment: Packages.toolEnv)
            if let data = result.output.data(using: .utf8),
               let deps = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["dependencies"] as? [String: Any] {
                tokens += deps.keys.filter { !["npm", "corepack"].contains($0) }.map { "npm:" + $0 }
            }
        }
        if let uv = Packages.uv.first(where: FileManager.default.isExecutableFile) {
            let result = runner.run(uv, ["tool", "list"], input: nil, environment: Packages.toolEnv)
            if result.status == 0 {
                tokens += InventoryReader.lines(result.output).filter { !$0.hasPrefix("-") }
                    .compactMap { $0.split(separator: " ").first.map { "uv:" + $0 } }
            }
        }
        // Claude Code plugins installed for the user, and where their marketplaces come from.
        let plugins = URL(fileURLWithPath: ExtrasFiles.expand("~/.claude/plugins", home: env.homeDirectory))
        if let data = try? Data(contentsOf: plugins.appendingPathComponent("installed_plugins.json")),
           let all = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["plugins"] as? [String: [[String: Any]]] {
            tokens += all.filter { $0.value.contains { ($0["scope"] as? String) == "user" } }.keys.map { "claude-plugin:" + $0 }
        }
        var marketplaces: [String: String] = [:]
        if let data = try? Data(contentsOf: plugins.appendingPathComponent("known_marketplaces.json")),
           let all = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            for (name, info) in all {
                let source = info["source"] as? [String: Any]
                if let repo = (source?["repo"] as? String) ?? (source?["url"] as? String) { marketplaces[name] = repo }
            }
        }
        // Steam games, so the other Macs can download them from Steam.
        let steam = ExtrasFiles.expand("~/Library/Application Support/Steam/steamapps", home: env.homeDirectory)
        for file in ((try? FileManager.default.contentsOfDirectory(atPath: steam)) ?? []) where file.hasPrefix("appmanifest_") {
            guard let text = try? String(contentsOfFile: steam + "/" + file, encoding: .utf8),
                  let id = Packages.vdf("appid", in: text), id.allSatisfy(\.isNumber) else { continue }
            tokens.append("steam:" + id)
            if let name = Packages.vdf("name", in: text) { names["steam:" + id] = String(name.prefix(80)) }
        }
        state.packages = Array(Set(tokens.filter(Packages.isSafe))).sorted()
        state.packageNames = names.isEmpty ? nil : names
        state.marketplaces = marketplaces.isEmpty ? nil : marketplaces
        state.packagesAt = now()
    }
}

public enum Packages {
    static let code = ["/usr/local/bin/code", "/opt/homebrew/bin/code", "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"]
    static let cursor = ["/usr/local/bin/cursor", "/opt/homebrew/bin/cursor", "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"]
    static let npm = ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"]
    static let uv = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", NSHomeDirectory() + "/.local/bin/uv"]
    static let claude = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", NSHomeDirectory() + "/.local/bin/claude",
                         NSHomeDirectory() + "/.claude/local/claude"]
    static let toolEnv = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
                          "NO_COLOR": "1", "HOMEBREW_NO_AUTO_UPDATE": "1"]

    public static let kinds: [(kind: String, label: String, symbol: String)] = [
        ("tap", "Homebrew taps", "mug"), ("vscode", "VS Code extensions", "puzzlepiece.extension"),
        ("cursor", "Cursor extensions", "puzzlepiece.extension"), ("npm", "npm packages", "shippingbox"),
        ("uv", "Python tools (uv)", "shippingbox"), ("claude-plugin", "Claude Code plugins", "sparkles"),
        ("steam", "Steam games", "gamecontroller"),
    ]

    public static func kind(_ token: String) -> String { String(token.prefix { $0 != ":" }) }
    public static func label(kind: String) -> String { kinds.first { $0.kind == kind }?.label ?? kind }

    static func isSafe(_ token: String) -> Bool {
        let kind = kind(token)
        let name = String(token.dropFirst(kind.count + 1))
        guard kinds.contains(where: { $0.kind == kind }), !name.isEmpty, !name.hasPrefix("-"), name.count < 200 else { return false }
        return name.range(of: "^[A-Za-z0-9@._/+-]+$", options: .regularExpression) != nil
    }

    static func canInstall(_ token: String, env: MacSyncEnvironment, locator: AppLocating) -> Bool {
        let fm = FileManager.default
        switch kind(token) {
        case "tap": return env.brewPath != nil
        case "vscode": return code.contains(where: fm.isExecutableFile)
        case "cursor": return cursor.contains(where: fm.isExecutableFile)
        case "npm": return npm.contains(where: fm.isExecutableFile)
        case "uv": return uv.contains(where: fm.isExecutableFile)
        case "claude-plugin": return claude.contains(where: fm.isExecutableFile)
        case "steam": return locator.path(forBundleID: "com.valvesoftware.steam") != nil
        default: return false
        }
    }

    static func install(_ token: String, env: MacSyncEnvironment, runner: CommandRunning, marketplaces: [String: String],
                        localMarketplaces: [String: String]) -> Result<Void, EngineError> {
        let fm = FileManager.default
        let name = String(token.dropFirst(kind(token).count + 1))
        func run(_ tools: [String], _ args: [String], env extra: [String: String] = toolEnv) -> Result<Void, EngineError> {
            guard let tool = tools.first(where: fm.isExecutableFile) else { return .failure(.refused("its tool isn't on this Mac")) }
            let result = runner.run(tool, args, input: nil, environment: extra)
            return result.status == 0 ? .success(()) : .failure(.refused(result.stderr.split(whereSeparator: \.isNewline).last.map(String.init) ?? "it didn't install"))
        }
        switch kind(token) {
        case "tap":
            guard let brew = env.brewPath else { return .failure(.refused("Homebrew isn't on this Mac")) }
            return run([brew], ["tap", name], env: InventoryReader.brewEnvironment(brew))
        case "vscode": return run(code, ["--install-extension", name])
        case "cursor": return run(cursor, ["--install-extension", name])
        case "npm": return run(npm, ["install", "-g", name])
        case "uv": return run(uv, ["tool", "install", name])
        case "claude-plugin":
            let market = name.split(separator: "@").last.map(String.init) ?? ""
            if localMarketplaces[market] == nil, let source = marketplaces[market], isSafe("tap:" + source) || source.hasPrefix("https://") {
                _ = run(claude, ["plugin", "marketplace", "add", source])
            }
            return run(claude, ["plugin", "install", name])
        case "steam":
            let result = runner.run("/usr/bin/open", ["steam://install/" + name], input: nil, environment: [:])
            return result.status == 0 ? .success(()) : .failure(.refused("Steam didn't open"))
        default: return .failure(.refused("unknown kind"))
        }
    }

    static func uninstall(_ token: String, env: MacSyncEnvironment, runner: CommandRunning) -> Result<Void, EngineError> {
        let fm = FileManager.default
        let name = String(token.dropFirst(kind(token).count + 1))
        func run(_ tools: [String], _ args: [String], env extra: [String: String] = toolEnv) -> Result<Void, EngineError> {
            guard let tool = tools.first(where: fm.isExecutableFile) else { return .failure(.refused("its tool isn't on this Mac")) }
            let result = runner.run(tool, args, input: nil, environment: extra)
            return result.status == 0 ? .success(()) : .failure(.refused(result.stderr.split(whereSeparator: \.isNewline).last.map(String.init) ?? "it wasn't removed"))
        }
        switch kind(token) {
        case "tap":
            guard let brew = env.brewPath else { return .failure(.refused("Homebrew isn't on this Mac")) }
            return run([brew], ["untap", name], env: InventoryReader.brewEnvironment(brew))
        case "vscode": return run(code, ["--uninstall-extension", name])
        case "cursor": return run(cursor, ["--uninstall-extension", name])
        case "npm": return run(npm, ["uninstall", "-g", name])
        case "uv": return run(uv, ["tool", "uninstall", name])
        case "claude-plugin": return run(claude, ["plugin", "uninstall", name])
        case "steam":
            let result = runner.run("/usr/bin/open", ["steam://uninstall/" + name], input: nil, environment: [:])
            return result.status == 0 ? .success(()) : .failure(.refused("Steam didn't open"))
        default: return .failure(.refused("unknown kind"))
        }
    }

    /// A value from Valve's key-value text ("appid"  "620").
    static func vdf(_ key: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\"\(key)\"\\s+\"([^\"]*)\"", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

// MARK: Signing in

/// Apps that need an account or a license after they are installed, and how to sign in.
public enum SignIn {
    static let hints: [(match: String, hint: String, first: Bool)] = [
        ("1password", "Sign in first: it can fill in the rest.", true),
        ("bitwarden", "Sign in first: it can fill in the rest.", true),
        ("dashlane", "Sign in first: it can fill in the rest.", true),
        ("whatsapp", "Scan the QR code with your phone.", false),
        ("telegram", "Enter your phone number, or scan the QR code with your phone.", false),
        ("signal", "Link it from Signal on your phone.", false),
        ("raycast", "Raycast keeps its data encrypted, so it can't be copied. On your other Mac use Settings → Advanced → Export, then Import it here.", false),
        ("microsoft", "Sign in with your Microsoft account to activate Office.", false),
        ("adobe", "Sign in to Creative Cloud.", false), ("photoshop", "Sign in to Creative Cloud.", false),
        ("chrome", "Sign in to Chrome to bring back bookmarks and passwords.", false),
        ("slack", "Sign in to each workspace.", false), ("discord", "Scan the QR code with your phone.", false),
        ("zoom", "Sign in.", false), ("spotify", "Sign in.", false), ("dropbox", "Sign in and choose what to sync.", false),
        ("google drive", "Sign in and choose what to sync.", false), ("notion", "Sign in.", false), ("figma", "Sign in.", false),
        ("steam", "Sign in; approve it in the Steam app on your phone.", false), ("chatgpt", "Sign in.", false),
        ("claude", "Sign in.", false), ("cursor", "Sign in.", false), ("arc", "Sign in to bring back your spaces.", false),
        ("nordvpn", "Sign in.", false), ("expressvpn", "Enter your activation code.", false), ("tailscale", "Sign in.", false),
        ("istat", "Enter your license from the Bjango email.", false), ("cleanshot", "Enter your license.", false),
        ("bartender", "Enter your license.", false), ("setapp", "Sign in to Setapp.", false), ("linear", "Sign in.", false),
        ("github desktop", "Sign in to GitHub.", false), ("docker", "Sign in to Docker Hub if you use it.", false),
    ]

    /// How to sign in to an app, if it is one that needs it.
    public static func hint(for name: String) -> String? {
        let lower = name.lowercased()
        return hints.first { lower.contains($0.match) }?.hint
    }

    /// Password managers go first, so they can fill in the rest.
    public static func goesFirst(_ name: String) -> Bool {
        let lower = name.lowercased()
        return hints.contains { $0.first && lower.contains($0.match) }
    }
}
