import Testing
@testable import TempoCore

@Suite("Hotkey decoder")
struct HotkeyTests {
    // macOS virtual key codes used in the tests below.
    let kA: UInt16 = 0
    let kQ: UInt16 = 12
    let k1: UInt16 = 18
    let k2: UInt16 = 19
    let kTab: UInt16 = 48
    let kEscape: UInt16 = 53

    @Test("alt + digit jumps to that workspace")
    func altDigitJumps() {
        #expect(HotkeyDecoder.decode(keyCode: k1, modifiers: .option) == .switchWorkspace("1"))
        #expect(HotkeyDecoder.decode(keyCode: k2, modifiers: .option) == .switchWorkspace("2"))
    }

    @Test("alt + letter jumps to that workspace (uppercase label)")
    func altLetterJumps() {
        #expect(HotkeyDecoder.decode(keyCode: kA, modifiers: .option) == .switchWorkspace("A"))
        #expect(HotkeyDecoder.decode(keyCode: kQ, modifiers: .option) == .switchWorkspace("Q"))
    }

    @Test("alt + shift + key moves the focused window to that workspace")
    func altShiftKeyMoves() {
        #expect(HotkeyDecoder.decode(keyCode: k1, modifiers: [.option, .shift]) ==
                .moveFocusedWindow("1"))
        #expect(HotkeyDecoder.decode(keyCode: kA, modifiers: [.option, .shift]) ==
                .moveFocusedWindow("A"))
    }

    @Test("alt + tab is back-and-forth")
    func altTabBack() {
        #expect(HotkeyDecoder.decode(keyCode: kTab, modifiers: .option) == .backAndForth)
    }

    @Test("missing the alt modifier returns nil")
    func missingAlt() {
        #expect(HotkeyDecoder.decode(keyCode: k1, modifiers: []) == nil)
        #expect(HotkeyDecoder.decode(keyCode: k1, modifiers: .shift) == nil)
    }

    @Test("extra modifiers (cmd, ctrl) disqualify the chord")
    func extraModifiers() {
        #expect(HotkeyDecoder.decode(keyCode: k1, modifiers: [.option, .command]) == nil)
        #expect(HotkeyDecoder.decode(keyCode: k1, modifiers: [.option, .control]) == nil)
    }

    @Test("unmapped key returns nil")
    func unmappedKey() {
        #expect(HotkeyDecoder.decode(keyCode: kEscape, modifiers: .option) == nil)
    }

    // macOS virtual key codes for the vim-style focus row.
    let kH: UInt16 = 4
    let kJ: UInt16 = 38
    let kK: UInt16 = 40
    let kL: UInt16 = 37

    @Test("h/j/k/l do NOT jump to workspace (reserved for focus-tile, AeroSpace-compat)")
    func hjklReservedForFocus() {
        for kc in [kH, kJ, kK, kL] {
            #expect(HotkeyDecoder.decode(keyCode: kc, modifiers: .option) == nil)
        }
    }

    @Test("alt+shift+h/j/k/l do NOT move to workspace (reserved for move-tile, AeroSpace-compat)")
    func hjklReservedForMove() {
        for kc in [kH, kJ, kK, kL] {
            #expect(HotkeyDecoder.decode(keyCode: kc, modifiers: [.option, .shift]) == nil)
        }
    }

    @Test("alt+shift+tab is NOT back-and-forth (reserved for move-workspace-to-monitor, N/A here)")
    func altShiftTabUnbound() {
        #expect(HotkeyDecoder.decode(keyCode: kTab, modifiers: [.option, .shift]) == nil)
    }
}
