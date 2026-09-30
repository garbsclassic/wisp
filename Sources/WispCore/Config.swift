import Foundation

/// Keys that were present but unreadable, for the footer. Passed through `userInfo` so no config
/// type stores it, and a class so nested decoders share one. `@unchecked Sendable` for `userInfo`.
public final class ConfigDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String] = []

    public init() {}

    public var malformedKeys: [String] { lock.withLock { keys } }

    public func note(_ key: String) { lock.withLock { keys.append(key) } }

    /// In the order the decoder visits keys, which is `WispConfig`'s declaration order.
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

/// Absent or null takes the default quietly; a present key of the wrong shape is noted by its full
/// path, such as "keymap.summon".
extension KeyedDecodingContainer {
    func lenientValue<T: Decodable>(
        forKey key: Key,
        default fallback: T,
        diagnostics: ConfigDiagnostics?
    ) -> T {
        do {
            return try decodeIfPresent(T.self, forKey: key) ?? fallback
        } catch {
            diagnostics?.note((codingPath + [key]).map(\.stringValue).joined(separator: "."))
            return fallback
        }
    }
}

/// Which screen the panel opens on. Same key and values as Clef's.
public enum MonitorTarget: String, Codable, CaseIterable, Sendable {
    /// The menu bar's screen; a saved position is used wherever it is.
    case primary
    /// The pointer's screen, with a saved position carried to the same relative spot.
    case pointer
}

/// Family names, where nil is the system face. A missing family falls back in `Typography`.
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

    /// Per-face defaults, so adding a face doesn't reset a customised set.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let diagnostics = decoder.configDiagnostics
        notes = container.lenientValue(
            forKey: .notes, default: nil, diagnostics: diagnostics)
        ui = container.lenientValue(
            forKey: .ui, default: nil, diagnostics: diagnostics)
        code = container.lenientValue(
            forKey: .code, default: nil, diagnostics: diagnostics)
    }
}

/// What the Tab key and list indentation write.
public enum IndentStyle: String, Codable, CaseIterable, Sendable {
    case spaces
    case tabs
}

/// How one level of indentation is spelled.
public struct Indent: Codable, Equatable, Sendable {
    public var style: IndentStyle
    /// Spaces per level; ignored under `.tabs`.
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
            forKey: .style, default: defaults.style, diagnostics: diagnostics)
        size = container.lenientValue(
            forKey: .size, default: defaults.size, diagnostics: diagnostics)
    }

    /// Bounded here rather than at decode, so a typo stays visible in the file.
    public var unit: String {
        switch style {
        case .tabs: return "\t"
        case .spaces: return String(repeating: " ", count: min(max(size, 1), 16))
        }
    }

    /// Columns per level, for a list item's depth. A tab counts as one.
    public var width: Int {
        style == .tabs ? 1 : min(max(size, 1), 16)
    }
}

/// How the caret moves to a new position.
public enum CaretMotion: String, Codable, CaseIterable, Sendable {
    /// Most of the way in the first third of a short animation, then a soft stop.
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

/// What the footer's leading label shows.
public enum FooterStatus: String, Codable, CaseIterable, Sendable {
    /// `12:4 · 120 words`.
    case position
    /// When the note was last saved; skips counting the note on every keystroke.
    case modified
}

/// Drawn as a Core Animation layer, so the move and the fade run on the render server.
public struct Caret: Codable, Equatable, Sendable {
    public var motion: CaretMotion
    /// A fade rather than the stock on/off. Off leaves the caret solid.
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
            forKey: .motion, default: defaults.motion, diagnostics: diagnostics)
        blink = container.lenientValue(
            forKey: .blink, default: defaults.blink, diagnostics: diagnostics)
    }
}

/// The panel's backdrop, Ghostty's `background-blur` and `background-opacity`.
public struct Background: Codable, Equatable, Sendable {
    public var blur: Bool
    /// The tint's alpha, 0–1. Nil takes the theme's own, since the themes tune it differently.
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
            forKey: .blur, default: defaults.blur, diagnostics: diagnostics)
        opacity = container.lenientValue(
            forKey: .opacity, default: defaults.opacity, diagnostics: diagnostics)
    }

    /// Bounded at use so a typo stays visible in the file, like `fontScale`.
    public var clampedOpacity: Double? {
        opacity.map { min(max($0, 0), 1) }
    }
}

/// The panel's remembered size. Position is separate, since Clef shares that key and not this one.
public struct PanelFrame: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// Everything Wisp persists; there is deliberately no UserDefaults beside it.
public struct WispConfig: Codable, Equatable, Sendable {
    public var theme: ThemeSetting
    public var fonts: FontSet
    /// Multiplies every design size in `Metrics`. Clamped on use, so a typo stays fixable.
    public var fontScale: Double
    /// What ⌘0 returns `fontScale` to, so reset means your normal size.
    public var defaultFontScale: Double
    public var background: Background
    public var monitor: MonitorTarget
    /// Where the panel was last dragged; nil opens it at the default spot.
    public var position: PanelPosition?
    /// Milliseconds the chord must be held to peek rather than pin; `0` always peeks. As in Clef.
    public var peekHold: Int
    /// Flashes a dot on each save, which is otherwise silent.
    public var saveIndicator: Bool
    /// ⌘V on a blank line turns a grid into a table and short lines into a list.
    public var smartPaste: Bool
    /// Folder holding `scratchpad.md`. Empty means the default, `~/Documents`.
    public var scratchpadFolder: String
    public var keymap: Keymap
    public var indent: Indent
    public var caret: Caret
    public var rule: RuleStyle
    /// Skips code, fenced blocks, and frontmatter.
    public var spellcheck: Bool
    /// Clicking the footer's label flips it; persisted.
    public var footerStatus: FooterStatus
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
        spellcheck: Bool = false,
        footerStatus: FooterStatus = .position,
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
        self.spellcheck = spellcheck
        self.footerStatus = footerStatus
        self.panel = panel
    }

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
        spellcheck = container.lenientValue(
            forKey: .spellcheck, default: defaults.spellcheck, diagnostics: diagnostics)
        footerStatus = container.lenientValue(
            forKey: .footerStatus, default: defaults.footerStatus, diagnostics: diagnostics)
        // `T` is `PanelFrame?`, so missing and null both mean no frame.
        panel = container.lenientValue(
            forKey: .panel, default: defaults.panel, diagnostics: diagnostics)
    }

    public var peekHoldSeconds: TimeInterval { max(0, Double(peekHold) / 1000) }

    /// Bounded so a typo can't render the app unreadable or unusable.
    public var clampedFontScale: Double { Metrics.clampFontScale(fontScale) }

    /// Bounded too, or ⌘0 could reach an unreadable size.
    public var clampedDefaultFontScale: Double { Metrics.clampFontScale(defaultFontScale) }

    /// Falls back to the default, or an unparseable chord would leave no way to open the app.
    public var summonChord: KeyChord {
        keymap.parsed(.summon) ?? KeyChord.parse(KeymapAction.summon.defaultChords.chords[0])!
    }

    /// For the footer; other actions report through `Keymap.unparseableActions`.
    public var summonChordIsValid: Bool { keymap.parsed(.summon) != nil }

    public var scratchpadFolderPath: URL {
        StorageLocation.folder(forConfiguredPath: scratchpadFolder)
    }
}
