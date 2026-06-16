import Foundation

/// Logical modifier keys Tempo cares about. Maps onto CGEventFlags on the engine side.
public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let option  = Modifiers(rawValue: 1 << 0) // a.k.a. alt
    public static let shift   = Modifiers(rawValue: 1 << 1)
    public static let command = Modifiers(rawValue: 1 << 2)
    public static let control = Modifiers(rawValue: 1 << 3)
}

/// A decoded hotkey action.
public enum Hotkey: Equatable, Sendable {
    /// Switch to the workspace labeled by the bound key.
    case switchWorkspace(WorkspaceID)
    /// Move the active workspace's focused window to the workspace labeled by the bound key.
    case moveFocusedWindow(WorkspaceID)
    /// Return to the previously active workspace.
    case backAndForth
    /// Move focus to the neighboring tile in the given direction within the active workspace.
    case focusTile(Direction)
    /// Swap the focused tile with its neighbor in the given direction.
    case moveTile(Direction)
}

/// Pure mapping from (keyCode, modifiers) to a `Hotkey`. v1 binding scheme:
/// - `alt + digit/letter` → jump to that workspace
/// - `alt + shift + digit/letter` → move focused window to that workspace
/// - `alt + tab` → back-and-forth
public enum HotkeyDecoder {
    public static func decode(keyCode: UInt16, modifiers: Modifiers) -> Hotkey? {
        let base = modifiers.subtracting(.shift)
        guard base == .option else { return nil }
        if keyCode == kTab {
            return modifiers.contains(.shift) ? nil : .backAndForth
        }
        if let direction = tileDirections[keyCode] {
            return modifiers.contains(.shift) ? .moveTile(direction)
                                              : .focusTile(direction)
        }
        guard let label = workspaceLabel(forKeyCode: keyCode) else { return nil }
        return modifiers.contains(.shift) ? .moveFocusedWindow(label)
                                          : .switchWorkspace(label)
    }

    private static let kTab: UInt16 = 48

    /// Vim-style HJKL → tile direction. H/J/K/L are intentionally omitted from
    /// `labels` so they reach this map first.
    private static let tileDirections: [UInt16: Direction] = [
        4: .left,    // H
        38: .down,   // J
        40: .up,     // K
        37: .right,  // L
    ]

    /// macOS virtual key codes for the digits 0–9 and letters A–Z mapped to their canonical
    /// workspace label string. Workspaces are identified by their key glyph (CONTEXT.md).
    /// H/J/K/L are deliberately absent — they're reserved for focus-tile / move-tile commands
    /// (AeroSpace muscle-memory parity; tile commands land in v1.1).
    private static let labels: [UInt16: String] = [
        // digits
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        // letters (H=4, J=38, K=40, L=37 intentionally omitted)
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G",         34: "I",
                                                              46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
    ]

    private static func workspaceLabel(forKeyCode keyCode: UInt16) -> String? {
        labels[keyCode]
    }
}
