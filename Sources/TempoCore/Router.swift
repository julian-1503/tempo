import Foundation

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

    private func isFloating(_ subrole: WindowSubrole) -> Bool {
        switch subrole {
        case .dialog, .floatingWindow: return true
        case .standardWindow, .other: return false
        }
    }

    /// The most specific matching assignment, if any. A matcher with both bundleId and
    /// titleRegex beats one with a single field.
    private func bestMatch(for window: WindowInfo, in assignments: [Assignment]) -> Assignment? {
        assignments
            .filter { matches($0.match, window) }
            .max { specificity($0.match) < specificity($1.match) }
    }

    private func matches(_ m: WindowMatch, _ window: WindowInfo) -> Bool {
        if m.bundleId == nil, m.titleRegex == nil { return false }
        if let bundleId = m.bundleId, bundleId != window.bundleId { return false }
        if let pattern = m.titleRegex {
            guard let regex = try? Regex(pattern), window.title.contains(regex) else {
                return false
            }
        }
        return true
    }

    private func specificity(_ m: WindowMatch) -> Int {
        (m.bundleId != nil ? 1 : 0) + (m.titleRegex != nil ? 1 : 0)
    }
}
