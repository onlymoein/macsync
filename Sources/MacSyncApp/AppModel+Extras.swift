import AppKit
import MacSyncCore

/// An app to sign in to, with how.
struct SignInItem: Codable, Equatable, Identifiable {
    var name: String
    var bundleID: String?
    var hint: String
    var id: String { bundleID ?? name }

    /// v2: only apps MacSync itself installed. The first list also held every app on the Mac.
    static let key = "signIn.queue.v2"
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
        // Not while apps install: both need Homebrew, which does one job at a time.
        guard !upgrading, !isApplying, getting.isEmpty, craftBusy.isEmpty, engine.upgrader.isDue() else { return }
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
        let ids = Dictionary(items.map { ($0.name, $0.token) }, uniquingKeysWith: { a, _ in a })
        work["brew"] = WorkProgress(verb: "Updating with Homebrew", names: items.map(\.name))
        Task {
            let report = await Task.detached { upgrader.upgrade(items) { message in
                Task { @MainActor [weak self] in self?.advance("brew", message: message, ids: ids) }
            } }.value
            work["brew"] = nil
            workCurrent["brew"] = nil
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

    /// After MacSync installs an app that needs an account, it's listed so you can sign in.
    func addToSignIn(name: String, bundleID: String?) {
        let lower = name.lowercased()
        // Helpers and command-line parts of an app (1Password CLI, 1Password for Safari) sign in through the app.
        guard !["cli", "for safari", "helper", "extension", "code"].contains(where: { lower.hasSuffix($0) }),
              let hint = SignIn.hint(for: name) ?? bundleID.flatMap({ SignIn.hint(for: $0) }),
              !signInQueue.contains(where: { $0.name == name }) else { return }
        signInQueue.append(SignInItem(name: name, bundleID: bundleID, hint: hint))
        sortSignIn()
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


/// How far a long job has got.
struct WorkProgress: Equatable {
    var verb: String
    var names: [String]
    var done = 0
    var failed = 0
    var current: String?
    /// What's happening to the current item ("Downloading AniCraft… 40%").
    var status: String?
    /// When the current item started, so a slow one shows it's still going.
    var since = Date()
    var total: Int { names.count }
    var next: String? {
        guard let current, let i = names.firstIndex(of: current), i + 1 < names.count else { return nil }
        return names[i + 1]
    }
    var line: String {
        let step = min(done + 1, max(total, 1))
        var text = total > 1 ? "\(verb): \(step) of \(total)" : verb
        if let status { text += " · " + status.replacingOccurrences(of: "…", with: "") }
        else if let current { text += " · \(current)" }
        if let next { text += " · next: \(next)" }
        if failed > 0 { text += " · \(failed) failed" }
        return text
    }

    /// The line, with how long the current item has taken once it's been a while.
    func line(at now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(since))
        guard seconds >= 20 else { return line }
        return line + (seconds < 60 ? " · \(seconds)s" : " · \(seconds / 60) min")
    }
}

extension AppModel {
    /// A job's progress message ("Installing AniCraft…") moves its bar to that item.
    func advance(_ job: String, message: String, ids: [String: String]) {
        guard var w = work[job] else { return }
        let name = w.names.first { message.contains($0) }
        if let name, let index = w.names.firstIndex(of: name) {
            if w.current != name { w.since = Date() }
            w.done = index
            w.current = name
            workCurrent[job] = ids[name]
        }
        w.status = message
        work[job] = w
        progress = message
    }

    /// One ArtCraft app is done: its row shows Installed or why not straight away.
    func craftFinished(_ app: CraftApp, _ result: Result<String, EngineError>) {
        craftBusy.remove(app.id)
        if case .failure(let error) = result {
            craftErrors[app.id] = error.localizedDescription
            work["craft"]?.failed += 1
        }
        if let index = work["craft"]?.names.firstIndex(of: app.name) { work["craft"]?.done = index + 1 }
        if workCurrent["craft"] == app.id { workCurrent["craft"] = nil; work["craft"]?.status = nil }
        loadCraft()
    }

    /// The job to show in the footer: installs first.
    var activeWork: WorkProgress? {
        for key in ["get", "craft", "remove", "craftRemove", "brew"] { if let w = work[key] { return w } }
        return nil
    }

    /// Where ArtCraft apps go: the folder picked here, else ArtCraft Launcher's own.
    var craftFolder: URL {
        if let path = UserDefaults.standard.string(forKey: "craft.folder") { return URL(fileURLWithPath: path) }
        return engine.craftInstallFolder()
    }

    /// Asks where ArtCraft apps go. True when a folder was picked.
    @discardableResult
    func chooseCraftFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = craftFolder.deletingLastPathComponent()
        panel.prompt = "Install Here"
        panel.message = "Choose where ArtCraft apps go. ArtCraft Launcher looks in this folder too."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        UserDefaults.standard.set(url.path, forKey: "craft.folder")
        objectWillChange.send()
        return true
    }

    /// The current ArtCraft download's percentage, while it's downloading.
    var craftPercent: Int? {
        guard let status = work["craft"]?.status, status.hasPrefix("Downloading"),
              let range = status.range(of: "\\d+(?=%)", options: .regularExpression) else { return nil }
        return Int(status[range])
    }

    /// Whether this row's item is queued but not started yet.
    func isWaiting(_ job: String, _ id: String) -> Bool { work[job] != nil && workCurrent[job] != id }
}
