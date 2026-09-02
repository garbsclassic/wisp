import Foundation

/// Line-oriented edits as pure range arithmetic: given the text and the
/// current selection, produce the one replacement that performs the edit
/// and where the selection lands afterwards.
///
/// Kept out of the text view on purpose. Every one of these has edges that
/// are easy to get wrong and awkward to reach through the UI — a last line
/// with no trailing newline, a selection that ends exactly on a line
/// boundary, a cursor sitting inside the whitespace an outdent is about to
/// remove — and here they are ordinary unit tests.
public enum LineEdits {
    /// One replacement plus the selection to restore after applying it.
    /// `range` is in the *pre-edit* text; `selection` is in the post-edit
    /// text.
    public struct Edit: Equatable {
        public let range: NSRange
        public let replacement: String
        public let selection: NSRange

        public init(range: NSRange, replacement: String, selection: NSRange) {
            self.range = range
            self.replacement = replacement
            self.selection = selection
        }

        /// True when applying this would leave the text exactly as it is,
        /// so callers can skip the undo group entirely.
        public var isNoOp: Bool { range.length == 0 && replacement.isEmpty }
    }

    private static let newline: unichar = 0x0A

    // MARK: Duplicate

    /// ⌘D. With a selection, the selected text is copied in immediately
    /// after itself and the copy is selected — so a second ⌘D duplicates
    /// the duplicate rather than compounding. With no selection the whole
    /// line is copied below, and the cursor rides onto the copy keeping
    /// its column, which is what Xcode and VS Code both do.
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
        // Last line of the document, with nothing after it. The newline
        // has to lead the copy rather than trail it, or the duplicate is
        // appended to the line it was supposed to sit under.
        let content = text.substring(with: line)
        return Edit(
            range: NSRange(location: insertAt, length: 0),
            replacement: "\n" + content,
            selection: NSRange(location: insertAt + 1 + column, length: 0))
    }

    // MARK: Whole-line copy and cut

    /// What ⌘C puts on the pasteboard when nothing is selected: the whole
    /// line, newline included. The newline is what makes the round trip
    /// idempotent — without it a paste lands mid-line instead of becoming
    /// a line of its own, so it is appended even on a last line that has
    /// none of its own.
    public static func lineForClipboard(
        in text: NSString, selection: NSRange
    ) -> (range: NSRange, string: String) {
        let line = lineRange(in: text, at: selection.location)
        let content = text.substring(with: line)
        return (line, endsWithNewline(line, in: text) ? content : content + "\n")
    }

    /// ⌘X with nothing selected. Removes the whole line and puts the
    /// cursor at the same column on whatever line moved up into its
    /// place, clamped to that line's length.
    public static func cutLine(in text: NSString, selection: NSRange) -> Edit {
        let line = lineRange(in: text, at: selection.location)
        let column = selection.location - line.location
        let followingLength = lineContentLength(in: text, from: NSMaxRange(line))
        return Edit(
            range: line,
            replacement: "",
            selection: NSRange(location: line.location + min(column, followingLength), length: 0))
    }

    // MARK: Indent and outdent

    /// Tab. Adds one `unit` to the front of every line the selection
    /// touches.
    public static func indent(in text: NSString, selection: NSRange, unit: String) -> Edit {
        rewriteLines(in: text, selection: selection) { _ in
            (inserted: unit, removed: 0)
        }
    }

    /// ⇧Tab. Removes one level from the front of every line the selection
    /// touches — a leading tab, or up to `unit`'s width in spaces. A line
    /// already flush left is left alone, so outdenting a mixed block
    /// doesn't drag the rest out of alignment.
    public static func outdent(in text: NSString, selection: NSRange, unit: String) -> Edit {
        let width = (unit as NSString).length
        return rewriteLines(in: text, selection: selection) { line in
            if line.hasPrefix("\t") { return (inserted: "", removed: 1) }
            let spaces = line.prefix { $0 == " " }.count
            return (inserted: "", removed: min(spaces, width))
        }
    }

    /// Shared engine for indent and outdent: applies `change` to the head
    /// of every line the selection touches and maps the selection through
    /// the resulting width changes.
    ///
    /// One replacement spanning the whole block rather than one per line,
    /// so the edit is a single undo step and the offsets never have to be
    /// re-derived against a text that is moving underneath them.
    private static func rewriteLines(
        in text: NSString,
        selection: NSRange,
        change: (String) -> (inserted: String, removed: Int)
    ) -> Edit {
        let block = lineBlock(in: text, covering: selection)

        /// How one line's head changed, and how far everything before it
        /// had already moved — enough to map any offset on that line.
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

        /// Maps one offset through its own line's head change. Clamped at
        /// the line start so a cursor sitting inside whitespace an outdent
        /// removed lands on the first surviving character rather than
        /// before it. An offset outside the block — only reachable when the
        /// block is empty — moves by the total shift.
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

    /// The full line range containing `offset`, clamped so an offset past
    /// the end of the text still resolves to the last line.
    public static func lineRange(in text: NSString, at offset: Int) -> NSRange {
        let safe = max(0, min(offset, text.length))
        return text.lineRange(for: NSRange(location: safe, length: 0))
    }

    /// Every line the selection touches, as one range.
    ///
    /// A selection ending exactly on a line boundary is pulled back off it
    /// first: selecting a line by dragging past its newline shouldn't
    /// indent the untouched line below.
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

    /// Characters from `start` up to the next newline, or the end of the
    /// text. Zero when `start` is already at the end.
    private static func lineContentLength(in text: NSString, from start: Int) -> Int {
        guard start < text.length else { return 0 }
        var index = start
        while index < text.length, text.character(at: index) != newline { index += 1 }
        return index - start
    }
}
