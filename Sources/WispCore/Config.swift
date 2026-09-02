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

/// Whether the Tab key — and the smart list indentation built on it —
/// writes spaces or a tab character.
public enum IndentStyle: String, Codable, CaseIterable, Sendable {
    case spaces
    case tabs
}

/// How one level of indentation is spelled.
public struct Indent: Codable, Equatable, Sendable {
    public var style: IndentStyle
    /// Spaces per level. Ignored under `.tabs`, where the width is the
    /// reader's tab stop rather than ours.
    public var size: Int

    public init(style: IndentStyle = .spaces, size: Int = 2) {
        self.style = style
        self.size = size
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let diagnostics = decoder.configDiagnostics
        let defaults = Indent()
        style = container.lenientValue(
            forKey: .style, default: defaults.style, diagnostics: diagnostics,
            pathPrefix: "indent.")
        size = container.lenientValue(
            forKey: .size, default: defaults.size, diagnostics: diagnostics,
            pathPrefix: "indent.")
    }

    /// The text one level of indentation inserts. `size` is bounded here
    /// rather than at decode time so a typo stays visible in the file and
    /// is recoverable by editing it back, the same bargain `fontScale`
    /// makes.
    public var unit: String {
        switch style {
        case .tabs: return "\t"
        case .spaces: return String(repeating: " ", count: min(max(size, 1), 16))
        }
    }

    /// Columns one level occupies, for working out a list item's nesting
    /// depth from its leading whitespace. A tab counts as one level.
    public var width: Int {
        style == .tabs ? 1 : min(max(size, 1), 16)
    }
}

/// Where the panel opens.
public enum PanelPosition: String, Codable, CaseIterable, Sendable {
    /// Centred horizontally, top edge a tenth of the way down the screen.
    /// `panel.x` / `panel.y` are neither read nor written, and the panel
    /// can't be dragged — there would be nowhere for the move to go.
    case auto
    /// The panel stays where it was last dragged. Until it has been
    /// dragged once it opens where `auto` would have put it.
    case manual
}

/// The remembered panel frame, in screen points.
///
/// The size is remembered from the first hide onwards; the origin only
/// once the panel has actually been moved, so `position: manual` can tell
/// "never dragged" (fall back to the auto placement) from "dragged to
/// exactly here". Written when the panel hides, never while it moves —
/// see `PanelController`.
public struct PanelFrame: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var x: Double?
    public var y: Double?

    public init(width: Double, height: Double, x: Double? = nil, y: Double? = nil) {
        self.width = width
        self.height = height
        self.x = x
        self.y = y
    }

    /// `w` / `h` were the names before the keys were spelled out. Still
    /// read, never written, so a config from an earlier version keeps its
    /// remembered size instead of silently reverting to the default.
    private enum LegacySizeKeys: String, CodingKey {
        case w, h
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacySizeKeys.self)
        guard
            let width = try container.decodeIfPresent(Double.self, forKey: .width)
                ?? legacy.decodeIfPresent(Double.self, forKey: .w),
            let height = try container.decodeIfPresent(Double.self, forKey: .height)
                ?? legacy.decodeIfPresent(Double.self, forKey: .h)
        else {
            throw DecodingError.keyNotFound(
                CodingKeys.width,
                .init(codingPath: decoder.codingPath, debugDescription: "panel has no size"))
        }
        self.width = width
        self.height = height
        x = try container.decodeIfPresent(Double.self, forKey: .x)
        y = try container.decodeIfPresent(Double.self, forKey: .y)
    }

    /// Both or neither: a lone coordinate has no placement to describe.
    public var origin: (x: Double, y: Double)? {
        guard let x, let y else { return nil }
        return (x, y)
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
    /// The one text-size control: a multiplier on every design size in
    /// `Metrics`, body and chrome alike. Moved by ⌘= / ⌘- and the footer
    /// buttons, and persisted, so a size you set survives a relaunch.
    /// Clamped on the way out, not on the way in, so a typo is
    /// recoverable by editing the file back.
    public var fontScale: Double
    /// What ⌘0 returns `fontScale` to. Separate from the live value so
    /// "reset" means *your* normal size rather than a constant 1.0.
    public var defaultFontScale: Double
    /// Blurs whatever is behind the panel. On by default in both themes —
    /// the tints are translucent so the blur is the panel's whole substance.
    public var vibrancy: Bool
    public var monitor: MonitorTarget
    /// Auto-placed on every summon, or left wherever it was last dragged.
    public var position: PanelPosition
    /// Clicking another app dismisses the panel outright. Switchable here so
    /// turning it off doesn't need a rebuild.
    public var dismissOnOutsideClick: Bool
    /// Flashes a dot in the panel's top corner each time the note is
    /// written to disk. On by default — the save is debounced and silent
    /// otherwise, so there is nothing else that says it happened.
    public var saveIndicator: Bool
    /// Folder holding `scratchpad.md`. Empty means the default, `~/Documents`.
    public var scratchpadPath: String
    public var keymap: Keymap
    /// What the Tab key writes, and the step smart list indentation moves by.
    public var indent: Indent
    /// Absent until the panel has been shown and hidden once.
    public var panel: PanelFrame?

    public init(
        theme: ThemePreference = .system,
        fonts: FontSet = FontSet(),
        fontScale: Double = 1.0,
        defaultFontScale: Double = 1.0,
        vibrancy: Bool = true,
        monitor: MonitorTarget = .primary,
        position: PanelPosition = .auto,
        dismissOnOutsideClick: Bool = true,
        saveIndicator: Bool = true,
        scratchpadPath: String = "",
        keymap: Keymap = Keymap(),
        indent: Indent = Indent(),
        panel: PanelFrame? = nil
    ) {
        self.theme = theme
        self.fonts = fonts
        self.fontScale = fontScale
        self.defaultFontScale = defaultFontScale
        self.vibrancy = vibrancy
        self.monitor = monitor
        self.position = position
        self.dismissOnOutsideClick = dismissOnOutsideClick
        self.saveIndicator = saveIndicator
        self.scratchpadPath = scratchpadPath
        self.keymap = keymap
        self.indent = indent
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
        fontScale = container.lenientValue(
            forKey: .fontScale, default: defaults.fontScale, diagnostics: diagnostics)
        defaultFontScale = container.lenientValue(
            forKey: .defaultFontScale, default: defaults.defaultFontScale,
            diagnostics: diagnostics)
        vibrancy = container.lenientValue(
            forKey: .vibrancy, default: defaults.vibrancy, diagnostics: diagnostics)
        monitor = container.lenientValue(
            forKey: .monitor, default: defaults.monitor, diagnostics: diagnostics)
        position = container.lenientValue(
            forKey: .position, default: defaults.position, diagnostics: diagnostics)
        dismissOnOutsideClick = container.lenientValue(
            forKey: .dismissOnOutsideClick, default: defaults.dismissOnOutsideClick,
            diagnostics: diagnostics)
        saveIndicator = container.lenientValue(
            forKey: .saveIndicator, default: defaults.saveIndicator, diagnostics: diagnostics)
        scratchpadPath = container.lenientValue(
            forKey: .scratchpadPath, default: defaults.scratchpadPath, diagnostics: diagnostics)
        keymap = container.lenientValue(
            forKey: .keymap, default: defaults.keymap, diagnostics: diagnostics)
        indent = container.lenientValue(
            forKey: .indent, default: defaults.indent, diagnostics: diagnostics)
        // `T` is `PanelFrame?` here, so a missing key and an explicit null
        // both land on "no remembered frame".
        panel = container.lenientValue(
            forKey: .panel, default: defaults.panel, diagnostics: diagnostics)
    }

    /// Bounded so a typo can't render the app unreadable or unusable.
    public var clampedFontScale: Double { Metrics.clampFontScale(fontScale) }

    /// The ⌘0 target, bounded the same way — a `defaultFontScale` outside
    /// the range would otherwise make reset the one way to reach an
    /// unreadable size.
    public var clampedDefaultFontScale: Double { Metrics.clampFontScale(defaultFontScale) }

    /// The summon chord, or the default when the configured string doesn't
    /// parse — an unusable chord would otherwise leave the app with no way
    /// to open at all.
    public var summonChord: KeyChord {
        keymap.parsed(.summon) ?? KeyChord.parse(KeymapAction.summon.defaultChord)!
    }

    /// True when the configured summon chord didn't parse, so the footer can
    /// say so rather than leaving the user wondering why their chord does
    /// nothing. Every other action reports through `unparseableActions`.
    public var summonChordIsValid: Bool { keymap.parsed(.summon) != nil }

    public var scratchpadFolder: URL {
        StorageLocation.folder(forConfiguredPath: scratchpadPath)
    }
}
