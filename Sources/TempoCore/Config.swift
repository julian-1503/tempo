import Foundation

/// Daemon-side static config (see CONTEXT.md). Hand-edited TOML at
/// `$TEMPO_HOME/tempo.toml`. Env vars (`TEMPO_MANAGE`, `TEMPO_SCENE`) override
/// matching config values — the env knobs exist for sandbox testing.
public struct Config: Equatable, Sendable {
    /// Bundle IDs the daemon should manage. `nil` means "no restriction".
    public var managed: [String]?
    /// Name of the Scene to apply on startup. Falls back through env / nothing.
    public var defaultScene: String?
    /// Workspace that's active when the daemon starts (and no Scene declares a focus).
    public var defaultWorkspace: String?

    public init(managed: [String]? = nil,
                defaultScene: String? = nil,
                defaultWorkspace: String? = nil) {
        self.managed = managed
        self.defaultScene = defaultScene
        self.defaultWorkspace = defaultWorkspace
    }
}

public enum ConfigParseError: Error, Equatable {
    case syntax(line: Int, reason: String)
}

/// Parser for the TOML subset Tempo uses today. Supported syntax:
/// - line comments starting with `#`
/// - `[section]` headers
/// - `key = "string"`
/// - `key = ["string", "string"]` (single-line arrays; trailing comma OK)
/// Unknown sections and keys are tolerated for forward-compat. Anything outside
/// this subset (nested tables, multi-line values, booleans, datetimes) is out
/// of scope and will either be ignored (unknown keys) or throw a syntax error.
public enum ConfigParser {
    public static func parse(_ source: String) throws -> Config {
        var config = Config()
        var section: String?
        var lineNo = 0
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNo += 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
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
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard section == "daemon" else { continue }
            switch key {
            case "managed":
                config.managed = try parseStringArray(value, line: lineNo)
            case "default_scene":
                config.defaultScene = try parseString(value, line: lineNo)
            case "default_workspace":
                config.defaultWorkspace = try parseString(value, line: lineNo)
            default:
                continue
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
