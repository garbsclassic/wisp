import Foundation

public enum SmartEditing {
    /// Plain-text horizontal rule, stored as the markdown-standard
    /// `---`. The visual full-width line is drawn by the custom layout
    /// manager (HorizontalRuleLayoutManager) — the on-disk text is
    /// just three dashes, so rendering tracks the panel's width and
    /// the file remains portable plain markdown.
    public static let horizontalRule = "---"

    public static func isHorizontalRuleTrigger(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "---"
    }

    /// Given a line of text, return the marker to insert on the next line if
    /// this line is a list item. Returns `nil` if not a list, or the next
    /// marker (e.g. `"- "`, `"3. "`, `"B. "`). Returns an empty string when
    /// the current line is an empty list item — the caller should treat that
    /// as a signal to exit the list.
    public static func nextListMarker(for line: String) -> String? {
        if let match = line.firstMatch(of: /^([-*+])\s/) {
            let bullet = String(match.1)
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(bullet) "
        }
        if let match = line.firstMatch(of: /^(\d+)\.\s/) {
            let n = Int(match.1) ?? 0
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(n + 1). "
        }
        if let match = line.firstMatch(of: /^([A-Z])\.\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            let c = Character(String(match.1))
            guard c < "Z", let ascii = c.asciiValue else { return nil }
            return "\(Character(UnicodeScalar(ascii + 1))). "
        }
        if let match = line.firstMatch(of: /^([a-z])\.\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            let c = Character(String(match.1))
            guard c < "z", let ascii = c.asciiValue else { return nil }
            return "\(Character(UnicodeScalar(ascii + 1))). "
        }
        return nil
    }

    private static func isEmptyAfter(_ range: Range<String.Index>, in line: String) -> Bool {
        line[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Pure: is the given line content (a line range in `nsString`) an
    /// HR-only line — at least three characters, all of which are either
    /// `-` (0x2D) or `─` (0x2500), with the trailing newline allowed.
    /// Lives here rather than on the layout manager so it is testable
    /// without AppKit.
    public static func isHorizontalRuleLine(lineRange: NSRange, in nsString: NSString) -> Bool {
        var contentEnd = lineRange.location + lineRange.length
        if contentEnd > lineRange.location,
           nsString.character(at: contentEnd - 1) == 0x0A {
            contentEnd -= 1
        }
        let contentLength = contentEnd - lineRange.location
        if contentLength < 3 { return false }
        for i in 0..<contentLength {
            let c = nsString.character(at: lineRange.location + i)
            if c != 0x2D && c != 0x2500 { return false }
        }
        return true
    }

    /// Convenience overload — treats the whole String as the line content,
    /// with no trailing newline expected.
    public static func isHorizontalRuleLine(_ line: String) -> Bool {
        let ns = line as NSString
        return isHorizontalRuleLine(
            lineRange: NSRange(location: 0, length: ns.length),
            in: ns
        )
    }
}
