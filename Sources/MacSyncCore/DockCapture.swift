import Foundation

/// Finds where an item lives on this Mac.
public protocol AppLocating {
    func path(forBundleID bundleID: String) -> String?
    func exists(path: String) -> Bool
}

/// Converts the Dock's raw preferences into portable items, and back.
public enum DockCapture {
    static let cryptexPrefix = "/System/Volumes/Preboot/Cryptexes/App"
    static let secretParameter = try! NSRegularExpression(
        pattern: "(token|key|secret|pass|pwd|auth|session|sig|code)", options: [.caseInsensitive])

    public static func section(from raw: [String: Any], changedAt: Date, basedOn: String? = nil,
                               home: String = NSHomeDirectory()) -> DockSection {
        DockSection(
            changedAt: changedAt,
            basedOn: basedOn,
            apps: items(raw["persistent-apps"], home: home),
            others: items(raw["persistent-others"], home: home),
            tileSize: (raw["tilesize"] as? NSNumber)?.doubleValue,
            orientation: raw["orientation"] as? String ?? "bottom")
    }

    static func items(_ value: Any?, home: String) -> [DockItem] {
        (value as? [[String: Any]] ?? []).compactMap { item(from: $0, home: home) }
    }

    /// Unknown tile types return nil: they are left out of the snapshot, never guessed at.
    public static func item(from tile: [String: Any], home: String = NSHomeDirectory()) -> DockItem? {
        let type = tile["tile-type"] as? String ?? ""
        let data = tile["tile-data"] as? [String: Any] ?? [:]
        let label = data["file-label"] as? String ?? data["label"] as? String ?? ""
        switch type {
        case "spacer-tile", "small-spacer-tile", "flex-spacer-tile":
            return DockItem(kind: .spacer, label: "Spacer", spacerStyle: type)
        case "url-tile":
            guard let raw = data["url"] as? [String: Any], let string = raw["_CFURLString"] as? String else { return nil }
            return DockItem(kind: .url, label: label, url: scrub(url: string))
        case "file-tile":
            guard let path = path(from: data, home: home) else { return nil }
            if path.hasSuffix(".app") || data["bundle-identifier"] != nil {
                return DockItem(kind: .app, label: label, bundleID: data["bundle-identifier"] as? String, path: path)
            }
            return DockItem(kind: .file, label: label, path: path)
        case "directory-tile":
            guard let path = path(from: data, home: home) else { return nil }
            return DockItem(kind: .folder, label: label, path: path, folder: .init(
                arrangement: data["arrangement"] as? Int, displayAs: data["displayas"] as? Int,
                showAs: data["showas"] as? Int, preferredItemSize: data["preferreditemsize"] as? Int))
        default:
            return nil
        }
    }

    static func path(from data: [String: Any], home: String) -> String? {
        guard let fileData = data["file-data"] as? [String: Any],
              let string = fileData["_CFURLString"] as? String else { return nil }
        if let url = URL(string: string), url.isFileURL { return normalize(path: url.path, home: home) }
        return normalize(path: string, home: home)
    }

    public static func normalize(path: String, home: String = NSHomeDirectory()) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        if path.hasPrefix(cryptexPrefix + "/") { path.removeFirst(cryptexPrefix.count) }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    public static func expand(path: String, home: String = NSHomeDirectory()) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    /// Dock links can carry credentials. Strips logins and any secret-looking query parameter.
    public static func scrub(url string: String) -> String {
        guard var parts = URLComponents(string: string) else { return string }
        parts.user = nil
        parts.password = nil
        parts.fragment = nil
        if let query = parts.queryItems {
            let kept = query.filter { item in
                let range = NSRange(item.name.startIndex..., in: item.name)
                return secretParameter.firstMatch(in: item.name, range: range) == nil
            }
            parts.queryItems = kept.isEmpty ? nil : kept
        }
        return parts.string ?? string
    }

    /// Builds a brand-new tile for an item this Mac's Dock does not have yet.
    static func newTile(for item: DockItem, localPath: String?) -> [String: Any]? {
        let guid = Int.random(in: 1...Int(Int32.max))
        switch item.kind {
        case .spacer:
            return ["GUID": guid, "tile-type": item.spacerStyle ?? "spacer-tile", "tile-data": [String: Any]()]
        case .url:
            guard let url = item.url else { return nil }
            return ["GUID": guid, "tile-type": "url-tile",
                    "tile-data": ["label": item.label, "url": ["_CFURLString": url, "_CFURLStringType": 15]]]
        case .app, .file, .folder:
            guard let localPath else { return nil }
            let isFolder = item.kind == .folder
            var data: [String: Any] = [
                "file-label": item.label,
                "file-type": isFolder ? 2 : (item.kind == .app ? 41 : 32),
                "file-data": ["_CFURLString": URL(fileURLWithPath: localPath, isDirectory: item.kind != .file).absoluteString,
                              "_CFURLStringType": 15],
            ]
            if let bundleID = item.bundleID { data["bundle-identifier"] = bundleID }
            if isFolder { apply(item.folder, to: &data) }
            return ["GUID": guid, "tile-type": isFolder ? "directory-tile" : "file-tile", "tile-data": data]
        }
    }

    static func apply(_ options: DockItem.FolderOptions?, to data: inout [String: Any]) {
        guard let options else { return }
        data["arrangement"] = options.arrangement ?? data["arrangement"]
        data["displayas"] = options.displayAs ?? data["displayas"]
        data["showas"] = options.showAs ?? data["showas"]
        data["preferreditemsize"] = options.preferredItemSize ?? data["preferreditemsize"]
    }
}
