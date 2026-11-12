import Foundation
import MacSyncCore

/// Catches each disk image ArtCraft Launcher downloads before it deletes it, and once an hour
/// lets Homebrew catch its records up from them (see CraftRecords). Nothing here downloads.
@MainActor
final class CraftRecordsWatch {
    static let shared = CraftRecordsWatch()
    private var source: DispatchSourceFileSystemObject?
    private var retry: Timer?
    private var hourly: Timer?
    private let queue = DispatchQueue(label: "macsync.craft-records")
    private var records: CraftRecords?

    func start(env: MacSyncEnvironment) {
        guard records == nil, env.dockFile == nil, env.brewPath != nil else { return }
        let records = CraftRecords(env: env, runner: SystemCommandRunner())
        self.records = records
        watch()
        queue.async { records.catchDownloads() }
        // Homebrew's casks trail ArtCraft's releases by up to a few hours; once an hour finds them soon after.
        hourly = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in self?.reconcile() }
    }

    private func reconcile() {
        guard let records else { return }
        queue.async { _ = records.reconcile(refreshHomebrew: true) }
    }

    /// Watches the launcher's downloads folder; until it exists, looks again every minute.
    private func watch() {
        guard let records, source == nil else { return }
        let fd = open(records.watchedFolder.path, O_EVTONLY)
        guard fd >= 0 else {
            retry?.invalidate()
            retry = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in Task { @MainActor in self?.watch() } }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in
            let event = source.data
            records.catchDownloads()
            // The folder itself was removed or moved: start over.
            if event.contains(.delete) || event.contains(.rename) {
                source.cancel()
                Task { @MainActor in self?.source = nil; self?.watch() }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }
}
