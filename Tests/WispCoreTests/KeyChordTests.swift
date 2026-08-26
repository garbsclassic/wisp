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

    @Test("Modifier glyphs render in macOS order")
    func symbolOrder() {
        #expect(KeyChord.symbols(for: "cmd+shift+opt+ctrl+f") == ["⌃", "⌥", "⇧", "⌘", "F"])
    }

    /// A menu item matches by character, so an arrow set verbatim would print
    /// the word "left" in the menu.
    @Test("Named keys become glyphs for a menu key equivalent")
    func menuEquivalents() {
        #expect(KeyChord.menuKeyEquivalent(for: "left") == "←")
        #expect(KeyChord.menuKeyEquivalent(for: "escape") == "⎋")
        #expect(KeyChord.menuKeyEquivalent(for: "f5") == "F5")
        #expect(KeyChord.menuKeyEquivalent(for: ".") == ".")
    }
}
