import Foundation

public struct Heading: Identifiable, Equatable {
    public let name: String
    public let level: Int
    /// NSString character offset where the heading line starts, used for
    /// scrolling the text view to the section.
    public let lineStart: Int

    public var id: Int { lineStart }
}

extension Array where Element == Heading {
    /// The nearest heading above the line at `lineStart`, or nil from the
    /// first section. The caret's own heading doesn't count — pressing
    /// "previous" from a heading line goes to the one before it.
    public func heading(before lineStart: Int) -> Heading? {
        last { $0.lineStart < lineStart }
    }

    /// The nearest heading below the line at `lineStart`, or nil past the
    /// last one.
    public func heading(after lineStart: Int) -> Heading? {
        first { $0.lineStart > lineStart }
    }
}

extension String {
    /// Parse `#`-prefixed markdown headings out of the text. Returns one
    /// entry per heading line, in document order.
    public func extractHeadings() -> [Heading] {
        let ns = self as NSString
        let total = ns.length
        var result: [Heading] = []
        var lineStart = 0
        while lineStart < total {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            let raw = ns.substring(with: lineRange)
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            if let match = line.firstMatch(of: /^(#{1,6})\s+(.+)/) {
                let name = String(match.2).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    result.append(Heading(
                        name: name,
                        level: match.1.count,
                        lineStart: lineRange.location
                    ))
                }
            }
            lineStart = lineRange.location + lineRange.length
        }
        return result
    }
}
