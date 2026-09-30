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

    init() {
        let load = ConfigStore.loadOrSeed()
        config = load.config
        configWarning = load.error
        applyTypography()
        installSchema()
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

    func setTheme(_ preference: ThemeSetting) {
        config.theme = preference
        write(["theme"], preference)
    }

    func setSpellcheck(_ isOn: Bool) {
        guard isOn != config.spellcheck else { return }
        config.spellcheck = isOn
        write(["spellcheck"], isOn)
    }

    func setFooterStatus(_ status: FooterStatus) {
        guard status != config.footerStatus else { return }
        config.footerStatus = status
        write(["footerStatus"], status)
    }

    /// Reconfigures `Typography` here, or the next SwiftUI pass would render at the old scale.
    func setFontScale(_ scale: Double) {
        let clamped = Metrics.clampFontScale(scale)
        guard clamped != config.fontScale else { return }
        config.fontScale = clamped
        applyTypography()
        write(["fontScale"], clamped)
    }

    /// A key code with no spelling is dropped, since the parser would reject it next launch.
    func setSummon(_ summon: KeyChord) {
        guard
            let chord = KeyChord.string(
                keyCode: summon.keyCode, carbonModifiers: summon.carbonModifiers)
        else { return }
        config.keymap.setChord(chord, for: .summon)
        write(["keymap", KeymapAction.summon.rawValue], chord)
    }

    func setScratchpadFolder(_ path: String) {
        config.scratchpadFolder = path
        write(["scratchpadFolder"], path)
    }

    /// The panel's size, written when it hides.
    func setPanel(_ panel: PanelFrame) {
        guard panel != config.panel else { return }
        config.panel = panel
        write(["panel"], panel)
    }

    /// Nil, written as `null`, returns the panel to the default spot.
    func setPosition(_ position: PanelPosition?) {
        guard position != config.position else { return }
        config.position = position
        write(["position"], position)
    }

    /// The Refresh menu item, for a file edited or synced in while Wisp ran.
    func reload() {
        let load = ConfigStore.loadOrSeed()
        config = load.config
        configWarning = load.error
        applyTypography()
    }

    /// The one place the config reaches `Typography`.
    private func applyTypography() {
        Typography.configure(fonts: config.fonts, scale: config.clampedFontScale)
    }

    /// The Settings… menu item; seeds the file first if it's missing.
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
}
