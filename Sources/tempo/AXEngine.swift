import AppKit
import ApplicationServices
import TempoCore

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
