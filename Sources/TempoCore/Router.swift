/// Decides where a newly observed window should go, given the active Scene and workspace.
public struct Router {
    public init() {}

    public func decide(for window: WindowInfo,
                       scene: Scene,
                       activeWorkspace: WorkspaceID) -> RoutingDecision {
        let floating = isFloating(window.subrole)
        guard let best = bestMatch(for: window, in: scene.assignments) else {
            return .showInCurrent(float: floating)
        }
        // Global focus-protection: routing to a non-active workspace never switches the
        // active workspace and never steals focus.
        let silent = best.workspace != activeWorkspace
        return .route(to: best.workspace, silent: silent, float: best.float || floating)
    }
}
