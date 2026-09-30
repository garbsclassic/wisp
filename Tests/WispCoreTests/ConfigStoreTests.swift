import Foundation
import Testing

@testable import WispCore

@Suite("JSONTextEdit")
struct JSONTextEditTests {
    /// A UI-driven change that reflowed the file would leave `chezmoi diff` dirty.
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

    /// Nil tells the caller to fall back to a full encode.
    @Test("An absent key yields nil", arguments: [["nope"], ["keymap", "nope"], ["theme", "nope"]])
    func absentKey(path: [String]) {
        let text = #"{ "theme": "dark", "keymap": { "summon": "cmd+j" } }"#
        #expect(JSONTextEdit.replacingValue(in: text, at: path, with: "1") == nil)
    }
}

/// Runs against a temporary `XDG_CONFIG_HOME`, never the real `~/.config/wisp`.
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

    @Test("First run seeds the file")
    func seeding() throws {
        let load = ConfigStore.loadOrSeed()
        #expect(load.error == nil)
        #expect(load.config == WispConfig())
        #expect(FileManager.default.fileExists(atPath: ConfigStore.fileURL.path))

        let second = ConfigStore.loadOrSeed()
        #expect(second.config == load.config)
    }

    /// chezmoi's modify_ script and re-add hook pipe the file through `jq`, which takes
    /// strict JSON only.
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
        config.keymap.setChord("cmd+opt+w", for: .summon)
        try ConfigStore.update(["keymap", "summon"], to: config.keymap.chord(for: .summon), in: config)

        let after = try String(contentsOf: ConfigStore.fileURL, encoding: .utf8)
        #expect(after.contains("// my summon chord"))
        #expect(after.contains("\"cmd+opt+w\""))
        #expect(ConfigStore.loadOrSeed().config.theme == .light)
    }

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
    }

    /// `$schema` is an editor hint, so loading must not report it as malformed.
    @Test("write emits $schema first, and loadOrSeed round-trips through it")
    func schemaKeyRoundTrips() throws {
        var config = WispConfig()
        config.panel = PanelFrame(width: 800, height: 640)
        try ConfigStore.write(config)

        let text = try String(contentsOf: ConfigStore.fileURL, encoding: .utf8)
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        #expect(object?["$schema"] as? String == "./wisp.schema.json")
        // "$" sorts before every letter, so "$schema" is the first key written.
        #expect(text.range(of: "\"$schema\"")?.lowerBound == text.range(of: "\"")?.lowerBound)

        let load = ConfigStore.loadOrSeed()
        #expect(load.error == nil)
        #expect(load.config == config)
    }

    /// A full rewrite on the first drag would drop any comment added since.
    @Test("A written config carries position: null, and the first save edits it in place")
    func firstPositionSaveIsInPlace() throws {
        var config = WispConfig()
        try ConfigStore.write(config)
        let written = try String(contentsOf: ConfigStore.fileURL, encoding: .utf8)
        #expect(written.contains(#""position" : null"#))

        try ("// kept\n" + written).write(
            to: ConfigStore.fileURL, atomically: true, encoding: .utf8)
        config.position = PanelPosition(x: 12, y: 34)
        try ConfigStore.update(["position"], to: config.position, in: config)

        let after = try String(contentsOf: ConfigStore.fileURL, encoding: .utf8)
        #expect(after.hasPrefix("// kept"))
        #expect(ConfigStore.loadOrSeed().config.position == PanelPosition(x: 12, y: 34))
    }

    /// The directory is watched for live reload, so a needless rewrite reads as an edit.
    @Test("installSchema doesn't rewrite the file when the bytes already match")
    func installSchemaSkipsIdenticalBytes() throws {
        let source = root.appendingPathComponent("source.schema.json")
        try "{ \"title\": \"test\" }".write(to: source, atomically: true, encoding: .utf8)
        try ConfigStore.installSchema(from: source)

        let past = Date(timeIntervalSinceNow: -60)
        try FileManager.default.setAttributes(
            [.modificationDate: past], ofItemAtPath: ConfigStore.schemaFileURL.path)

        try ConfigStore.installSchema(from: source)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: ConfigStore.schemaFileURL.path)
        let modified = attributes[.modificationDate] as? Date
        #expect(modified?.timeIntervalSince1970.rounded() == past.timeIntervalSince1970.rounded())
    }

    @Test("installSchema overwrites the file when the source has changed")
    func installSchemaOverwritesChangedBytes() throws {
        let source = root.appendingPathComponent("source.schema.json")
        try "{ \"title\": \"old\" }".write(to: source, atomically: true, encoding: .utf8)
        try ConfigStore.installSchema(from: source)

        try "{ \"title\": \"new\" }".write(to: source, atomically: true, encoding: .utf8)
        try ConfigStore.installSchema(from: source)

        let installed = try String(contentsOf: ConfigStore.schemaFileURL, encoding: .utf8)
        #expect(installed.contains("new"))
    }
}

/// Nothing else fails when `Resources/wisp.schema.json` drifts from what `WispConfig`
/// encodes.
@Suite("Schema sync")
struct SchemaSyncTests {
    private static var schemaURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/wisp.schema.json")
    }

    private static func schemaProperties(at path: [String]) throws -> Set<String> {
        let data = try Data(contentsOf: schemaURL)
        var node = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        for key in path {
            node = (node?[key] as? [String: Any])
        }
        let properties = node?["properties"] as? [String: Any]
        return Set(properties?.keys ?? [:].keys)
    }

    private static func encodedKeys(of config: some Encodable) throws -> Set<String> {
        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return Set(object?.keys ?? [:].keys)
    }

    @Test("Every top-level key the encoder writes is in the schema, plus the optional ones")
    func topLevelKeysMatchSchema() throws {
        let written = try Self.encodedKeys(of: WispConfig())
        let schemaKeys = try Self.schemaProperties(at: [])
        // Nil omits "panel" and "position", and "$schema" comes from `SchemaTagged`.
        #expect(schemaKeys == written.union(["panel", "position", "$schema"]))
    }

    @Test("keymap's schema keys match KeymapAction's cases")
    func keymapKeysMatchKeymapAction() throws {
        let schemaKeys = try Self.schemaProperties(at: ["properties", "keymap"])
        #expect(schemaKeys == Set(KeymapAction.allCases.map(\.rawValue)))
    }
}
