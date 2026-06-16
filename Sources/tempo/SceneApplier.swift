import AppKit
import ApplicationServices
import TempoCore

/// One-shot Scene activation: focus-workspace windows go on-screen, other assigned
/// windows go off-screen, unassigned apps are hidden (when the Scene says so).
/// The persistent workspace daemon will subsume this; for now it proves the placement path.
enum SceneApplier {
    // Provisional fixed coordinates until the workspace engine computes real tiling.
    static let onScreen = CGPoint(x: 120, y: 120)
    static let offScreen = CGPoint(x: 6000, y: 200)

    static func apply(_ scene: Scene) {
        let pairs = AXEngine.allWindows()
        let plan = Planner().plan(windows: pairs.map(\.info), scene: scene)
        let focus = scene.focusWorkspace ?? plan.placements.first?.workspace

        var consumed = Set<Int>()
        for placement in plan.placements {
            guard let index = pairs.indices.first(where: {
                !consumed.contains($0) && pairs[$0].info == placement.window
            }) else { continue }
            consumed.insert(index)
            let target = placement.workspace == focus ? onScreen : offScreen
            AXEngine.setPosition(pairs[index].element, target)
        }

        for bundleId in plan.hides {
            AXEngine.hideApp(bundleId: bundleId)
        }
    }
}
