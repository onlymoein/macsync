import Foundation

/// The same preview in words, for the CLI and Raycast.
public enum PreviewText {
    public static func render(_ overview: SyncOverview) -> String {
        var lines: [String] = []
        if let plan = overview.dockPlan {
            lines.append("Dock, from \(plan.sourceMachine):")
            for item in plan.added { lines.append("  + add \(item.label)") }
            for item in plan.removed { lines.append("  - remove \(item.label)") }
            for item in plan.moved { lines.append("  ~ move \(item.label)") }
            if let change = plan.tileSizeChange { lines.append("  ~ size \(format(change.from)) to \(format(change.to))") }
            if let change = plan.orientationChange { lines.append("  ~ position \(change.from ?? "bottom") to \(change.to)") }
            for item in plan.folderOptionsChanged { lines.append("  ~ folder style of \(item.label)") }
        }
        if !overview.dockMissing.isEmpty {
            lines.append("Left out of the Dock, not on this Mac: " + overview.dockMissing.map(\.label).joined(separator: ", "))
        }
        if !overview.missingApps.isEmpty {
            lines.append("Apps on your other Macs, not on this one:")
            for missing in overview.missingApps {
                lines.append("  \(missing.app.token)  \(missing.app.name)  (\(missing.fromMachines.joined(separator: ", ")))")
            }
        }
        if lines.isEmpty { lines.append("Nothing to change. This Mac matches your other Macs.") }
        return lines.joined(separator: "\n")
    }

    static func format(_ value: Double?) -> String { value.map { String(format: "%g", $0) } ?? "default" }
}
