import Carbon.HIToolbox
import Foundation
import Testing

@testable import WispCore

@Suite("Configurable hyper key")
struct HyperKeyTests {
    private func decode(_ json: String, diagnostics: ConfigDiagnostics? = nil) throws -> WispConfig
    {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        if let diagnostics { decoder.userInfo[.configDiagnostics] = diagnostics }
        return try decoder.decode(WispConfig.self, from: Data(json.utf8))
    }

    @Test("The default and custom modifier sets expand and display consistently")
    func expansionAndDisplay() throws {
        let defaults = Keymap()
        let defaultHyper = try #require(KeyChord.parse("hyper+.", hyperKey: defaults.hyperKey))
        #expect(defaultHyper.carbonModifiers == UInt32(controlKey | optionKey | shiftKey | cmdKey))
        #expect(defaultHyper.displayString(hyperKey: defaults.hyperKey) == "❖.")

        let hyperKey = try #require(HyperKey("ctrl+alt"))
        let config = try decode(#"{"keymap":{"hyperKey":"ctrl+alt","summon":"❖+."}}"#)
        let parsed = try #require(config.keymap.parsed(.summon))
        #expect(parsed.carbonModifiers == UInt32(controlKey | optionKey))
        #expect(parsed.displayString(hyperKey: config.keymap.hyperKey) == "❖.")
        #expect(config.keymap.display(.summon) == "❖.")
        #expect(config.keymap.primaryDisplay(.summon) == "❖.")
        #expect(parsed.displayString(hyperKey: defaults.hyperKey) == "⌃⌥.")

        #expect(KeyChord.parse("ctrl+opt+.", hyperKey: hyperKey) == parsed)

        let allFour = try #require(KeyChord.parse("ctrl+opt+shift+cmd+.", hyperKey: hyperKey))
        #expect(allFour.carbonModifiers == UInt32(controlKey | optionKey | shiftKey | cmdKey))
    }

    @Test("The keymap defaults and round-trips its hyper key as a string")
    func configRoundTrip() throws {
        let config = try decode(#"{"keymap":{"hyperKey":"command+control"}}"#)
        #expect(config.keymap.hyperKey.rawValue == "command+control")

        let data = try JSONEncoder().encode(config.keymap)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["hyperKey"] as? String == "command+control")
        #expect(try JSONDecoder().decode(Keymap.self, from: data) == config.keymap)
        #expect(Keymap().hyperKey == .standard)
    }

    @Test("Invalid hyper key values fall back and are diagnosed")
    func malformedHyperKey() throws {
        let diagnostics = ConfigDiagnostics()
        let config = try decode(#"{"keymap":{"hyperKey":"ctrl+bogus"}}"#, diagnostics: diagnostics)

        #expect(config.keymap.hyperKey == .standard)
        #expect(diagnostics.malformedKeys == ["keymap.hyperKey"])
        #expect(HyperKey("❖") == nil)
        #expect(HyperKey("ctrl+.") == nil)
        #expect(HyperKey("") == nil)
    }
}
