import AppKit
import Carbon.HIToolbox
import Testing

@testable import WispCore

@Suite("HotKey")
struct HotKeyTests {
    @Test("The default binding is ⌥Space")
    func defaultBinding() {
        #expect(HotKey.default.keyCode == UInt32(kVK_Space))
        #expect(HotKey.default.modifiers == UInt32(optionKey))
        #expect(HotKey.default.displayString == "⌥Space")
    }

    /// Glyph order is fixed at ⌃⌥⇧⌘ regardless of how the modifiers were
    /// captured, so the same chord always reads the same way.
    @Test("Modifier glyphs render in a fixed order")
    func glyphOrder() {
        let cmdShiftP = HotKey(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey))
        #expect(cmdShiftP.displayString == "⇧⌘P")

        let allMods = HotKey(
            keyCode: UInt32(kVK_ANSI_F),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        #expect(allMods.displayString == "⌃⌥⇧⌘F")
    }

    @Test("An unmapped key code degrades to a readable placeholder")
    func unknownKeyCode() {
        #expect(HotKey(keyCode: 9999, modifiers: UInt32(cmdKey)).displayString == "⌘Key9999")
    }

    @Test("AppKit modifier flags convert to their Carbon masks")
    func carbonModifiers() {
        #expect(HotKey.carbonModifiers(from: [.command]) == UInt32(cmdKey))
        #expect(HotKey.carbonModifiers(from: [.option, .shift]) == UInt32(optionKey | shiftKey))
        #expect(
            HotKey.carbonModifiers(from: [.command, .option, .shift, .control])
                == UInt32(cmdKey | optionKey | shiftKey | controlKey)
        )
        #expect(HotKey.carbonModifiers(from: []) == 0)
    }
}
