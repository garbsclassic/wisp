import Carbon.HIToolbox
import Testing

@testable import WispCore

@Suite("KeyChord parsing")
struct KeyChordParseTests {
    @Test("The default summon chord parses to ctrl+opt+period")
    func summonDefault() throws {
        let chord = try #require(KeyChord.parse("ctrl+opt+."))
        #expect(chord.keyCode == UInt32(kVK_ANSI_Period))
        #expect(chord.carbonModifiers == UInt32(controlKey | optionKey))
    }

    /// Order and spacing are the user's business, not the parser's.
    @Test("Modifier order and spacing don't matter")
    func orderInsensitive() throws {
        let a = try #require(KeyChord.parse("ctrl+opt+."))
        let b = try #require(KeyChord.parse(" opt + ctrl + . "))
        #expect(a.keyCode == b.keyCode)
        #expect(a.carbonModifiers == b.carbonModifiers)
    }

    @Test("Every spelling of a modifier lands on the same mask")
    func modifierSpellings() throws {
        let masks = ["cmd+a", "command+a", "⌘+a"].compactMap { KeyChord.parse($0)?.carbonModifiers }
        #expect(masks == [UInt32(cmdKey), UInt32(cmdKey), UInt32(cmdKey)])
    }

    @Test(
        "Malformed chords are rejected rather than half-read",
        arguments: ["", "+", "ctrl+opt", "ctrl+a+b", "ctrl+opt+nosuchkey"]
    )
    func rejected(text: String) {
        #expect(KeyChord.parse(text) == nil)
    }

    /// `hyper` and the glyph both spell "all four modifiers at once", so a
    /// remapped Caps Lock is one token in the config rather than four.
    @Test("hyper and ❖ expand to all four modifiers", arguments: ["hyper+.", "❖+."])
    func hyper(text: String) throws {
        let chord = try #require(KeyChord.parse(text))
        let spelled = try #require(KeyChord.parse("ctrl+opt+shift+cmd+."))
        #expect(chord.keyCode == spelled.keyCode)
        #expect(chord.carbonModifiers == spelled.carbonModifiers)
        // Naming one of the four again is redundant, not an error.
        #expect(KeyChord.parse("hyper+cmd+.")?.carbonModifiers == spelled.carbonModifiers)
    }

    @Test("All four modifiers spell themselves back as hyper")
    func hyperRoundTrip() {
        let all = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        #expect(KeyChord.string(keyCode: UInt32(kVK_ANSI_Period), carbonModifiers: all) == "hyper+.")
    }

    @Test("A bare key with no modifiers is still a chord")
    func bareKey() throws {
        #expect(try #require(KeyChord.parse("f5")).carbonModifiers == 0)
    }
}

@Suite("KeyChord rendering")
struct KeyChordRenderTests {
    /// The shortcut-capture overlay hands back Carbon integers, and what has
    /// to land in the config is text the parser will accept again.
    @Test(
        "A captured chord round-trips through the config's own string form",
        arguments: ["ctrl+opt+.", "cmd+shift+p", "opt+space", "f5", "cmd+opt+left"]
    )
    func roundTrip(text: String) throws {
        let parsed = try #require(KeyChord.parse(text))
        let rendered = try #require(
            KeyChord.string(keyCode: parsed.keyCode, carbonModifiers: parsed.carbonModifiers)
        )
        let reparsed = try #require(KeyChord.parse(rendered))
        #expect(reparsed.keyCode == parsed.keyCode)
        #expect(reparsed.carbonModifiers == parsed.carbonModifiers)
    }

    /// Every code round-trips to *one* spelling, so the same chord captured
    /// twice never writes two different strings into the file.
    @Test("Rendering picks the canonical spelling, not an alias")
    func canonicalSpelling() {
        #expect(
            KeyChord.string(keyCode: UInt32(kVK_ANSI_Period), carbonModifiers: 0) == "."
        )
        #expect(KeyChord.string(keyCode: UInt32(kVK_Escape), carbonModifiers: 0) == "escape")
    }

    @Test("An unmapped key code has no spelling and fails rather than lying")
    func unmappedKeyCode() {
        #expect(KeyChord.string(keyCode: 9999, carbonModifiers: UInt32(cmdKey)) == nil)
    }
}
