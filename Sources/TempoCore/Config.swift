import Foundation

/// Daemon-side static config (see CONTEXT.md). Hand-edited TOML at
/// `$TEMPO_HOME/tempo.toml`.
public struct Config: Equatable, Sendable {
    /// Workspace that's active when the daemon starts.
    public var defaultWorkspace: String?
    /// Workspaces shown in the menu bar's "Switch Workspace" submenu. Chord
    /// bindings (alt+key / alt+shift+key) still work for any 1–9/A–Z label
    /// regardless of this list — this is purely a menu-curation knob, à la
    /// AeroSpace's `workspace-to-monitor-force-assignment` list.
    public var workspaces: [WorkspaceID]

    public init(defaultWorkspace: String? = nil,
                workspaces: [WorkspaceID] = []) {
        self.defaultWorkspace = defaultWorkspace
        self.workspaces = workspaces
    }
}

public enum ConfigParseError: Error, Equatable {
    case syntax(line: Int, reason: String)
}

/// Parser for the TOML subset Tempo uses today. Supported syntax:
/// - line comments starting with `#`
/// - `[section]` headers
/// - `key = "string"`
/// - `key = ["string", "string"]` (single- or multi-line arrays; trailing comma OK)
/// Unknown sections and keys are tolerated for forward-compat. Anything outside
/// this subset (nested tables, booleans, datetimes) is out of scope and will
/// either be ignored (unknown keys) or throw a syntax error.
public enum ConfigParser {
    public static func parse(_ source: String) throws -> Config {
        var config = Config()
        var section: String?
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < lines.count {
            let lineNo = i + 1
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            i += 1
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                guard line.hasSuffix("]") else {
                    throw ConfigParseError.syntax(line: lineNo, reason: "unclosed section header")
                }
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let eq = line.firstIndex(of: "=") else {
                throw ConfigParseError.syntax(line: lineNo, reason: "expected `key = value`")
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            // Multi-line array: gather subsequent lines until the matching `]`.
            if value.hasPrefix("[") && !value.hasSuffix("]") {
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    i += 1
                    let trimmedNext = next.split(separator: "#").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                    value += " " + trimmedNext
                    if trimmedNext.hasSuffix("]") { break }
                }
            }
            switch section {
            case "daemon":
                switch key {
                case "default_workspace":
                    config.defaultWorkspace = try parseString(value, line: lineNo)
                case "workspaces":
                    let raw = try parseStringArray(value, line: lineNo)
                    // H/J/K/L are tile-nav chords; F is the fullscreen chord (alt+shift+f).
                    // None of them can be workspace labels. Silently drop them if listed.
                    let reserved: Set<String> = ["F", "H", "J", "K", "L"]
                    config.workspaces = raw.filter { !reserved.contains($0.uppercased()) }
                default: continue
                }
            default: continue
            }
        }
        return config
    }

    private static func parseString(_ raw: String, line: Int) throws -> String {
        guard raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 else {
            throw ConfigParseError.syntax(line: line, reason: "expected a double-quoted string")
        }
        return String(raw.dropFirst().dropLast())
    }

    private static func parseStringArray(_ raw: String, line: Int) throws -> [String] {
        guard raw.hasPrefix("["), raw.hasSuffix("]") else {
            throw ConfigParseError.syntax(line: line, reason: "expected `[...]` array")
        }
        let inner = raw.dropFirst().dropLast()
        if inner.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        var results: [String] = []
        for part in inner.split(separator: ",") {
            let trimmed = String(part).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            results.append(try parseString(trimmed, line: line))
        }
        return results
    }
}
