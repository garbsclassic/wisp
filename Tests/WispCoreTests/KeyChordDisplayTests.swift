import AppKit
import Carbon.HIToolbox
import Testing

@testable import WispCore

@Suite("KeyChord display")
struct KeyChordDisplayTests {
    /// Glyph order is fixed at ⌃⌥⇧⌘ regardless of how the modifiers were
    /// captured, so the same chord always reads the same way.
    @Test("Modifier glyphs render in a fixed order")
    func glyphOrder() {
        let cmdShiftP = KeyChord(
            keyCode: UInt32(kVK_ANSI_P), carbonModifiers: UInt32(cmdKey | shiftKey))
        #expect(cmdShiftP.displayString == "⇧⌘P")

        let ctrlOptSlash = KeyChord(
            keyCode: UInt32(kVK_ANSI_Slash), carbonModifiers: UInt32(controlKey | optionKey))
        #expect(ctrlOptSlash.displayString == "⌃⌥/")
    }

    /// All four at once is a hyperkey, not four modifiers — and `⌃⌥⇧⌘` is
    /// four fifths of a help-page row before the key even arrives.
    @Test("All four modifiers collapse to the hyperkey glyph")
    func hyperkey() {
        let hyperPeriod = KeyChord(
            keyCode: UInt32(kVK_ANSI_Period),
            carbonModifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        #expect(hyperPeriod.displayString == "❖.")

        // One modifier short is still spelled out — the glyph stands for the
        // whole set or it means nothing.
        let almost = KeyChord(
            keyCode: UInt32(kVK_ANSI_Period),
            carbonModifiers: UInt32(controlKey | optionKey | shiftKey)
        )
        #expect(almost.displayString == "⌃⌥⇧.")
    }

    @Test("An unmapped key code degrades to a readable placeholder")
    func unknownKeyCode() {
        #expect(
            KeyChord(keyCode: 9999, carbonModifiers: UInt32(cmdKey)).displayString == "⌘Key9999")
    }

    @Test("AppKit modifier flags convert to their Carbon masks")
    func carbonModifiers() {
        #expect(KeyChord.carbonModifiers(from: [.command]) == UInt32(cmdKey))
        #expect(KeyChord.carbonModifiers(from: [.option, .shift]) == UInt32(optionKey | shiftKey))
        #expect(
            KeyChord.carbonModifiers(from: [.command, .option, .shift, .control])
                == UInt32(cmdKey | optionKey | shiftKey | controlKey)
        )
        #expect(KeyChord.carbonModifiers(from: []) == 0)
        // An arrow key's event carries these too; a chord never spells them.
        #expect(
            KeyChord.carbonModifiers(from: [.command, .function, .numericPad]) == UInt32(cmdKey))
    }

    @Test("Carbon masks convert back to AppKit flags, which share CGEventFlags' bits")
    func modifierFlags() {
        let chord = KeyChord(
            keyCode: UInt32(kVK_ANSI_9),
            carbonModifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
        #expect(chord.modifierFlags == [.control, .option, .shift, .command])
        #expect(
            CGEventFlags(rawValue: UInt64(chord.modifierFlags.rawValue))
                == [.maskControl, .maskAlternate, .maskShift, .maskCommand])
        #expect(KeyChord(keyCode: 0, carbonModifiers: 0).modifierFlags.isEmpty)
    }
}
