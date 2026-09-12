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
    /// marker (e.g. `"- "`, `"3. "`, `"  B. "`). Returns an empty string when
    /// the current line is an empty list item — the caller should treat that
    /// as a signal to exit the list.
    ///
    /// The line's own leading whitespace is part of what comes back, so ↵ on a
    /// nested item continues the list at the depth it was already at rather
    /// than dropping it back to the margin.
    public static func nextListMarker(for line: String) -> String? {
        if let match = line.firstMatch(of: /^([ \t]*)([-*+])\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(match.1)\(match.2) "
        }
        if let match = line.firstMatch(of: /^([ \t]*)(\d+)\.\s/) {
            let n = Int(match.2) ?? 0
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(match.1)\(n + 1). "
        }
        if let match = line.firstMatch(of: /^([ \t]*)([A-Z])\.\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            guard let next = nextAlphaMarker(Character(String(match.2)), limit: "Z") else {
                return nil
            }
            return String(match.1) + next
        }
        if let match = line.firstMatch(of: /^([ \t]*)([a-z])\.\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            guard let next = nextAlphaMarker(Character(String(match.2)), limit: "z") else {
                return nil
            }
            return String(match.1) + next
        }
        return nil
    }

    /// The leading spaces and tabs on `line`, for carrying an indent onto the
    /// next one. Empty when the line is flush left, which is the caller's
    /// signal to leave ↵ to AppKit.
    public static func leadingIndent(of line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    private static func isEmptyAfter(_ range: Range<String.Index>, in line: String) -> Bool {
        line[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func nextAlphaMarker(_ c: Character, limit: Character) -> String? {
        guard c < limit, let ascii = c.asciiValue else { return nil }
        return "\(Character(UnicodeScalar(ascii + 1))). "
    }

    // MARK: List structure

    /// A list line taken apart: where its indent, marker, and content
    /// each begin. Offsets are absolute, into the whole text, so the
    /// styling pass can apply attributes straight from one of these.
    public struct ListItem: Equatable {
        /// What kind of marker leads the line. Only `bullet` is drawn as
        /// a glyph — an ordered marker *is* its own content, and swapping
        /// it for a symbol would lose the number.
        public enum Marker: Equatable {
            /// `-`, `*`, or `+`.
            case bullet
            /// `1.`, `A.`, or `a.`.
            case ordered
        }

        public let marker: Marker
        /// The marker characters themselves — not the whitespace on
        /// either side. This is the range the bullet glyph replaces.
        public let markerRange: NSRange
        /// Where the item's text starts, past the whitespace after the
        /// marker. Wrapped lines hang to here.
        public let contentStart: Int
        /// Leading whitespace, in characters.
        public let indentWidth: Int

        /// Nesting level, counting from zero. Whitespace that doesn't
        /// divide evenly rounds down, so a hand-typed three-space indent
        /// under a two-space setting still reads as one level in rather
        /// than as none.
        public func depth(indentWidth unit: Int) -> Int {
            guard unit > 0 else { return 0 }
            return indentWidth / unit
        }
    }

    /// Parses `lineRange` as a list item, or returns nil if it isn't one.
    ///
    /// Deliberately stricter than `nextListMarker`: that one runs on Enter
    /// against the line you just typed, while this runs on every line of
    /// the document on every keystroke, and a false positive here shows up
    /// as a stray glyph rather than a missed continuation. A marker with no
    /// whitespace after it isn't a list item — `-word` is a hyphen.
    public static func listItem(lineRange: NSRange, in text: NSString) -> ListItem? {
        var contentEnd = NSMaxRange(lineRange)
        if contentEnd > lineRange.location, text.character(at: contentEnd - 1) == 0x0A {
            contentEnd -= 1
        }

        var index = lineRange.location
        while index < contentEnd, isSpaceOrTab(text.character(at: index)) { index += 1 }
        let indentWidth = index - lineRange.location
        let markerStart = index

        // An HR is three or more `-` and nothing else; it would otherwise
        // parse as a bullet whose content is the remaining dashes.
        if isHorizontalRuleLine(lineRange: lineRange, in: text) { return nil }

        let marker: ListItem.Marker
        if index < contentEnd, isBulletCharacter(text.character(at: index)) {
            marker = .bullet
            index += 1
        } else {
            var digits = 0
            while index < contentEnd, isOrderedCharacter(text.character(at: index), first: digits == 0)
            {
                digits += 1
                index += 1
                // `A.` and `a.` are single-character markers; only digits
                // run on.
                if !isDigit(text.character(at: index - 1)) { break }
            }
            guard digits > 0, index < contentEnd, text.character(at: index) == 0x2E else {
                return nil
            }
            marker = .ordered
            index += 1
        }
        let markerRange = NSRange(location: markerStart, length: index - markerStart)

        // The whitespace after the marker is required, and is what
        // separates a list item from a stray character.
        guard index < contentEnd, isSpaceOrTab(text.character(at: index)) else { return nil }
        while index < contentEnd, isSpaceOrTab(text.character(at: index)) { index += 1 }

        return ListItem(
            marker: marker, markerRange: markerRange, contentStart: index,
            indentWidth: indentWidth)
    }

    /// Where Home lands on a list line: the start of the item's text, or
    /// column 0 when the cursor is already there. The marker is chrome
    /// rather than content — it is drawn as a glyph — so the stop a
    /// second press adds is the one that puts the cursor before it. Nil
    /// off a list line, which keeps the ordinary behavior.
    public static func homeTarget(in text: NSString, cursor: Int) -> Int? {
        let line = LineEdits.lineRange(in: text, at: cursor)
        guard let item = listItem(lineRange: line, in: text) else { return nil }
        return cursor == item.contentStart ? line.location : item.contentStart
    }

    /// ↵ with the caret before a list item's text — at column 0, or inside
    /// the indent or marker. There is nothing to split there: continuing
    /// the list would put a fresh marker in front of the one already on
    /// the line (`- - foo`). Instead the item moves down intact and the
    /// caret rides with it, which is what Obsidian and iA Writer do. Nil
    /// off a list line or once the caret reaches the content, where the
    /// ordinary continuation applies.
    public static func newlineBeforeItem(in text: NSString, cursor: Int) -> LineEdits.Edit? {
        let line = LineEdits.lineRange(in: text, at: cursor)
        guard let item = listItem(lineRange: line, in: text), cursor < item.contentStart else {
            return nil
        }
        return LineEdits.Edit(
            range: NSRange(location: line.location, length: 0), replacement: "\n",
            selection: NSRange(location: line.location + 1, length: 0))
    }

    /// The glyph drawn in place of a hidden bullet marker at each nesting
    /// level.
    public static let bulletGlyphs = ["•", "◦", "▪"]

    /// Cycles rather than clamping past the last glyph, the way Word and
    /// Docs do. The indent already states the absolute depth, so what a
    /// fourth level needs from its glyph is to look different from its
    /// parent — not to be a fourth distinct symbol.
    public static func bulletGlyph(depth: Int) -> String {
        let count = bulletGlyphs.count
        return bulletGlyphs[((depth % count) + count) % count]
    }

    private static func isSpaceOrTab(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }
    private static func isDigit(_ c: unichar) -> Bool { c >= 0x30 && c <= 0x39 }
    private static func isBulletCharacter(_ c: unichar) -> Bool {
        c == 0x2D || c == 0x2A || c == 0x2B
    }

    /// Digits anywhere, or a single letter in the first position.
    private static func isOrderedCharacter(_ c: unichar, first: Bool) -> Bool {
        if isDigit(c) { return true }
        guard first else { return false }
        return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
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
