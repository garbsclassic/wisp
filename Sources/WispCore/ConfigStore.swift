import Foundation

/// Reads and writes `wisp.jsonc`.
public enum ConfigStore {
    /// `~/.config/wisp`, honouring `XDG_CONFIG_HOME` — alongside the rest of
    /// the user's tools rather than buried in Application Support, and
    /// straightforward for chezmoi to manage. Neither location is
    /// TCC-protected, so reading it prompts for nothing.
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

    public struct Load {
        public let config: WispConfig
        /// Unreadable file, or keys that were present but malformed. Shown
        /// in the footer rather than swallowed.
        public let error: String?
        /// True when this call created the file, which is the app's cue to
        /// migrate the old UserDefaults values into it.
        public let seeded: Bool
    }

    /// Reads the config, seeding it with `defaults` on first run. A malformed
    /// file falls back to defaults rather than leaving the app inert.
    public static func loadOrSeed(defaults: WispConfig = WispConfig()) -> Load {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            do {
                try write(defaults)
            } catch {
                return Load(
                    config: defaults,
                    error: "Couldn't write \(fileURL.path): \(error.localizedDescription)",
                    seeded: false)
            }
            return Load(config: defaults, error: nil, seeded: true)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let diagnostics = ConfigDiagnostics()
            let decoder = JSONDecoder()
            decoder.userInfo[.configDiagnostics] = diagnostics
            // JSON5 is a strict superset of JSONC — comments and trailing
            // commas both parse — so wisp.jsonc needs no hand-rolled
            // stripper.
            decoder.allowsJSON5 = true
            return Load(
                config: try decoder.decode(WispConfig.self, from: data),
                error: diagnostics.summary, seeded: false)
        } catch {
            return Load(
                config: defaults,
                error: "wisp.jsonc is unreadable, using defaults: \(error.localizedDescription)",
                seeded: false)
        }
    }

    /// Writes the whole document as strict JSON.
    ///
    /// Strict, not JSONC, on purpose: `jq` parses strict JSON only, and both
    /// chezmoi's `modify_` script and the re-add hook run the deployed file
    /// through `jq`. A comment in the live file makes that merge fall back to
    /// managed-only values and drop every preserved setting.
    public static func write(_ config: WispConfig) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        // Without this, Foundation writes "ctrl+opt+\/" and "~\/Source\/...".
        // Both are valid JSON, but they're noise to read and invite someone
        // to think the escaping is required when hand-editing. It never was.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }

    /// Rewrites a single value in place, leaving the rest of the file's text —
    /// key order, indentation, and any comment the user added — untouched.
    ///
    /// Falls back to a full strict-JSON encode of `config` when the file is
    /// missing or the key isn't in it (a setting added since the file was
    /// written, say). `config` must already carry the new value, so both
    /// paths land in the same place.
    public static func update(
        _ path: [String], to value: some Encodable, in config: WispConfig
    ) throws {
        guard let literal = jsonLiteral(for: value),
            let text = try? String(contentsOf: fileURL, encoding: .utf8),
            let rewritten = JSONTextEdit.replacingValue(in: text, at: path, with: literal)
        else {
            try write(config)
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try rewritten.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// One value as the JSON text that stands for it. Uses the fragment
    /// encoder so a bare string or number comes back without being wrapped
    /// in an object first.
    static func jsonLiteral(for value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
