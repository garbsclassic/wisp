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

    @Test("Every action has a chord that parses")
    func defaultsAllParse() {
        let keymap = Keymap()
        for action in KeymapAction.allCases {
            #expect(keymap.parsed(action) != nil, "\(action.rawValue) has an unparseable default")
        }
        #expect(keymap.unparseableActions.isEmpty)
    }

    @Test("No two actions share a chord")
    func defaultsAreUnique() {
        let chords = KeymapAction.allCases.map(\.defaultChord)
        #expect(Set(chords).count == chords.count)
    }

    @Test("A partial keymap object keeps the defaults for everything else")
    func partialOverlay() throws {
        let config = try decode(#"{ "keymap": { "bold": "cmd+shift+b" } }"#)
        #expect(config.keymap.chord(for: .bold) == "cmd+shift+b")
        #expect(config.keymap.chord(for: .italic) == KeymapAction.italic.defaultChord)
        #expect(config.keymap.chord(for: .summon) == KeymapAction.summon.defaultChord)
    }

    @Test("A malformed chord value is named rather than swallowed")
    func malformedValue() throws {
        let diagnostics = ConfigDiagnostics()
        let config = try decode(#"{ "keymap": { "bold": 7 } }"#, diagnostics: diagnostics)
        #expect(config.keymap.chord(for: .bold) == KeymapAction.bold.defaultChord)
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
        let object = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(object?.count == KeymapAction.allCases.count)
        for action in KeymapAction.allCases {
            #expect(object?[action.rawValue] == action.defaultChord)
        }
    }

    @Test("A round trip through JSON preserves an override")
    func roundTrip() throws {
        var keymap = Keymap()
        keymap.setChord("ctrl+opt+k", for: .highlight)
        let decoded = try JSONDecoder().decode(Keymap.self, from: JSONEncoder().encode(keymap))
        #expect(decoded == keymap)
        #expect(decoded.chord(for: .highlight) == "ctrl+opt+k")
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
            #expect(
                keymap.parsed(action)?.menuEquivalent != nil,
                "\(action.rawValue) has no menu equivalent")
        }
    }
}
