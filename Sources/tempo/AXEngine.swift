import AppKit
import ApplicationServices
import TempoCore

// Private API used by tiling WMs to get a stable window id for an AX window.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                   _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Low-level Accessibility window operations. The verified primitives the workspace
/// engine will build on. (Dev-facing for now, exercised via `tempo debug`.)
enum AXEngine {
    static func application(bundleId: String) -> AXUIElement? {
        guard let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleId }) else { return nil }
        return AXUIElementCreateApplication(running.processIdentifier)
    }

    static func firstWindow(bundleId: String) -> AXUIElement? {
        guard let axApp = application(bundleId: bundleId) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first
    }

    /// All regular apps' windows paired with their TempoCore description.
    static func allWindows() -> [(element: AXUIElement, info: TempoCore.WindowInfo)] {
        var result: [(AXUIElement, TempoCore.WindowInfo)] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, let bundleId = app.bundleIdentifier else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for axWindow in windows {
                var titleRef: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                var subroleRef: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleRef)
                let info = TempoCore.WindowInfo(
                    bundleId: bundleId,
                    title: titleRef as? String ?? "",
                    subrole: TempoCore.WindowSubrole(axValue: subroleRef as? String ?? "AXStandardWindow"))
                result.append((axWindow, info))
            }
        }
        return result
    }

    static func hideApp(bundleId: String) {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleId }?.hide()
    }

    /// Describe a single window element (resolving its app's bundle id via the owning pid).
    static func windowInfo(_ window: AXUIElement) -> TempoCore.WindowInfo? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid),
              let bundleId = app.bundleIdentifier else { return nil }
        var titleRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        var subroleRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
        return TempoCore.WindowInfo(
            bundleId: bundleId,
            title: titleRef as? String ?? "",
            subrole: TempoCore.WindowSubrole(axValue: subroleRef as? String ?? "AXStandardWindow"))
    }

    static func position(_ window: AXUIElement) -> CGPoint? {
        axValue(window, kAXPositionAttribute, type: .cgPoint, default: CGPoint.zero)
    }

    static func size(_ window: AXUIElement) -> CGSize? {
        axValue(window, kAXSizeAttribute, type: .cgSize, default: CGSize.zero)
    }

    @discardableResult
    static func setPosition(_ window: AXUIElement, _ point: CGPoint) -> Bool {
        var value = point
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue) == .success
    }

    @discardableResult
    static func setSize(_ window: AXUIElement, _ size: CGSize) -> Bool {
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue) == .success
    }

    /// Place a window at `position` with `size` deterministically.
    ///
    /// Two macOS quirks are handled here:
    ///   1. **Clamp-on-first-write**: some apps clamp position to the *old* size
    ///      (or size to the old position). Setting size → position → size again
    ///      defeats it (AeroSpace issues #143/#335, yabai, Rectangle).
    ///   2. **Animated resizes**: apps with `AXEnhancedUserInterface` enabled
    ///      (Chrome/Electron, anything VoiceOver has touched) *animate* AX-driven
    ///      frame changes, so the window visibly lands at the wrong size and
    ///      "settles" a moment later. We force the attribute off before writing.
    @discardableResult
    static func setFrame(_ window: AXUIElement, position: CGPoint, size: CGSize) -> Bool {
        // Skip when the window is already at the target frame (within a couple of
        // points). This is not just an optimization: it breaks a feedback loop.
        // Writing the frame toggles AXEnhancedUserInterface (below), which makes
        // Chrome rebuild its window and emit create/destroy notifications; the
        // daemon re-applies on those, which calls setFrame again. Because Chrome
        // re-enables AXEnhancedUserInterface on each rebuild, "disable and leave
        // off" alone never converges. Only writing on a *real* frame change stops
        // the loop — once the window is placed, subsequent applies do nothing.
        if let p = AXEngine.position(window), let s = AXEngine.size(window),
           abs(p.x - position.x) < 2, abs(p.y - position.y) < 2,
           abs(s.width - size.width) < 2, abs(s.height - size.height) < 2 {
            return true
        }
        disableEnhancedUI(window)
        setSize(window, size)
        setPosition(window, position)
        setSize(window, size)
        return true
    }

    /// Force the owning app's `AXEnhancedUserInterface` OFF and leave it off.
    /// No-op if the attribute is absent or already off.
    ///
    /// We must NOT restore it to `on`: flipping it back on makes Chrome tear
    /// down and rebuild its AX window, which fires destroy+create
    /// notifications. The daemon re-adopts/re-applies on those, which calls
    /// `setFrame` again, which toggles again — a runaway notification storm.
    /// (Observed on a workspace holding only Chrome: thousands of adopt/forget
    /// cycles, phantom tile counts, and the cursor stuck re-centering on every
    /// fullscreen re-apply.) Leaving it off converges after a single rebuild —
    /// the next `setFrame` sees it already off and does nothing. This is what
    /// yabai does; animations stay disabled for the app process, which is the
    /// desired behavior for a tiling WM anyway.
    private static func disableEnhancedUI(_ window: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return }
        let app = AXUIElementCreateApplication(pid)
        let key = "AXEnhancedUserInterface" as CFString
        var current: CFTypeRef?
        let isOn = AXUIElementCopyAttributeValue(app, key, &current) == .success
            && (current as? Bool == true)
        if isOn { AXUIElementSetAttributeValue(app, key, kCFBooleanFalse) }
    }

    /// Stable window id for an AX window (CGWindowID), or nil.
    static func windowID(_ window: AXUIElement) -> TempoCore.WindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &id) == .success, id != 0 else { return nil }
        return TempoCore.WindowID(id)
    }

    /// The user's currently focused window (the focused app's focused window), or nil.
    ///
    /// Resolves the frontmost app via AppKit's `NSWorkspace` rather than the
    /// systemwide `kAXFocusedApplicationAttribute`. The systemwide attribute
    /// messages the focused app's AX server to resolve it, and Chrome — which
    /// throttles its accessibility interface — makes that query fail with
    /// `kAXErrorCannotComplete` (-25212). That silently no-op'd every
    /// focus/move/fullscreen chord whenever a Chrome window was frontmost.
    /// `NSWorkspace.frontmostApplication` reads from the window server, so it
    /// never touches the target's AX server and stays reliable.
    static func focusedWindow() -> AXUIElement? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        var winRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
           let winRef {
            return (winRef as! AXUIElement)
        }
        // Some apps expose only a main window when no child has explicit focus.
        var mainRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &mainRef) == .success,
           let mainRef {
            return (mainRef as! AXUIElement)
        }
        return nil
    }

    /// Stable id of the currently focused window, or nil.
    static func focusedWindowID() -> TempoCore.WindowID? {
        guard let win = focusedWindow() else { return nil }
        return windowID(win)
    }

    /// Bring `window`'s owning app forward and ask AX to make this its main/focused
    /// window. Also re-centers the mouse cursor on the focused window — matches
    /// AeroSpace's `on-focus-changed = "move-mouse window-lazy-center"` ergonomics so
    /// any subsequent click lands inside the just-focused tile.
    static func focus(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return }
        NSRunningApplication(processIdentifier: pid)?.activate()
        centerCursor(on: window)
    }

    /// Warp the mouse cursor to the center of `window` and re-associate so subsequent
    /// mouse events land where the cursor is. No-op if AX can't report the frame.
    static func centerCursor(on window: AXUIElement) {
        guard let origin = position(window), let size = size(window) else { return }
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        CGWarpMouseCursorPosition(center)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// The full bounds of the main display, in the top-left global coordinates AX uses.
    static func mainDisplayArea() -> Frame {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return Frame(x: bounds.origin.x, y: bounds.origin.y,
                     width: bounds.size.width, height: bounds.size.height)
    }

    private static func axValue<T>(_ element: AXUIElement,
                                   _ attribute: String,
                                   type: AXValueType,
                                   default defaultValue: T) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var result = defaultValue
        guard AXValueGetValue(ref as! AXValue, type, &result) else { return nil }
        return result
    }
}
