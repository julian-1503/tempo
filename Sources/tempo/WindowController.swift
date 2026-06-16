import AppKit
import ApplicationServices
import TempoCore

/// Bridges the pure WorkspaceModel to live AX windows: holds the element handles and
/// applies the visible/hidden decision (tile visible windows, push the rest off-screen).
@MainActor
final class WindowController {
    private var model: WorkspaceModel
    private var elements: [WindowID: AXUIElement] = [:]
    private let tiler = Tiler()
    private let area: Frame
    private let offScreen: CGPoint

    init(active: WorkspaceID, area: Frame) {
        self.model = WorkspaceModel(active: active)
        self.area = area
        // Bottom-right corner: leaves only a ~1px sliver. Pushing windows *fully* off-screen
        // trips macOS's clamp that keeps part of the window reachable.
        self.offScreen = CGPoint(x: area.x + area.width - 1, y: area.y + area.height - 1)
    }

    var active: WorkspaceID { model.active }
    var knownIDs: Set<WindowID> { Set(elements.keys) }

    /// Snapshot every tracked window as `[PlacedWindow]`, joining the model's
    /// assignments with the caller's WindowInfo cache. Used to publish `state.json`.
    func placedWindows(using infos: [WindowID: WindowInfo]) -> [PlacedWindow] {
        model.placedWindows(using: infos)
    }

    func adopt(_ id: WindowID, element: AXUIElement, workspace: WorkspaceID) {
        elements[id] = element
        model.add(id, to: workspace)
    }

    func forget(_ id: WindowID) {
        elements[id] = nil
        model.remove(id)
    }

    func switchTo(_ workspace: WorkspaceID) {
        model.switchTo(workspace)
        apply()
    }

    func backAndForth() {
        model.switchBackAndForth()
        apply()
    }

    /// Tile the active workspace's windows; push everything else off-screen.
    func apply() {
        let visible = model.visibleWindows
        let frames = tiler.layout(count: visible.count, in: area, mode: .tiles)
        for (id, frame) in zip(visible, frames) {
            guard let element = elements[id] else { continue }
            AXEngine.setSize(element, CGSize(width: frame.width, height: frame.height))
            AXEngine.setPosition(element, CGPoint(x: frame.x, y: frame.y))
            AXEngine.setSize(element, CGSize(width: frame.width, height: frame.height))
        }
        for id in model.hiddenWindows {
            guard let element = elements[id] else { continue }
            AXEngine.setPosition(element, offScreen)
        }
    }
}
