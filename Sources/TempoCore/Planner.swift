/// Computes the placement plan for activating a Scene over the currently open windows.
public struct Planner {
    public init() {}

    public func plan(windows: [WindowInfo], scene: Scene) -> PlacementPlan {
        var placements: [WindowPlacement] = []
        var matchedBundles: Set<String> = []
        var orderedBundles: [String] = []
        var seenBundles: Set<String> = []

        for window in windows {
            if seenBundles.insert(window.bundleId).inserted {
                orderedBundles.append(window.bundleId)
            }
            if let assignment = bestMatch(for: window, in: scene.assignments) {
                let float = assignment.float || isFloating(window.subrole)
                placements.append(WindowPlacement(window: window,
                                                  workspace: assignment.workspace,
                                                  float: float))
                matchedBundles.insert(window.bundleId)
            }
        }

        // Hide an app only when none of its windows matched an assignment.
        let hides = scene.hideUnassigned
            ? orderedBundles.filter { !matchedBundles.contains($0) }
            : []

        return PlacementPlan(placements: placements, hides: hides)
    }
}
