import Foundation

/// Calls back a few seconds after the Dock's settings file changes, so moving an icon is saved
/// to iCloud straight away instead of at the next timed sync.
///
/// The Dock's preferences are rewritten by replacing the file, which ends a watch on the file
/// itself, so this watches its folder and checks the file's modification date.
final class DockWatcher {
    private let file: URL
    private let delay: TimeInterval
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var lastModified: Date?
    private var pending: DispatchWorkItem?

    init(file: URL, delay: TimeInterval = 4, onChange: @escaping () -> Void) {
        self.file = file
        self.delay = delay
        self.onChange = onChange
        lastModified = modified()
        start()
    }

    deinit { source?.cancel(); fileSource?.cancel() }

    private func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    private func start() {
        let folder = file.deletingLastPathComponent().path
        let fd = open(folder, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .link], queue: .main)
        source.setEventHandler { [weak self] in self?.folderChanged() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        watchFile()
    }

    /// Also watches the file itself, for writes made in place. Re-armed whenever the file is replaced.
    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(file.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self else { return }
            if let flags = source?.data, !flags.isDisjoint(with: [.delete, .rename]) { self.watchFile() }
            self.folderChanged()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSource = source
    }

    private func folderChanged() {
        if fileSource == nil { watchFile() }
        guard let now = modified(), now != lastModified else { return }
        lastModified = now
        // A drag can write several times; wait until it settles, then sync once.
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
