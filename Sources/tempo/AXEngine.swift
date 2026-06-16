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

    /// Stable window id for an AX window (CGWindowID), or nil.
    static func windowID(_ window: AXUIElement) -> TempoCore.WindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &id) == .success, id != 0 else { return nil }
        return TempoCore.WindowID(id)
    }

    /// The user's currently focused window (the focused app's focused window), or nil.
    static func focusedWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let appRef else { return nil }
        let app = appRef as! AXUIElement
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef else { return nil }
        return (winRef as! AXUIElement)
    }

    /// Stable id of the currently focused window, or nil.
    static func focusedWindowID() -> TempoCore.WindowID? {
        guard let win = focusedWindow() else { return nil }
        return windowID(win)
    }

    /// Bring `window`'s owning app forward and ask AX to make this its main/focused window.
    static func focus(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return }
        NSRunningApplication(processIdentifier: pid)?.activate()
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
