import Foundation

public struct Heading: Identifiable, Equatable {
    public let name: String
    public let level: Int
    /// UTF-16 offset of the heading's first line.
    public let lineStart: Int
    /// Just past the last character, before any newline. A setext heading ends on its underline.
    public let end: Int
    /// The `#` run, or a setext heading's whole underline; painted dimmer than the name.
    public let marker: NSRange

    public var id: Int { lineStart }
}

extension Array where Element == Heading {
    /// The nearest heading above, not counting the one `lineStart` is part of.
    public func heading(before lineStart: Int) -> Heading? {
        last { $0.end < lineStart }
    }

    public func heading(after lineStart: Int) -> Heading? {
        first { $0.lineStart > lineStart }
    }
}

extension String {
    /// ATX and setext headings in document order, skipping fenced code.
    public func extractHeadings() -> [Heading] {
        let ns = self as NSString
        return MarkdownBlocks(ns).headings(in: ns)
    }
}

extension MarkdownBlocks {
    /// `text` is the note these lines were classified from.
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
