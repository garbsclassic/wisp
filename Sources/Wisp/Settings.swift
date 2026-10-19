import AppKit
import WispCore

/// The live view of `wisp.jsonc` and its only writer: each `set…` updates memory and rewrites that
/// one key.
@MainActor
final class Settings: ObservableObject {
    @Published private(set) var config: WispConfig
    /// An unreadable file, malformed keys, or a failed write, for the footer.
    @Published private(set) var configWarning: String?
    /// A directory whose watcher didn't start, so edits there need ⌘R. Lasts until relaunch.
    @Published private(set) var watcherWarning: String?

    let configFileURL: URL

    init(configFileURL: URL = ConfigStore.fileURL) {
        self.configFileURL = configFileURL
        let load = ConfigStore.loadOrSeed(at: configFileURL)
        config = load.config
        configWarning = load.error
        applyTypography()
        if configFileURL == ConfigStore.fileURL { installSchema() }
    }

    /// Under `swift run` there is no bundled copy to install. A failed write never displaces a
    /// config warning.
    private func installSchema() {
        guard let source = Bundle.main.url(forResource: "wisp.schema", withExtension: "json")
        else { return }
        do {
            try ConfigStore.installSchema(from: source)
        } catch where configWarning == nil {
            configWarning = "Couldn't write wisp.schema.json: \(error.localizedDescription)"
        } catch {}
    }

    /// The most severe warning, since the footer has room for one. Follows Clef.
    var warning: String? {
        if let configWarning { return configWarning }
        if let watcherWarning { return watcherWarning }
        if !config.summonChordIsValid {
            return "Unreadable summon chord \"\(config.keymap.chord(for: .summon))\" — using the default"
        }
        let unbound = config.keymap.unparseableActions.filter { $0 != .summon }
        if !unbound.isEmpty {
            let names = unbound.map(\.rawValue).joined(separator: ", ")
            return unbound.count == 1
                ? "Unreadable keymap chord: \(names)"
                : "Unreadable keymap chords: \(names)"
        }
        let missing = Typography.missingFamilies
        if !missing.isEmpty {
            return missing.count == 1
                ? "Font not installed: \(missing[0])"
                : "Fonts not installed: \(missing.joined(separator: ", "))"
        }
        return nil
    }

    /// Set once at launch, from whichever watchers failed to start.
    func reportWatcherFailure(_ description: String) {
        watcherWarning = description
    }

    // MARK: Mutations

    @discardableResult
    func setTheme(_ preference: ThemeSetting) -> Bool {
        var next = config
        next.theme = preference
        return write(["theme"], preference, next: next)
    }

    @discardableResult
    func setSpellcheck(_ isOn: Bool) -> Bool {
        var next = config
        next.spellcheck = isOn
        return write(["spellcheck"], isOn, next: next)
    }

    @discardableResult
    func setFooterStatus(_ status: FooterStatus) -> Bool {
        var next = config
        next.footerStatus = status
        return write(["footerStatus"], status, next: next)
    }

    @discardableResult
    func setFontScale(_ scale: Double) -> Bool {
        var next = config
        next.fontScale = Metrics.clampFontScale(scale)
        return write(["fontScale"], next.fontScale, next: next)
    }

    @discardableResult
    func setSummon(_ summon: KeyChord) -> Bool {
        guard let chord = KeyChord.string(
            keyCode: summon.keyCode, carbonModifiers: summon.carbonModifiers)
        else { return false }
        var next = config
        next.keymap.setChord(chord, for: .summon)
        return write(["keymap", KeymapAction.summon.rawValue], chord, next: next)
    }

    @discardableResult
    func setScratchpadFolder(_ path: String) -> Bool {
        var next = config
        next.scratchpadFolder = path
        return write(["scratchpadFolder"], path, next: next)
    }

    /// Prepare a folder change before publishing any new settings.
    @discardableResult
    func reload(prepare: (WispConfig) throws -> Void = { _ in }) -> Bool {
        let load = ConfigStore.loadOrSeed(at: configFileURL)
        guard !load.failed else { configWarning = load.error; return false }
        do {
            try prepare(load.config)
            config = load.config
            configWarning = load.error
            applyTypography()
            return true
        } catch {
            configWarning = "Couldn't reload settings: \(error.localizedDescription)"
            return false
        }
    }

    /// The one place the config reaches `Typography`.
    private func applyTypography() {
        Typography.configure(fonts: config.fonts, scale: config.clampedFontScale)
    }

    /// The Settings… menu item; seeds the file first if it's missing.
    func openConfigFile() {
        if !FileManager.default.fileExists(atPath: configFileURL.path) {
            try? ConfigStore.write(config, at: configFileURL)
        }
        NSWorkspace.shared.open(configFileURL)
    }

    private func write(_ path: [String], _ value: some Encodable, next: WispConfig) -> Bool {
        guard next != config else { return true }
        do {
            try ConfigStore.update(path, to: value, in: next, at: configFileURL)
            config = next
            configWarning = nil
            applyTypography()
            return true
        } catch {
            configWarning = "Couldn't write wisp.jsonc: \(error.localizedDescription)"
            return false
        }
    }
}
