import AppKit
import Carbon.HIToolbox

/// One action's chords: a bare string or an alias list, encoded in whichever form fits so a seeded
/// config has no one-element arrays. Follows Clef's `ChordSet`.
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
            // Not `try?`: a wrong shape must throw so `lenientValue` reports it.
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

/// Every action Wisp binds. The config, the menu, and the panel-focus gate derive from this list.
public enum KeymapAction: String, CaseIterable, Codable, Sendable {
    /// Registered with Carbon; the only chord that fires while another app is frontmost.
    case summon

    case find
    case settings
    case refresh
    case help

    case cycleTheme
    case sourceView
    case spellcheck

    case bold
    case italic
    case highlight
    case underline
    case strikethrough
    case code

    case duplicateLine
    case openLineBelow
    case openLineAbove
    case bulletedList
    case checklist
    case moveLineUp
    case moveLineDown
    case previousHeading
    case nextHeading

    case increaseFontScale
    case decreaseFontScale
    case resetFontScale

    case reveal
    case resetPosition

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
        case .spellcheck: return "Check Spelling"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .code: return "Code"
        case .duplicateLine: return "Duplicate Line"
        case .openLineBelow: return "New Line Below"
        case .openLineAbove: return "New Line Above"
        case .bulletedList: return "Bulleted List"
        case .checklist: return "Checklist"
        case .moveLineUp: return "Move Line Up"
        case .moveLineDown: return "Move Line Down"
        case .previousHeading: return "Previous Heading"
        case .nextHeading: return "Next Heading"
        case .increaseFontScale: return "Increase Font Size"
        case .decreaseFontScale: return "Decrease Font Size"
        case .resetFontScale: return "Reset Font Size"
        case .reveal: return "Reveal in Finder"
        case .resetPosition: return "Reset Position"
        }
    }

    public var defaultChords: ChordSet {
        switch self {
        case .summon: return "ctrl+opt+."
        case .find: return "cmd+f"
        case .settings: return "cmd+,"
        case .refresh: return "cmd+r"
        // F1 first; ⌘/ is the alias people reach for.
        case .help: return ["f1", "cmd+/"]
        case .bold: return "cmd+b"
        case .italic: return "cmd+i"
        case .cycleTheme: return "cmd+t"
        // VS Code's preview chord; Obsidian's ⌘E and Typora's ⌘/ are taken here.
        case .sourceView: return "cmd+shift+v"
        // Sublime Text's F6, and ⌘;, the system's own spelling chord.
        case .spellcheck: return ["f6", "cmd+;"]
        case .highlight: return "opt+h"
        // Inserts `<u>`, as Obsidian's underline command does.
        case .underline: return "cmd+u"
        // Notion's chord, and the user's Obsidian binding.
        case .strikethrough: return "cmd+shift+s"
        case .code: return "cmd+e"
        case .duplicateLine: return "cmd+d"
        // VS Code and Xcode's pair.
        case .openLineBelow: return "cmd+return"
        case .openLineAbove: return "cmd+shift+return"
        case .bulletedList: return "cmd+l"
        // ⌘L's shifted sibling.
        case .checklist: return "cmd+shift+l"
        case .moveLineUp: return "opt+up"
        case .moveLineDown: return "opt+down"
        // ⌥↑/↓ move a line; ⌃⇧↑/↓ move the caret a section.
        case .previousHeading: return "ctrl+shift+up"
        case .nextHeading: return "ctrl+shift+down"
        case .increaseFontScale: return "cmd+="
        case .decreaseFontScale: return "cmd+-"
        case .resetFontScale: return "cmd+0"
        // A cousin of ⌘R: one re-reads the note, the other shows it in Finder.
        case .reveal: return "opt+cmd+r"
        // Beside ⌘0's text-size reset, and the same as Clef's.
        case .resetPosition: return "cmd+opt+0"
        }
    }

    /// Acts only with the panel in front. `find`, `settings`, and `refresh` open a dismissed
    /// panel, and `summon` is global by nature.
    public var isPanelScoped: Bool {
        switch self {
        case .summon, .find, .settings, .refresh: return false
        default: return true
        }
    }
}

/// Action → chords. Decoding overlays the file onto the defaults, so a `keymap` naming one
/// action still works.
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
                forKey: key, default: action.defaultChords, diagnostics: diagnostics)
        }
        bindings = table
    }

    /// Writes every binding, so a seeded config documents them all.
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

    /// The first chord: what Set Shortcut… rewrites.
    public func chord(for action: KeymapAction) -> String {
        chordSet(for: action).chords.first ?? ""
    }

    /// Replaces every chord, collapsing an alias list: the capture overlay binds one key.
    public mutating func setChord(_ chord: String, for action: KeymapAction) {
        bindings[action.rawValue] = ChordSet([chord])
    }

    /// Drops unparseable chords, so one typo doesn't cost the aliases that were fine.
    public func parsedChords(for action: KeymapAction) -> [KeyChord] {
        chordSet(for: action).chords.compactMap(KeyChord.parse)
    }

    /// The first parsed chord, for the places that can only show one.
    public func parsed(_ action: KeymapAction) -> KeyChord? {
        parsedChords(for: action).first
    }

    /// "⌘B", or "F1 / ⌘/" for an alias list. Falls back to the raw text when nothing parses.
    public func display(_ action: KeymapAction) -> String {
        let parsed = parsedChords(for: action)
        guard !parsed.isEmpty else { return chordSet(for: action).chords.joined(separator: " / ") }
        return parsed
            .map(\.displayString)
            .joined(separator: " / ")
    }

    /// Just the first chord, for a tooltip with room for one.
    public func primaryDisplay(_ action: KeymapAction) -> String {
        guard let chord = parsed(action) else { return self.chord(for: action) }
        return chord.displayString
    }

    /// Actions with no working chord, in `allCases` order, for the footer.
    public var unparseableActions: [KeymapAction] {
        KeymapAction.allCases.filter { parsedChords(for: $0).isEmpty }
    }
}

/// A coding key known only at runtime, since `CodingKeys` can't come from a `CaseIterable`.
struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
