import AppKit
import ApplicationServices
import TempoCore

enum EngineError: Error {
    case accessibilityNotTrusted
}

/// Reads the live set of windows via the macOS Accessibility API.
struct AXWindowSource: WindowSource {
    func currentWindows() throws -> [WindowInfo] {
        guard AXIsProcessTrusted() else { throw EngineError.accessibilityNotTrusted }

        var windows: [WindowInfo] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, let bundleId = app.bundleIdentifier else { continue }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            guard let axWindows = axCopy(axApp, kAXWindowsAttribute) as? [AXUIElement] else { continue }

            for axWindow in axWindows {
                let title = axCopy(axWindow, kAXTitleAttribute) as? String ?? ""
                let subrole = axCopy(axWindow, kAXSubroleAttribute) as? String ?? "AXStandardWindow"
                windows.append(WindowInfo(bundleId: bundleId,
                                          title: title,
                                          subrole: WindowSubrole(axValue: subrole)))
            }
        }
        return windows
    }
}

private func axCopy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value
}
