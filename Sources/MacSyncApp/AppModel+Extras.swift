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

    // MARK: Keeping apps and tools up to date

    /// Runs on open and after a sync, at most every six hours.
    func upgradeIfDue() {
        if upgradeReport == nil { upgradeReport = engine.upgrader.lastReport() }
        guard !upgrading, !isApplying, engine.upgrader.isDue() else { return }
        if autoUpgrade { upgradeAll() } else { checkUpgrades() }
    }

    /// Looks for newer versions and lists them, without installing anything.
    func checkUpgrades() {
        guard !upgrading else { return }
        upgrading = true
        let upgrader = engine.upgrader
        Task {
            let report = await Task.detached { upgrader.check() }.value
            upgrading = false
            upgradeReport = report
        }
    }

    /// Updates the ones listed (all of them, or one row).
    func upgrade(_ items: [OutdatedItem]) {
        guard !upgrading, !items.isEmpty else { return }
        upgrading = true
        for item in items { upgradeBusy.insert(item.token) }
        let upgrader = engine.upgrader
        Task {
            let report = await Task.detached { upgrader.upgrade(items) { message in
                Task { @MainActor [weak self] in self?.progress = message }
            } }.value
            for item in items { upgradeBusy.remove(item.token) }
            upgrading = false
            progress = nil
            upgradeReport = report
            if !report.upgraded.isEmpty { runSync(refreshInventory: true) }
        }
    }

    func upgradeAll() {
        guard !upgrading else { return }
        upgrading = true
        let upgrader = engine.upgrader
        Task {
            let report = await Task.detached { upgrader.upgradeAll { message in
                Task { @MainActor [weak self] in self?.progress = message }
            } }.value
            upgrading = false
            progress = nil
            upgradeReport = report
            if !report.upgraded.isEmpty { runSync(refreshInventory: true) }
        }
    }

    /// Quits an open app, updates it, and opens it again.
    func upgradeNow(_ item: OutdatedItem) {
        guard !upgradeBusy.contains(item.token) else { return }
        upgradeBusy.insert(item.token)
        let upgrader = engine.upgrader
        Task {
            let result = await Task.detached { upgrader.upgradeNow(item) }.value
            upgradeBusy.remove(item.token)
            upgradeReport = upgrader.lastReport()
            if case .failure(let error) = result { upgradeReport?.failures.append("\(item.name): \(error.localizedDescription)") }
        }
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

// MARK: Sharing a setup

extension AppModel {
    /// Writes a .macsync file with the chosen sections, then saves it or hands it to the share menu.
    func makeSetupFile(name: String, sections: Set<ShareSection>) async -> Result<URL, Error> {
        let engine = engine
        return await Task.detached {
            Result {
                let data = try engine.exportSetup(name: name, sections: sections)
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacSync Share", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let safe = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
                let url = folder.appendingPathComponent("\(safe.isEmpty ? "My" : safe + "'s") MacSync setup.macsync")
                try data.write(to: url, options: .atomic)
                return url
            }
        }.value
    }

    func openSharedSetup(_ url: URL) {
        let engine = engine
        Task {
            let result = await Task.detached { Result { try engine.importSetup(try Data(contentsOf: url)) } }.value
            switch result {
            case .success(let info):
                importedSetups = engine.importedSetups()
                actionError = nil
                undoMessage = "\(info.name) is ready. Pick what you want from it, then press Apply."
            case .failure(let error):
                actionError = error.localizedDescription
            }
            runSync(refreshInventory: false)
            ReviewWindow.shared.show(model: self)
        }
    }

    func chooseSharedSetup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "macsync") ?? .data]
        panel.message = "Choose a MacSync setup someone shared with you"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { openSharedSetup(url) }
    }

    func removeImportedSetup(_ setup: ImportedSetup) {
        let engine = engine
        Task {
            _ = await Task.detached { try? engine.removeImportedSetup(setup.id) }.value
            importedSetups = engine.importedSetups()
            runSync(refreshInventory: false)
        }
    }
}
