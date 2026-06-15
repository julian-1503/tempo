import Foundation

/// Errors raised when a Scene file violates the schema's invariants.
public enum SceneCodingError: Error, Equatable {
    case emptyName
    case emptyMatch
    case emptyWorkspace
}

extension Assignment: Codable {
    enum CodingKeys: String, CodingKey { case match, workspace, float }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            match: try container.decode(WindowMatch.self, forKey: .match),
            workspace: try container.decode(String.self, forKey: .workspace),
            float: try container.decodeIfPresent(Bool.self, forKey: .float) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(match, forKey: .match)
        try container.encode(workspace, forKey: .workspace)
        try container.encode(float, forKey: .float)
    }
}

extension Scene: Codable {
    enum CodingKeys: String, CodingKey { case name, hideUnassigned, assignments }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            assignments: try container.decode([Assignment].self, forKey: .assignments),
            hideUnassigned: try container.decodeIfPresent(Bool.self, forKey: .hideUnassigned) ?? true
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(hideUnassigned, forKey: .hideUnassigned)
        try container.encode(assignments, forKey: .assignments)
    }
}

public extension Scene {
    /// Decode and validate a Scene from JSON file contents.
    static func load(fromJSON data: Data) throws -> Scene {
        let scene = try JSONDecoder().decode(Scene.self, from: data)
        try scene.validate()
        return scene
    }

    /// Encode the Scene to pretty, stable JSON suitable for a Scene file.
    func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Enforce the schema invariants that Codable alone cannot.
    func validate() throws {
        if name.isEmpty { throw SceneCodingError.emptyName }
        for assignment in assignments {
            if assignment.match.bundleId == nil, assignment.match.titleRegex == nil {
                throw SceneCodingError.emptyMatch
            }
            if assignment.workspace.isEmpty { throw SceneCodingError.emptyWorkspace }
        }
    }
}
