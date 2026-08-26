import Foundation
import Testing

@testable import WispCore

@Suite("JSONTextEdit")
struct JSONTextEditTests {
    /// The whole reason this exists: a UI-driven setting change must not
    /// reflow the file, or `chezmoi diff` fills with churn nobody made.
    @Test("Only the target value changes — order, indentation, and comments survive")
    func surgical() throws {
        let before = """
            {
                // Appearance
                "theme": "system",
                "fonts": { "notes": "Inter Nerd Font", "ui": "Inter Nerd Font Propo" },
                "vibrancy": true,
            }
            """
        let after = try #require(
            JSONTextEdit.replacingValue(in: before, at: ["theme"], with: "\"dark\""))
        #expect(after == before.replacingOccurrences(of: "\"system\"", with: "\"dark\""))
    }

    @Test("A nested path addresses the inner value")
    func nestedPath() throws {
        let before = #"{ "keymap": { "summon": "ctrl+opt+." } }"#
        let after = try #require(
            JSONTextEdit.replacingValue(in: before, at: ["keymap", "summon"], with: "\"cmd+j\""))
        #expect(after == #"{ "keymap": { "summon": "cmd+j" } }"#)
    }

    /// A key that also appears one level down must not shadow the one being
    /// addressed.
    @Test("A same-named key in a nested object doesn't shadow the outer one")
    func noShadowing() throws {
        let before = #"{ "fonts": { "ui": "A" }, "ui": "B" }"#
        let after = try #require(
            JSONTextEdit.replacingValue(in: before, at: ["ui"], with: "\"C\""))
        #expect(after == #"{ "fonts": { "ui": "A" }, "ui": "C" }"#)
    }

    @Test("An object value is replaced whole")
    func objectValue() throws {
        let before = #"{ "panel": { "x": 1, "y": 2, "w": 3, "h": 4 }, "vibrancy": true }"#
        let after = try #require(
            JSONTextEdit.replacingValue(in: before, at: ["panel"], with: #"{"x":9}"#))
        #expect(after == #"{ "panel": {"x":9}, "vibrancy": true }"#)
    }

    @Test("A comment between the key and its value is stepped over, not eaten")
    func commentBeforeValue() throws {
        let before = """
            {
                "vibrancy": /* on */ true
            }
            """
        let after = try #require(
            JSONTextEdit.replacingValue(in: before, at: ["vibrancy"], with: "false"))
        #expect(after.contains("/* on */ false"))
    }

    /// Nil is the caller's cue to fall back to a full encode, so an absent
    /// key has to be distinguishable from a successful no-op.
    @Test("An absent key yields nil", arguments: [["nope"], ["keymap", "nope"], ["theme", "nope"]])
    func absentKey(path: [String]) {
        let text = #"{ "theme": "dark", "keymap": { "summon": "cmd+j" } }"#
        #expect(JSONTextEdit.replacingValue(in: text, at: path, with: "1") == nil)
    }

    /// The deployed file is biome-formatted by chezmoi, and the app writes
    /// to it afterwards. If a UI-driven change reflowed it, `chezmoi diff`
    /// would be permanently dirty — which is the whole reason this rewriter
    /// exists rather than a plain re-encode.
    @Test("A chezmoi-deployed file survives a UI-driven change byte for byte")
    func chezmoiDeployedShape() throws {
        let deployed = """
            {
              "dismissOnOutsideClick": true,
              "fonts": {
                "notes": "Inter Nerd Font",
                "ui": "Inter Nerd Font Propo"
              },
              "keymap": {
                "summon": "ctrl+opt+."
              },
              "scratchpadPath": "",
              "vibrancy": true,
              "theme": "system"
            }

            """
        let after = try #require(
            JSONTextEdit.replacingValue(in: deployed, at: ["theme"], with: "\"dark\""))
        #expect(after == deployed.replacingOccurrences(of: "\"system\"", with: "\"dark\""))
    }

    @Test("A rewritten document still parses")
    func stillParses() throws {
        let before = """
            {
                // keep me
                "theme": "system",
                "fontScale": 1.0,
            }
            """
        let after = try #require(
            JSONTextEdit.replacingValue(in: before, at: ["fontScale"], with: "1.5"))
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let config = try decoder.decode(WispConfig.self, from: Data(after.utf8))
        #expect(config.fontScale == 1.5)
        #expect(after.contains("// keep me"))
    }
}

/// These touch the filesystem, so they run one at a time against a temporary
/// `XDG_CONFIG_HOME` — never the real `~/.config/wisp`.
@Suite("ConfigStore", .serialized)
final class ConfigStoreTests {
    private let previousXDG = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
    private let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wisp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        setenv("XDG_CONFIG_HOME", root.path, 1)
    }

    deinit {
        if let previousXDG {
            setenv("XDG_CONFIG_HOME", previousXDG, 1)
        } else {
            unsetenv("XDG_CONFIG_HOME")
        }
        try? FileManager.default.removeItem(at: root)
    }

    @Test("The location honours XDG_CONFIG_HOME")
    func directoryFollowsXDG() {
        #expect(ConfigStore.directory == root.appendingPathComponent("wisp", isDirectory: true))
        #expect(ConfigStore.fileURL.lastPathComponent == "wisp.jsonc")
    }

    @Test("First run seeds the file and says so")
    func seeding() throws {
        let load = ConfigStore.loadOrSeed()
        #expect(load.seeded)
        #expect(load.error == nil)
        #expect(load.config == WispConfig())
        #expect(FileManager.default.fileExists(atPath: ConfigStore.fileURL.path))

        // Second run reads what was written and is no longer a first run.
        let second = ConfigStore.loadOrSeed()
        #expect(!second.seeded)
        #expect(second.config == load.config)
    }

    /// `jq` parses strict JSON only, and both chezmoi's modify_ script and
    /// the re-add hook run the deployed file through it.
    @Test("The seeded file is strict JSON, unescaped and stably ordered")
    func seededFileIsStrictJSON() throws {
        _ = ConfigStore.loadOrSeed()
        let text = try String(contentsOf: ConfigStore.fileURL, encoding: .utf8)
        #expect(!text.contains("//"))
        #expect(!text.contains("\\/"))
        #expect(try JSONSerialization.jsonObject(with: Data(text.utf8)) is [String: Any])
    }

    @Test("A targeted update rewrites one value and leaves the file's shape alone")
    func targetedUpdate() throws {
        _ = ConfigStore.loadOrSeed()
        let before = try String(contentsOf: ConfigStore.fileURL, encoding: .utf8)

        var config = WispConfig()
        config.theme = .dark
        try ConfigStore.update(["theme"], to: config.theme, in: config)

        let after = try String(contentsOf: ConfigStore.fileURL, encoding: .utf8)
        #expect(after == before.replacingOccurrences(of: "\"system\"", with: "\"dark\""))
        #expect(ConfigStore.loadOrSeed().config.theme == .dark)
    }

    /// A hand-edited file is the case the rewriter exists for.
    @Test("A hand-edited file keeps its comments through an update")
    func updatePreservesComments() throws {
        try FileManager.default.createDirectory(
            at: ConfigStore.directory, withIntermediateDirectories: true)
        try """
            {
                // my summon chord
                "keymap": { "summon": "ctrl+opt+." },
                "theme": "light"
            }
            """.write(to: ConfigStore.fileURL, atomically: true, encoding: .utf8)

        var config = ConfigStore.loadOrSeed().config
        config.keymap.summon = "cmd+opt+w"
        try ConfigStore.update(["keymap", "summon"], to: config.keymap.summon, in: config)

        let after = try String(contentsOf: ConfigStore.fileURL, encoding: .utf8)
        #expect(after.contains("// my summon chord"))
        #expect(after.contains("\"cmd+opt+w\""))
        #expect(ConfigStore.loadOrSeed().config.theme == .light)
    }

    /// A setting added since the file was written has no key to rewrite, so
    /// the whole document is re-encoded instead of the change being dropped.
    @Test("An update to an absent key falls back to a full encode")
    func updateFallsBack() throws {
        try FileManager.default.createDirectory(
            at: ConfigStore.directory, withIntermediateDirectories: true)
        try #"{ "theme": "light" }"#.write(
            to: ConfigStore.fileURL, atomically: true, encoding: .utf8)

        var config = ConfigStore.loadOrSeed().config
        config.fontScale = 1.5
        try ConfigStore.update(["fontScale"], to: config.fontScale, in: config)

        let reloaded = ConfigStore.loadOrSeed().config
        #expect(reloaded.fontScale == 1.5)
        #expect(reloaded.theme == .light)
    }

    @Test("An unreadable file falls back to defaults and reports why")
    func malformedFile() throws {
        try FileManager.default.createDirectory(
            at: ConfigStore.directory, withIntermediateDirectories: true)
        try "{ this is not json".write(to: ConfigStore.fileURL, atomically: true, encoding: .utf8)

        let load = ConfigStore.loadOrSeed()
        #expect(load.config == WispConfig())
        #expect(load.error?.contains("unreadable") == true)
        #expect(!load.seeded)
    }

    @Test("The panel frame round-trips through the file")
    func panelFrameRoundTrip() throws {
        _ = ConfigStore.loadOrSeed()
        var config = WispConfig()
        config.panel = PanelFrame(x: 12, y: 34, w: 800, h: 640)
        try ConfigStore.update(["panel"], to: config.panel, in: config)
        #expect(ConfigStore.loadOrSeed().config.panel == config.panel)
    }
}
