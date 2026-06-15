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

/// A window matcher. At least one field is set; more specific matchers win.
public struct WindowMatch: Equatable, Sendable, Codable {
    public let bundleId: String?
    public let titleRegex: String?

    public init(bundleId: String? = nil, titleRegex: String? = nil) {
        self.bundleId = bundleId
        self.titleRegex = titleRegex
    }
}

/// A rule mapping matched windows to a workspace.
public struct Assignment: Equatable, Sendable {
    public let match: WindowMatch
    public let workspace: WorkspaceID
    public let float: Bool

    public init(match: WindowMatch, workspace: WorkspaceID, float: Bool = false) {
        self.match = match
        self.workspace = workspace
        self.float = float
    }
}

/// A named, switchable profile of assignments plus visibility.
public struct Scene: Equatable, Sendable {
    public let name: String
    public let assignments: [Assignment]
    public let hideUnassigned: Bool

    public init(name: String, assignments: [Assignment], hideUnassigned: Bool = true) {
        self.name = name
        self.assignments = assignments
        self.hideUnassigned = hideUnassigned
    }
}

/// The decision for where a newly observed window should go.
public enum RoutingDecision: Equatable, Sendable {
    /// Place the window on `to`. `silent` means: do not switch the active workspace and do
    /// not steal keyboard focus (the global focus-protection guarantee).
    case route(to: WorkspaceID, silent: Bool, float: Bool)
    /// No assignment matched: show the window in the current workspace (ephemeral).
    case showInCurrent(float: Bool)
}

/// A single window's target placement when a Scene is activated.
public struct WindowPlacement: Equatable, Sendable {
    public let window: WindowInfo
    public let workspace: WorkspaceID
    public let float: Bool

    public init(window: WindowInfo, workspace: WorkspaceID, float: Bool) {
        self.window = window
        self.workspace = workspace
        self.float = float
    }
}

/// The full plan for activating a Scene: where matched windows go, and which apps to hide.
public struct PlacementPlan: Equatable, Sendable {
    public let placements: [WindowPlacement]
    /// Bundle ids of apps to app-hide (apps whose every window is unassigned).
    public let hides: [String]

    public init(placements: [WindowPlacement], hides: [String]) {
        self.placements = placements
        self.hides = hides
    }
}
