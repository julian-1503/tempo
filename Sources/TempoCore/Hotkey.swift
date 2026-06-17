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
    /// Toggle the active workspace's tile orientation between horizontal and vertical.
    case toggleTileOrientation
    /// Toggle the active workspace's layout mode between tiles and accordion.
    case toggleAccordion
    /// Toggle fullscreen for the focused window in the active workspace.
    case toggleFullscreen
    /// Toggle the floating flag for the focused window in the active workspace.
    case toggleFloating
    /// Pause/resume Tempo. While paused, hidden windows are restored to screen and the
    /// daemon stops moving things — only the resume chord and `quit` still fire.
    case togglePaused
    /// Apply the named Scene. Triggered by user-configured `[scenes]` bindings in
    /// `tempo.toml` (e.g. `main = "alt+ctrl+m"`).
    case applyScene(String)
}

/// Parsed chord — a key code plus its required modifier set. The decoder/daemon
/// uses this to match the configured `[scenes]` bindings before falling through
/// to the built-in chord map.
public struct ChordBinding: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: Modifiers
    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }
}

/// Parse a chord string like `"alt+ctrl+m"`, `"cmd+shift+f1"`, `"alt+space"` into
/// a `ChordBinding`. Returns nil on unknown modifier names, unknown key names, or
/// missing key. Case- and whitespace-insensitive. Modifiers: `alt`/`option`,
/// `shift`, `ctrl`/`control`, `cmd`/`command`. Keys: a-z, 0-9, `tab`, `space`,
/// `escape`, `slash`, `comma`, `semicolon`, `quote`, `backtick`, `f1`–`f12`.
public func parseChord(_ chord: String) -> ChordBinding? {
    let parts = chord.lowercased().split(separator: "+").map {
        $0.trimmingCharacters(in: .whitespaces)
    }
    var mods: Modifiers = []
    var keyName: String?
    for part in parts {
        switch part {
        case "alt", "option": mods.insert(.option)
        case "shift": mods.insert(.shift)
        case "ctrl", "control": mods.insert(.control)
        case "cmd", "command": mods.insert(.command)
        case "": return nil
        default:
            if keyName != nil { return nil }
            keyName = part
        }
    }
    guard let name = keyName, let kc = chordKeyCode(for: name) else { return nil }
    return ChordBinding(keyCode: kc, modifiers: mods)
}

private let chordKeyCodeMap: [String: UInt16] = [
    // letters
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34,
    "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15,
    "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    // digits
    "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    // named keys
    "tab": 48, "space": 49, "escape": 53, "esc": 53,
    "return": 36, "enter": 36,
    "slash": 44, "comma": 43, "semicolon": 41, "quote": 39, "backtick": 50, "grave": 50,
    "minus": 27, "equal": 24, "period": 47,
    // function keys
    "f1": 122, "f2": 120, "f3": 99,  "f4": 118, "f5": 96,  "f6": 97,
    "f7": 98,  "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
]

private func chordKeyCode(for name: String) -> UInt16? { chordKeyCodeMap[name] }

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
        if keyCode == kSlash {
            return modifiers.contains(.shift) ? nil : .toggleTileOrientation
        }
        if keyCode == kComma {
            return modifiers.contains(.shift) ? nil : .toggleAccordion
        }
        if keyCode == kSpace {
            return modifiers.contains(.shift) ? nil : .toggleFloating
        }
        if let direction = tileDirections[keyCode] {
            return modifiers.contains(.shift) ? .moveTile(direction)
                                              : .focusTile(direction)
        }
        // alt+shift+f wins over move-to-workspace-F so AeroSpace's fullscreen muscle
        // memory carries over. alt+f still switches to workspace F.
        if keyCode == kF && modifiers.contains(.shift) {
            return .toggleFullscreen
        }
        // alt+shift+escape pauses/resumes the whole daemon — the escape hatch back to
        // a normal-mac-windowing session without quitting Tempo.
        if keyCode == kEscape && modifiers.contains(.shift) {
            return .togglePaused
        }
        guard let label = workspaceLabel(forKeyCode: keyCode) else { return nil }
        return modifiers.contains(.shift) ? .moveFocusedWindow(label)
                                          : .switchWorkspace(label)
    }

    private static let kTab: UInt16 = 48
    private static let kSlash: UInt16 = 44
    private static let kComma: UInt16 = 43
    private static let kF: UInt16 = 3
    private static let kSpace: UInt16 = 49
    private static let kEscape: UInt16 = 53

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
