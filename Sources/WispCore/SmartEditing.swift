import Foundation

public enum SmartEditing {
    /// Stored as plain `---`; `NotesLayoutManager` draws the full-width line.
    public static let horizontalRule = "---"

    /// The marker ↵ continues a list item with, indent included, or nil off a list. "" for an
    /// empty item, the signal to leave the list.
    public static func nextListMarker(for line: String) -> String? {
        // `* * *` and `- - -` would otherwise continue as bullets.
        if isRuleShaped(line) { return nil }
        // Before the plain bullet, which would take `[ ]` as content. A new box starts undone.
        if let match = line.firstMatch(of: /^([ \t]*)([-*+])[ \t]+\[[ xX]\]\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(match.1)\(match.2) [ ] "
        }
        if let match = line.firstMatch(of: /^([ \t]*)([-*+])\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(match.1)\(match.2) "
        }
        // `1)` as well as `1.`, as CommonMark allows; the letters take only `.`.
        if let match = line.firstMatch(of: /^([ \t]*)(\d+)([.)])\s/) {
            let n = Int(match.2) ?? 0
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(match.1)\(n + 1)\(match.3) "
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

    /// A list line taken apart, with offsets into the whole text.
    public struct ListItem: Equatable {
        public enum Marker: Equatable {
            /// `-`, `*`, or `+`.
            case bullet
            /// `1.`, `1)`, `A.`, or `a.`.
            case ordered
            /// `- [ ]` or `- [x]`, any bullet character; the box is part of the marker.
            case checklist(checked: Bool)

            public var isChecklist: Bool {
                if case .checklist = self { return true }
                return false
            }
        }

        public let marker: Marker
        /// The marker characters, without the whitespace around them.
        public let markerRange: NSRange
        /// Past the whitespace after the marker; wrapped lines hang here.
        public let contentStart: Int
        /// Leading whitespace, in characters.
        public let indentWidth: Int

        /// Zero-based; an uneven indent rounds down.
        public func depth(indentWidth unit: Int) -> Int {
            guard unit > 0 else { return 0 }
            return indentWidth / unit
        }

        /// Painted clear and drawn over by `NotesLayoutManager`; only an ordered marker shows.
        public var isMarkerHidden: Bool {
            if case .ordered = marker { return false }
            return true
        }

        /// The character typeset in place of a bullet; nil for a checklist or ordered marker.
        public func glyph(indentWidth unit: Int) -> String? {
            guard case .bullet = marker else { return nil }
            return bulletGlyph(depth: depth(indentWidth: unit))
        }

        /// The ` ` or `x` a check toggles.
        public var checklistStateIndex: Int? {
            marker.isChecklist ? NSMaxRange(markerRange) - 2 : nil
        }
    }

    /// Stricter than `nextListMarker`, since this styles every line and a false positive is a
    /// stray glyph. A marker needs whitespace after it: `-word` is a hyphen.
    public static func listItem(lineRange: NSRange, in text: NSString) -> ListItem? {
        var contentEnd = NSMaxRange(lineRange)
        if contentEnd > lineRange.location, text.character(at: contentEnd - 1) == 0x0A {
            contentEnd -= 1
        }

        var index = lineRange.location
        while index < contentEnd, isSpaceOrTab(text.character(at: index)) { index += 1 }
        let indentWidth = index - lineRange.location
        let markerStart = index

        // A rule shape would otherwise parse as a bullet.
        if MarkdownBlocks.isRuleShaped(lineRange: lineRange, in: text) { return nil }

        var marker: ListItem.Marker
        if index < contentEnd, isBulletCharacter(text.character(at: index)) {
            marker = .bullet
            index += 1
            // `- [ ]` with nothing after it is a bullet until the space arrives.
            if let box = checklistBox(at: index, before: contentEnd, in: text) {
                marker = .checklist(checked: box.checked)
                index = box.end
            }
        } else {
            var digits = 0
            while index < contentEnd, isOrderedCharacter(text.character(at: index), first: digits == 0)
            {
                digits += 1
                index += 1
                // Only digits run on; a letter marker is one character.
                if !isDigit(text.character(at: index - 1)) { break }
            }
            guard digits > 0, index < contentEnd else { return nil }
            // `)` only after digits, as CommonMark has it, so `a)` stays text.
            let delimiter = text.character(at: index)
            let afterDigits = isDigit(text.character(at: index - 1))
            guard delimiter == 0x2E || (delimiter == 0x29 && afterDigits) else { return nil }
            marker = .ordered
            index += 1
        }
        let markerRange = NSRange(location: markerStart, length: index - markerStart)

        guard index < contentEnd, isSpaceOrTab(text.character(at: index)) else { return nil }
        while index < contentEnd, isSpaceOrTab(text.character(at: index)) { index += 1 }

        return ListItem(
            marker: marker, markerRange: markerRange, contentStart: index,
            indentWidth: indentWidth)
    }

    /// Home on a list line: the item's text, or column 0 from there. Nil off a list line.
    public static func homeTarget(in text: NSString, cursor: Int) -> Int? {
        let line = LineEdits.lineRange(in: text, at: cursor)
        guard let item = listItem(lineRange: line, in: text) else { return nil }
        return cursor == item.contentStart ? line.location : item.contentStart
    }

    /// ↵ in a list or on an indented line, or nil to leave it to AppKit and keep undo coalescing.
    /// ⇧↵ in an item starts a continuation line. The caller tries `ruleOnReturn` first.
    public static func returnEdit(
        in text: NSString, selection: NSRange, shifted: Bool, unit: String
    ) -> LineEdits.Edit? {
        let cursor = selection.location
        if shifted, let continuation = continuationLine(in: text, cursor: cursor) {
            return .insert(continuation, replacing: selection)
        }
        if selection.length == 0, let edit = newlineBeforeItem(in: text, cursor: cursor) {
            return edit
        }

        let lineRange = LineEdits.lineRange(in: text, at: cursor)
        let content = NSRange(
            location: lineRange.location,
            length: MarkdownBlocks.contentEnd(of: lineRange, in: text) - lineRange.location)
        let line = text.substring(with: content)

        // On a continuation line, the owning item's next marker.
        if let continued = continuedItem(lineRange: lineRange, in: text),
            cursor >= lineRange.location + leadingIndent(of: line).utf16.count,
            let marker = nextListMarker(
                for: text.substring(with: NSRange(
                    location: continued.line.location,
                    length: LineEdits.contentLength(of: continued.line, in: text)))),
            !marker.isEmpty
        {
            return .insert("\n" + marker, replacing: selection)
        }

        guard let marker = nextListMarker(for: line) else {
            // Carry the indent up to the cursor, so a split inside the indent doesn't double it.
            let head = text.substring(
                with: NSRange(location: lineRange.location, length: cursor - lineRange.location))
            let indent = leadingIndent(of: head)
            return indent.isEmpty ? nil : .insert("\n" + indent, replacing: selection)
        }
        guard marker.isEmpty else { return .insert("\n" + marker, replacing: selection) }

        // An empty item steps out a level, or leaves the list when flush, in place. A selection
        // past the line takes a plain ↵.
        if selection.length == 0 {
            return .insert(outdentedEmptyItem(line, unit: unit) ?? "", replacing: content)
        }
        return .insert(
            "\n",
            replacing: NSRange(
                location: lineRange.location, length: NSMaxRange(selection) - lineRange.location))
    }

    /// ↵ before an item's text moves the item down intact, as Obsidian does, rather than making
    /// `- - foo`.
    public static func newlineBeforeItem(in text: NSString, cursor: Int) -> LineEdits.Edit? {
        let line = LineEdits.lineRange(in: text, at: cursor)
        guard let item = listItem(lineRange: line, in: text), cursor < item.contentStart else {
            return nil
        }
        return LineEdits.Edit(
            range: NSRange(location: line.location, length: 0), replacement: "\n",
            selection: NSRange(location: line.location + 1, length: 0))
    }

    /// ⌫ at the start of an item's text removes the marker and keeps the indent; one space would
    /// leave `-item`.
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

    /// An empty nested item one level shallower, by `LineEdits.leadingLevel`. Nil when flush left.
    public static func outdentedEmptyItem(_ line: String, unit: String) -> String? {
        guard !leadingIndent(of: line).isEmpty else { return nil }
        return String(line.dropFirst(LineEdits.leadingLevel(of: line, unit: unit)))
    }

    /// ⇧↵ in an item's text: a newline and whitespace out to the content column, CommonMark's
    /// continuation. The indent is copied as written; only the marker's width becomes spaces.
    public static func continuationLine(in text: NSString, cursor: Int) -> String? {
        let line = LineEdits.lineRange(in: text, at: cursor)
        let item: ListItem
        let itemLine: NSRange
        if let own = listItem(lineRange: line, in: text) {
            guard cursor >= own.contentStart else { return nil }
            (item, itemLine) = (own, line)
        } else if let continued = continuedItem(lineRange: line, in: text) {
            // Past the whitespace, as past a marker.
            guard cursor >= line.location + leadingIndent(of: text.substring(with: line)).utf16.count
            else { return nil }
            (item, itemLine) = continued
        } else {
            return nil
        }
        let indent = text.substring(
            with: NSRange(location: itemLine.location, length: item.indentWidth))
        let markerColumns = item.contentStart - itemLine.location - item.indentWidth
        return "\n" + indent + String(repeating: " ", count: markerColumns)
    }

    /// Leading whitespace reaching the item's content column. A whitespace-only line counts, since
    /// that is what ⇧↵ just wrote.
    public static func isContinuation(
        lineRange: NSRange, in text: NSString, of item: ListItem, itemLine: NSRange
    ) -> Bool {
        let contentColumn = item.contentStart - itemLine.location
        var index = lineRange.location
        let end = NSMaxRange(lineRange)
        while index < end, isSpaceOrTab(text.character(at: index)) { index += 1 }
        return index - lineRange.location >= contentColumn
    }

    /// The item a continuation line belongs to, walking up over other continuation lines.
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
            // Only whitespace-led lines sit between an item and its continuation.
            guard line.length > 0, isSpaceOrTab(text.character(at: line.location))
            else { return nil }
            cursor = line.location
        }
        return nil
    }

    // MARK: Indent guides

    /// A line's depth for indent guides, or nil outside a list. A blank between list lines takes
    /// the shallower depth, so a loose list keeps its guides.
    public static func guideDepth(
        lineRange: NSRange, in text: NSString, indentWidth: Int
    ) -> Int? {
        if let depth = listDepth(lineRange: lineRange, in: text, indentWidth: indentWidth) {
            return depth
        }
        guard isBlank(lineRange, in: text),
              let above = nearestListDepth(
                from: lineRange, in: text, indentWidth: indentWidth, stepping: lineAbove),
              let below = nearestListDepth(
                from: lineRange, in: text, indentWidth: indentWidth, stepping: lineBelow)
        else { return nil }
        return min(above, below)
    }

    /// The items a nested line hangs under, one slot per level. A parent two levels up fills both
    /// slots; a slot stays nil when nothing above is shallow enough.
    public static func ancestors(
        of lineRange: NSRange, depth: Int, in text: NSString, indentWidth: Int
    ) -> [(item: ListItem, line: NSRange)?] {
        var slots = [(item: ListItem, line: NSRange)?](repeating: nil, count: max(depth, 0))
        var level = depth - 1
        var line = lineRange
        while level >= 0, let above = lineAbove(line, in: text) {
            if let item = listItem(lineRange: above, in: text) {
                let itemDepth = item.depth(indentWidth: indentWidth)
                if itemDepth <= level {
                    for slot in itemDepth...level { slots[slot] = (item, above) }
                    level = itemDepth - 1
                }
            } else if !isBlank(above, in: text), continuedItem(lineRange: above, in: text) == nil {
                break
            }
            line = above
        }
        return slots
    }

    private static func listDepth(
        lineRange: NSRange, in text: NSString, indentWidth: Int
    ) -> Int? {
        if let item = listItem(lineRange: lineRange, in: text) {
            return item.depth(indentWidth: indentWidth)
        }
        return continuedItem(lineRange: lineRange, in: text)?.item.depth(indentWidth: indentWidth)
    }

    /// The first list line's depth in `step`'s direction, skipping blanks.
    private static func nearestListDepth(
        from lineRange: NSRange, in text: NSString, indentWidth: Int,
        stepping step: (NSRange, NSString) -> NSRange?
    ) -> Int? {
        var line = lineRange
        while let next = step(line, text) {
            if let depth = listDepth(lineRange: next, in: text, indentWidth: indentWidth) {
                return depth
            }
            guard isBlank(next, in: text) else { return nil }
            line = next
        }
        return nil
    }

    private static func isBlank(_ lineRange: NSRange, in text: NSString) -> Bool {
        text.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func lineAbove(_ lineRange: NSRange, in text: NSString) -> NSRange? {
        guard lineRange.location > 0 else { return nil }
        return LineEdits.lineRange(in: text, at: lineRange.location - 1)
    }

    private static func lineBelow(_ lineRange: NSRange, in text: NSString) -> NSRange? {
        guard NSMaxRange(lineRange) < text.length else { return nil }
        return LineEdits.lineRange(in: text, at: NSMaxRange(lineRange))
    }

    /// Longer digit runs are serial numbers, not positions, and stay as typed.
    public static let maxCountedDigits = 9

    /// Ordered markers put back in sequence, as edits. A run is consecutive items at one indent
    /// with one marker kind, counting from the first item's value; deeper and indented lines stay
    /// inside it, and a blank, a flush line, a bullet, or a shallower item ends it.
    public static func renumber(
        in text: NSString, blocks: MarkdownBlocks? = nil
    ) -> [LineEdits.Edit] {
        enum Kind { case digits, upper, lower }
        // `1.` then `1)` starts a new list, as in CommonMark.
        struct Run { let kind: Kind; let delimiter: unichar; var next: Int }
        var runs: [Int: Run] = [:]
        var edits: [LineEdits.Edit] = []
        for block in (blocks ?? MarkdownBlocks(text)).lines {
            // A `1.` in code or frontmatter is text.
            if block.kind == .fencedCode || block.kind == .frontmatter { continue }
            let line = block.range

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
            let delimiter = text.character(at: NSMaxRange(item.markerRange) - 1)
            let kind: Kind
            let value: Int
            if marker.count == 1, let c = marker.first?.asciiValue, !isDigit(unichar(c)) {
                kind = c >= 0x61 ? .lower : .upper
                value = Int(c - (kind == .lower ? 0x61 : 0x41))
            } else if marker.count <= maxCountedDigits, let n = Int(marker) {
                kind = .digits
                value = n
            } else {
                // Too long to count: left as typed, and it ends the run.
                runs[item.indentWidth] = nil
                continue
            }

            guard let run = runs[item.indentWidth], run.kind == kind, run.delimiter == delimiter
            else {
                runs[item.indentWidth] = Run(kind: kind, delimiter: delimiter, next: value + 1)
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

    /// `[ ]` to `[x]` or back: a one-character swap, so `selection` survives it.
    public static func toggledChecklist(
        in text: NSString, lineAt index: Int, selection: NSRange
    ) -> LineEdits.Edit? {
        let line = LineEdits.lineRange(in: text, at: index)
        guard let item = listItem(lineRange: line, in: text), let state = item.checklistStateIndex,
              case .checklist(let checked) = item.marker
        else { return nil }
        return LineEdits.Edit(
            range: NSRange(location: state, length: 1), replacement: checked ? " " : "x",
            selection: selection)
    }

    /// One per nesting level.
    public static let bulletGlyphs = ["•", "◦", "▪"]

    /// Cycles past the last glyph, as Word does: a level only needs to differ from its parent.
    public static func bulletGlyph(depth: Int) -> String {
        let count = bulletGlyphs.count
        return bulletGlyphs[((depth % count) + count) % count]
    }

    /// Whitespace, `[ ]` or `[x]`, then whitespace; any run before the box, so `-\t[ ] foo`
    /// counts. The returned `end` is just past the `]`.
    private static func checklistBox(
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

    static func isRuleShaped(_ content: String) -> Bool {
        let ns = content as NSString
        return MarkdownBlocks.isRuleShaped(
            lineRange: NSRange(location: 0, length: ns.length), in: ns)
    }
}
