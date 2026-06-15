import Foundation

public extension WindowSubrole {
    /// The macOS Accessibility subrole string.
    var axValue: String {
        switch self {
        case .standardWindow: return "AXStandardWindow"
        case .dialog: return "AXDialog"
        case .floatingWindow: return "AXFloatingWindow"
        case .other(let value): return value
        }
    }

    init(axValue: String) {
        switch axValue {
        case "AXStandardWindow": self = .standardWindow
        case "AXDialog": self = .dialog
        case "AXFloatingWindow": self = .floatingWindow
        default: self = .other(axValue)
        }
    }
}

extension WindowInfo: Codable {
    enum CodingKeys: String, CodingKey { case bundleId, title, subrole }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bundleId: try container.decode(String.self, forKey: .bundleId),
            title: try container.decode(String.self, forKey: .title),
            subrole: WindowSubrole(axValue: try container.decode(String.self, forKey: .subrole))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleId, forKey: .bundleId)
        try container.encode(title, forKey: .title)
        try container.encode(subrole.axValue, forKey: .subrole)
    }
}
