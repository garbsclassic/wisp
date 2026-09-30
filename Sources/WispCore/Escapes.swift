import Foundation

/// Backslash escapes, as UTF-16 offsets. Obsidian's set, plus `=` `<` `+` `)` that Wisp renders
/// and `|` for table cells. Block parsers already refuse escaped markers, so only the inline
/// passes consult these.
public enum Escapes {
    public static let escapable: Set<Character> = [
        "\\", "`", "*", "_", "=", "#", "-", "+", ".", ")", "<", "|", "~",
    ]

    private static let backslash: unichar = 0x5C

    /// Each escapable character is one UTF-16 unit.
    private static let escapableUnits: Set<unichar> = Set(
        escapable.compactMap { $0.unicodeScalars.first.map { unichar($0.value) } })

    public struct Marks: Equatable, Sendable {
        /// Painted faint.
        public let backslashes: Set<Int>
        /// A delimiter on one of these isn't markup.
        public let escaped: Set<Int>

        public static let none = Marks(backslashes: [], escaped: [])

        public init(backslashes: Set<Int>, escaped: Set<Int>) {
            self.backslashes = backslashes
            self.escaped = escaped
        }

        public var isEmpty: Bool { backslashes.isEmpty }

        public func isEscaped(_ offset: Int) -> Bool { escaped.contains(offset) }

        /// Escaped characters blanked to spaces, offsets unchanged. Masking, not filtering matches
        /// afterwards: a rejected match has already consumed the run that began inside it.
        public func masking(_ text: String) -> String {
            guard !isEmpty else { return text }
            let masked = NSMutableString(string: text)
            for offset in escaped where offset < masked.length {
                masked.replaceCharacters(in: NSRange(location: offset, length: 1), with: " ")
            }
            return masked as String
        }
    }

    /// Each pair is consumed whole, so `\\` escapes itself and can't escape a third character.
    public static func scan(_ text: NSString) -> Marks {
        guard text.length > 1 else { return .none }
        var backslashes: Set<Int> = []
        var escaped: Set<Int> = []
        var index = 0
        // Stops before the last character, so a trailing backslash is inert.
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
