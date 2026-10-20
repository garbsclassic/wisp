import Foundation

/// One immutable document revision shared by editing, navigation, styling, and spelling.
public final class DocumentAnalysis {
    public let text: String
    public let blocks: MarkdownBlocks
    public let headings: [Heading]
    private let nsText: NSString
    private let lineStarts: [Int]
    private let lineNumbers: [Int]

    /// Only requested by the spellchecker, which is usually off.
    public private(set) lazy var codeRanges: [NSRange] = blocks.codeRanges(in: nsText)

    public init(_ text: String) {
        self.text = text
        let ns = text as NSString
        nsText = ns
        let blocks = MarkdownBlocks(ns)
        self.blocks = blocks
        headings = blocks.headings(in: ns)
        var starts: [Int] = []
        var numbers: [Int] = []
        starts.reserveCapacity(blocks.lines.count + 1)
        numbers.reserveCapacity(blocks.lines.count + 1)
        var number = 1
        for line in blocks.lines {
            starts.append(line.range.location)
            numbers.append(number)
            // Preserve the footer's LF-based numbering, including CRLF notes.
            if ns.character(at: NSMaxRange(line.range) - 1) == 0x0A { number += 1 }
        }
        if starts.isEmpty
            || ns.lineRange(for: NSRange(location: ns.length, length: 0)).location
                == ns.length
        {
            starts.append(ns.length)
            numbers.append(number)
        }
        lineStarts = starts
        lineNumbers = numbers
    }

    /// Swift String equality folds canonical equivalents, whose TextKit offsets can differ.
    public func matches(_ other: String) -> Bool {
        text.utf16.elementsEqual(other.utf16)
    }

    /// Binary search the revision's line index; only the current line is copied for its column.
    public func caretPosition(at offset: Int) -> CaretPosition {
        let ns = nsText
        let safe = max(0, min(offset, ns.length))
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = low + (high - low) / 2
            if lineStarts[mid] <= safe { low = mid + 1 } else { high = mid }
        }
        let index = max(0, low - 1)
        let start = lineStarts[index]
        return CaretPosition(
            line: lineNumbers[index],
            column: 1 + ns.substring(with: NSRange(location: start, length: safe - start)).count)
    }
}
