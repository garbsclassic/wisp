import Foundation

@testable import WispCore

/// Single-line queries over `MarkdownBlocks`, for tests that assert on one line.
extension SmartEditing {
    static func isHorizontalRuleLine(lineRange: NSRange, in text: NSString) -> Bool {
        MarkdownBlocks(text).line(at: lineRange.location)?.kind == .rule
    }

    static func isHorizontalRuleLine(_ line: String) -> Bool {
        isHorizontalRuleLine(lineRange: NSRange(location: 0, length: 0), in: line as NSString)
    }

    static func isSetextUnderline(lineRange: NSRange, in text: NSString) -> Bool {
        setextLevel(lineRange: lineRange, in: text) != nil
    }

    static func setextLevel(lineRange: NSRange, in text: NSString) -> Int? {
        guard case .setextUnderline(let level, _) = MarkdownBlocks(text).line(
            at: lineRange.location)?.kind
        else { return nil }
        return level
    }

    static func isInsideFence(lineStart: Int, in text: NSString) -> Bool {
        MarkdownBlocks(text).line(at: lineStart)?.kind == .fencedCode
    }
}
