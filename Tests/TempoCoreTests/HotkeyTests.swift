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

    @Test("alt+h and alt+l decode to focusTile .left / .right")
    func altFocusHL() {
        #expect(HotkeyDecoder.decode(keyCode: kH, modifiers: .option) == .focusTile(.left))
        #expect(HotkeyDecoder.decode(keyCode: kL, modifiers: .option) == .focusTile(.right))
    }

    @Test("alt+j and alt+k decode to focusTile .down / .up (handler responsible for no-op)")
    func altFocusJK() {
        #expect(HotkeyDecoder.decode(keyCode: kJ, modifiers: .option) == .focusTile(.down))
        #expect(HotkeyDecoder.decode(keyCode: kK, modifiers: .option) == .focusTile(.up))
    }

    @Test("alt+shift+h and alt+shift+l decode to moveTile .left / .right")
    func altShiftMoveHL() {
        #expect(HotkeyDecoder.decode(keyCode: kH, modifiers: [.option, .shift]) == .moveTile(.left))
        #expect(HotkeyDecoder.decode(keyCode: kL, modifiers: [.option, .shift]) == .moveTile(.right))
    }

    @Test("alt+shift+j and alt+shift+k decode to moveTile .down / .up")
    func altShiftMoveJK() {
        #expect(HotkeyDecoder.decode(keyCode: kJ, modifiers: [.option, .shift]) == .moveTile(.down))
        #expect(HotkeyDecoder.decode(keyCode: kK, modifiers: [.option, .shift]) == .moveTile(.up))
    }

    @Test("alt+shift+tab is NOT back-and-forth (reserved for move-workspace-to-monitor, N/A here)")
    func altShiftTabUnbound() {
        #expect(HotkeyDecoder.decode(keyCode: kTab, modifiers: [.option, .shift]) == nil)
    }

    let kSlash: UInt16 = 44

    @Test("alt+slash decodes to toggleTileOrientation")
    func altSlashTogglesOrientation() {
        #expect(HotkeyDecoder.decode(keyCode: kSlash, modifiers: .option) == .toggleTileOrientation)
    }

    @Test("alt+shift+slash returns nil (only the unshifted chord toggles)")
    func altShiftSlashUnbound() {
        #expect(HotkeyDecoder.decode(keyCode: kSlash, modifiers: [.option, .shift]) == nil)
    }

    let kComma: UInt16 = 43

    @Test("alt+comma decodes to toggleAccordion")
    func altCommaTogglesAccordion() {
        #expect(HotkeyDecoder.decode(keyCode: kComma, modifiers: .option) == .toggleAccordion)
    }

    @Test("alt+shift+comma returns nil")
    func altShiftCommaUnbound() {
        #expect(HotkeyDecoder.decode(keyCode: kComma, modifiers: [.option, .shift]) == nil)
    }
}
