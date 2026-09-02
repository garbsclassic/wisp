import AppKit
import Carbon.HIToolbox

/// Every action Wisp binds a key to.
///
/// One case per binding, carrying its own default chord and its own scope,
/// so the config file, the menu, and the panel-focus gate are all generated
/// from this list rather than kept in step by hand. Adding a binding is
/// adding a case.
public enum KeymapAction: String, CaseIterable, Codable, Sendable {
    /// The global chord, registered with Carbon. The only one that fires
    /// while another app is frontmost.
    case summon

    case find
    case settings
    case refresh
    case help

    case bold
    case italic
    case highlight

    case duplicateLine
    case toggleListItem
    case moveLineUp
    case moveLineDown

    case increaseFontScale
    case decreaseFontScale
    case resetFontScale

    /// What the menu item reads. Not derived from the case name — "Actual
    /// Size" and "Duplicate" are what these are called on a Mac.
    public var title: String {
        switch self {
        case .summon: return "Summon"
        case .find: return "Find"
        case .settings: return "Settings…"
        case .refresh: return "Refresh"
        case .help: return "Keyboard Shortcuts"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .highlight: return "Highlight"
        case .duplicateLine: return "Duplicate"
        case .toggleListItem: return "Toggle List Item"
        case .moveLineUp: return "Move Line Up"
        case .moveLineDown: return "Move Line Down"
        case .increaseFontScale: return "Increase Text Size"
        case .decreaseFontScale: return "Decrease Text Size"
        case .resetFontScale: return "Actual Size"
        }
    }

    public var defaultChord: String {
        switch self {
        case .summon: return "ctrl+opt+."
        case .find: return "cmd+f"
        case .settings: return "cmd+,"
        case .refresh: return "cmd+r"
        case .help: return "cmd+/"
        case .bold: return "cmd+b"
        case .italic: return "cmd+i"
        case .highlight: return "opt+h"
        case .duplicateLine: return "cmd+d"
        case .toggleListItem: return "opt+l"
        case .moveLineUp: return "opt+up"
        case .moveLineDown: return "opt+down"
        case .increaseFontScale: return "cmd+="
        case .decreaseFontScale: return "cmd+-"
        case .resetFontScale: return "cmd+0"
        }
    }

    /// True when the action only means something with the panel in front
    /// of the user, and so should do nothing when Wisp is merely active.
    ///
    /// `find`, `settings`, and `refresh` are the exceptions: each opens the
    /// panel when it is closed, which is the point of them. `summon` isn't
    /// a menu item at all — Carbon owns it, and being global is its job.
    public var isPanelScoped: Bool {
        switch self {
        case .summon, .find, .settings, .refresh: return false
        default: return true
        }
    }
}

/// Every chord Wisp binds, as an action → chord table.
///
/// A table rather than fifteen properties: fifteen lenient-decode blocks
/// would have to be kept in step with fifteen declarations and fifteen menu
/// call sites, and the whole point of `KeymapAction` is that the list lives
/// in one place. Decoding overlays the file onto the defaults, so a
/// `keymap` object naming only one action still works — the same bargain
/// every other key in the config makes.
public struct Keymap: Codable, Equatable, Sendable {
    private var chords: [String: String]

    public init(_ overrides: [KeymapAction: String] = [:]) {
        var table: [String: String] = [:]
        for action in KeymapAction.allCases {
            table[action.rawValue] = overrides[action] ?? action.defaultChord
        }
        chords = table
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        let diagnostics = decoder.configDiagnostics
        var table: [String: String] = [:]
        for action in KeymapAction.allCases {
            let key = DynamicKey(stringValue: action.rawValue)!
            table[action.rawValue] = container.lenientValue(
                forKey: key, default: action.defaultChord, diagnostics: diagnostics,
                pathPrefix: "keymap.")
        }
        chords = table
    }

    /// Written back in full, so a seeded config lists every binding there
    /// is — a keymap you have to consult the README to discover is not
    /// hand-editable in any useful sense.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for action in KeymapAction.allCases {
            try container.encode(chord(for: action), forKey: DynamicKey(stringValue: action.rawValue)!)
        }
    }

    public func chord(for action: KeymapAction) -> String {
        chords[action.rawValue] ?? action.defaultChord
    }

    public mutating func setChord(_ chord: String, for action: KeymapAction) {
        chords[action.rawValue] = chord
    }

    /// The parsed chord, or nil when the configured text doesn't parse.
    /// Nil rather than a silent fallback: an action bound to nothing is
    /// visibly missing its shortcut, which is a better clue than one that
    /// works but isn't the chord you wrote.
    public func parsed(_ action: KeymapAction) -> KeyChord? {
        KeyChord.parse(chord(for: action))
    }

    /// The chord as a person reads it — "⌘B", "⌥↑". Falls back to the raw
    /// configured text when it doesn't parse, so the help page shows what
    /// is actually in the file rather than a blank.
    public func display(_ action: KeymapAction) -> String {
        guard let parsedChord = parsed(action) else { return chord(for: action) }
        return HotKey(
            keyCode: parsedChord.keyCode, modifiers: parsedChord.carbonModifiers).displayString
    }

    /// Actions whose configured chord doesn't parse, for the footer
    /// warning. In `allCases` order so the message reads consistently.
    public var unparseableActions: [KeymapAction] {
        KeymapAction.allCases.filter { parsed($0) == nil }
    }
}

/// A coding key for a name only known at runtime — here, the raw values of
/// `KeymapAction`. `CodingKeys` can't be generated from a `CaseIterable`.
struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
