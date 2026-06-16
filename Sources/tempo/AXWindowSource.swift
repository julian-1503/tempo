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
        return AXEngine.allWindows().map(\.info)
    }
}
