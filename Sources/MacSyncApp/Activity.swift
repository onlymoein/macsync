import AppKit
import Combine
import SwiftUI

// MARK: What MacSync is doing

extension AppModel {
    /// Anything running: the menu shows a bar for it and the menu bar icon turns.
    var isBusy: Bool {
        isSyncing || isApplying || upgrading || isUpdating || craftLoading || !work.isEmpty
            || !getting.isEmpty || !removing.isEmpty || !craftBusy.isEmpty || !extraBusy.isEmpty || !upgradeBusy.isEmpty
    }

    /// One line on what's happening, for under the bar.
    var busyLine: String? {
        guard isBusy else { return nil }
        if let job = activeWork { return job.line(at: Date()) }
        if let progress { return progress }
        if isApplying { return "Applying changes…" }
        if isUpdating { return updateMessage ?? "Updating MacSync…" }
        if !upgradeBusy.isEmpty { return "Updating with Homebrew…" }
        if upgrading { return "Looking for newer versions…" }
        if isSyncing { return "Syncing with your other Macs…" }
        if !removing.isEmpty { return "Removing…" }
        if craftLoading || !craftBusy.isEmpty { return "Working on ArtCraft apps…" }
        return "Working…"
    }
}

// MARK: The bar at the bottom of the menu

/// A thin bar along the menu's bottom edge while anything runs: it fills for an install with a
/// known number of items, and keeps moving for a sync or a check. Drawn over the menu, so it
/// never changes the menu's height.
struct ActivityBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.isBusy {
            Group {
                if let job = model.activeWork {
                    ProgressView(value: Double(min(job.done, job.total)), total: Double(max(job.total, 1)))
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .controlSize(.mini)
            .padding(.horizontal, 10).padding(.bottom, 3)
            .transition(.opacity)
            .accessibilityLabel(model.busyLine ?? "Working")
        }
    }
}

// MARK: The menu bar icon

/// Turns the menu bar icon while MacSync works. Kept apart from AppModel so ten frames a second
/// redraw only the icon, not the menu.
@MainActor
final class MenuBarSpinner: ObservableObject {
    @Published private(set) var angle: CGFloat = 0
    private var timer: Timer?
    private var watch: AnyCancellable?

    func follow(_ model: AppModel) {
        guard watch == nil else { return }
        // objectWillChange fires before the change lands, so look a moment later.
        watch = model.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak model] _ in
            guard let self, let model else { return }
            self.set(running: model.isBusy)
        }
        set(running: model.isBusy)
    }

    private func set(running: Bool) {
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if running && !still {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.angle = ((self?.angle ?? 0) - 30).truncatingRemainder(dividingBy: 360) }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if timer != nil {
            timer?.invalidate()
            timer = nil
            angle = 0
        }
    }

    /// The symbol, turned, as a template image so it takes the menu bar's colour.
    static func image(symbol: String, angle: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "MacSync")?.withSymbolConfiguration(config)
        else { return NSImage() }
        guard angle != 0 else { base.isTemplate = true; return base }
        let side = ceil(max(base.size.width, base.size.height))
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let context = NSGraphicsContext.current?.cgContext
            context?.translateBy(x: rect.midX, y: rect.midY)
            context?.rotate(by: angle * .pi / 180)
            base.draw(in: NSRect(x: -base.size.width / 2, y: -base.size.height / 2, width: base.size.width, height: base.size.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var spinner: MenuBarSpinner

    var body: some View {
        let symbol = model.isBusy ? "arrow.triangle.2.circlepath" : model.menuBarSymbol
        Image(nsImage: MenuBarSpinner.image(symbol: symbol, angle: spinner.angle))
            .accessibilityLabel(model.isBusy ? "MacSync, working" : "MacSync")
    }
}
