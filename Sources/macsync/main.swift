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
      --no-settings          Leave settings alone (Pro)
      --install a,b          Also install these (e.g. cask:ghostty,formula:jq,mas:497799835)
      --all-apps             Also install everything your other Macs have
  macsync undo [--yes]       Undo the last apply
  macsync app-prefs [add|remove <domain>]   Choose apps whose preferences sync (Pro)
  macsync upgrade            Update every Homebrew app and tool, npm package and uv tool (open apps wait)
  macsync outdated           List Homebrew apps and tools, npm packages and uv tools with newer versions
  macsync files              List the config files, AI setup and app data this Mac shares, and what it keeps back
  macsync restore-points     List saved restore points
  macsync restore <id>       Go back to just before that restore point

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

let known: Set<String> = ["--json", "--yes", "--no-dock", "--no-settings", "--install", "--all-apps"]
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
        let applySettings = !flags.contains("--no-settings")
        guard (applyDock && overview.dockPlan != nil) || (applySettings && overview.settingsPlan != nil) || !apps.isEmpty else {
            if json { try printJSON(ApplyReportEmpty()) } else if !overview.missingApps.isEmpty {
                print("\nNothing selected. Use --install or --all-apps to install apps.")
            }
            exit(0)
        }
        confirm("Apply these changes? A restore point is saved first.", assumeYes: yes)
        let report = try engine.apply(ApplyRequest(applyDock: applyDock, apps: apps, applySettings: applySettings)) { message in
            if !json { print(message) }
        }
        if json {
            try printJSON(report)
        } else {
            for result in report.results {
                print("\(result.app.token): \(result.outcome.rawValue)\(result.message.map { " (\($0))" } ?? "")")
            }
            print(report.dockChanged ? "Dock updated. Run `macsync undo` to go back." : "Dock not changed.")
            if report.settingsChanged { print("Settings updated. Run `macsync undo` to go back.") }
            if let error = report.settingsError { print("Settings: \(error)") }
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
            print("Restored.")
            if !undone.installed.isEmpty {
                print("These stay installed. Remove them yourself if you want: " + undone.installed.joined(separator: ", "))
            }
        }
    case "app-prefs":
        guard engine.proEnabledForCLI else { fail("App preferences are a Pro feature.") }
        let words = arguments.dropFirst().filter { !$0.hasPrefix("--") }
        var chosen = engine.appPrefDomains()
        if words.first == "add", words.count == 2 {
            chosen.append(words[1])
            try engine.setAppPrefDomains(chosen)
        } else if words.first == "remove", words.count == 2 {
            try engine.setAppPrefDomains(chosen.filter { $0 != words[1] })
        } else if !words.isEmpty {
            fail("Usage: macsync app-prefs [add|remove <domain>]", code: 2)
        }
        let now = engine.appPrefDomains()
        if json { try printJSON(now) } else {
            print(now.isEmpty ? "No apps chosen yet. Try: macsync app-prefs add com.raycast.macos" : "Syncing preferences of: " + now.joined(separator: ", "))
            if words.isEmpty { print("Available on this Mac: \(engine.availableAppPrefDomains().count). Passwords, tokens and keys are never synced.") }
        }
    case "upgrade":
        let report = engine.upgrader.upgradeAll { message in print(message) }
        if json { try printJSON(report) } else {
            print(report.summary)
            for item in report.waiting { print("Waiting until you quit it: \(item.name)") }
            for failure in report.failures { print("Didn't update: \(failure)") }
        }
    case "outdated":
        let report = engine.upgrader.check()
        let items = report.outdated ?? []
        if json { try printJSON(items) } else if items.isEmpty { print("Everything is up to date.") } else {
            for item in items { print("\(item.name): \(item.from) → \(item.to)  (\(item.token))") }
        }
    case "files":
        let scan = engine.scanFiles()
        if json { try printJSON(["shared": scan.shared.map(\.path), "kept": scan.kept.map { "\($0.path): \($0.reason)" }]) } else {
            for (group, files) in Dictionary(grouping: scan.shared, by: \.group).sorted(by: { $0.key < $1.key }) {
                print("\(group) (\(files.count))")
                for file in files.prefix(12) { print("  \(file.path)\(file.localOnly ? "  [kept to this Mac]" : "")") }
                if files.count > 12 { print("  … and \(files.count - 12) more") }
            }
            if !scan.kept.isEmpty {
                print("\nKept on this Mac:")
                for file in scan.kept { print("  \(file.path): \(file.reason)") }
            }
        }
    case "restore-points":
        let points = engine.restorePoints()
        if json { try printJSON(points) } else if points.isEmpty { print("No restore points yet.") } else {
            for point in points {
                print("\(point.id)  \(point.createdAt): \(point.summary) from \(point.sourceMachine)\(point.undoneAt == nil ? "" : " (undone)")")
            }
        }
    case "restore":
        guard let id = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else {
            fail("Say which restore point: macsync restore <id> (see macsync restore-points).", code: 2)
        }
        let point = try engine.restore(id)
        print("Back to how this Mac was before \(point.createdAt).")
    default:
        fail("Unknown command \(command).\n\n\(usage)", code: 2)
    }
} catch {
    fail(error.localizedDescription)
}

struct ApplyReportEmpty: Encodable { var dockChanged = false }
