import Foundation

/// Where this copy of MacSync runs from, and moving it into Applications.
///
/// An app opened straight from Downloads or a disk image keeps working, but macOS may run it from
/// a hidden, read-only copy (App Translocation), it can't update itself there, and it is gone
/// when the disk image is ejected. In Applications it stays put and can update itself.
public struct AppInstallLocation: Equatable {
    public let appURL: URL
    public let home: String

    public init(appURL: URL, home: String = NSHomeDirectory()) {
        self.appURL = appURL.standardizedFileURL
        self.home = home
    }

    /// /Applications or ~/Applications.
    public static func folders(home: String) -> [String] { ["/Applications", home + "/Applications"] }

    public var isInApplications: Bool {
        let parent = appURL.deletingLastPathComponent().path
        return Self.folders(home: home).contains(parent)
    }

    /// macOS is running a hidden copy because the app was opened where it was downloaded.
    public var isTranslocated: Bool { appURL.path.contains("/AppTranslocation/") }

    /// Opened from a mounted disk image.
    public var isOnDiskImage: Bool { appURL.path.hasPrefix("/Volumes/") }

    /// Where the copy goes.
    public static let destination = URL(fileURLWithPath: "/Applications/MacSync.app")

    /// The version of the MacSync already in Applications, if there is one and it isn't this copy.
    public func copyInApplications(fileManager: FileManager = .default) -> String? {
        let dest = Self.destination
        guard dest.standardizedFileURL != appURL, fileManager.fileExists(atPath: dest.path) else { return nil }
        let info = NSDictionary(contentsOf: dest.appendingPathComponent("Contents/Info.plist"))
        return info?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Copies this app into `destination`, putting any older copy there in the Trash first, then
    /// puts the copy it came from in the Trash when that is an ordinary file the person can move
    /// (not a disk image, and not macOS's hidden translocated copy).
    @discardableResult
    public func move(to destination: URL = AppInstallLocation.destination, runner: CommandRunning,
                     fileManager: FileManager = .default) -> Result<URL, EngineError> {
        guard destination.standardizedFileURL != appURL else { return .success(destination) }
        if fileManager.fileExists(atPath: destination.path) {
            do { try fileManager.trashItem(at: destination, resultingItemURL: nil) } catch {
                return .failure(.refused("The MacSync already in Applications couldn't be replaced. Drag it to the Trash, then try again."))
            }
        }
        let copy = runner.run("/usr/bin/ditto", [appURL.path, destination.path], input: nil, environment: [:])
        guard copy.status == 0, fileManager.fileExists(atPath: destination.appendingPathComponent("Contents/Info.plist").path) else {
            return .failure(.refused("MacSync couldn't copy itself into Applications. Drag it there in Finder instead."))
        }
        if !isTranslocated && !isOnDiskImage {
            try? fileManager.trashItem(at: appURL, resultingItemURL: nil)
        }
        return .success(destination)
    }
}
