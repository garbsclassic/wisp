import Foundation

/// Every line of a note, classified by the Markdown block it belongs to, in one forward pass.
///
/// Whether `---` is a rule or a heading underline, and whether `#` starts a heading, depends on
/// the lines above: an open paragraph, a list item, a code fence, frontmatter. Deciding one line
/// in isolation means rescanning its neighbours, which turns every pass over the note quadratic.
/// Classify once per edit instead, and read the result.
///
/// The scanners read UTF-16 units directly. A regex literal in a function body is rebuilt on
/// every call, which costs about 75 µs each, and these run for every line on every keystroke.
public struct MarkdownBlocks: Sendable {
    public enum Kind: Equatable, Sendable {
        case blank
        /// Paragraph text. `paragraphStart` is where its paragraph began, or nil when the text
        /// continues a list item, quote, or table row, which an underline can't make a heading.
        case text(paragraphStart: Int?)
        case listItem
        case quote
        case tableRow
        /// A `#` heading; `level` is the number of `#`.
        case heading(level: Int)
        /// `===` (level 1) or `---` (level 2) under the paragraph that starts at `paragraphStart`.
        case setextUnderline(level: Int, paragraphStart: Int)
        case rule
        /// A line that opens or closes a ```` ``` ```` or `~~~` code block.
        case fence
        /// A line between an opening fence and its closer.
        case fencedCode
        /// A line indented four columns with no paragraph open, which CommonMark reads as code.
        case indentedCode
        /// The `---` … `---` properties block at the top of the note, as Obsidian reads it.
        case frontmatter
    }

    public struct Line: Equatable, Sendable {
        /// The line's range, including its newline.
        public let range: NSRange
        public let kind: Kind
    }

    public let lines: [Line]

    public init(_ text: NSString) {
        enum Paragraph { case none, plain(start: Int), owned }

        var lines: [Line] = []
        var paragraph = Paragraph.none
        // Set by a list item and kept across blank lines, so an indented paragraph after a blank
        // still belongs to the item, as in a loose list.
        var inList = false
        var fence: (mark: unichar, count: Int)?
        let frontmatterEnd = Self.frontmatterEnd(in: text)
        var cursor = 0

        while cursor < text.length {
            let range = text.lineRange(for: NSRange(location: cursor, length: 0))
            let scan = Scan(line: range, in: text)
            cursor = NSMaxRange(range)

            let kind: Kind
            if range.location < frontmatterEnd {
                kind = .frontmatter
            } else if let open = fence {
                if scan.closesFence(mark: open.mark, count: open.count) {
                    kind = .fence
                    fence = nil
                } else {
                    kind = .fencedCode
                }
            } else if scan.isBlank {
                kind = .blank
            } else if let opened = scan.opensFence() {
                kind = .fence
                fence = opened
            } else if let marker = scan.atxMarker() {
                kind = .heading(level: marker.length)
            } else if case .plain(let start) = paragraph, let level = scan.setextLevel() {
                kind = .setextUnderline(level: level, paragraphStart: start)
            } else if scan.isRuleShaped {
                kind = .rule
            } else if SmartEditing.listItem(lineRange: range, in: text) != nil {
                kind = .listItem
            } else if scan.startsQuote {
                kind = .quote
            } else if scan.startsTableRow {
                kind = .tableRow
            } else {
                switch paragraph {
                case .plain(let start): kind = .text(paragraphStart: start)
                case .owned: kind = .text(paragraphStart: nil)
                case .none:
                    if inList, scan.isIndented {
                        kind = .text(paragraphStart: nil)
                    } else {
                        kind = scan.isIndentedCode
                            ? .indentedCode : .text(paragraphStart: range.location)
                    }
                }
            }

            switch kind {
            case .text(let start): paragraph = start.map { .plain(start: $0) } ?? .owned
            case .listItem, .quote, .tableRow: paragraph = .owned
            default: paragraph = .none
            }
            switch kind {
            case .listItem: inList = true
            case .blank, .text(paragraphStart: nil): break
            default: inList = false
            }
            lines.append(Line(range: range, kind: kind))
        }
        self.lines = lines
    }

    /// The line containing `offset`, or nil past the last line.
    public func line(at offset: Int) -> Line? {
        var low = 0
        var high = lines.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let range = lines[mid].range
            if offset < range.location {
                high = mid - 1
            } else if offset >= NSMaxRange(range) {
                low = mid + 1
            } else {
                return lines[mid]
            }
        }
        return nil
    }

    /// Where a line's content ends: before its `\n`, and before a `\r` ahead of it, so a note
    /// saved with CRLF line endings reads the same as one with LF.
    public static func contentEnd(of lineRange: NSRange, in text: NSString) -> Int {
        var end = lineRange.location + LineEdits.contentLength(of: lineRange, in: text)
        if end > lineRange.location, text.character(at: end - 1) == 0x0D { end -= 1 }
        return end
    }

    /// The `#` run of an ATX heading line, or nil when the line isn't one.
    public static func atxMarker(lineRange: NSRange, in text: NSString) -> NSRange? {
        Scan(line: lineRange, in: text).atxMarker()
    }

    /// Three or more of one of `-`, `*`, or `_`, spaces or tabs between them, up to three spaces
    /// before: a thematic break's shape, whatever the lines around it make of it.
    public static func isRuleShaped(lineRange: NSRange, in text: NSString) -> Bool {
        Scan(line: lineRange, in: text).isRuleShaped
    }

    /// Where frontmatter ends: past the next `---` line, when the note's first line is `---`.
    /// Zero when the note has none, and then a first-line `---` is a rule. Obsidian closes
    /// frontmatter only with `---`, not YAML's `...`.
    private static func frontmatterEnd(in text: NSString) -> Int {
        let first = text.lineRange(for: NSRange(location: 0, length: 0))
        guard first.length > 0, Scan(line: first, in: text).isExactly("---") else { return 0 }
        var cursor = NSMaxRange(first)
        while cursor < text.length {
            let range = text.lineRange(for: NSRange(location: cursor, length: 0))
            let scan = Scan(line: range, in: text)
            if scan.isExactly("---") { return NSMaxRange(range) }
            cursor = NSMaxRange(range)
        }
        return 0
    }
}

/// One line's content, `start..<end` in `text`, with the scanners the classifier needs.
private struct Scan {
    let text: NSString
    let start: Int
    let end: Int

    init(text: NSString, start: Int, end: Int) {
        self.text = text
        self.start = start
        self.end = end
    }

    init(line: NSRange, in text: NSString) {
        self.init(
            text: text, start: line.location,
            end: MarkdownBlocks.contentEnd(of: line, in: text))
    }

    private static let space: unichar = 0x20
    private static let tab: unichar = 0x09

    private func at(_ index: Int) -> unichar { text.character(at: index) }
    private func isSpaceOrTab(_ c: unichar) -> Bool { c == Self.space || c == Self.tab }

    /// The index after up to three leading spaces, or nil when a fourth follows them.
    private var afterIndent: Int? {
        var index = start
        while index < end, at(index) == Self.space, index - start < 3 { index += 1 }
        return index < end && at(index) == Self.space ? nil : index
    }

    private func isBlank(from index: Int) -> Bool {
        (index..<end).allSatisfy { isSpaceOrTab(at($0)) }
    }

    var isBlank: Bool { isBlank(from: start) }

    var isIndented: Bool { start < end && isSpaceOrTab(at(start)) }

    var isIndentedCode: Bool {
        guard start < end else { return false }
        return at(start) == Self.tab || afterIndent == nil
    }

    func isExactly(_ literal: String) -> Bool {
        let units = Array(literal.utf16)
        var index = start
        for unit in units {
            guard index < end, at(index) == unit else { return false }
            index += 1
        }
        return isBlank(from: index)
    }

    /// A run of `mark` starting at `index`: its length and the index after it.
    private func run(of mark: unichar, from index: Int) -> (count: Int, next: Int) {
        var next = index
        while next < end, at(next) == mark { next += 1 }
        return (next - index, next)
    }

    func atxMarker() -> NSRange? {
        guard let index = afterIndent else { return nil }
        let hashes = run(of: 0x23, from: index)
        guard (1...6).contains(hashes.count),
            hashes.next == end || isSpaceOrTab(at(hashes.next))
        else { return nil }
        return NSRange(location: index, length: hashes.count)
    }

    /// 1 for a `===` underline, 2 for `---`: three or more, where CommonMark takes one, so typing
    /// a list item or a `==highlight==` under a paragraph doesn't flash it into a heading.
    func setextLevel() -> Int? {
        guard let index = afterIndent, index < end else { return nil }
        let mark = at(index)
        guard mark == 0x3D || mark == 0x2D else { return nil }
        let marks = run(of: mark, from: index)
        guard marks.count >= 3, isBlank(from: marks.next) else { return nil }
        return mark == 0x3D ? 1 : 2
    }

    var isRuleShaped: Bool {
        guard let index = afterIndent, index < end else { return false }
        let mark = at(index)
        guard mark == 0x2D || mark == 0x2A || mark == 0x5F else { return false }
        var count = 0
        for i in index..<end {
            let c = at(i)
            if c == mark {
                count += 1
            } else if !isSpaceOrTab(c) {
                return false
            }
        }
        return count >= 3
    }

    /// An opening fence: three or more backticks or tildes. A backtick fence's info string
    /// can't contain a backtick, so ```` ```ls``` ```` is inline code, not a fence.
    func opensFence() -> (mark: unichar, count: Int)? {
        guard let index = afterIndent, index < end else { return nil }
        let mark = at(index)
        guard mark == 0x60 || mark == 0x7E else { return nil }
        let marks = run(of: mark, from: index)
        guard marks.count >= 3 else { return nil }
        if mark == 0x60, (marks.next..<end).contains(where: { at($0) == 0x60 }) { return nil }
        return (mark, marks.count)
    }

    /// A closing fence: the opener's character, at least as many, and nothing after.
    func closesFence(mark: unichar, count: Int) -> Bool {
        guard let index = afterIndent else { return false }
        let marks = run(of: mark, from: index)
        return marks.count >= count && isBlank(from: marks.next)
    }

    var startsQuote: Bool {
        guard let index = afterIndent else { return false }
        return index < end && at(index) == 0x3E
    }

    var startsTableRow: Bool {
        var index = start
        while index < end, isSpaceOrTab(at(index)) { index += 1 }
        return index < end && at(index) == 0x7C
    }
}
