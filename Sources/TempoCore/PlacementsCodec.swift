import Foundation

/// Canonical JSON encoding of a daemon-state snapshot: an array of `PlacedWindow`s.
/// Lives in TempoCore so both the daemon (writer) and the CLI (reader) speak the same format.
public enum Placements {
    public static func encodeJSON(_ placements: [PlacedWindow]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(placements)
    }

    public static func decodeJSON(_ data: Data) throws -> [PlacedWindow] {
        try JSONDecoder().decode([PlacedWindow].self, from: data)
    }
}

/// Flat row shape: bundleId, title, subrole, workspace at the top level — easy to grep / jq.
extension PlacedWindow: Codable {
    enum CodingKeys: String, CodingKey {
        case bundleId, title, subrole, workspace
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let window = WindowInfo(
            bundleId: try container.decode(String.self, forKey: .bundleId),
            title: try container.decode(String.self, forKey: .title),
            subrole: WindowSubrole(axValue: try container.decode(String.self, forKey: .subrole))
        )
        self.init(window: window,
                  workspace: try container.decode(WorkspaceID.self, forKey: .workspace))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(window.bundleId, forKey: .bundleId)
        try container.encode(window.title, forKey: .title)
        try container.encode(window.subrole.axValue, forKey: .subrole)
        try container.encode(workspace, forKey: .workspace)
    }
}
