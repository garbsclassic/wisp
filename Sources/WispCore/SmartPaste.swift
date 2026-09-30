import Foundation

/// Rewrites a pasted list or table as Markdown; the caller decides when a paste qualifies.
public enum SmartPaste {
    /// Longer lines are prose that happens to have line breaks.
    static let maxItemLength = 80

    /// Nil means paste as-is. Drops a trailing newline, since the caller pastes onto its own line.
    public static func format(_ text: String) -> String? {
        let lines = splitLines(text)
        guard lines.count >= 2 else { return nil }
        if let table = pipeTable(lines) { return table }
        if let list = bulletedList(lines) { return list }
        return nil
    }

    /// A tab-separated grid, as a spreadsheet copies one, with every row the same width.
    static func pipeTable(_ lines: [String]) -> String? {
        let rows = lines.map { $0.components(separatedBy: "\t") }
        guard let width = rows.first?.count, width >= 2,
            rows.allSatisfy({ $0.count == width })
        else { return nil }

        let cells = rows.map { row in
            row.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "|", with: "\\|") }
        }
        let widths = (0..<width).map { column in
            max(3, cells.map { $0[column].count }.max() ?? 0)
        }
        func line(_ row: [String]) -> String {
            "| " + zip(row, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
                .joined(separator: " | ") + " |"
        }
        let divider = "| " + widths.map { String(repeating: "-", count: $0) }.joined(separator: " | ") + " |"
        return ([line(cells[0]), divider] + cells.dropFirst().map(line)).joined(separator: "\n")
    }

    /// Short plain lines, such as a shopping list or a column copied out of a sheet.
    static func bulletedList(_ lines: [String]) -> String? {
        guard lines.allSatisfy(isPlainItem) else { return nil }
        // Together: a table, fence, quote, or setext heading only shows beside its neighbours.
        let blocks = MarkdownBlocks(lines.joined(separator: "\n") as NSString)
        guard blocks.lines.allSatisfy({ if case .text = $0.kind { true } else { false } })
        else { return nil }
        return lines.map { "- " + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }

    static func isPlainItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= maxItemLength else { return false }
        guard SmartEditing.nextListMarker(for: trimmed) == nil,
            !SmartEditing.isRuleShaped(trimmed),
            trimmed.firstMatch(of: /^#{1,6}\s/) == nil
        else { return false }
        return true
    }

    /// Any newline convention; trailing blank lines are dropped.
    static func splitLines(_ text: String) -> [String] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        return lines
    }
}
