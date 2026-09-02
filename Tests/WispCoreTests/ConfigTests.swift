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
        let config = try decode(
            #"{ "panel": { "x": 10, "y": 20, "width": 800, "height": 640 } }"#)
        #expect(config.panel == PanelFrame(width: 800, height: 640, x: 10, y: 20))
    }

    /// A size-only frame is what `position: auto` and a never-dragged
    /// `manual` panel both write, so it has to be a first-class shape and
    /// not a malformed one.
    @Test("A frame with no origin decodes as one")
    func panelFrameWithoutOrigin() throws {
        let config = try decode(#"{ "panel": { "width": 800, "height": 640 } }"#)
        #expect(config.panel?.origin == nil)
        #expect(config.panel?.width == 800)
    }

    /// A lone coordinate describes no placement, so it reads as none.
    @Test("Half an origin is no origin")
    func panelFrameHalfOrigin() throws {
        let config = try decode(#"{ "panel": { "width": 800, "height": 640, "x": 10 } }"#)
        #expect(config.panel?.origin == nil)
    }

    @Test("The pre-rename w / h keys still carry a remembered size")
    func panelFrameLegacyKeys() throws {
        let config = try decode(#"{ "panel": { "x": 10, "y": 20, "w": 800, "h": 640 } }"#)
        #expect(config.panel == PanelFrame(width: 800, height: 640, x: 10, y: 20))
    }

    /// A panel object with no size at all can't be honoured, and a key
    /// that's present but unusable is named rather than silently dropped.
    @Test("A sizeless panel object is reported, not silently defaulted")
    func panelFrameWithoutSize() throws {
        let diagnostics = ConfigDiagnostics()
        let config = try decode(#"{ "panel": { "x": 10, "y": 20 } }"#, diagnostics: diagnostics)
        #expect(config.panel == nil)
        #expect(diagnostics.malformedKeys == ["panel"])
    }

    @Test("Position defaults to auto and reads both modes")
    func position() throws {
        #expect(try decode("{}").position == .auto)
        #expect(try decode(#"{ "position": "manual" }"#).position == .manual)
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
        // The written value stays as typed so it is recoverable by editing
        // the file back; only what the Tab key inserts is clamped.
        #expect(Indent(style: .spaces, size: 400).size == 400)
        #expect(Indent(style: .spaces, size: 400).unit.count == 16)
        #expect(Indent(style: .spaces, size: 0).unit == " ")
    }

    @Test("A malformed style is named rather than swallowed")
    func malformed() throws {
        let diagnostics = ConfigDiagnostics()
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        decoder.userInfo[.configDiagnostics] = diagnostics
        let config = try decoder.decode(
            WispConfig.self, from: Data(#"{ "indent": { "style": 7 } }"#.utf8))
        #expect(config.indent.style == .spaces)
        #expect(diagnostics.malformedKeys == ["indent.style"])
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

    @Test("A removed fontSize key is ignored without a warning")
    func retiredKeyIsQuiet() throws {
        let diagnostics = ConfigDiagnostics()
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        decoder.userInfo[.configDiagnostics] = diagnostics
        let config = try decoder.decode(
            WispConfig.self, from: Data(#"{ "fontSize": "large", "fontScale": 1.2 }"#.utf8))
        #expect(config.fontScale == 1.2)
        #expect(diagnostics.malformedKeys.isEmpty)
    }
}
