import Foundation

/// Line edits as pure range arithmetic: one replacement plus where the selection lands. Kept out
/// of the text view so edge cases, like a last line with no newline, are ordinary unit tests.
public enum LineEdits {
    /// `range` is in the pre-edit text; `selection` is in the post-edit text.
    public struct Edit: Equatable {
        public let range: NSRange
        public let replacement: String
        public let selection: NSRange

        public init(range: NSRange, replacement: String, selection: NSRange) {
            self.range = range
            self.replacement = replacement
            self.selection = selection
        }

        /// Lets callers skip the undo group.
        public var isNoOp: Bool { range.length == 0 && replacement.isEmpty }

        /// Leaves the caret just after the replacement, as typing it would.
        public static func insert(_ replacement: String, replacing range: NSRange) -> Edit {
            Edit(
                range: range, replacement: replacement,
                selection: NSRange(
                    location: range.location + (replacement as NSString).length, length: 0))
        }
    }

    private static let newline: unichar = 0x0A
    private static let space: unichar = 0x20
    private static let tab: unichar = 0x09

    private static func isSpaceOrTab(_ c: unichar) -> Bool { c == space || c == tab }

    // MARK: Duplicate

    /// ⌘D: a selection is copied after itself and the copy selected; with none, the line is
    /// copied below and the caret keeps its column on the copy.
    public static func duplicate(in text: NSString, selection: NSRange) -> Edit {
        if selection.length > 0 {
            let copy = text.substring(with: selection)
            let insertAt = NSMaxRange(selection)
            return Edit(
                range: NSRange(location: insertAt, length: 0),
                replacement: copy,
                selection: NSRange(location: insertAt, length: selection.length))
        }

        let line = lineRange(in: text, at: selection.location)
        let column = selection.location - line.location
        let insertAt = NSMaxRange(line)

        if endsWithNewline(line, in: text) {
            let content = text.substring(
                with: NSRange(location: line.location, length: line.length - 1))
            return Edit(
                range: NSRange(location: insertAt, length: 0),
                replacement: content + "\n",
                selection: NSRange(location: insertAt + column, length: 0))
        }
        // On a last line with no newline, the newline leads the copy.
        let content = text.substring(with: line)
        return Edit(
            range: NSRange(location: insertAt, length: 0),
            replacement: "\n" + content,
            selection: NSRange(location: insertAt + 1 + column, length: 0))
    }

    // MARK: Open a line

    /// ⌘↩ / ⌘⇧↩: a new line below or above, wherever the caret is, as in VS Code. It keeps the
    /// line's indent but not a list marker, since this steps out of what you were typing.
    public static func openLine(in text: NSString, selection: NSRange, below: Bool) -> Edit {
        let block = lineBlock(in: text, covering: selection)
        let line = below ? lineRange(in: text, at: max(block.location, NSMaxRange(block) - 1))
            : lineRange(in: text, at: block.location)
        let indent = leadingWhitespace(of: line, in: text)
        let indentLength = (indent as NSString).length

        if !below || endsWithNewline(line, in: text) {
            let insertAt = below ? NSMaxRange(line) : line.location
            return Edit(
                range: NSRange(location: insertAt, length: 0),
                replacement: indent + "\n",
                selection: NSRange(location: insertAt + indentLength, length: 0))
        }
        // On a last line with no newline, the newline leads, as in `duplicate`.
        let insertAt = NSMaxRange(line)
        return Edit(
            range: NSRange(location: insertAt, length: 0),
            replacement: "\n" + indent,
            selection: NSRange(location: insertAt + 1 + indentLength, length: 0))
    }

    private static func leadingWhitespace(of line: NSRange, in text: NSString) -> String {
        var end = line.location
        while end < NSMaxRange(line), isSpaceOrTab(text.character(at: end)) { end += 1 }
        return text.substring(with: NSRange(location: line.location, length: end - line.location))
    }

    // MARK: Whole-line copy, cut, and paste

    /// ⌘C with nothing selected: the whole line, always with a newline so it pastes as a line.
    public static func lineForClipboard(
        in text: NSString, selection: NSRange
    ) -> (range: NSRange, string: String) {
        let line = lineRange(in: text, at: selection.location)
        let content = text.substring(with: line)
        return (line, endsWithNewline(line, in: text) ? content : content + "\n")
    }

    /// ⌘X with nothing selected: removes the line, keeping the column on the line that moves up.
    public static func cutLine(in text: NSString, selection: NSRange) -> Edit {
        let line = lineRange(in: text, at: selection.location)
        let column = selection.location - line.location
        let followingLength = lineContentLength(in: text, from: NSMaxRange(line))
        return Edit(
            range: line,
            replacement: "",
            selection: NSRange(location: line.location + min(column, followingLength), length: 0))
    }

    /// ⌘V of a whole-line copy goes above the current line rather than splitting it, as in VS
    /// Code. `line` comes from `lineForClipboard`.
    public static func pasteLine(in text: NSString, selection: NSRange, line: String) -> Edit {
        let current = lineRange(in: text, at: selection.location)
        return Edit(
            range: NSRange(location: current.location, length: 0),
            replacement: line,
            selection: NSRange(
                location: selection.location + (line as NSString).length, length: 0))
    }

    // MARK: Indent and outdent

    /// ⇥: one `unit` at the front of every line the selection touches.
    public static func indent(in text: NSString, selection: NSRange, unit: String) -> Edit {
        rewriteLines(in: text, selection: selection) { _ in
            (inserted: unit, removed: 0)
        }
    }

    /// ⇧⇥: one level off the front of every line the selection touches.
    public static func outdent(in text: NSString, selection: NSRange, unit: String) -> Edit {
        rewriteLines(in: text, selection: selection) { line in
            (inserted: "", removed: leadingLevel(of: line, unit: unit))
        }
    }

    /// The length of one indent level at the front of `line`: a leading tab,
    /// or up to `unit`'s width in spaces.
    static func leadingLevel(of line: String, unit: String) -> Int {
        if line.hasPrefix("\t") { return 1 }
        return min(line.prefix { $0 == " " }.count, (unit as NSString).length)
    }

    /// One indent level just before `cursor`, no further back than `floor`: a tab, or up to a unit
    /// of spaces, so `\t  ` gives up its spaces before its tab.
    private static func levelBefore(
        _ cursor: Int, floor: Int, in text: NSString, unit: String
    ) -> Int {
        if text.character(at: cursor - 1) == tab { return 1 }
        var spaces = 0
        while cursor - spaces - 1 >= floor, text.character(at: cursor - spaces - 1) == space {
            spaces += 1
        }
        return min(spaces, (unit as NSString).length)
    }

    /// ⇧⇥ after mid-line whitespace takes back what a mid-line ⇥ inserted. Nil otherwise, so the
    /// caller outdents the whole line.
    public static func outdentAtCursor(
        in text: NSString, selection: NSRange, unit: String
    ) -> Edit? {
        guard selection.length == 0 else { return nil }
        let cursor = max(0, min(selection.location, text.length))
        let line = lineRange(in: text, at: cursor)

        var runStart = cursor
        while runStart > line.location, isSpaceOrTab(text.character(at: runStart - 1)) {
            runStart -= 1
        }
        // Nothing to take, or the run is the leading indent.
        guard runStart < cursor, runStart > line.location else { return nil }

        let removed = levelBefore(cursor, floor: runStart, in: text, unit: unit)
        guard removed > 0 else { return nil }
        return .insert("", replacing: NSRange(location: cursor - removed, length: removed))
    }

    /// ⌫ with only whitespace before the caret takes one indent level, as Obsidian does, so ⇥ ⌫
    /// round trips. Nil anywhere else.
    public static func backspaceInIndent(
        in text: NSString, selection: NSRange, unit: String
    ) -> Edit? {
        guard selection.length == 0 else { return nil }
        let cursor = max(0, min(selection.location, text.length))
        let line = lineRange(in: text, at: cursor)
        guard cursor > line.location else { return nil }
        for index in line.location..<cursor where !isSpaceOrTab(text.character(at: index)) {
            return nil
        }

        let removed = levelBefore(cursor, floor: line.location, in: text, unit: unit)
        return .insert("", replacing: NSRange(location: cursor - removed, length: removed))
    }

    // MARK: Move and toggle

    /// ⌥↑ / ⌥↓: swaps the selected lines with the neighbour above (-1) or below (+1). A no-op at
    /// either end rather than wrapping.
    public static func moveLines(in text: NSString, selection: NSRange, by steps: Int) -> Edit {
        let noOp = Edit(
            range: NSRange(location: selection.location, length: 0), replacement: "",
            selection: selection)
        let block = lineBlock(in: text, covering: selection)

        let neighbour: NSRange
        if steps < 0 {
            guard block.location > 0 else { return noOp }
            neighbour = lineRange(in: text, at: block.location - 1)
        } else {
            guard NSMaxRange(block) < text.length else { return noOp }
            neighbour = lineRange(in: text, at: NSMaxRange(block))
        }

        let combined = NSUnionRange(block, neighbour)
        let trailingNewline = endsWithNewline(combined, in: text)
        var lines = contentLines(of: combined, in: text)
        guard lines.count > 1 else { return noOp }

        if steps < 0 {
            lines.append(lines.removeFirst())
        } else {
            lines.insert(lines.removeLast(), at: 0)
        }
        let joined = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")

        // Where the moved block starts afterwards.
        let blockStart =
            steps < 0
            ? combined.location
            : combined.location + (contentLength(of: neighbour, in: text) + 1)
        let offset = selection.location - block.location
        return Edit(
            range: combined,
            replacement: joined,
            selection: NSRange(location: blockStart + offset, length: selection.length))
    }

    /// ⌘L: bullets every line the selection touches, or strips them when all are items. A mixed
    /// block becomes a list; the indent survives either way.
    public static func toggleBulletedList(
        in text: NSString, selection: NSRange, marker: String = "- "
    ) -> Edit {
        let block = lineBlock(in: text, covering: selection)
        let allItems = everyLine(of: block, in: text) { line in
            guard let marker = SmartEditing.listItem(lineRange: line, in: text)?.marker else {
                return false
            }
            return marker == .bullet || marker.isChecklist
        }

        return rewriteLines(in: text, selection: selection) { body in
            let indent = body.prefix { $0 == " " || $0 == "\t" }
            let ns = body as NSString
            if allItems {
                // Strip through the marker's whitespace, then restore the indent.
                let lineRange = NSRange(location: 0, length: ns.length)
                guard let item = SmartEditing.listItem(lineRange: lineRange, in: ns) else {
                    return (inserted: "", removed: 0)
                }
                return (inserted: String(indent), removed: item.contentStart)
            }
            return (inserted: indent + marker, removed: indent.count)
        }
    }

    /// ⌘⇧L: lines that aren't all checklists become unchecked ones; an all-checklist block is
    /// checked, or unchecked when every box is ticked. A bullet gains a box, and an ordered item
    /// becomes a bullet, as in Apple Notes, since a box would hide its number.
    public static func toggleChecklist(in text: NSString, selection: NSRange) -> Edit {
        let block = lineBlock(in: text, covering: selection)
        let allChecklists = everyLine(of: block, in: text) { line in
            SmartEditing.listItem(lineRange: line, in: text)?.marker.isChecklist == true
        }
        let allChecked =
            allChecklists
            && everyLine(of: block, in: text) { line in
                SmartEditing.listItem(lineRange: line, in: text)?.marker == .checklist(checked: true)
            }

        return rewriteLines(in: text, selection: selection) { body in
            let ns = body as NSString
            let lineRange = NSRange(location: 0, length: ns.length)
            let item = SmartEditing.listItem(lineRange: lineRange, in: ns)

            if allChecklists, let item, let state = item.checklistStateIndex {
                let head = NSMutableString(string: ns.substring(to: item.contentStart))
                head.replaceCharacters(
                    in: NSRange(location: state, length: 1), with: allChecked ? " " : "x")
                return (inserted: head as String, removed: item.contentStart)
            }
            if let item {
                switch item.marker {
                case .checklist:
                    return (inserted: "", removed: 0)
                case .bullet:
                    return (inserted: ns.substring(to: item.contentStart) + "[ ] ",
                            removed: item.contentStart)
                case .ordered:
                    return (inserted: ns.substring(to: item.indentWidth) + "- [ ] ",
                            removed: item.contentStart)
                }
            }
            let indent = body.prefix { $0 == " " || $0 == "\t" }
            return (inserted: indent + "- [ ] ", removed: indent.count)
        }
    }

    /// False for an empty range: nothing to unset.
    private static func everyLine(
        of range: NSRange, in text: NSString, _ predicate: (NSRange) -> Bool
    ) -> Bool {
        var cursor = range.location
        var sawOne = false
        while cursor < NSMaxRange(range) {
            let line = text.lineRange(for: NSRange(location: cursor, length: 0))
            if !predicate(line) { return false }
            sawOne = true
            cursor = NSMaxRange(line)
        }
        return sawOne
    }

    /// The lines in `range`, each without its trailing newline.
    private static func contentLines(of range: NSRange, in text: NSString) -> [String] {
        var lines: [String] = []
        var cursor = range.location
        while cursor < NSMaxRange(range) {
            let line = text.lineRange(for: NSRange(location: cursor, length: 0))
            lines.append(
                text.substring(with: NSRange(
                    location: line.location, length: contentLength(of: line, in: text))))
            cursor = NSMaxRange(line)
        }
        return lines
    }

    /// A line's length without its trailing newline.
    public static func contentLength(of line: NSRange, in text: NSString) -> Int {
        endsWithNewline(line, in: text) ? line.length - 1 : line.length
    }

    /// Applies `change` to the head of every line the selection touches, as one replacement so
    /// it is one undo step, and maps the selection through.
    private static func rewriteLines(
        in text: NSString,
        selection: NSRange,
        change: (String) -> (inserted: String, removed: Int)
    ) -> Edit {
        let block = lineBlock(in: text, covering: selection)

        /// One line's head change, and how far earlier lines had moved it.
        struct LineShift {
            let oldStart: Int
            let shift: Int
            let headDelta: Int
        }

        var rewritten = ""
        var shifts: [LineShift] = []
        var runningShift = 0
        var cursor = block.location

        while cursor < NSMaxRange(block) {
            let line = text.lineRange(for: NSRange(location: cursor, length: 0))
            let body = text.substring(with: line)
            let (inserted, removed) = change(body)
            rewritten += inserted + (body as NSString).substring(from: removed)

            shifts.append(
                LineShift(
                    oldStart: line.location, shift: runningShift,
                    headDelta: (inserted as NSString).length - removed))
            runningShift += (inserted as NSString).length - removed
            cursor = NSMaxRange(line)
        }

        /// Clamped at the line start, so a caret in whitespace an outdent removed lands on the
        /// first surviving character.
        func mapped(_ offset: Int) -> Int {
            guard let line = shifts.last(where: { $0.oldStart <= offset }) else {
                return offset + runningShift
            }
            let column = offset - line.oldStart
            return line.oldStart + line.shift + max(0, column + line.headDelta)
        }

        let newStart = mapped(selection.location)
        let newEnd = mapped(NSMaxRange(selection))
        return Edit(
            range: block,
            replacement: rewritten,
            selection: NSRange(location: newStart, length: max(0, newEnd - newStart)))
    }

    // MARK: Line helpers

    /// Clamps `offset`, so one past the end resolves to the last line.
    public static func lineRange(in text: NSString, at offset: Int) -> NSRange {
        let safe = max(0, min(offset, text.length))
        return text.lineRange(for: NSRange(location: safe, length: 0))
    }

    /// Every line the selection touches. A selection ending just past a newline doesn't take the
    /// next line.
    public static func lineBlock(in text: NSString, covering selection: NSRange) -> NSRange {
        var range = NSRange(
            location: max(0, min(selection.location, text.length)),
            length: min(selection.length, text.length - min(selection.location, text.length)))
        if range.length > 0, text.character(at: NSMaxRange(range) - 1) == newline {
            range.length -= 1
        }
        return text.lineRange(for: range)
    }

    private static func endsWithNewline(_ line: NSRange, in text: NSString) -> Bool {
        line.length > 0 && text.character(at: NSMaxRange(line) - 1) == newline
    }

    /// Characters from `start` to the next newline or the end.
    private static func lineContentLength(in text: NSString, from start: Int) -> Int {
        guard start < text.length else { return 0 }
        var index = start
        while index < text.length, text.character(at: index) != newline { index += 1 }
        return index - start
    }
}
