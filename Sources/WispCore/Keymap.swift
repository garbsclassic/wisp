import AppKit
import Carbon.HIToolbox

/// The chords bound to one action. A single string or a list — `"cmd+/"`
/// and `["f1", "cmd+/"]` both decode — since most actions want one chord and
/// wrapping every one of those in an array would be noise to read and to
/// write. It encodes back in whichever of the two forms fits, so a seeded
/// config doesn't sprout one-element arrays.
///
/// Aliasing is the point: F1 and ⌘/ are the same action reached two ways,
/// and this is what lets the config say so. Follows Clef's `ChordSet`.
public struct ChordSet: Codable, Equatable, Sendable, ExpressibleByStringLiteral,
    ExpressibleByArrayLiteral
{
    public var chords: [String]

    public init(_ chords: [String]) { self.chords = chords }
    public init(stringLiteral value: String) { self.chords = [value] }
    public init(arrayLiteral elements: String...) { self.chords = elements }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            chords = [single]
        } else {
            // Not `try?`: a value that's neither string nor array of strings
            // has to throw, or `lenientValue` never hears about it and the
            // typo goes unreported.
            chords = try container.decode([String].self)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if chords.count == 1 {
            try container.encode(chords[0])
        } else {
            try container.encode(chords)
        }
    }
}

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

    case cycleTheme
    case sourceView

    case bold
    case italic
    case highlight
    case underline
    case strikethrough
    case code

    case duplicateLine
    case openLineBelow
    case openLineAbove
    case toggleBulletedList
    case toggleTaskItem
    case moveLineUp
    case moveLineDown
    case previousHeading
    case nextHeading

    case increaseFontScale
    case decreaseFontScale
    case resetFontScale

    case reveal

    /// What the menu item reads.
    public var title: String {
        switch self {
        case .summon: return "Summon"
        case .find: return "Find"
        case .settings: return "Settings…"
        case .refresh: return "Refresh"
        case .help: return "Help"
        case .cycleTheme: return "Cycle Theme"
        case .sourceView: return "Source View"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .code: return "Code"
        case .duplicateLine: return "Duplicate Line"
        case .openLineBelow: return "New Line Below"
        case .openLineAbove: return "New Line Above"
        case .toggleBulletedList: return "Toggle Bulleted List"
        case .toggleTaskItem: return "Toggle Task Item"
        case .moveLineUp: return "Move Line Up"
        case .moveLineDown: return "Move Line Down"
        case .previousHeading: return "Previous Heading"
        case .nextHeading: return "Next Heading"
        case .increaseFontScale: return "Increase Font Size"
        case .decreaseFontScale: return "Decrease Font Size"
        case .resetFontScale: return "Reset Font Size"
        case .reveal: return "Reveal in Finder"
        }
    }

    public var defaultChords: ChordSet {
        switch self {
        case .summon: return "ctrl+opt+."
        case .find: return "cmd+f"
        case .settings: return "cmd+,"
        case .refresh: return "cmd+r"
        // F1 first, since that is what the key is for; ⌘/ is the alias
        // people reach for without thinking.
        case .help: return ["f1", "cmd+/"]
        case .bold: return "cmd+b"
        case .italic: return "cmd+i"
        case .cycleTheme: return "cmd+t"
        // VS Code's markdown-preview chord. Obsidian's ⌘E and Typora's ⌘/
        // are both taken here, and the other unclaimed ⌘-letters read as
        // formatting commands.
        case .sourceView: return "cmd+shift+v"
        case .highlight: return "opt+h"
        // `<u>` is HTML, not markdown — which is also what Obsidian's own
        // underline command inserts, and this note is read there too.
        case .underline: return "cmd+u"
        // Notion's chord, and the one the user's Obsidian is set to.
        case .strikethrough: return "cmd+shift+s"
        case .code: return "cmd+e"
        case .duplicateLine: return "cmd+d"
        // The VS Code / Xcode pair: ⌘↩ steps out of the line you're on onto
        // a fresh one below, ⇧ puts it above.
        case .openLineBelow: return "cmd+return"
        case .openLineAbove: return "cmd+shift+return"
        case .toggleBulletedList: return "cmd+l"
        // The shifted sibling of ⌘L: one says "is this a list", the other
        // "is this done".
        case .toggleTaskItem: return "cmd+shift+l"
        case .moveLineUp: return "opt+up"
        case .moveLineDown: return "opt+down"
        // Beside ⌥↑/↓, which move a line: ⌃⇧ moves the caret a section.
        case .previousHeading: return "ctrl+shift+up"
        case .nextHeading: return "ctrl+shift+down"
        case .increaseFontScale: return "cmd+="
        case .decreaseFontScale: return "cmd+-"
        case .resetFontScale: return "cmd+0"
        // ⌘R with Option, beside the plain ⌘R it is a cousin of: one
        // re-reads the note, the other goes and looks at it.
        case .reveal: return "opt+cmd+r"
        }
    }

    /// True when the action only means something with the panel in front
    /// of the user, and so should do nothing when Wisp is merely active.
    ///
    /// `find`, `settings`, and `refresh` are the exceptions: each opens the
    /// panel when it is dismissed, which is the point of them. `summon` isn't
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
    private var bindings: [String: ChordSet]

    public init(_ overrides: [KeymapAction: ChordSet] = [:]) {
        var table: [String: ChordSet] = [:]
        for action in KeymapAction.allCases {
            table[action.rawValue] = overrides[action] ?? action.defaultChords
        }
        bindings = table
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        let diagnostics = decoder.configDiagnostics
        var table: [String: ChordSet] = [:]
        for action in KeymapAction.allCases {
            let key = DynamicKey(stringValue: action.rawValue)!
            table[action.rawValue] = container.lenientValue(
                forKey: key, default: action.defaultChords, diagnostics: diagnostics,
                pathPrefix: "keymap.")
        }
        bindings = table
    }

    /// Written back in full, so a seeded config lists every binding there
    /// is — a keymap you have to consult the README to discover is not
    /// hand-editable in any useful sense.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for action in KeymapAction.allCases {
            try container.encode(
                chordSet(for: action), forKey: DynamicKey(stringValue: action.rawValue)!)
        }
    }

    public func chordSet(for action: KeymapAction) -> ChordSet {
        bindings[action.rawValue] ?? action.defaultChords
    }

    /// The first chord bound to the action — what the Set Shortcut… overlay
    /// rewrites, and what the help page prints when there is only one.
    public func chord(for action: KeymapAction) -> String {
        chordSet(for: action).chords.first ?? ""
    }

    /// Replaces every chord on the action. The capture overlay binds one
    /// key at a time, so an alias list it rewrites collapses to that key —
    /// which is what picking a shortcut in a UI means.
    public mutating func setChord(_ chord: String, for action: KeymapAction) {
        bindings[action.rawValue] = ChordSet([chord])
    }

    /// Every chord on the action that parses. Unparseable ones are dropped
    /// rather than failing the whole set, so one typo in an alias list
    /// doesn't cost you the alias that was fine.
    public func parsedChords(for action: KeymapAction) -> [KeyChord] {
        chordSet(for: action).chords.compactMap(KeyChord.parse)
    }

    /// The first parsed chord, for the places that can only show one.
    public func parsed(_ action: KeymapAction) -> KeyChord? {
        parsedChords(for: action).first
    }

    /// The chords as a person reads them — "⌘B", or "F1 / ⌘/" for an alias
    /// list. Falls back to the raw configured text when nothing parses, so
    /// the help page shows what is actually in the file rather than a blank.
    public func display(_ action: KeymapAction) -> String {
        let parsed = parsedChords(for: action)
        guard !parsed.isEmpty else { return chordSet(for: action).chords.joined(separator: " / ") }
        return parsed
            .map { HotKey(keyCode: $0.keyCode, modifiers: $0.carbonModifiers).displayString }
            .joined(separator: " / ")
    }

    /// Just the first chord, for places with room for one — a tooltip
    /// listing "F1 / ⌘/" is naming the feature twice rather than telling
    /// you the shortcut.
    public func primaryDisplay(_ action: KeymapAction) -> String {
        guard let chord = parsed(action) else { return self.chord(for: action) }
        return HotKey(keyCode: chord.keyCode, modifiers: chord.carbonModifiers).displayString
    }

    /// Actions left with no working chord at all, for the footer warning.
    /// In `allCases` order so the message reads consistently.
    public var unparseableActions: [KeymapAction] {
        KeymapAction.allCases.filter { parsedChords(for: $0).isEmpty }
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
