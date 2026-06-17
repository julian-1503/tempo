/// Identifier of a workspace (e.g. "A", "C", "1"). Workspaces are a fixed, named set.
public typealias WorkspaceID = String

/// AX subrole of a window, reduced to the cases Tempo cares about.
public enum WindowSubrole: Equatable, Sendable {
    case standardWindow
    case dialog
    case floatingWindow
    case other(String)
}

/// A snapshot of a window observed via the Accessibility API.
public struct WindowInfo: Equatable, Sendable {
    public let bundleId: String
    public let title: String
    public let subrole: WindowSubrole

    public init(bundleId: String, title: String, subrole: WindowSubrole) {
        self.bundleId = bundleId
        self.title = title
        self.subrole = subrole
    }
}
