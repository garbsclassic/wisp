import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import WispCore

@Suite("Keymap")
struct KeymapTests {
    private func decode(_ json: String, diagnostics: ConfigDiagnostics? = nil) throws -> WispConfig {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        if let diagnostics { decoder.userInfo[.configDiagnostics] = diagnostics }
        return try decoder.decode(WispConfig.self, from: Data(json.utf8))
    }

    @Test("Every action has at least one chord that parses")
    func defaultsAllParse() {
        let keymap = Keymap()
        for action in KeymapAction.allCases {
            #expect(
                !keymap.parsedChords(for: action).isEmpty,
                "\(action.rawValue) has no parseable default")
        }
        #expect(keymap.unparseableActions.isEmpty)
    }

    @Test("No chord is bound to two actions")
    func defaultsAreUnique() {
        let all = KeymapAction.allCases.flatMap(\.defaultChords.chords)
        #expect(Set(all).count == all.count)
    }

    @Test("A partial keymap object keeps the defaults for everything else")
    func partialOverlay() throws {
        let config = try decode(#"{ "keymap": { "bold": "cmd+shift+b" } }"#)
        #expect(config.keymap.chord(for: .bold) == "cmd+shift+b")
        #expect(config.keymap.chordSet(for: .italic) == KeymapAction.italic.defaultChords)
        #expect(config.keymap.chordSet(for: .summon) == KeymapAction.summon.defaultChords)
    }

    @Test("A malformed chord value is named rather than swallowed")
    func malformedValue() throws {
        let diagnostics = ConfigDiagnostics()
        let config = try decode(#"{ "keymap": { "bold": 7 } }"#, diagnostics: diagnostics)
        #expect(config.keymap.chordSet(for: .bold) == KeymapAction.bold.defaultChords)
        #expect(diagnostics.malformedKeys == ["keymap.bold"])
    }

    @Test("An unparseable chord leaves that action unbound and flagged")
    func unparseableChord() throws {
        let config = try decode(#"{ "keymap": { "bold": "cmd+nosuchkey" } }"#)
        #expect(config.keymap.parsed(.bold) == nil)
        #expect(config.keymap.unparseableActions == [.bold])
        // Only that one — the rest are untouched.
        #expect(config.keymap.parsed(.italic) != nil)
    }

    @Test("Encoding writes every action, so a seeded file lists them all")
    func encodesEveryAction() throws {
        let data = try JSONEncoder().encode(Keymap())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?.count == KeymapAction.allCases.count)
        // Single chords encode as a bare string; only an alias list becomes
        // an array, so a seeded file has no one-element arrays in it.
        #expect(object?["bold"] as? String == "cmd+b")
        #expect(object?["help"] as? [String] == ["f1", "cmd+/"])
    }

    @Test("A round trip through JSON preserves an override")
    func roundTrip() throws {
        var keymap = Keymap()
        keymap.setChord("ctrl+opt+k", for: .highlight)
        let decoded = try JSONDecoder().decode(Keymap.self, from: JSONEncoder().encode(keymap))
        #expect(decoded == keymap)
        #expect(decoded.chord(for: .highlight) == "ctrl+opt+k")
    }

    @Test("A chord list binds every entry, and one bad entry doesn't cost the others")
    func aliasList() throws {
        let config = try decode(#"{ "keymap": { "help": ["f1", "cmd+/", "cmd+nope"] } }"#)
        let parsed = config.keymap.parsedChords(for: .help)
        #expect(parsed.count == 2)
        #expect(config.keymap.unparseableActions.isEmpty)
        #expect(config.keymap.display(.help) == "F1 / ⌘/")
    }

    @Test("A bare string still decodes, so old configs keep working")
    func singleStringForm() throws {
        let config = try decode(#"{ "keymap": { "help": "cmd+h" } }"#)
        #expect(config.keymap.chordSet(for: .help) == ChordSet(["cmd+h"]))
    }

    @Test("A value that is neither a string nor a list is reported")
    func wrongShape() throws {
        let diagnostics = ConfigDiagnostics()
        let config = try decode(#"{ "keymap": { "help": { "key": "f1" } } }"#, diagnostics: diagnostics)
        #expect(config.keymap.chordSet(for: .help) == KeymapAction.help.defaultChords)
        #expect(diagnostics.malformedKeys == ["keymap.help"])
    }

    @Test("Setting a chord from the capture overlay collapses an alias list")
    func setCollapses() {
        var keymap = Keymap()
        #expect(keymap.chordSet(for: .help).chords.count == 2)
        keymap.setChord("cmd+k", for: .help)
        #expect(keymap.chordSet(for: .help) == ChordSet(["cmd+k"]))
    }

    @Test("Help defaults to F1 with ⌘/ as an alias")
    func helpDefaults() {
        #expect(KeymapAction.help.defaultChords == ["f1", "cmd+/"])
    }

    @Test("Only the actions that open the panel are unscoped")
    func scoping() {
        #expect(!KeymapAction.find.isPanelScoped)
        #expect(!KeymapAction.refresh.isPanelScoped)
        #expect(!KeymapAction.settings.isPanelScoped)
        #expect(!KeymapAction.summon.isPanelScoped)
        #expect(KeymapAction.bold.isPanelScoped)
        #expect(KeymapAction.moveLineUp.isPanelScoped)
        #expect(KeymapAction.help.isPanelScoped)
        #expect(KeymapAction.toggleTheme.isPanelScoped)
    }
}

@Suite("KeyChord — menu equivalents")
struct MenuEquivalentTests {
    @Test("A letter chord becomes its character plus a modifier mask")
    func letter() throws {
        let equivalent = try #require(KeyChord.parse("cmd+b")?.menuEquivalent)
        #expect(equivalent.character == "b")
        #expect(equivalent.modifiers == [.command])
    }

    @Test("Shift lands in the mask, never in the character")
    func shift() throws {
        // An uppercase keyEquivalent makes AppKit draw a second ⇧.
        let equivalent = try #require(KeyChord.parse("cmd+shift+b")?.menuEquivalent)
        #expect(equivalent.character == "b")
        #expect(equivalent.modifiers == [.command, .shift])
    }

    @Test("Option-only chords are legal equivalents")
    func optionOnly() throws {
        let equivalent = try #require(KeyChord.parse("opt+h")?.menuEquivalent)
        #expect(equivalent.character == "h")
        #expect(equivalent.modifiers == [.option])
    }

    @Test("Arrows use the function-key scalars AppKit reserves for them")
    func arrows() throws {
        let up = try #require(KeyChord.parse("opt+up")?.menuEquivalent)
        #expect(up.character == String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!))
        #expect(up.modifiers == [.option])

        let down = try #require(KeyChord.parse("opt+down")?.menuEquivalent)
        #expect(down.character == String(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!))
    }

    @Test("Punctuation keeps its own character")
    func punctuation() throws {
        #expect(KeyChord.parse("cmd+=")?.menuEquivalent?.character == "=")
        #expect(KeyChord.parse("cmd+-")?.menuEquivalent?.character == "-")
        #expect(KeyChord.parse("cmd+/")?.menuEquivalent?.character == "/")
        #expect(KeyChord.parse("cmd+,")?.menuEquivalent?.character == ",")
    }

    @Test("Every default chord has a menu spelling")
    func everyDefaultIsBindable() {
        let keymap = Keymap()
        for action in KeymapAction.allCases where action != .summon {
            for chord in keymap.parsedChords(for: action) {
                #expect(
                    chord.menuEquivalent != nil,
                    "\(action.rawValue) chord \(chord.raw) has no menu equivalent")
            }
        }
    }
}
