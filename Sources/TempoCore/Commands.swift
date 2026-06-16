import Foundation

/// Supplies the set of currently open windows. The real implementation drives the
/// Accessibility API; tests inject a fake.
public protocol WindowSource {
    func currentWindows() throws -> [WindowInfo]
}

/// Pure command logic for the CLI, written against injected dependencies so it is
/// testable without the Accessibility API or the real filesystem location.
public enum Commands {
    public static func queryWindows(source: WindowSource) throws -> String {
        let windows = try source.currentWindows()
        let data = try cliJSONEncoder().encode(windows)
        return String(decoding: data, as: UTF8.self)
    }

    public static func sceneFromPlacements(_ placements: [PlacedWindow],
                                           name: String,
                                           hideUnassigned: Bool = true) -> Scene {
        // First pass: collect every workspace each bundle appears on.
        var workspacesByBundle: [String: Set<WorkspaceID>] = [:]
        for placement in placements {
            workspacesByBundle[placement.window.bundleId, default: []].insert(placement.workspace)
        }

        // Second pass: a bundle on multiple workspaces needs title-based discrimination;
        // a bundle on one workspace can use the broader bundleId-only matcher.
        var assignments: [Assignment] = []
        var seen = Set<String>()
        for placement in placements {
            let bundleId = placement.window.bundleId
            let workspace = placement.workspace
            let multiWorkspace = (workspacesByBundle[bundleId]?.count ?? 0) > 1
            let match: WindowMatch
            let key: String
            if multiWorkspace {
                let title = placement.window.title
                if title.isEmpty { continue }
                let regex = NSRegularExpression.escapedPattern(for: title)
                match = WindowMatch(bundleId: bundleId, titleRegex: regex)
                key = "\(bundleId)\u{0}\(regex)\u{0}\(workspace)"
            } else {
                match = WindowMatch(bundleId: bundleId)
                key = "\(bundleId)\u{0}\(workspace)"
            }
            if seen.insert(key).inserted {
                assignments.append(Assignment(match: match, workspace: workspace))
            }
        }

        let sorted = assignments.sorted { a, b in
            if a.workspace != b.workspace { return a.workspace < b.workspace }
            let ab = a.match.bundleId ?? ""
            let bb = b.match.bundleId ?? ""
            if ab != bb { return ab < bb }
            return (a.match.titleRegex ?? "") < (b.match.titleRegex ?? "")
        }
        return Scene(name: name, assignments: sorted, hideUnassigned: hideUnassigned)
    }

    /// Snapshot the live daemon state (encoded by `Placements.encodeJSON`) into a saved Scene.
    /// Pure: I/O is delegated to the injected `SceneStore`.
    public static func sceneCreate(fromState data: Data,
                                   name: String,
                                   store: SceneStore) throws {
        let placements = try Placements.decodeJSON(data)
        try store.save(sceneFromPlacements(placements, name: name))
    }

    public static func renderScene(_ scene: Scene) -> String {
        var lines = ["Scene: \(scene.name)" + (scene.hideUnassigned ? " [hide unassigned]" : "")]
        let sorted = scene.assignments.sorted {
            ($0.workspace, $0.match.bundleId ?? "") < ($1.workspace, $1.match.bundleId ?? "")
        }
        for assignment in sorted {
            var parts: [String] = []
            if let bundleId = assignment.match.bundleId { parts.append(bundleId) }
            if let titleRegex = assignment.match.titleRegex { parts.append("~\(titleRegex)") }
            if assignment.float { parts.append("(float)") }
            lines.append("  [\(assignment.workspace)] " + parts.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    public static func sceneList(store: SceneStore, json: Bool) throws -> String {
        let names = try store.list()
        if json {
            let data = try cliJSONEncoder().encode(names)
            return String(decoding: data, as: UTF8.self)
        }
        return names.joined(separator: "\n")
    }

    public static func sceneShow(store: SceneStore, name: String) throws -> String {
        let scene = try store.load(name)
        return String(decoding: try scene.encodedJSON(), as: UTF8.self)
    }
}

/// JSON encoder used for CLI `--json` output: pretty and stable.
func cliJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}
