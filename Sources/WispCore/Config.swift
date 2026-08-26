import Foundation

/// Collects keys that were present but unreadable, so one bad value can be
/// named in the footer rather than silently becoming its default. Passed
/// through `JSONDecoder.userInfo` so the config types don't have to carry a
/// stored property that would then land in `Equatable` and get written back
/// out on the next encode.
///
/// A class, not a struct: the decoder hands this to several nested
/// `init(from:)` calls and they all have to append to the *same* collector.
/// `@unchecked Sendable` because `userInfo` requires it and the lock is the
/// handling — decoding is single-threaded, so it is never contended.
public final class ConfigDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String] = []

    public init() {}

    public var malformedKeys: [String] { lock.withLock { keys } }

    public func note(_ key: String) { lock.withLock { keys.append(key) } }

    /// Reported in the order the decoder visits them — `WispConfig`'s
    /// declaration order, not the order the keys happen to appear in the
    /// file — so it reads as "here's what I skipped on the way through".
    public var summary: String? {
        let malformed = malformedKeys
        guard !malformed.isEmpty else { return nil }
        let list = malformed.joined(separator: ", ")
        return malformed.count == 1
            ? "Ignored unreadable config key: \(list)"
            : "Ignored unreadable config keys: \(list)"
    }
}

extension CodingUserInfoKey {
    public static let configDiagnostics = CodingUserInfoKey(rawValue: "wisp.configDiagnostics")!
}

extension Decoder {
    var configDiagnostics: ConfigDiagnostics? {
        userInfo[.configDiagnostics] as? ConfigDiagnostics
    }
}

/// Reads one optional config value, shared by every decoder in the file.
///
/// A key that's absent — or explicitly null — takes its default quietly,
/// which is what keeps hand-edited configs working across new settings. A key
/// that's *present but the wrong shape* is a different thing: it looks like
/// it's doing something and isn't, so it gets named. `decodeIfPresent`
/// returns nil for both quiet cases, so only a genuine type mismatch reaches
/// `catch`.
///
/// `pathPrefix` qualifies nested keys ("keymap.summon") so a warning says
/// where to look rather than naming a bare "summon".
extension KeyedDecodingContainer {
    func lenientValue<T: Decodable>(
        forKey key: Key,
        default fallback: T,
        diagnostics: ConfigDiagnostics?,
        pathPrefix: String? = nil
    ) -> T {
        do {
            return try decodeIfPresent(T.self, forKey: key) ?? fallback
        } catch {
            diagnostics?.note(pathPrefix.map { "\($0)\(key.stringValue)" } ?? key.stringValue)
            return fallback
        }
    }
}

/// Which screen the panel opens on when it has no usable remembered frame —
/// and, for `pointer`, even when it does.
public enum MonitorTarget: String, Codable, CaseIterable, Sendable {
    /// The screen holding the menu bar. A remembered frame wins here.
    case primary
    /// Whichever screen the pointer is on, carrying the remembered frame's
    /// size and its position relative to its old screen.
    case pointer
}

/// The two faces Wisp draws with.
///
/// Referenced by name and never bundled, so both are allowed to be missing —
/// `Typography` falls back to the system face and the footer says which one
/// didn't resolve.
public struct FontSet: Codable, Equatable, Sendable {
    /// The notes body. Monospaced-icon Nerd Font, so glyphs column-align in
    /// a list.
    public var notes: String
    /// Chrome — header, footer, overlays. The proportional cut reads more
    /// naturally at UI sizes.
    public var ui: String

    public init(notes: String = "Inter Nerd Font", ui: String = "Inter Nerd Font Propo") {
        self.notes = notes
        self.ui = ui
    }

    /// Missing keys fall back per-face, so adding one doesn't reset a font
    /// set someone has already customised.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let diagnostics = decoder.configDiagnostics
        let defaults = FontSet()
        notes = container.lenientValue(
            forKey: .notes, default: defaults.notes, diagnostics: diagnostics, pathPrefix: "fonts.")
        ui = container.lenientValue(
            forKey: .ui, default: defaults.ui, diagnostics: diagnostics, pathPrefix: "fonts.")
    }
}

/// Every chord Wisp binds. Only one so far, but it keeps the shape of the
/// file stable if a second ever arrives, and it matches Clef's `keymap`.
public struct Keymap: Codable, Equatable, Sendable {
    /// The global summon chord, registered with Carbon at launch.
    public var summon: String

    public init(summon: String = "ctrl+opt+.") {
        self.summon = summon
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summon = container.lenientValue(
            forKey: .summon, default: Keymap().summon, diagnostics: decoder.configDiagnostics,
            pathPrefix: "keymap.")
    }
}

/// The remembered panel frame, in screen points.
///
/// Absent until the panel has been shown once. Written when the panel hides,
/// never while it moves — see `PanelController`.
public struct PanelFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// Everything Wisp persists, and the only place it persists it.
///
/// There is deliberately no shadow store beside this: with the updater and
/// the tour gone, every value that used to live in UserDefaults is a key
/// here.
public struct WispConfig: Codable, Equatable, Sendable {
    /// Light, dark, or follow the system. Richer than Clef's, which has no
    /// system option.
    public var theme: ThemePreference
    public var fonts: FontSet
    /// The small/medium/large cycle behind ⌘1 / ⌘2 / ⌘3.
    public var fontSize: FontSize
    /// A continuous multiplier on top of `fontSize`, for a display that
    /// needs everything a notch bigger. Clamped on the way out, not on the
    /// way in, so a typo is recoverable by editing the file back.
    public var fontScale: Double
    /// Blurs whatever is behind the panel. On by default in both themes —
    /// the tints are translucent so the blur is the panel's whole substance.
    public var vibrancy: Bool
    public var monitor: MonitorTarget
    /// Clicking another app dismisses the panel outright. Switchable here so
    /// turning it off doesn't need a rebuild.
    public var dismissOnOutsideClick: Bool
    /// Folder holding `scratchpad.md`. Empty means the default,
    /// `~/Library/Application Support/Wisp`.
    public var scratchpadPath: String
    public var keymap: Keymap
    /// Absent until the panel has been shown and hidden once.
    public var panel: PanelFrame?

    public init(
        theme: ThemePreference = .system,
        fonts: FontSet = FontSet(),
        fontSize: FontSize = .medium,
        fontScale: Double = 1.0,
        vibrancy: Bool = true,
        monitor: MonitorTarget = .primary,
        dismissOnOutsideClick: Bool = true,
        scratchpadPath: String = "",
        keymap: Keymap = Keymap(),
        panel: PanelFrame? = nil
    ) {
        self.theme = theme
        self.fonts = fonts
        self.fontSize = fontSize
        self.fontScale = fontScale
        self.vibrancy = vibrancy
        self.monitor = monitor
        self.dismissOnOutsideClick = dismissOnOutsideClick
        self.scratchpadPath = scratchpadPath
        self.keymap = keymap
        self.panel = panel
    }

    /// Every key is optional on the way in, so adding a setting never
    /// invalidates a config someone has already edited by hand.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let diagnostics = decoder.configDiagnostics
        let defaults = WispConfig()

        theme = container.lenientValue(
            forKey: .theme, default: defaults.theme, diagnostics: diagnostics)
        fonts = container.lenientValue(
            forKey: .fonts, default: defaults.fonts, diagnostics: diagnostics)
        fontSize = container.lenientValue(
            forKey: .fontSize, default: defaults.fontSize, diagnostics: diagnostics)
        fontScale = container.lenientValue(
            forKey: .fontScale, default: defaults.fontScale, diagnostics: diagnostics)
        vibrancy = container.lenientValue(
            forKey: .vibrancy, default: defaults.vibrancy, diagnostics: diagnostics)
        monitor = container.lenientValue(
            forKey: .monitor, default: defaults.monitor, diagnostics: diagnostics)
        dismissOnOutsideClick = container.lenientValue(
            forKey: .dismissOnOutsideClick, default: defaults.dismissOnOutsideClick,
            diagnostics: diagnostics)
        scratchpadPath = container.lenientValue(
            forKey: .scratchpadPath, default: defaults.scratchpadPath, diagnostics: diagnostics)
        keymap = container.lenientValue(
            forKey: .keymap, default: defaults.keymap, diagnostics: diagnostics)
        // `T` is `PanelFrame?` here, so a missing key and an explicit null
        // both land on "no remembered frame".
        panel = container.lenientValue(
            forKey: .panel, default: defaults.panel, diagnostics: diagnostics)
    }

    /// Bounded so a typo can't render the app unreadable or unusable.
    public var clampedFontScale: Double { min(max(fontScale, 0.6), 2.5) }

    /// The summon chord, or the default when the configured string doesn't
    /// parse — an unusable chord would otherwise leave the app with no way
    /// to open at all.
    public var summonChord: KeyChord {
        KeyChord.parse(keymap.summon) ?? KeyChord.parse(Keymap().summon)!
    }

    /// True when the configured chord didn't parse, so the footer can say so
    /// rather than leaving the user wondering why their chord does nothing.
    public var summonChordIsValid: Bool { KeyChord.parse(keymap.summon) != nil }

    public var scratchpadFolder: URL {
        StorageLocation.folder(forConfiguredPath: scratchpadPath)
    }
}
