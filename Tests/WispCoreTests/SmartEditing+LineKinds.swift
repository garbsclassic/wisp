import Foundation

@testable import WispCore

/// One-line questions about how `MarkdownBlocks` classifies a line, for tests that assert on a
/// single line.
extension SmartEditing {
    /// Is the given line drawn as a rule? Classifies the whole note to answer, which suits a
    /// test about one line; the app reads one `MarkdownBlocks` per pass instead.
    static func isHorizontalRuleLine(lineRange: NSRange, in text: NSString) -> Bool {
        MarkdownBlocks(text).line(at: lineRange.location)?.kind == .rule
    }

    /// Convenience overload — treats the whole String as the note, one line long.
    static func isHorizontalRuleLine(_ line: String) -> Bool {
        isHorizontalRuleLine(lineRange: NSRange(location: 0, length: 0), in: line as NSString)
    }

    /// True when the line underlines the paragraph above it, making it a setext heading.
    static func isSetextUnderline(lineRange: NSRange, in text: NSString) -> Bool {
        setextLevel(lineRange: lineRange, in: text) != nil
    }

    /// The level a setext underline gives the paragraph above it: 1 for `===`, 2 for `---`, or
    /// nil when the line isn't one.
    static func setextLevel(lineRange: NSRange, in text: NSString) -> Int? {
        guard case .setextUnderline(let level, _) = MarkdownBlocks(text).line(
            at: lineRange.location)?.kind
        else { return nil }
        return level
    }

    /// True when `lineStart` falls inside a fenced code block, between its fences.
    static func isInsideFence(lineStart: Int, in text: NSString) -> Bool {
        MarkdownBlocks(text).line(at: lineStart)?.kind == .fencedCode
    }
}
