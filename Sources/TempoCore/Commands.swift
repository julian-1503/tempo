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
}

/// JSON encoder used for CLI `--json` output: pretty and stable.
func cliJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}
