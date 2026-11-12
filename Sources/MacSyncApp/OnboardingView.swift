import AppKit
import MacSyncCore
import SwiftUI
import UniformTypeIdentifiers

/// When the welcome window opens on its own.
enum Onboarding {
    static let seenKey = "onboardingSeen"
    /// "Not now" on moving: remembered for the place it was said, so it doesn't ask there again.
    static let keptAtKey = "onboardingKeptAt"

    /// The website's picture shows what someone who just downloaded MacSync sees.
    static var location: AppInstallLocation {
        ProcessInfo.processInfo.environment["MACSYNC_UI_PROBE"] != nil
            ? AppInstallLocation(appURL: URL(fileURLWithPath: NSHomeDirectory() + "/Downloads/MacSync.app"))
            : AppInstallLocation(appURL: Bundle.main.bundleURL)
    }

    /// The MacSync already in Applications, when this isn't it. The website's picture shows the Move button.
    static var otherCopy: String? {
        ProcessInfo.processInfo.environment["MACSYNC_UI_PROBE"] != nil ? nil : location.copyInApplications()
    }

    static var isNeeded: Bool {
        let defaults = UserDefaults.standard
        // Builds run from the project folder, and the copy that draws the website's pictures.
        guard Bundle.main.bundleURL.pathExtension == "app",
              ProcessInfo.processInfo.environment["MACSYNC_UI_PROBE"] == nil,
              !Bundle.main.bundleURL.path.contains("/build/") else { return false }
        if !location.isInApplications && defaults.string(forKey: keptAtKey) != Bundle.main.bundleURL.path { return true }
        guard defaults.object(forKey: seenKey) == nil else { return false }
        // Someone who used MacSync before this window existed has seen it all already.
        let usedBefore = defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("review.") || $0 == "relaunchedFor" }
        if usedBefore { defaults.set(true, forKey: seenKey) }
        return !usedBefore
    }
}

@MainActor
final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let host = NSHostingController(rootView: OnboardingView(model: model) { [weak self] in self?.close() })
            let window = NSWindow(contentViewController: host)
            window.title = "Welcome to MacSync"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        UserDefaults.standard.set(true, forKey: Onboarding.seenKey)
        window?.close()
    }
}

/// The welcome page: put MacSync in Applications, then pick which versions you get.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    let done: () -> Void

    @State private var location = Onboarding.location
    @State private var otherCopy = Onboarding.otherCopy
    @State private var dropTargeted = false
    @State private var moving = false
    @State private var problem: String?
    private let watch = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 14) {
                installCard
                channelCard
            }
            .padding(.horizontal, 28)
            footer
        }
        .frame(width: 560)
        .background(.background)
        // Dragged into Applications in Finder: the copy there shows up here.
        .onReceive(watch) { _ in otherCopy = Onboarding.otherCopy }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Welcome to MacSync").font(.title.weight(.semibold))
            Text("Your Dock, apps and settings, the same on every Mac, through your own iCloud Drive.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 34).padding(.bottom, 22).padding(.horizontal, 40)
    }

    // MARK: Applications

    private var installCard: some View {
        Card(number: 1, title: "Put MacSync in Applications", done: location.isInApplications) {
            if location.isInApplications {
                Text("MacSync is in Applications, so it stays put and keeps itself up to date.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(whereItIs).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    dragRow
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Color.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        if let version = otherCopy {
                            Button("Open the Copy in Applications") { openOther() }
                                .buttonStyle(.borderedProminent)
                                .help("MacSync \(version) is already in Applications: this copy quits and that one opens")
                        } else {
                            Button(moving ? "Moving…" : "Move to Applications") { moveIn() }
                                .buttonStyle(.borderedProminent).disabled(moving)
                        }
                        Button("Not Now") {
                            UserDefaults.standard.set(Bundle.main.bundleURL.path, forKey: Onboarding.keptAtKey)
                            problem = "MacSync works from here, but it can't update itself until it's in Applications."
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var whereItIs: String {
        if location.isOnDiskImage { return "MacSync is running from the disk image. Drag it onto Applications so it's still here after you eject it." }
        if location.isTranslocated { return "MacSync is running from where it was downloaded. Drag it onto Applications so it can update itself." }
        return "MacSync is running from your \(location.appURL.deletingLastPathComponent().lastPathComponent) folder. Drag it onto Applications so it can update itself."
    }

    /// The app icon, an arrow and the Applications folder: drag one onto the other, as in Finder.
    private var dragRow: some View {
        HStack(spacing: 18) {
            VStack(spacing: 4) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable().frame(width: 64, height: 64)
                    .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                    .help("Drag onto Applications, here or in Finder")
                Text("MacSync").font(.caption)
            }
            Image(systemName: "arrow.right").font(.title2.weight(.semibold)).foregroundStyle(.tertiary)
            VStack(spacing: 4) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: "/Applications"))
                    .resizable().frame(width: 64, height: 64)
                    .scaleEffect(dropTargeted ? 1.12 : 1)
                    .animation(.spring(response: 0.25), value: dropTargeted)
                    .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: NSURL.self) { item, _ in
                            let dropped = (item as? URL)?.standardizedFileURL
                            Task { @MainActor in
                                if dropped == Bundle.main.bundleURL.standardizedFileURL { moveIn() }
                            }
                        }
                        return true
                    }
                Text("Applications").font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35)))
    }

    private func moveIn() {
        guard !moving else { return }
        moving = true
        problem = nil
        let location = location
        Task { @MainActor in
            let result = await Blocking { location.move(runner: SystemCommandRunner()) }.value
            moving = false
            switch result {
            case .success(let url): reopen(at: url)
            case .failure(let error): problem = error.localizedDescription
            }
        }
    }

    private func openOther() { reopen(at: AppInstallLocation.destination) }

    /// Quits this copy and opens the one in Applications, which picks up where this left off.
    private func reopen(at url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", url.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: Channel

    private var channelCard: some View {
        Card(number: 2, title: "Choose which versions you get", done: false) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(UpdateChannel.allCases) { channel in
                    ChannelOption(channel: channel, selected: model.updateChannel == channel) { model.updateChannel = channel }
                }
                Text("Every version is signed with MacSync's Developer ID. Apple then checks each one for malware (notarization), which can take a while. Stable waits for that check. Change this any time in Settings.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("MacSync lives in the menu bar, at the top of the screen.", systemImage: "menubar.arrow.up.rectangle")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Get Started") { done() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 24)
    }
}

/// A numbered step.
private struct Card<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor).frame(width: 24, height: 24)
                if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
                else { Text("\(number)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.45)))
    }
}

private struct ChannelOption: View {
    let channel: UpdateChannel
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15)).foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: channel == .stable ? "checkmark.seal.fill" : "sparkles")
                            .foregroundStyle(channel == .stable ? Color.green : Color.orange)
                        Text(channel.title).font(.body.weight(.semibold))
                        if channel == .stable {
                            Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    Text(channel.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
