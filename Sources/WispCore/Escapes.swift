import Foundation

/// Backslash escapes, as offsets into the text.
///
/// Obsidian's set, since these notes are read there too, extended with the
/// markers Wisp renders that Obsidian's list doesn't name (`=` for
/// `==highlight==`, `<` for `<u>`, `+` for a bullet). `|` means nothing here
/// — no tables — but a `\|` typed in Obsidian should still read as an escape
/// rather than as a stray backslash.
///
/// Most of what an escape has to stop, the parsers already refuse on their
/// own: `\# foo` doesn't match the heading pattern, `\- foo` isn't a bullet
/// because `\` isn't a bullet character, and `\---` isn't a rule because the
/// line isn't all dashes. What the escape buys there is only the *rendering* —
/// the backslash is painted faint so it reads as syntax. It is the inline
/// passes, whose patterns happily match starting one character in, that need
/// to be told to skip.
public enum Escapes {
    public static let escapable: Set<Character> = [
        "\\", "`", "*", "_", "=", "#", "-", "+", ".", "<", "|", "~",
    ]

    private static let backslash: unichar = 0x5C

    /// The escapable set as UTF-16 units. Every one of them is a single BMP
    /// code unit, so the membership test is a comparison rather than a
    /// grapheme walk.
    private static let escapableUnits: Set<unichar> = Set(
        escapable.compactMap { $0.unicodeScalars.first.map { unichar($0.value) } })

    /// Where the active backslashes are, and what they cover. Offsets are
    /// UTF-16, to line up with `NSTextStorage` and `NSRange` without
    /// conversion.
    public struct Marks: Equatable, Sendable {
        /// Backslashes doing the escaping. Painted faint.
        public let backslashes: Set<Int>
        /// The characters they escape. A pattern whose delimiter starts on
        /// one of these is not markup.
        public let escaped: Set<Int>

        public static let none = Marks(backslashes: [], escaped: [])

        public init(backslashes: Set<Int>, escaped: Set<Int>) {
            self.backslashes = backslashes
            self.escaped = escaped
        }

        public var isEmpty: Bool { backslashes.isEmpty }

        public func isEscaped(_ offset: Int) -> Bool { escaped.contains(offset) }

        /// The text with every escaped character blanked to a space, for the
        /// inline passes to scan instead of the real thing. Offsets are
        /// unchanged — every escapable character is one UTF-16 unit — so a
        /// match on the masked text is a range into the storage.
        ///
        /// Masking rather than filtering matches after the fact: a regex
        /// scan is left-to-right and non-overlapping, so a match that a
        /// filter then rejects has still consumed its characters, and the
        /// real run that began inside it never gets a turn. `~a\~ b~` found
        /// `~a\~`, threw it away, and had only ` b~` left to look at. With
        /// the escaped tilde blanked there is nothing for the scanner to
        /// pair wrongly in the first place.
        public func masking(_ text: String) -> String {
            guard !isEmpty else { return text }
            let masked = NSMutableString(string: text)
            for offset in escaped where offset < masked.length {
                masked.replaceCharacters(in: NSRange(location: offset, length: 1), with: " ")
            }
            return masked as String
        }
    }

    /// Scanned left to right, consuming both characters of every pair, so
    /// `\\` escapes itself and the second backslash cannot go on to escape a
    /// third character. Only the first of the two is painted.
    public static func scan(_ text: NSString) -> Marks {
        guard text.length > 1 else { return .none }
        var backslashes: Set<Int> = []
        var escaped: Set<Int> = []
        var index = 0
        // `length - 1`, so a trailing backslash is inert without a special
        // case: the loop can never stand on the last character, and there is
        // nothing after it to escape anyway.
        while index < text.length - 1 {
            guard text.character(at: index) == backslash,
                escapableUnits.contains(text.character(at: index + 1))
            else {
                index += 1
                continue
            }
            backslashes.insert(index)
            escaped.insert(index + 1)
            index += 2
        }
        return Marks(backslashes: backslashes, escaped: escaped)
    }

    public static func scan(_ text: String) -> Marks { scan(text as NSString) }
}
