/// Opaque window identifier. The shell maps this to an AXUIElement / CGWindowID.
public typealias WindowID = Int

/// The daemon's pure workspace state: which window lives in which workspace, which
/// workspace is active, the per-workspace tile order, and (derived) which windows
/// should be visible vs off-screen.
public struct WorkspaceModel {
    public private(set) var active: WorkspaceID
    private var assignment: [WindowID: WorkspaceID] = [:]
    /// Per-workspace tile order — index 0 is leftmost (horizontal) or topmost (vertical).
    /// Maintained in sync with `assignment`.
    private var order: [WorkspaceID: [WindowID]] = [:]
    private var orientations: [WorkspaceID: Orientation] = [:]
    private var previous: WorkspaceID?

    public init(active: WorkspaceID) {
        self.active = active
    }

    /// Track `window` on `workspace`. If it was on a different workspace, it's moved.
    /// A newly tracked window is appended to the end of the workspace's tile order.
    public mutating func add(_ window: WindowID, to workspace: WorkspaceID) {
        if let prev = assignment[window] {
            if prev == workspace { return }
            order[prev]?.removeAll { $0 == window }
        }
        assignment[window] = workspace
        order[workspace, default: []].append(window)
    }

    public mutating func remove(_ window: WindowID) {
        if let prev = assignment[window] {
            order[prev]?.removeAll { $0 == window }
        }
        assignment[window] = nil
    }

    /// Reassign `window` to `workspace`. Same insertion semantics as `add`.
    public mutating func move(_ window: WindowID, to workspace: WorkspaceID) {
        add(window, to: workspace)
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
        order[workspace] ?? []
    }

    public var visibleWindows: [WindowID] {
        windows(in: active)
    }

    public var hiddenWindows: [WindowID] {
        assignment.filter { $0.value != active }.map(\.key).sorted()
    }

    /// The tile orientation of `workspace`. Defaults to `.horizontal` for any workspace
    /// the user hasn't explicitly reoriented.
    public func orientation(of workspace: WorkspaceID) -> Orientation {
        orientations[workspace] ?? .horizontal
    }

    /// Set the tile orientation of `workspace`. Persists across workspace switches.
    public mutating func setOrientation(_ orientation: Orientation, for workspace: WorkspaceID) {
        orientations[workspace] = orientation
    }

    /// The previous/next tile of `window` within its workspace's order, or nil at the
    /// edge or when the direction is perpendicular to the workspace's orientation.
    public func neighbor(of window: WindowID, direction: Direction) -> WindowID? {
        guard let workspace = assignment[window],
              let list = order[workspace],
              let index = list.firstIndex(of: window),
              let delta = step(direction, for: workspace) else { return nil }
        let target = index + delta
        guard list.indices.contains(target) else { return nil }
        return list[target]
    }

    /// Swap `window` with its neighbor along the workspace's orientation axis; returns
    /// true if a swap happened. No-op (returns false) at edges or for the perpendicular axis.
    public mutating func swapWithNeighbor(_ window: WindowID, direction: Direction) -> Bool {
        guard let workspace = assignment[window],
              var list = order[workspace],
              let index = list.firstIndex(of: window),
              let delta = step(direction, for: workspace) else { return false }
        let target = index + delta
        guard list.indices.contains(target) else { return false }
        list.swapAt(index, target)
        order[workspace] = list
        return true
    }

    /// Translate a `Direction` into a step (-1 prev / +1 next) along the workspace's
    /// orientation, or nil for the perpendicular axis.
    private func step(_ direction: Direction, for workspace: WorkspaceID) -> Int? {
        switch (orientation(of: workspace), direction) {
        case (.horizontal, .left),  (.vertical, .up):   return -1
        case (.horizontal, .right), (.vertical, .down): return +1
        default: return nil
        }
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

/// Tile navigation direction for focus-tile and move-tile commands.
public enum Direction: Equatable, Sendable {
    case left, right, up, down
}
