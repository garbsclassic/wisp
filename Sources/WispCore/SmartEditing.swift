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
        // Before the plain bullet, which this would otherwise match as a
        // bullet whose content is `[ ]`. The next box is always empty —
        // a new task starts undone whatever the one above it says.
        if let match = line.firstMatch(of: /^([ \t]*)([-*+])[ \t]+\[[ xX]\]\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(match.1)\(match.2) [ ] "
        }
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
            /// `- [ ]` or `- [x]`, any bullet character. The box is part
            /// of the marker, not the content: it is drawn as one glyph
            /// and the caret's stops treat it as chrome.
            case task(checked: Bool)

            public var isTask: Bool {
                if case .task = self { return true }
                return false
            }
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

        /// What is drawn in place of the marker, or nil for an ordered
        /// marker, which is its own content and stays visible.
        public func glyph(indentWidth unit: Int) -> String? {
            switch marker {
            case .bullet: return bulletGlyph(depth: depth(indentWidth: unit))
            case .task(let checked): return taskGlyph(checked: checked)
            case .ordered: return nil
            }
        }

        /// The character inside a task's box — the ` ` or `x` — which is
        /// the one character a check toggles.
        public var taskStateIndex: Int? {
            marker.isTask ? NSMaxRange(markerRange) - 2 : nil
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

        var marker: ListItem.Marker
        if index < contentEnd, isBulletCharacter(text.character(at: index)) {
            marker = .bullet
            index += 1
            // `- [ ] ` and `- [x] `. The box needs whitespace after it
            // like any marker does; `- [ ]` alone at the end of a line is
            // a bullet whose content is the box, until the space arrives.
            if let box = taskBox(at: index, before: contentEnd, in: text) {
                marker = .task(checked: box.checked)
                index = box.end
            }
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

    /// ⌫ with the caret at the start of an item's text. What comes off is
    /// the marker and the whitespace after it, not the one space before
    /// the caret — deleting that leaves `-item`, which silently stops
    /// being a list item anyway. The indent stays, so a nested item
    /// becomes a nested line; ⇧⇥ is the key for flattening it. Nil
    /// anywhere else on the line, where ⌫ is an ordinary ⌫.
    public static func backspaceAtItemStart(in text: NSString, cursor: Int) -> LineEdits.Edit? {
        let line = LineEdits.lineRange(in: text, at: cursor)
        guard let item = listItem(lineRange: line, in: text), cursor == item.contentStart else {
            return nil
        }
        let markerStart = line.location + item.indentWidth
        return LineEdits.Edit(
            range: NSRange(location: markerStart, length: cursor - markerStart), replacement: "",
            selection: NSRange(location: markerStart, length: 0))
    }

    /// ↵ on an empty item that is nested: the line, one level shallower.
    /// Each press steps out a level and only the last leaves the list —
    /// the only way ↵ alone can walk a caret back up to its parent. Nil
    /// for a flush-left item, which is the signal to exit. Mirrors
    /// `LineEdits.outdent`: one leading tab, or up to a unit of spaces.
    public static func outdentedEmptyItem(_ line: String, unit: String) -> String? {
        let indent = leadingIndent(of: line)
        guard !indent.isEmpty else { return nil }
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        let spaces = line.prefix { $0 == " " }.count
        return String(line.dropFirst(min(spaces, (unit as NSString).length)))
    }

    /// ⇧↵ inside an item's text: a newline plus whitespace out to the
    /// content column, so the next line reads as more of the same item.
    /// CommonMark's own spelling of a continuation, which is what keeps
    /// it an item in Obsidian too. The indent is copied as written — tabs
    /// stay tabs — and only the marker's width is padded with spaces.
    /// Nil off a list line or with the caret before the content.
    public static func continuationLine(in text: NSString, cursor: Int) -> String? {
        let line = LineEdits.lineRange(in: text, at: cursor)
        guard let item = listItem(lineRange: line, in: text), cursor >= item.contentStart else {
            return nil
        }
        let indent = text.substring(
            with: NSRange(location: line.location, length: item.indentWidth))
        let markerColumns = item.contentStart - line.location - item.indentWidth
        return "\n" + indent + String(repeating: " ", count: markerColumns)
    }

    /// Whether a non-list line is a continuation of the item above it:
    /// its leading whitespace reaches the item's content column. Blank
    /// lines don't count — whitespace with nothing after it is not a
    /// paragraph.
    public static func isContinuation(
        lineRange: NSRange, in text: NSString, of item: ListItem, itemLine: NSRange
    ) -> Bool {
        let contentColumn = item.contentStart - itemLine.location
        var index = lineRange.location
        let end = NSMaxRange(lineRange)
        while index < end, isSpaceOrTab(text.character(at: index)) { index += 1 }
        guard index - lineRange.location >= contentColumn, index < end else { return false }
        return text.character(at: index) != 0x0A
    }

    /// The item a continuation line belongs to: walking up over any
    /// continuation lines, the first list item whose content column the
    /// line's whitespace reaches. Nil when the line isn't a continuation
    /// of anything. `nextListMarker` on the item's line is then what ↵
    /// continues with.
    public static func continuedItem(
        lineRange: NSRange, in text: NSString
    ) -> (item: ListItem, line: NSRange)? {
        guard listItem(lineRange: lineRange, in: text) == nil else { return nil }
        var cursor = lineRange.location
        while cursor > 0 {
            let line = LineEdits.lineRange(in: text, at: cursor - 1)
            if let item = listItem(lineRange: line, in: text) {
                return isContinuation(lineRange: lineRange, in: text, of: item, itemLine: line)
                    ? (item, line) : nil
            }
            // Only whitespace-led, non-blank lines can sit between an
            // item and its continuation.
            guard line.length > 0, isSpaceOrTab(text.character(at: line.location)),
                  text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines) != ""
            else { return nil }
            cursor = line.location
        }
        return nil
    }

    /// Ordered markers put back in sequence. A run is consecutive items
    /// at one indent with one kind of marker — `1.`, `A.`, or `a.` —
    /// and the first item's value is kept, so a list can start at 3 or
    /// at C. Deeper items, continuation lines, and any indented line
    /// sit inside a run without breaking it; a blank line, a flush
    /// non-list line, a bullet at the run's depth, or an item at a
    /// shallower depth all end it. The result is the set of markers
    /// that differ from what the sequence says, as pre-edit ranges.
    public static func renumber(in text: NSString) -> [LineEdits.Edit] {
        enum Kind { case digits, upper, lower }
        struct Run { let kind: Kind; var next: Int }
        var runs: [Int: Run] = [:]
        var edits: [LineEdits.Edit] = []

        var lineStart = 0
        while lineStart < text.length {
            let line = LineEdits.lineRange(in: text, at: lineStart)
            defer { lineStart = NSMaxRange(line) }

            guard let item = listItem(lineRange: line, in: text) else {
                let blankOrFlush =
                    line.length == 0 || !isSpaceOrTab(text.character(at: line.location))
                    || text.substring(with: line)
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if blankOrFlush { runs.removeAll() }
                continue
            }
            for depth in runs.keys where depth > item.indentWidth { runs[depth] = nil }
            guard item.marker == .ordered else {
                runs[item.indentWidth] = nil
                continue
            }

            let marker = text.substring(
                with: NSRange(location: item.markerRange.location, length: item.markerRange.length - 1))
            let kind: Kind
            let value: Int
            if let n = Int(marker) {
                kind = .digits
                value = n
            } else if let c = marker.first?.asciiValue, marker.count == 1 {
                kind = c >= 0x61 ? .lower : .upper
                value = Int(c - (kind == .lower ? 0x61 : 0x41))
            } else {
                continue
            }

            guard let run = runs[item.indentWidth], run.kind == kind else {
                runs[item.indentWidth] = Run(kind: kind, next: value + 1)
                continue
            }
            let expected: String
            switch kind {
            case .digits: expected = String(run.next)
            case .upper, .lower:
                // Past Z there is nothing to count with; leave it as typed.
                guard run.next < 26 else { runs[item.indentWidth] = nil; continue }
                expected = String(UnicodeScalar(UInt8(run.next) + (kind == .lower ? 0x61 : 0x41)))
            }
            runs[item.indentWidth]!.next = run.next + 1
            if expected != marker {
                let range = NSRange(
                    location: item.markerRange.location, length: item.markerRange.length - 1)
                edits.append(LineEdits.Edit(range: range, replacement: expected, selection: range))
            }
        }
        return edits
    }

    /// Flips the box on the task line at `index`: `[ ]` to `[x]` or back.
    /// A one-character swap, so `selection` survives it untouched. Nil
    /// off a task line.
    public static func toggledTask(
        in text: NSString, lineAt index: Int, selection: NSRange
    ) -> LineEdits.Edit? {
        let line = LineEdits.lineRange(in: text, at: index)
        guard let item = listItem(lineRange: line, in: text), let state = item.taskStateIndex,
              case .task(let checked) = item.marker
        else { return nil }
        return LineEdits.Edit(
            range: NSRange(location: state, length: 1), replacement: checked ? " " : "x",
            selection: selection)
    }

    /// The glyph drawn in place of a hidden bullet marker at each nesting
    /// level.
    public static let bulletGlyphs = ["•", "◦", "▪"]

    /// Drawn in place of a hidden `- [ ]` or `- [x]`.
    public static func taskGlyph(checked: Bool) -> String {
        checked ? "☑" : "☐"
    }

    /// Cycles rather than clamping past the last glyph, the way Word and
    /// Docs do. The indent already states the absolute depth, so what a
    /// fourth level needs from its glyph is to look different from its
    /// parent — not to be a fourth distinct symbol.
    public static func bulletGlyph(depth: Int) -> String {
        let count = bulletGlyphs.count
        return bulletGlyphs[((depth % count) + count) % count]
    }

    /// Whitespace, then `[ ]` or `[x]`, then more whitespace, starting at
    /// `index`. Any run of whitespace before the box, not one space: a
    /// tab-separated `-\t[ ] foo` is a task too, and ⌘⇧L puts the box
    /// after whatever whitespace the marker already had. `end` is the
    /// index one past the closing bracket.
    private static func taskBox(
        at index: Int, before end: Int, in text: NSString
    ) -> (checked: Bool, end: Int)? {
        var i = index
        while i < end, isSpaceOrTab(text.character(at: i)) { i += 1 }
        guard i > index, i + 3 < end,
              text.character(at: i) == 0x5B,
              text.character(at: i + 2) == 0x5D,
              isSpaceOrTab(text.character(at: i + 3))
        else { return nil }
        switch text.character(at: i + 1) {
        case 0x20: return (false, i + 3)
        case 0x78, 0x58: return (true, i + 3)
        default: return nil
        }
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
