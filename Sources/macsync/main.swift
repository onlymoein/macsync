import Foundation
import MacSyncCore

let usage = """
macsync \(MacSyncEnvironment.appVersion): keep your Macs set up the same way.

  macsync status             Show each Mac and whether it's in sync
  macsync sync               Save this Mac's setup and check the others (changes nothing here)
  macsync preview            Show what applying would change
  macsync apply              Apply, after showing the preview and asking
      --yes                  Don't ask (required when not run from a terminal)
      --no-dock              Leave the Dock alone
      --install a,b          Also install these (e.g. cask:ghostty,formula:jq,mas:497799835)
      --all-apps             Also install everything your other Macs have
  macsync undo [--yes]       Undo the last apply
  macsync restore-points     List saved restore points

Add --json to status, sync, preview, apply or undo for machine-readable output.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

func confirm(_ question: String, assumeYes: Bool) {
    if assumeYes { return }
    guard isatty(STDIN_FILENO) == 1 else { fail("Refusing to change this Mac without --yes.", code: 2) }
    print("\(question) [y/N] ", terminator: "")
    guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
        print("Nothing changed.")
        exit(0)
    }
}

func printStatus(_ overview: SyncOverview) {
    let formatter = RelativeDateTimeFormatter()
    if !overview.iCloudAvailable { print("iCloud Drive isn't available.") }
    for machine in overview.machines {
        let state = machine.isLayoutSource ? "latest layout" : (machine.dockMatchesSource ? "in sync" : "behind")
        let name = machine.name + (machine.isThisMac ? " (this Mac)" : "")
        print("\(name): \(state), \(machine.dockItemCount) Dock items, \(machine.appCount) apps, saved \(formatter.localizedString(for: machine.savedAt, relativeTo: Date()))")
    }
    for issue in overview.issues { print("Note: \(issue)") }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "status"
let flags = Set(arguments.dropFirst().filter { $0.hasPrefix("--") })
let json = flags.contains("--json")
let yes = flags.contains("--yes")

let known: Set<String> = ["--json", "--yes", "--no-dock", "--install", "--all-apps"]
if let unknown = flags.first(where: { !known.contains($0) }) { fail("Unknown option \(unknown).\n\n\(usage)", code: 2) }

do {
    let engine = Engine.live()
    switch command {
    case "help", "--help", "-h":
        print(usage)
    case "version", "--version":
        print(MacSyncEnvironment.appVersion)
    case "status", "sync", "push":
        let overview = try engine.sync()
        if json { try printJSON(overview) } else { printStatus(overview) }
    case "preview":
        let overview = try engine.sync()
        if json { try printJSON(overview) } else { print(PreviewText.render(overview)) }
    case "apply", "pull":
        let overview = try engine.sync()
        var tokens = Set<String>()
        if let index = arguments.firstIndex(of: "--install"), index + 1 < arguments.count {
            tokens = Set(arguments[index + 1].split(separator: ",").map(String.init))
        }
        let known = Dictionary(uniqueKeysWithValues: overview.missingApps.map { ($0.app.token, $0.app) })
        if let bad = tokens.first(where: { known[$0] == nil }) {
            fail("\(bad) isn't on your other Macs, or is already here. Run `macsync preview` to see what can be installed.", code: 2)
        }
        let apps = flags.contains("--all-apps") ? overview.missingApps.map(\.app) : tokens.compactMap { known[$0] }.sorted()
        let applyDock = !flags.contains("--no-dock")
        if !json {
            print(PreviewText.render(overview))
            if !apps.isEmpty { print("Will install: " + apps.map(\.token).joined(separator: ", ")) }
        }
        guard (applyDock && overview.dockPlan != nil) || !apps.isEmpty else {
            if json { try printJSON(ApplyReportEmpty()) } else if !overview.missingApps.isEmpty {
                print("\nNothing selected. Use --install or --all-apps to install apps.")
            }
            exit(0)
        }
        confirm("Apply these changes? A restore point is saved first.", assumeYes: yes)
        let report = try engine.apply(ApplyRequest(applyDock: applyDock, apps: apps)) { message in
            if !json { print(message) }
        }
        if json {
            try printJSON(report)
        } else {
            for result in report.results {
                print("\(result.app.token): \(result.outcome.rawValue)\(result.message.map { " (\($0))" } ?? "")")
            }
            print(report.dockChanged ? "Dock updated. Run `macsync undo` to go back." : "Dock not changed.")
        }
        if report.hasFailures { exit(1) }
    case "undo":
        guard let point = engine.restorePoints().first(where: { $0.undoneAt == nil }) else { throw EngineError.nothingToUndo }
        if !json { print("Undo: \(point.summary), from \(point.sourceMachine).") }
        confirm("Put the Dock back as it was?", assumeYes: yes)
        let undone = try engine.undoLast()
        if json {
            try printJSON(undone)
        } else {
            print("Dock restored.")
            if !undone.installed.isEmpty {
                print("These stay installed. Remove them yourself if you want: " + undone.installed.joined(separator: ", "))
            }
        }
    case "restore-points":
        let points = engine.restorePoints()
        if json { try printJSON(points) } else if points.isEmpty { print("No restore points yet.") } else {
            for point in points {
                print("\(point.createdAt): \(point.summary) from \(point.sourceMachine)\(point.undoneAt == nil ? "" : " (undone)")")
            }
        }
    default:
        fail("Unknown command \(command).\n\n\(usage)", code: 2)
    }
} catch {
    fail(error.localizedDescription)
}

struct ApplyReportEmpty: Encodable { var dockChanged = false }
