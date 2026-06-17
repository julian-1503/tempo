import AppKit
import ApplicationServices
import TempoCore

/// Per-WindowID record of everything the daemon-side bridge holds about a tracked window.
/// Lives in `WindowController` as `[WindowID: TrackedWindow]` — a single forget Seam for
/// adding new per-window concepts without proliferating sibling dicts.
struct TrackedWindow {
    let element: AXUIElement
    var info: WindowInfo
    /// Last on-screen (position, size) — restored when the window's workspace becomes
    /// active again. Nil until the window has been seen on-screen at least once.
    var floatFrame: (position: CGPoint, size: CGSize)?

    init(element: AXUIElement, info: WindowInfo) {
        self.element = element
        self.info = info
        self.floatFrame = nil
    }
}

/// Bridges the pure WorkspaceModel to live AX windows: holds the per-window records and
/// applies the visible/hidden decision (tile visible windows, push the rest off-screen).
@MainActor
final class WindowController {
    private var model: WorkspaceModel
    private var tracked: [WindowID: TrackedWindow] = [:]
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
    var knownIDs: Set<WindowID> { Set(tracked.keys) }

    /// Find the WindowID of a tracked element by AX equality. Used by the daemon's
    /// destroyed/title-changed notifications, where only the raw AXUIElement is available.
    func windowID(matching element: AXUIElement) -> WindowID? {
        for (id, record) in tracked where CFEqual(record.element, element) { return id }
        return nil
    }

    func info(of id: WindowID) -> WindowInfo? {
        tracked[id]?.info
    }

    /// Update the cached `WindowInfo` for a tracked window. Returns true if the value changed.
    @discardableResult
    func setInfo(_ info: WindowInfo, for id: WindowID) -> Bool {
        guard var record = tracked[id], record.info != info else { return false }
        record.info = info
        tracked[id] = record
        return true
    }

    func adopt(_ id: WindowID, element: AXUIElement, info: WindowInfo, workspace: WorkspaceID) {
        tracked[id] = TrackedWindow(element: element, info: info)
        model.add(id, to: workspace)
    }

    func forget(_ id: WindowID) {
        tracked[id] = nil
        model.remove(id)
    }

    /// Switch the active workspace. If `focusing` is set, focus that specific window
    /// after apply (used by focus-follows-app: the user already focused this window
    /// via Cmd+Tab or Spotlight, so we sync to its workspace and leave focus alone).
    /// Otherwise the first tile in the new workspace gets focus.
    func switchTo(_ workspace: WorkspaceID, focusing: WindowID? = nil) {
        model.switchTo(workspace)
        apply()
        if let focusing, let element = tracked[focusing]?.element {
            AXEngine.focus(element)
        } else {
            focusFirstTracked()
        }
    }

    /// Which workspace a tracked window belongs to, or nil if it isn't tracked.
    func workspace(of id: WindowID) -> WorkspaceID? {
        model.workspace(of: id)
    }

    /// Reassign a tracked window to a different workspace and reapply layout.
    /// No-op if the window isn't tracked. When the window leaves the active
    /// workspace, focus falls to the first remaining tile there — the moved
    /// window is now hidden, so keeping focus on it would strand the keyboard
    /// on an off-screen window (AeroSpace parity).
    func moveWindow(_ id: WindowID, to workspace: WorkspaceID) {
        guard tracked[id] != nil else { return }
        let leavingActive = model.workspace(of: id) == model.active && workspace != model.active
        model.move(id, to: workspace)
        apply()
        if leavingActive { focusFirstTracked() }
    }

    /// Move keyboard focus to the neighboring tile within the active workspace.
    /// Returns true if focus moved, false on a no-op (no managed focus, no neighbor, vertical).
    /// Auto-exits fullscreen so the focused window is actually visible.
    func focusTile(_ direction: Direction) -> Bool {
        guard let focused = AXEngine.focusedWindowID(),
              let target = model.neighbor(of: focused, direction: direction),
              let element = tracked[target]?.element else { return false }
        if model.fullscreen(in: model.active) != nil {
            model.clearFullscreen(in: model.active)
            apply()
        }
        AXEngine.focus(element)
        return true
    }

    /// Swap the focused tile with its neighbor in the tile order and reapply layout.
    /// Returns true if a swap happened. Auto-exits fullscreen so the rearrangement is visible.
    func moveTile(_ direction: Direction) -> Bool {
        guard let focused = AXEngine.focusedWindowID(),
              model.swapWithNeighbor(focused, direction: direction) else { return false }
        model.clearFullscreen(in: model.active)
        apply()
        return true
    }

    /// Toggle floating for the focused window (must be in the active workspace).
    /// Returns the new state as a label on success, nil on no-op. Clears any active-
    /// workspace fullscreen first, otherwise the fullscreen short-circuit in apply()
    /// would hide the float result.
    func toggleFloating() -> String? {
        let active = model.active
        guard let focused = AXEngine.focusedWindowID(),
              model.workspace(of: focused) == active,
              tracked[focused] != nil else { return nil }
        if model.fullscreen(in: active) != nil {
            model.clearFullscreen(in: active)
        }
        let newState = !model.isFloating(focused)
        model.markFloating(focused, newState)
        apply()
        return newState ? "set on \(focused)" : "cleared on \(focused)"
    }

    /// Toggle fullscreen for the focused window (must be in the active workspace).
    /// Returns the new state as a label ("set" / "cleared") on success, nil on no-op.
    func toggleFullscreen() -> String? {
        let active = model.active
        guard let focused = AXEngine.focusedWindowID(),
              model.workspace(of: focused) == active,
              tracked[focused] != nil else { return nil }
        if model.fullscreen(in: active) == focused {
            model.clearFullscreen(in: active)
            apply()
            if let element = tracked[focused]?.element { AXEngine.focus(element) }
            return "cleared"
        }
        model.setFullscreen(focused, in: active)
        apply()
        if let element = tracked[focused]?.element { AXEngine.focus(element) }
        return "set on \(focused)"
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
        focusFirstTracked()
    }

    /// Tile the active workspace's non-floating windows; push hidden ones off-screen;
    /// keep floats wherever they were and restore from cache when they re-enter view.
    /// Fullscreen takes precedence: when set, only the fullscreen window is visible at the
    /// full workspace area; everything else (tiles, floats, other workspaces) is hidden.
    func apply() {
        // 0. Reconcile: drop tracked windows that have closed. macOS'
        // kAXUIElementDestroyedNotification is unreliable (some apps — e.g.
        // Karabiner's Settings window — never fire a usable one), so a closed
        // window can linger in the model and inflate the tile count, leaving a
        // phantom split with no window in it. Validate each element via
        // _AXUIElementGetWindow (AXEngine.windowID): a destroyed window returns
        // nil, a merely-hidden/off-screen one still resolves. Same principle as
        // AeroSpace's refresh: reconcile, don't trust the destroy notification.
        pruneClosedWindows()

        let active = model.active

        // 1. Snapshot every on-screen float's current frame (user may have dragged it).
        captureFloatFrames()

        // 2a. Fullscreen short-circuit: one window owns the whole area, everything else hides.
        // Note: focus is NOT set here — apply() only lays out. Stealing focus (and
        // warping the cursor) on every apply() fought the user's mouse whenever a
        // background event re-ran layout. Focus is set explicitly by the actions
        // that should move it (switchTo, toggleFullscreen, focusTile).
        if let fs = model.fullscreen(in: active), let fsElement = tracked[fs]?.element {
            AXEngine.setFrame(fsElement,
                              position: CGPoint(x: area.x, y: area.y),
                              size: CGSize(width: area.width, height: area.height))
            for (id, record) in tracked where id != fs {
                AXEngine.setPosition(record.element, offScreen)
            }
            return
        }

        // 2b. Tile the active workspace's non-floating windows.
        let tiled = model.tiledWindows(in: active)
        let mode: TilingMode = switch model.mode(of: active) {
        case .tiles: .tiles(model.orientation(of: active))
        case .accordion: .accordion
        }
        let frames = tiler.layout(count: tiled.count, in: area, mode: mode)
        for (id, frame) in zip(tiled, frames) {
            guard let element = tracked[id]?.element else { continue }
            AXEngine.setFrame(element,
                              position: CGPoint(x: frame.x, y: frame.y),
                              size: CGSize(width: frame.width, height: frame.height))
        }

        // 3. Push everything in hidden workspaces (tiles + floats) off-screen.
        for id in model.hiddenWindows {
            guard let element = tracked[id]?.element else { continue }
            AXEngine.setPosition(element, offScreen)
        }

        // 4. Restore each active float to its cached frame; capture the initial
        // frame if we don't have one yet; center it as a last resort when the
        // window is currently off-screen with no cache (e.g. daemon restart).
        for id in model.floatingWindows(in: active) {
            guard let record = tracked[id] else { continue }
            let element = record.element
            if let cached = record.floatFrame, !isOffScreen(cached.position) {
                AXEngine.setFrame(element, position: cached.position, size: cached.size)
            } else if let p = AXEngine.position(element), let s = AXEngine.size(element),
                      !isOffScreen(p) {
                tracked[id]?.floatFrame = (position: p, size: s)
            } else if let s = AXEngine.size(element) {
                let centered = CGPoint(
                    x: area.x + (area.width  - s.width)  / 2,
                    y: area.y + (area.height - s.height) / 2)
                AXEngine.setPosition(element, centered)
                tracked[id]?.floatFrame = (position: centered, size: s)
            }
        }
    }

    func markFloating(_ id: WindowID, _ floating: Bool) {
        guard tracked[id] != nil else { return }
        model.markFloating(id, floating)
    }

    /// Bring every off-screen tracked window back to a usable on-screen frame — its
    /// cached float position if any, otherwise centered in the workspace area. Used
    /// when entering pause: hidden windows must be reachable so the user can work in
    /// the normal-mac windowing model until they resume Tempo.
    func restoreAllToScreen() {
        for (_, record) in tracked {
            guard let p = AXEngine.position(record.element), isOffScreen(p) else { continue }
            if let cached = record.floatFrame, !isOffScreen(cached.position) {
                AXEngine.setSize(record.element, cached.size)
                AXEngine.setPosition(record.element, cached.position)
            } else if let s = AXEngine.size(record.element) {
                let centered = CGPoint(
                    x: area.x + (area.width  - s.width)  / 2,
                    y: area.y + (area.height - s.height) / 2)
                AXEngine.setPosition(record.element, centered)
            }
        }
    }

    /// Focus the first window of the new active workspace so subsequent move-focused /
    /// focus-tile hotkeys have a managed target. AeroSpace does the same on switch.
    /// If the workspace has a fullscreen tile, that window takes focus.
    private func focusFirstTracked() {
        let active = model.active
        if let fs = model.fullscreen(in: active), let element = tracked[fs]?.element {
            AXEngine.focus(element)
            return
        }
        let order = model.tiledWindows(in: active) + model.floatingWindows(in: active)
        guard let id = order.first, let element = tracked[id]?.element else { return }
        AXEngine.focus(element)
    }

    /// Drop tracked windows whose AX element no longer resolves to a live window.
    /// Returns the pruned ids (for logging). Safe to call before every layout.
    @discardableResult
    func pruneClosedWindows() -> [WindowID] {
        let dead = tracked.keys.filter { AXEngine.windowID(tracked[$0]!.element) == nil }
        for id in dead {
            tracked[id] = nil
            model.remove(id)
        }
        if !dead.isEmpty {
            FileHandle.standardError.write(Data("reconcile -> pruned closed window(s) \(dead.sorted())\n".utf8))
        }
        return dead
    }

    /// Human-readable snapshot of tracked windows for the `dump` command.
    func debugDump() -> String {
        var lines = ["active=\(model.active) fullscreen=\(model.fullscreen(in: model.active).map(String.init) ?? "none")"]
        let byWorkspace = Dictionary(grouping: tracked.keys) { model.workspace(of: $0) ?? "?" }
        for ws in byWorkspace.keys.sorted() {
            let tiles = model.tiledWindows(in: ws)
            lines.append("ws \(ws): \(tiles.count) tiled, \(model.floatingWindows(in: ws).count) float")
            for id in (byWorkspace[ws] ?? []).sorted() {
                let rec = tracked[id]
                let alive = AXEngine.windowID(rec!.element) != nil
                lines.append("  id=\(id) \(rec?.info.bundleId ?? "?") float=\(model.isFloating(id)) alive=\(alive) [\(rec?.info.title ?? "")]")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func captureFloatFrames() {
        for id in Array(tracked.keys) where model.isFloating(id) {
            guard let element = tracked[id]?.element,
                  let p = AXEngine.position(element),
                  let s = AXEngine.size(element) else { continue }
            if !isOffScreen(p) {
                tracked[id]?.floatFrame = (position: p, size: s)
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
