import Foundation

public struct Heading: Identifiable, Equatable {
    public let name: String
    public let level: Int
    /// NSString character offset where the heading line starts, used for
    /// scrolling the text view to the section.
    public let lineStart: Int
    /// NSString offset just past the heading's last character, before any newline. A setext
    /// heading runs from its first paragraph line through the underline.
    public let end: Int
    /// The syntax that makes the line a heading, painted dimmer than the heading: the `#` run,
    /// or a setext heading's whole `===` or `---` underline.
    public let marker: NSRange

    public var id: Int { lineStart }
}

extension Array where Element == Heading {
    /// The nearest heading above the line at `lineStart`, or nil from the
    /// first section. The caret's own heading doesn't count — pressing
    /// "previous" from any line of a heading, a setext underline included,
    /// goes to the one before it.
    public func heading(before lineStart: Int) -> Heading? {
        last { $0.end < lineStart }
    }

    /// The nearest heading below the line at `lineStart`, or nil past the
    /// last one.
    public func heading(after lineStart: Int) -> Heading? {
        first { $0.lineStart > lineStart }
    }
}

extension String {
    /// Parse markdown headings out of the text: `#`-prefixed lines, and paragraphs underlined
    /// with `===` (level 1) or `---` (level 2). Lines inside a fenced code block are code, not
    /// headings. Returns one entry per heading, in document order.
    public func extractHeadings() -> [Heading] {
        let ns = self as NSString
        return MarkdownBlocks(ns).headings(in: ns)
    }
}

extension MarkdownBlocks {
    /// The headings among these lines, in document order. `text` is the note they were
    /// classified from.
    public func headings(in text: NSString) -> [Heading] {
        var result: [Heading] = []
        for line in lines {
            let lineEnd = MarkdownBlocks.contentEnd(of: line.range, in: text)
            switch line.kind {
            case .heading:
                guard let marker = MarkdownBlocks.atxMarker(lineRange: line.range, in: text)
                else { continue }
                let nameStart = NSMaxRange(marker)
                let name = text.substring(
                    with: NSRange(location: nameStart, length: lineEnd - nameStart))
                    .trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                result.append(Heading(
                    name: name, level: marker.length, lineStart: line.range.location,
                    end: lineEnd, marker: marker))
            case .setextUnderline(let level, let start):
                let name = text.substring(
                    with: NSRange(location: start, length: line.range.location - start))
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
                result.append(Heading(
                    name: name, level: level, lineStart: start, end: lineEnd,
                    marker: NSRange(
                        location: line.range.location, length: lineEnd - line.range.location)))
            default:
                continue
            }
        }
        return result
    }
}
