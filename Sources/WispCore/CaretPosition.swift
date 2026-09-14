import Foundation

/// Where the caret is, as the footer prints it: 1-based line and column.
///
/// The column counts characters rather than UTF-16 units, so an emoji is
/// one column and not two — the footer is for a person, and the offset it
/// is computed from never leaves the app.
public struct CaretPosition: Equatable, Sendable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    /// The position of the caret at UTF-16 `offset` into `text`. An offset
    /// past the end clamps to the end, since the model's offset can briefly
    /// outlive a reload that shortened the note.
    public init(in text: String, at offset: Int) {
        let ns = text as NSString
        let safe = max(0, min(offset, ns.length))
        let lineStart = ns.lineRange(for: NSRange(location: safe, length: 0)).location
        let before = ns.substring(to: lineStart)
        // Every line ends in a newline except possibly the last, so the
        // newlines before this line's start count exactly the lines above.
        line = 1 + before.utf16.filter { $0 == 0x0A }.count
        column = 1 + ns.substring(with: NSRange(location: lineStart, length: safe - lineStart)).count
    }
}
