import Foundation
import Testing

@testable import WispCore

private func decode(_ json: String, diagnostics: ConfigDiagnostics? = nil) throws -> WispConfig {
    let decoder = JSONDecoder()
    decoder.allowsJSON5 = true
    if let diagnostics { decoder.userInfo[.configDiagnostics] = diagnostics }
    return try decoder.decode(WispConfig.self, from: Data(json.utf8))
}

@Suite("Config decoding")
struct ConfigDecodingTests {
    /// Adding a setting must never invalidate a config someone already wrote.
    @Test("An empty object decodes to the defaults")
    func emptyObject() throws {
        #expect(try decode("{}") == WispConfig())
    }

    @Test("A partial config keeps its own values and defaults the rest")
    func partial() throws {
        let config = try decode(#"{ "theme": "dark", "fontScale": 1.25 }"#)
        #expect(config.theme == .dark)
        #expect(config.fontScale == 1.25)
        #expect(config.fonts == FontSet())
        #expect(config.monitor == .primary)
    }

    @Test("Nested keys default independently")
    func nestedDefaults() throws {
        let config = try decode(#"{ "fonts": { "ui": "Helvetica" } }"#)
        #expect(config.fonts.ui == "Helvetica")
        #expect(config.fonts.notes == FontSet().notes)
    }

    @Test("A sizeless panel object is reported, not silently defaulted")
    func panelFrameWithoutSize() throws {
        let diagnostics = ConfigDiagnostics()
        let config = try decode(#"{ "panel": { "width": 800 } }"#, diagnostics: diagnostics)
        #expect(config.panel == nil)
        #expect(diagnostics.malformedKeys == ["panel"])
    }
}

@Suite("Config diagnostics")
struct ConfigDiagnosticsTests {
    @Test("A malformed key is named and its default still applies")
    func malformedKey() throws {
        let diagnostics = ConfigDiagnostics()
        let config = try decode(#"{ "saveIndicator": "yes please" }"#, diagnostics: diagnostics)
        #expect(config.saveIndicator == WispConfig().saveIndicator)
        #expect(diagnostics.malformedKeys == ["saveIndicator"])
        #expect(diagnostics.summary == "Ignored unreadable config key: saveIndicator")
    }

    @Test("A nested malformed key is reported with its path")
    func nestedPath() throws {
        let diagnostics = ConfigDiagnostics()
        _ = try decode(#"{ "keymap": { "summon": 42 } }"#, diagnostics: diagnostics)
        #expect(diagnostics.malformedKeys == ["keymap.summon"])
    }

    @Test("An unknown enum value is malformed, not fatal")
    func unknownEnumCase() throws {
        let diagnostics = ConfigDiagnostics()
        let config = try decode(#"{ "monitor": "projector" }"#, diagnostics: diagnostics)
        #expect(config.monitor == .primary)
        #expect(diagnostics.malformedKeys == ["monitor"])
    }

    @Test("A missing key is quiet — only a wrong shape is worth reporting")
    func missingKeyIsQuiet() throws {
        let diagnostics = ConfigDiagnostics()
        _ = try decode("{}", diagnostics: diagnostics)
        #expect(diagnostics.summary == nil)
    }

    @Test("Several bad keys are summarised together")
    func plural() throws {
        let diagnostics = ConfigDiagnostics()
        _ = try decode(#"{ "saveIndicator": 1.5, "theme": [] }"#, diagnostics: diagnostics)
        #expect(diagnostics.summary == "Ignored unreadable config keys: theme, saveIndicator")
    }
}

@Suite("Config derived values")
struct ConfigDerivedTests {
    @Test(
        "Type scale is bounded so a typo can't make the app unusable",
        arguments: [(1.0, 1.0), (0.1, 0.6), (99.0, 2.5), (2.5, 2.5), (0.6, 0.6)]
    )
    func fontScaleClamp(raw: Double, clamped: Double) {
        #expect(WispConfig(fontScale: raw).clampedFontScale == clamped)
    }

    @Test("A broken summon chord falls back to the default and is flagged")
    func brokenChord() {
        let config = WispConfig(keymap: Keymap([.summon: ChordSet(["ctrl+opt+nosuchkey"])]))
        #expect(!config.summonChordIsValid)
        #expect(config.summonChord == WispConfig().summonChord)
    }

    @Test("An empty scratchpad path means the default folder")
    func scratchpadFolder() {
        #expect(WispConfig().scratchpadFolderPath == StorageLocation.defaultFolder)
        #expect(
            WispConfig(scratchpadFolder: "~/Notes").scratchpadFolderPath.path
                == NSString(string: "~/Notes").expandingTildeInPath
        )
    }
}

@Suite("Indent")
struct IndentConfigTests {
    private func decode(_ json: String) throws -> WispConfig {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(WispConfig.self, from: Data(json.utf8))
    }

    @Test("Defaults to two spaces")
    func defaults() throws {
        let config = try decode("{}")
        #expect(config.indent == Indent())
        #expect(config.indent.unit == "  ")
        #expect(config.indent.width == 2)
    }

    @Test("Tabs ignore the size")
    func tabs() throws {
        let config = try decode(#"{ "indent": { "style": "tabs", "size": 8 } }"#)
        #expect(config.indent.unit == "\t")
        // One tab is one level, however wide the reader renders it.
        #expect(config.indent.width == 1)
    }

    @Test("A size is decoded and used")
    func size() throws {
        #expect(try decode(#"{ "indent": { "size": 4 } }"#).indent.unit == "    ")
    }

    @Test("An absurd size is bounded on the way out, not on the way in")
    func bounded() {
        #expect(Indent(style: .spaces, size: 400).size == 400)
        #expect(Indent(style: .spaces, size: 400).unit.count == 16)
        #expect(Indent(style: .spaces, size: 0).unit == " ")
    }
}

@Suite("Caret")
struct CaretConfigTests {
    private func decode(_ json: String) throws -> WispConfig {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(WispConfig.self, from: Data(json.utf8))
    }

    @Test("A partial caret object keeps blink at its default")
    func partial() throws {
        let config = try decode(#"{ "caret": { "motion": "off" } }"#)
        #expect(config.caret.motion == .off)
        #expect(config.caret.blink)
    }
}

@Suite("Background")
struct BackgroundConfigTests {
    private func decode(_ json: String) throws -> WispConfig {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(WispConfig.self, from: Data(json.utf8))
    }

    @Test("A partial background object keeps blur at its default")
    func partial() throws {
        let config = try decode(#"{ "background": { "opacity": 1 } }"#)
        #expect(config.background.blur)
        #expect(config.background.opacity == 1)
    }

    @Test(
        "Opacity is clamped to 0...1 on the way out",
        arguments: [(1.7, 1.0), (-0.2, 0.0), (0.5, 0.5)]
    )
    func opacityClamp(raw: Double, clamped: Double) {
        #expect(Background(opacity: raw).clampedOpacity == clamped)
    }
}

@Suite("Default font scale")
struct DefaultFontScaleTests {
    @Test("Defaults to 1.0 and is clamped like the live value")
    func clamped() {
        #expect(WispConfig().defaultFontScale == 1.0)
        #expect(WispConfig(defaultFontScale: 9).clampedDefaultFontScale
            == Metrics.fontScaleRange.upperBound)
    }
}

@Suite("Position")
struct PositionConfigTests {
    private func decode(_ json: String, diagnostics: ConfigDiagnostics? = nil) throws -> WispConfig {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        if let diagnostics { decoder.userInfo[.configDiagnostics] = diagnostics }
        return try decoder.decode(WispConfig.self, from: Data(json.utf8))
    }

    @Test("An explicit null means nil without a diagnostic")
    func explicitNull() throws {
        let diagnostics = ConfigDiagnostics()
        let config = try decode(#"{ "position": null }"#, diagnostics: diagnostics)
        #expect(config.position == nil)
        #expect(diagnostics.malformedKeys.isEmpty)
    }
}

@Suite("Peek hold")
struct PeekHoldConfigTests {
    @Test("Converts to seconds, clamping a negative value to 0")
    func seconds() {
        #expect(WispConfig(peekHold: 250).peekHoldSeconds == 0.25)
        #expect(WispConfig(peekHold: 0).peekHoldSeconds == 0)
        #expect(WispConfig(peekHold: -100).peekHoldSeconds == 0)
    }
}
