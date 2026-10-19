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

    @Test("An absent top-level key is added to an empty object")
    func insertIntoEmptyObject() throws {
        let after = try #require(
            JSONTextEdit.replacingValue(in: "{}", at: ["theme"], with: "\"dark\""))
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        #expect(try decoder.decode(WispConfig.self, from: Data(after.utf8)).theme == .dark)
    }

    @Test("An absent key is added to a comment-only object without dropping the comment")
    func insertIntoCommentOnlyObject() throws {
        let before = "{\n  // keep this note\n}\n"
        let after = try #require(
            JSONTextEdit.replacingValue(in: before, at: ["theme"], with: "\"dark\""))
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        #expect(after.contains("// keep this note"))
        #expect(try decoder.decode(WispConfig.self, from: Data(after.utf8)).theme == .dark)
    }

    @Test("A new key follows a trailing line comment on the last member")
    func insertAfterTrailingLineComment() throws {
        let before = "{\n  \"theme\": \"light\" // keep { braces, and commas }\n}\n"
        let after = try #require(
            JSONTextEdit.replacingValue(in: before, at: ["fontScale"], with: "1.5"))
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let decoded = try decoder.decode(WispConfig.self, from: Data(after.utf8))
        #expect(after.contains("// keep { braces, and commas }"))
        #expect(decoded.theme == .light)
        #expect(decoded.fontScale == 1.5)
    }

    @Test("A missing nested object and key are inserted without changing existing values")
    func insertMissingNestedPath() throws {
        let before = "{\n  // preserve me\n  \"theme\": \"light\"\n}\n"
        let after = try #require(
            JSONTextEdit.replacingValue(
                in: before, at: ["keymap", "summon"], with: "\"cmd+j\""))
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let decoded = try decoder.decode(WispConfig.self, from: Data(after.utf8))
        #expect(after.contains("// preserve me"))
        #expect(decoded.theme == .light)
        #expect(decoded.keymap.chord(for: .summon) == "cmd+j")
    }

    @Test("An escaped JSON5 key is matched by its decoded name")
    func escapedKey() throws {
        let before = #"{ "font\u0053cale": 1.0 }"#
        let after = try #require(
            JSONTextEdit.replacingValue(in: before, at: ["fontScale"], with: "1.5"))
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        #expect(try decoder.decode(WispConfig.self, from: Data(after.utf8)).fontScale == 1.5)
    }

    @Test("An unquoted escaped JSON5 key survives insertion of another key")
    func insertBesideEscapedUnquotedKey() throws {
        let before = #"{ \u0074heme: 'light' }"#
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let original = try decoder.decode([String: String].self, from: Data(before.utf8))
        let after = try #require(
            JSONTextEdit.replacingValue(in: before, at: ["fontScale"], with: "1.5"))
        let decoded = try decoder.decode(WispConfig.self, from: Data(after.utf8))
        #expect(original[#"\u0074heme"#] == "light")
        #expect(after.contains(#"\u0074heme: 'light'"#))
        #expect(decoded.theme == WispConfig().theme)
        #expect(decoded.fontScale == 1.5)
    }

    @Test("Inserted members keep CRLF newlines and the existing member indentation")
    func insertedMemberPreservesCRLF() throws {
        let before = "{\r\n\t\"theme\": 'light'\r\n}\r\n"
        let after = try #require(
            JSONTextEdit.replacingValue(in: before, at: ["fontScale"], with: "1.5"))
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let decoded = try decoder.decode(WispConfig.self, from: Data(after.utf8))
        #expect(after.contains("\r\n\t\"fontScale\": 1.5\r\n"))
        #expect(!after.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(decoded.theme == .light)
        #expect(decoded.fontScale == 1.5)
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

    @Test("A missing top-level key is inserted without rewriting partial config text")
    func updateInsertsAbsentTopLevelKey() throws {
        let fileURL = root.appendingPathComponent("partial.jsonc")
        let before = "{\n  // hand-edited config\n  \"theme\": \"light\"\n}\n"
        try before.write(to: fileURL, atomically: true, encoding: .utf8)
        var config = WispConfig()
        config.fontScale = 1.5
        try ConfigStore.update(["fontScale"], to: config.fontScale, in: config, at: fileURL)

        let after = try String(contentsOf: fileURL, encoding: .utf8)
        let reloaded = ConfigStore.loadOrSeed(at: fileURL).config
        #expect(after.contains("// hand-edited config"))
        #expect(after.contains("\"theme\": \"light\""))
        #expect(reloaded.fontScale == 1.5)
        #expect(reloaded.theme == .light)
    }

    @Test("The first nested setting save creates only the missing object and key")
    func updateInsertsAbsentNestedKey() throws {
        let fileURL = root.appendingPathComponent("partial-nested.jsonc")
        let before = "{\n  // keep my notes\n  \"theme\": \"light\"\n}\n"
        try before.write(to: fileURL, atomically: true, encoding: .utf8)
        var config = WispConfig()
        config.keymap.setChord("cmd+opt+w", for: .summon)

        try ConfigStore.update(
            ["keymap", "summon"], to: config.keymap.chord(for: .summon), in: config,
            at: fileURL)

        let after = try String(contentsOf: fileURL, encoding: .utf8)
        let load = ConfigStore.loadOrSeed(at: fileURL)
        #expect(after.contains("// keep my notes"))
        #expect(after.contains("\"theme\": \"light\""))
        #expect(load.config.keymap.chord(for: .summon) == "cmd+opt+w")
        #expect(load.config.theme == .light)
    }

    @Test("Replacing a primitive leaves trailing block and line comments valid")
    func primitiveTrailingComments() throws {
        let fileURL = root.appendingPathComponent("comments.jsonc")
        let before = """
            {
              "fontScale": 1 /* keep, { braces, and commas } */ // keep this line too
              ,
              "theme": "light"
            }
            """
        try before.write(to: fileURL, atomically: true, encoding: .utf8)
        var config = WispConfig()
        config.fontScale = 1.5

        try ConfigStore.update(["fontScale"], to: config.fontScale, in: config, at: fileURL)

        let after = try String(contentsOf: fileURL, encoding: .utf8)
        let load = ConfigStore.loadOrSeed(at: fileURL)
        #expect(after.contains("1.5 /* keep, { braces, and commas } */"))
        #expect(after.contains("// keep this line too"))
        #expect(load.config.fontScale == 1.5)
        #expect(load.config.theme == .light)
    }

    @Test("An unreadable file falls back to defaults and reports why")
    func malformedFile() throws {
        try FileManager.default.createDirectory(
            at: ConfigStore.directory, withIntermediateDirectories: true)
        try "{ this is not json".write(to: ConfigStore.fileURL, atomically: true, encoding: .utf8)

        let load = ConfigStore.loadOrSeed()
        #expect(load.config == WispConfig())
        #expect(load.error?.contains("unreadable") == true)
        #expect(load.failed)
    }

    @Test("A lenient field diagnostic does not mark the whole file as failed")
    func malformedFieldIsNotAFileFailure() throws {
        let fileURL = root.appendingPathComponent("bad-field.jsonc")
        try #"{ "fontScale": "large", "theme": "dark" }"#.write(
            to: fileURL, atomically: true, encoding: .utf8)

        let load = ConfigStore.loadOrSeed(at: fileURL)

        #expect(!load.failed)
        #expect(load.error?.contains("fontScale") == true)
        #expect(load.config.fontScale == WispConfig().fontScale)
        #expect(load.config.theme == .dark)
    }

    @Test("Updating malformed JSON fails without replacing its text")
    func malformedUpdatePreservesFile() throws {
        let fileURL = root.appendingPathComponent("malformed.jsonc")
        let original = "{ this is not json"
        try original.write(to: fileURL, atomically: true, encoding: .utf8)
        var failed = false

        do {
            try ConfigStore.update(["theme"], to: ThemeSetting.dark, in: WispConfig(), at: fileURL)
        } catch {
            failed = true
        }

        #expect(failed)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == original)
    }

    @Test("Updating invalid UTF-8 fails without replacing the bytes")
    func invalidUTF8UpdatePreservesBytes() throws {
        let fileURL = root.appendingPathComponent("invalid-utf8.jsonc")
        let original = Data([0x7B, 0xFF, 0x80, 0x7D])
        try original.write(to: fileURL)
        var failed = false

        do {
            try ConfigStore.update(["theme"], to: ThemeSetting.dark, in: WispConfig(), at: fileURL)
        } catch {
            failed = true
        }

        #expect(failed)
        #expect(try Data(contentsOf: fileURL) == original)
    }

    @Test("Updating a directory in place of the config fails and leaves the directory")
    func directoryAtConfigPathIsPreserved() throws {
        let fileURL = root.appendingPathComponent("config-is-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        var failed = false

        do {
            try ConfigStore.update(["theme"], to: ThemeSetting.dark, in: WispConfig(), at: fileURL)
        } catch {
            failed = true
        }

        var isDirectory: ObjCBool = false
        #expect(failed)
        #expect(FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    /// `$schema` is an editor hint, so loading must not report it as malformed.
    @Test("write emits $schema first, and loadOrSeed round-trips through it")
    func schemaKeyRoundTrips() throws {
        let config = WispConfig()
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

    @Test("Written config excludes local window geometry")
    func geometryIsNotWritten() throws {
        try ConfigStore.write(WispConfig())
        let data = try Data(contentsOf: ConfigStore.fileURL)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["panel"] == nil)
        #expect(object["position"] == nil)
        #expect(object["monitor"] == nil)
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
        // "$schema" comes from `SchemaTagged`.
        #expect(schemaKeys == written.union(["$schema"]))
    }

    @Test("keymap's schema keys match KeymapAction's cases")
    func keymapKeysMatchKeymapAction() throws {
        let schemaKeys = try Self.schemaProperties(at: ["properties", "keymap"])
        #expect(schemaKeys == Set(KeymapAction.allCases.map(\.rawValue)))
    }
}
