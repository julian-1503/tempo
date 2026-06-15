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
