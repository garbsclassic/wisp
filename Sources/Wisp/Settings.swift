import AppKit
import WispCore

/// The app's live view of `~/.config/wisp/wisp.jsonc`, and the only thing
/// that writes to it.
///
/// Every setting the UI can change goes through a `set…` here, which updates
/// the in-memory config and rewrites just that one key in the file. Nothing
/// else in the app persists anything: with the updater and the tour gone,
/// `wisp.jsonc` is the whole store.
@MainActor
final class Settings: ObservableObject {
    @Published private(set) var config: WispConfig
    /// Unreadable file, malformed keys, or a failed write — surfaced in the
    /// footer rather than swallowed.
    @Published private(set) var configWarning: String?

    init() {
        let load = ConfigStore.loadOrSeed()
        config = load.config
        configWarning = load.error
        if load.seeded { migrateLegacyDefaults() }
        Typography.configure(fonts: config.fonts, scale: config.clampedFontScale)
    }

    /// The one warning worth showing, most severe first.
    ///
    /// Coalesced rather than stacked: the footer has room for one line, and
    /// a config that won't parse makes everything downstream of it moot
    /// anyway. Follows Clef's footer warning.
    var warning: String? {
        if let configWarning { return configWarning }
        if !config.summonChordIsValid {
            return "Unreadable summon chord \"\(config.keymap.summon)\" — using the default"
        }
        let missing = Typography.missingFamilies
        if !missing.isEmpty {
            return missing.count == 1
                ? "Font not installed: \(missing[0])"
                : "Fonts not installed: \(missing.joined(separator: ", "))"
        }
        return nil
    }

    // MARK: Mutations

    func setTheme(_ preference: ThemePreference) {
        config.theme = preference
        write(["theme"], preference)
    }

    func setFontSize(_ size: FontSize) {
        config.fontSize = size
        write(["fontSize"], size)
    }

    /// Stores the chord as the text a person would have typed. A capture
    /// whose key code has no spelling is kept in memory but not written —
    /// writing something the parser rejects would break the binding on the
    /// next launch.
    func setSummon(keyCode: UInt32, carbonModifiers: UInt32) {
        guard let chord = KeyChord.string(keyCode: keyCode, carbonModifiers: carbonModifiers)
        else { return }
        config.keymap.summon = chord
        write(["keymap", "summon"], chord)
    }

    func setScratchpadPath(_ path: String) {
        config.scratchpadPath = path
        write(["scratchpadPath"], path)
    }

    /// Written when the panel hides, never while it moves — see
    /// `PanelController.handleHide`.
    func setPanelFrame(_ frame: NSRect) {
        let panel = PanelFrame(
            x: Double(frame.origin.x), y: Double(frame.origin.y),
            w: Double(frame.width), h: Double(frame.height))
        guard panel != config.panel else { return }
        config.panel = panel
        write(["panel"], panel)
    }

    /// Opens the config in whatever app owns `.jsonc`, seeding it first if
    /// it isn't there — the Settings… menu item.
    func openConfigFile() {
        if !FileManager.default.fileExists(atPath: ConfigStore.fileURL.path) {
            try? ConfigStore.write(config)
        }
        NSWorkspace.shared.open(ConfigStore.fileURL)
    }

    private func write(_ path: [String], _ value: some Encodable) {
        do {
            try ConfigStore.update(path, to: value, in: config)
        } catch {
            configWarning = "Couldn't write wisp.jsonc: \(error.localizedDescription)"
        }
    }

    // MARK: Migration

    /// Carries the pre-config UserDefaults values into the freshly seeded
    /// file, then clears them. Runs once, on the first launch after the
    /// upgrade; afterwards `defaults read dev.garbs.wisp` is empty and there
    /// is no shadow store beside the config.
    private func migrateLegacyDefaults() {
        let defaults = UserDefaults.standard
        var migrated = config

        if let raw = defaults.string(forKey: "Theme"), let pref = ThemePreference(rawValue: raw) {
            migrated.theme = pref
        }
        if let raw = defaults.string(forKey: "FontSize"), let size = FontSize(rawValue: raw) {
            migrated.fontSize = size
        }
        if defaults.object(forKey: "HotKeyCode") != nil {
            let keyCode = UInt32(defaults.integer(forKey: "HotKeyCode"))
            let modifiers = UInt32(defaults.integer(forKey: "HotKeyMods"))
            if let chord = KeyChord.string(keyCode: keyCode, carbonModifiers: modifiers) {
                migrated.keymap.summon = chord
            }
        }
        if let path = defaults.string(forKey: StorageLocation.legacyFolderKey), !path.isEmpty {
            migrated.scratchpadPath = path
        }
        if let saved = defaults.string(forKey: "PanelFrame") {
            let rect = NSRectFromString(saved)
            if !rect.isEmpty {
                migrated.panel = PanelFrame(
                    x: Double(rect.origin.x), y: Double(rect.origin.y),
                    w: Double(rect.width), h: Double(rect.height))
            }
        }

        guard migrated != config else { return }
        config = migrated
        do {
            try ConfigStore.write(migrated)
        } catch {
            configWarning = "Couldn't write wisp.jsonc: \(error.localizedDescription)"
            return
        }
        for key in ["Theme", "FontSize", "HotKeyCode", "HotKeyMods", "PanelFrame",
                    StorageLocation.legacyFolderKey, "HasSeenFirstRunTour"] {
            defaults.removeObject(forKey: key)
        }
    }
}
