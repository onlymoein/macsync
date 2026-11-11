import AppKit
import MacSyncCore

/// An app to sign in to, with how.
struct SignInItem: Codable, Equatable, Identifiable {
    var name: String
    var bundleID: String?
    var hint: String
    var id: String { bundleID ?? name }

    static let key = "signIn.queue"
    static func load() -> [SignInItem] {
        (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([SignInItem].self, from: $0) } ?? []
    }
    static func save(_ items: [SignInItem]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key)
    }
}

extension AppModel {
    // MARK: Files, login items, packages

    func removeExtra(_ token: String, name: String, everywhere: Bool) {
        guard !extraBusy.contains(token) else { return }
        extraBusy.insert(token)
        extraErrors[token] = nil
        let engine = engine
        Task {
            let result = await Task.detached { engine.removeExtra(token, name: name, everywhere: everywhere) }.value
            extraBusy.remove(token)
            if case .failure(let error) = result { extraErrors[token] = error.localizedDescription }
            // Taken off this Mac only: stop offering it here too.
            else if !everywhere && !token.hasPrefix("file:") { _ = await Task.detached { try? engine.setSkipped([token], true) }.value }
            runSync(refreshInventory: false)
        }
    }

    func keepExtraHere(_ token: String) {
        let engine = engine
        Task { _ = await Task.detached { try? engine.keepExtraHere(token) }.value; runSync(refreshInventory: false) }
    }

    func cancelExtraRemoval(_ token: String) {
        let engine = engine
        Task { _ = await Task.detached { try? engine.cancelExtraRemoval(token) }.value; runSync(refreshInventory: false) }
    }

    func setFilesLocalOnly(_ paths: [String], _ localOnly: Bool) {
        let engine = engine
        Task { _ = await Task.detached { try? engine.setFilesLocalOnly(paths, localOnly) }.value; runSync(refreshInventory: false) }
    }

    // MARK: Signing in

    func addToSignIn(name: String, bundleID: String?) {
        guard let hint = SignIn.hint(for: name) ?? bundleID.flatMap({ SignIn.hint(for: $0) }),
              !signInQueue.contains(where: { $0.name == name }) else { return }
        signInQueue.append(SignInItem(name: name, bundleID: bundleID, hint: hint))
        sortSignIn()
    }

    /// Adds every app on this Mac that needs signing in to.
    func findAppsToSignIn() {
        for app in overview?.installedApps ?? [] { addToSignIn(name: app.displayName, bundleID: app.detail?.bundleID) }
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []) where name.hasSuffix(".app") {
            let path = "/Applications/" + name
            let bundle = Bundle(path: path)?.bundleIdentifier
            if bundle?.hasPrefix("com.apple.") == true { continue }
            addToSignIn(name: String(name.dropLast(4)), bundleID: bundle)
        }
    }

    func signInDone(_ item: SignInItem) {
        signInQueue.removeAll { $0.id == item.id }
        SignInItem.save(signInQueue)
    }

    func openForSignIn(_ item: SignInItem) {
        if let id = item.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/\(item.name).app"))
        }
    }

    private func sortSignIn() {
        signInQueue.sort { (SignIn.goesFirst($0.name) ? 0 : 1, $0.name) < (SignIn.goesFirst($1.name) ? 0 : 1, $1.name) }
        SignInItem.save(signInQueue)
    }

    func icon(forApp bundleID: String?) -> NSImage? {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
