import Foundation

/// Reads and writes `wisp.jsonc`.
public enum ConfigStore {
    /// `~/.config/wisp`, or under `XDG_CONFIG_HOME`: beside the user's other tools, where chezmoi
    /// can manage it and reading needs no TCC prompt.
    public static var directory: URL {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: NSString(string: xdg).expandingTildeInPath)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("wisp", isDirectory: true)
    }

    public static var fileURL: URL { directory.appendingPathComponent("wisp.jsonc") }

    /// Kept beside the config so an editor validates it offline. `installSchema` refreshes it
    /// from the bundle at launch.
    public static var schemaFileURL: URL { directory.appendingPathComponent(schemaFilename) }
    public static let schemaFilename = "wisp.schema.json"
    /// Relative, so moving the app never breaks it.
    public static let schemaReference = "./\(schemaFilename)"

    public struct Load {
        public let config: WispConfig
        /// An unreadable file or malformed keys, for the footer.
        public let error: String?
        public let failed: Bool

        init(config: WispConfig, error: String?, failed: Bool = false) {
            self.config = config
            self.error = error
            self.failed = failed
        }
    }

    /// Seeds the file on first run. A malformed file falls back to defaults.
    public static func loadOrSeed(
        defaults: WispConfig = WispConfig(), at fileURL: URL = ConfigStore.fileURL
    ) -> Load {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            do {
                try write(defaults, at: fileURL)
            } catch {
                return Load(
                    config: defaults,
                    error: "Couldn't write \(fileURL.path): \(error.localizedDescription)",
                    failed: true)
            }
            return Load(config: defaults, error: nil)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let diagnostics = ConfigDiagnostics()
            let decoder = JSONDecoder()
            decoder.userInfo[.configDiagnostics] = diagnostics
            // JSON5 also covers JSONC's comments and trailing commas.
            decoder.allowsJSON5 = true
            return Load(
                config: try decoder.decode(WispConfig.self, from: data),
                error: diagnostics.summary)
        } catch {
            return Load(
                config: defaults,
                error: "wisp.jsonc is unreadable, using defaults: \(error.localizedDescription)",
                failed: true)
        }
    }

    /// Writes only when the bytes differ: the watcher would read a rewrite as an edit.
    public static func installSchema(from source: URL) throws {
        let schema = try Data(contentsOf: source)
        if let current = try? Data(contentsOf: schemaFileURL), current == schema { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try schema.write(to: schemaFileURL, options: .atomic)
    }

    /// Strict JSON: chezmoi's `modify_` script and re-add hook run the file through `jq`, and a
    /// comment would make that merge drop every preserved setting.
    public static func write(_ config: WispConfig, at fileURL: URL = ConfigStore.fileURL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        // Otherwise Foundation writes "ctrl+opt+\/": valid, but noise to hand-edit.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(SchemaTagged(config: config)).write(to: fileURL, options: .atomic)
    }

    /// `config` plus a `$schema` key in the same container, so `WispConfig` stores no constant.
    private struct SchemaTagged: Encodable {
        let config: WispConfig

        private enum Keys: String, CodingKey {
            case schema = "$schema"
            case position
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(schemaReference, forKey: .schema)
            // A `null` position makes the first save an in-place edit, not a full rewrite.
            if config.position == nil { try container.encodeNil(forKey: .position) }
            try config.encode(to: encoder)
        }
    }

    /// Edits existing text only after validating it; full encoding is for a missing file.
    public static func update(
        _ path: [String], to value: some Encodable, in config: WispConfig,
        at fileURL: URL = ConfigStore.fileURL
    ) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try write(config, at: fileURL)
            return
        }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        _ = try decoder.decode(WispConfig.self, from: Data(text.utf8))
        guard let literal = jsonLiteral(for: value),
            let rewritten = JSONTextEdit.replacingValue(in: text, at: path, with: literal)
        else { throw CocoaError(.fileReadCorruptFile) }
        _ = try decoder.decode(WispConfig.self, from: Data(rewritten.utf8))
        try rewritten.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// One value as JSON text; a bare string or number comes back unwrapped.
    static func jsonLiteral(for value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
