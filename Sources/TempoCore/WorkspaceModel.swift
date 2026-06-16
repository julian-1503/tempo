/// Opaque window identifier. The shell maps this to an AXUIElement / CGWindowID.
public typealias WindowID = Int

/// The daemon's pure workspace state: which window lives in which workspace, which
/// workspace is active, and (derived) which windows should be visible vs off-screen.
public struct WorkspaceModel {
    public private(set) var active: WorkspaceID
    private var assignment: [WindowID: WorkspaceID] = [:]
    private var previous: WorkspaceID?

    public init(active: WorkspaceID) {
        self.active = active
    }

    public mutating func add(_ window: WindowID, to workspace: WorkspaceID) {
        assignment[window] = workspace
    }

    public mutating func remove(_ window: WindowID) {
        assignment[window] = nil
    }

    public mutating func move(_ window: WindowID, to workspace: WorkspaceID) {
        assignment[window] = workspace
    }

    public mutating func switchTo(_ workspace: WorkspaceID) {
        guard workspace != active else { return }
        previous = active
        active = workspace
    }

    public mutating func switchBackAndForth() {
        guard let previous else { return }
        switchTo(previous)
    }

    public func windows(in workspace: WorkspaceID) -> [WindowID] {
        assignment.filter { $0.value == workspace }.map(\.key).sorted()
    }

    public var visibleWindows: [WindowID] {
        windows(in: active)
    }

    public var hiddenWindows: [WindowID] {
        assignment.filter { $0.value != active }.map(\.key).sorted()
    }

    /// Snapshot every assigned window as a `[PlacedWindow]`, joining the model's
    /// (window→workspace) map with the caller's `WindowID → WindowInfo` cache.
    /// Sorted by (workspace, windowID) for deterministic state-file output.
    /// Windows whose info is missing are skipped silently.
    public func placedWindows(using infos: [WindowID: WindowInfo]) -> [PlacedWindow] {
        assignment
            .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
            .compactMap { id, workspace in
                infos[id].map { PlacedWindow(window: $0, workspace: workspace) }
            }
    }
}
