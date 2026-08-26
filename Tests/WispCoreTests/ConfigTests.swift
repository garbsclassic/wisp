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
    /// The property that makes the file hand-editable: adding a setting to
    /// the app must never invalidate a config someone already wrote.
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

    /// JSON5 is a strict superset of JSONC, so the reader takes comments and
    /// trailing commas with no hand-rolled stripper.
    @Test("Comments and trailing commas parse")
    func jsonc() throws {
        let config = try decode(
            """
            {
                // the summon chord
                "keymap": { "summon": "cmd+opt+w" },
                /* block */
                "vibrancy": false,
            }
            """)
        #expect(config.keymap.summon == "cmd+opt+w")
        #expect(!config.vibrancy)
    }

    @Test("Nested keys default independently")
    func nestedDefaults() throws {
        let config = try decode(#"{ "fonts": { "ui": "Helvetica" } }"#)
        #expect(config.fonts.ui == "Helvetica")
        #expect(config.fonts.notes == FontSet().notes)
    }

    @Test("A remembered frame decodes, and its absence is not an error")
    func panelFrame() throws {
        #expect(try decode("{}").panel == nil)
        let config = try decode(#"{ "panel": { "x": 10, "y": 20, "w": 800, "h": 640 } }"#)
        #expect(config.panel == PanelFrame(x: 10, y: 20, w: 800, h: 640))
    }
}

@Suite("Config diagnostics")
struct ConfigDiagnosticsTests {
    /// A key that is present but the wrong shape looks like it's doing
    /// something and isn't — so it gets named instead of silently defaulting.
    @Test("A malformed key is named and its default still applies")
    func malformedKey() throws {
        let diagnostics = ConfigDiagnostics()
        let config = try decode(#"{ "vibrancy": "yes please" }"#, diagnostics: diagnostics)
        #expect(config.vibrancy == WispConfig().vibrancy)
        #expect(diagnostics.malformedKeys == ["vibrancy"])
        #expect(diagnostics.summary == "Ignored unreadable config key: vibrancy")
    }

    /// A bare "summon" would leave you hunting for which section it's in.
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
        _ = try decode(#"{ "vibrancy": 1.5, "theme": [] }"#, diagnostics: diagnostics)
        #expect(diagnostics.summary == "Ignored unreadable config keys: theme, vibrancy")
    }
}

@Suite("Config derived values")
struct ConfigDerivedTests {
    /// Clamping happens on the way out, not on the way in: the file keeps
    /// what was typed, so editing it back is all it takes to recover.
    @Test(
        "Type scale is bounded so a typo can't make the app unusable",
        arguments: [(1.0, 1.0), (0.1, 0.6), (99.0, 2.5), (2.5, 2.5), (0.6, 0.6)]
    )
    func fontScaleClamp(raw: Double, clamped: Double) {
        #expect(WispConfig(fontScale: raw).clampedFontScale == clamped)
    }

    /// An unparseable chord would otherwise leave the app with no way to open
    /// at all, so the default stands in and the footer says why.
    @Test("A broken summon chord falls back to the default and is flagged")
    func brokenChord() {
        let config = WispConfig(keymap: Keymap(summon: "ctrl+opt+nosuchkey"))
        #expect(!config.summonChordIsValid)
        #expect(config.summonChord == WispConfig().summonChord)
    }

    @Test("An empty scratchpad path means the default folder")
    func scratchpadFolder() {
        #expect(WispConfig().scratchpadFolder == StorageLocation.defaultFolder)
        #expect(
            WispConfig(scratchpadPath: "~/Notes").scratchpadFolder.path
                == NSString(string: "~/Notes").expandingTildeInPath
        )
    }
}
