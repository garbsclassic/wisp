import Foundation

/// The footer's 1-based line and column, counting characters rather than UTF-16 units.
public struct CaretPosition: Equatable, Sendable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    /// Clamps `offset`, which can briefly outlive a reload that shortened the note.
    public init(in text: String, at offset: Int) {
        let ns = text as NSString
        let safe = max(0, min(offset, ns.length))
        let lineStart = ns.lineRange(for: NSRange(location: safe, length: 0)).location
        let before = ns.substring(to: lineStart)
        line = 1 + before.utf16.filter { $0 == 0x0A }.count
        column = 1 + ns.substring(with: NSRange(location: lineStart, length: safe - lineStart)).count
    }
}
