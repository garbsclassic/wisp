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

/// Which screen the panel opens on. Same key and values as Clef's.
public enum MonitorTarget: String, Codable, CaseIterable, Sendable {
    /// The screen holding the menu bar. A saved position is used wherever it
    /// is, even on another screen.
    case primary
    /// Whichever screen the pointer is on, with a saved position carried to
    /// the same relative spot there.
    case pointer
}

/// The three faces Wisp draws with, by family name.
///
/// Nil, the default, is the system's own face: SF Pro for `notes` and `ui`,
/// SF Mono for `code`. A named family is never bundled, so it's allowed to be
/// missing — `Typography` falls back to the system face and the footer says
/// which one didn't resolve.
public struct FontSet: Codable, Equatable, Sendable {
    /// The notes body.
    public var notes: String?
    /// Chrome — header, footer, overlays.
    public var ui: String?
    /// `` `inline code` `` runs, and the whole body in source view.
    public var code: String?

    public init(notes: String? = nil, ui: String? = nil, code: String? = nil) {
        self.notes = notes
        self.ui = ui
        self.code = code
    }

    /// Missing keys fall back per-face, so adding one doesn't reset a font
    /// set someone has already customised.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let diagnostics = decoder.configDiagnostics
        notes = container.lenientValue(
            forKey: .notes, default: nil, diagnostics: diagnostics, pathPrefix: "fonts.")
        ui = container.lenientValue(
            forKey: .ui, default: nil, diagnostics: diagnostics, pathPrefix: "fonts.")
        code = container.lenientValue(
            forKey: .code, default: nil, diagnostics: diagnostics, pathPrefix: "fonts.")
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

/// How the caret gets from where it was to where it is going.
public enum CaretMotion: String, Codable, CaseIterable, Sendable {
    /// Lands almost at once and settles — most of the distance in the
    /// first third of a short animation, then a soft stop.
    case snappy
    /// The slower slide that makes a jump easy to follow with the eye.
    case gliding
    /// The stock teleport.
    case off
}

/// How a thematic break (`---`, `***`, `___`) is drawn.
public enum RuleStyle: String, Codable, CaseIterable, Sendable {
    /// A hairline across the text column.
    case line
    /// A book's section break: `*  *  *`, centred.
    case seam
}

/// The caret's animation: how it moves, and whether it blinks.
///
/// Drawn by `NotesTextView` as a Core Animation layer rather than by
/// AppKit, so both the move and the fade run on the render server.
public struct Caret: Codable, Equatable, Sendable {
    public var motion: CaretMotion
    /// A fade in and out rather than the stock on/off. Off leaves the
    /// caret solid.
    public var blink: Bool

    public init(motion: CaretMotion = .snappy, blink: Bool = true) {
        self.motion = motion
        self.blink = blink
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let diagnostics = decoder.configDiagnostics
        let defaults = Caret()
        motion = container.lenientValue(
            forKey: .motion, default: defaults.motion, diagnostics: diagnostics,
            pathPrefix: "caret.")
        blink = container.lenientValue(
            forKey: .blink, default: defaults.blink, diagnostics: diagnostics,
            pathPrefix: "caret.")
    }
}

/// The panel's backdrop, Ghostty's `background-blur` and `background-opacity`.
public struct Background: Codable, Equatable, Sendable {
    /// Blurs whatever is behind the panel.
    public var blur: Bool
    /// Alpha of the panel's tint, 0–1. Nil takes the theme's own value —
    /// the two themes tune it differently, so one number can't be the
    /// default for both.
    public var opacity: Double?

    public init(blur: Bool = true, opacity: Double? = nil) {
        self.blur = blur
        self.opacity = opacity
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let diagnostics = decoder.configDiagnostics
        let defaults = Background()
        blur = container.lenientValue(
            forKey: .blur, default: defaults.blur, diagnostics: diagnostics,
            pathPrefix: "background.")
        opacity = container.lenientValue(
            forKey: .opacity, default: defaults.opacity, diagnostics: diagnostics,
            pathPrefix: "background.")
    }

    /// Bounded at use so a typo stays visible in the file, like `fontScale`.
    public var clampedOpacity: Double? {
        opacity.map { min(max($0, 0), 1) }
    }
}

/// The panel's remembered size, in screen points. Written when the panel
/// hides; where it sits is `WispConfig.position`, kept apart because Clef
/// shares that key and not this one.
public struct PanelFrame: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
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
    public var theme: ThemeSetting
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
    /// Blur and tint alpha. Blur is on by default in both themes — the
    /// tints are translucent so the blur is the panel's whole substance.
    public var background: Background
    public var monitor: MonitorTarget
    /// Where the panel was last dragged to. Nil — absent, or `null` after
    /// Reset Position — opens it at the default spot.
    public var position: PanelPosition?
    /// Milliseconds the summon chord must be held before the panel becomes a
    /// peek, which closes when the chord is let go, instead of a pin. `0`
    /// peeks straight away, so the chord never pins. Same key as Clef's.
    public var peekHold: Int
    /// Flashes a dot in the panel's top corner each time the note is
    /// written to disk. On by default — the save is debounced and silent
    /// otherwise, so there is nothing else that says it happened.
    public var saveIndicator: Bool
    /// ⌘V onto a blank line turns a tab-separated grid into a pipe table
    /// and a run of short plain lines into a bulleted list. Off pastes
    /// everything verbatim.
    public var smartPaste: Bool
    /// Folder holding `scratchpad.md`. Empty means the default, `~/Documents`.
    public var scratchpadFolder: String
    public var keymap: Keymap
    /// What the Tab key writes, and the step smart list indentation moves by.
    public var indent: Indent
    /// How the caret moves and blinks.
    public var caret: Caret
    /// How a `---` rule is drawn.
    public var rule: RuleStyle
    /// Absent until the panel has been shown and hidden once.
    public var panel: PanelFrame?

    public init(
        theme: ThemeSetting = .system,
        fonts: FontSet = FontSet(),
        fontScale: Double = 1.0,
        defaultFontScale: Double = 1.0,
        background: Background = Background(),
        monitor: MonitorTarget = .primary,
        position: PanelPosition? = nil,
        peekHold: Int = 250,
        saveIndicator: Bool = true,
        smartPaste: Bool = true,
        scratchpadFolder: String = "",
        keymap: Keymap = Keymap(),
        indent: Indent = Indent(),
        caret: Caret = Caret(),
        rule: RuleStyle = .line,
        panel: PanelFrame? = nil
    ) {
        self.theme = theme
        self.fonts = fonts
        self.fontScale = fontScale
        self.defaultFontScale = defaultFontScale
        self.background = background
        self.monitor = monitor
        self.position = position
        self.peekHold = peekHold
        self.saveIndicator = saveIndicator
        self.smartPaste = smartPaste
        self.scratchpadFolder = scratchpadFolder
        self.keymap = keymap
        self.indent = indent
        self.caret = caret
        self.rule = rule
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
        background = container.lenientValue(
            forKey: .background, default: defaults.background, diagnostics: diagnostics)
        monitor = container.lenientValue(
            forKey: .monitor, default: defaults.monitor, diagnostics: diagnostics)
        position = container.lenientValue(
            forKey: .position, default: defaults.position, diagnostics: diagnostics)
        peekHold = container.lenientValue(
            forKey: .peekHold, default: defaults.peekHold, diagnostics: diagnostics)
        saveIndicator = container.lenientValue(
            forKey: .saveIndicator, default: defaults.saveIndicator, diagnostics: diagnostics)
        smartPaste = container.lenientValue(
            forKey: .smartPaste, default: defaults.smartPaste, diagnostics: diagnostics)
        scratchpadFolder = container.lenientValue(
            forKey: .scratchpadFolder, default: defaults.scratchpadFolder, diagnostics: diagnostics)
        keymap = container.lenientValue(
            forKey: .keymap, default: defaults.keymap, diagnostics: diagnostics)
        indent = container.lenientValue(
            forKey: .indent, default: defaults.indent, diagnostics: diagnostics)
        caret = container.lenientValue(
            forKey: .caret, default: defaults.caret, diagnostics: diagnostics)
        rule = container.lenientValue(
            forKey: .rule, default: defaults.rule, diagnostics: diagnostics)
        // `T` is `PanelFrame?` here, so a missing key and an explicit null
        // both land on "no remembered frame".
        panel = container.lenientValue(
            forKey: .panel, default: defaults.panel, diagnostics: diagnostics)
    }

    public var peekHoldSeconds: TimeInterval { max(0, Double(peekHold) / 1000) }

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
        keymap.parsed(.summon) ?? KeyChord.parse(KeymapAction.summon.defaultChords.chords[0])!
    }

    /// True when the configured summon chord didn't parse, so the footer can
    /// say so rather than leaving the user wondering why their chord does
    /// nothing. Every other action reports through `unparseableActions`.
    public var summonChordIsValid: Bool { keymap.parsed(.summon) != nil }

    public var scratchpadFolderPath: URL {
        StorageLocation.folder(forConfiguredPath: scratchpadFolder)
    }
}
