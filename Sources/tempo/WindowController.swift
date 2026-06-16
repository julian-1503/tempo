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
    /// Last on-screen (position, size) per floating window. Restored when its
    /// workspace becomes active again.
    private var floatFrames: [WindowID: (position: CGPoint, size: CGSize)] = [:]

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

    /// Reassign a tracked window to a different workspace and reapply layout.
    /// No-op if the window isn't tracked.
    func moveWindow(_ id: WindowID, to workspace: WorkspaceID) {
        guard elements[id] != nil else { return }
        model.move(id, to: workspace)
        apply()
    }

    /// Move keyboard focus to the neighboring tile within the active workspace.
    /// Returns true if focus moved, false on a no-op (no managed focus, no neighbor, vertical).
    func focusTile(_ direction: Direction) -> Bool {
        guard let focused = AXEngine.focusedWindowID(),
              let target = model.neighbor(of: focused, direction: direction),
              let element = elements[target] else { return false }
        AXEngine.focus(element)
        return true
    }

    /// Swap the focused tile with its neighbor in the tile order and reapply layout.
    /// Returns true if a swap happened.
    func moveTile(_ direction: Direction) -> Bool {
        guard let focused = AXEngine.focusedWindowID(),
              model.swapWithNeighbor(focused, direction: direction) else { return false }
        apply()
        return true
    }

    func orientation(of workspace: WorkspaceID) -> Orientation {
        model.orientation(of: workspace)
    }

    /// Update a workspace's tile orientation; reapply layout if it's the active one.
    func setOrientation(_ orientation: Orientation, for workspace: WorkspaceID) {
        model.setOrientation(orientation, for: workspace)
        if workspace == model.active { apply() }
    }

    func mode(of workspace: WorkspaceID) -> WorkspaceMode {
        model.mode(of: workspace)
    }

    /// Update a workspace's layout mode; reapply layout if it's the active one.
    func setMode(_ mode: WorkspaceMode, for workspace: WorkspaceID) {
        model.setMode(mode, for: workspace)
        if workspace == model.active { apply() }
    }

    func backAndForth() {
        model.switchBackAndForth()
        apply()
    }

    /// Tile the active workspace's non-floating windows; push hidden ones off-screen;
    /// keep floats wherever they were and restore from cache when they re-enter view.
    func apply() {
        let active = model.active

        // 1. Snapshot every on-screen float's current frame (user may have dragged it).
        captureFloatFrames()

        // 2. Tile the active workspace's non-floating windows.
        let tiled = model.tiledWindows(in: active)
        let mode: TilingMode = switch model.mode(of: active) {
        case .tiles: .tiles(model.orientation(of: active))
        case .accordion: .accordion
        }
        let frames = tiler.layout(count: tiled.count, in: area, mode: mode)
        for (id, frame) in zip(tiled, frames) {
            guard let element = elements[id] else { continue }
            AXEngine.setSize(element, CGSize(width: frame.width, height: frame.height))
            AXEngine.setPosition(element, CGPoint(x: frame.x, y: frame.y))
            AXEngine.setSize(element, CGSize(width: frame.width, height: frame.height))
        }

        // 3. Push everything in hidden workspaces (tiles + floats) off-screen.
        for id in model.hiddenWindows {
            guard let element = elements[id] else { continue }
            AXEngine.setPosition(element, offScreen)
        }

        // 4. Restore each active float to its cached frame; capture the initial
        // frame if we don't have one yet; center it as a last resort when the
        // window is currently off-screen with no cache (e.g. daemon restart).
        for id in model.floatingWindows(in: active) {
            guard let element = elements[id] else { continue }
            if let cached = floatFrames[id], !isOffScreen(cached.position) {
                AXEngine.setSize(element, cached.size)
                AXEngine.setPosition(element, cached.position)
            } else if let p = AXEngine.position(element), let s = AXEngine.size(element),
                      !isOffScreen(p) {
                floatFrames[id] = (position: p, size: s)
            } else if let s = AXEngine.size(element) {
                let centered = CGPoint(
                    x: area.x + (area.width  - s.width)  / 2,
                    y: area.y + (area.height - s.height) / 2)
                AXEngine.setPosition(element, centered)
                floatFrames[id] = (position: centered, size: s)
            }
        }
    }

    func markFloating(_ id: WindowID, _ floating: Bool) {
        guard elements[id] != nil else { return }
        model.markFloating(id, floating)
    }

    private func captureFloatFrames() {
        for (id, element) in elements where model.isFloating(id) {
            guard let p = AXEngine.position(element), let s = AXEngine.size(element) else { continue }
            if !isOffScreen(p) {
                floatFrames[id] = (position: p, size: s)
            }
        }
    }

    /// True when the window sits in the off-screen corner — only `x` is checked, since
    /// macOS clamps the bottom edge and a hidden window's y may be tens of pixels above
    /// `offScreen.y`. The x edge holds firm at `area.x + area.width - 1`.
    private func isOffScreen(_ p: CGPoint) -> Bool {
        p.x >= area.x + area.width - 5
    }
}
