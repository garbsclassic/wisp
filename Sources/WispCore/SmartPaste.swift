import Foundation

/// Recognises pasted text that is obviously a list or a table and writes it
/// as the markdown Wisp already renders. Pure: the caller decides when a
/// paste qualifies (nothing selected, blank line, not source view).
public enum SmartPaste {
    /// The longest line that still reads as a list item rather than a
    /// paragraph. Anything wrapping past it is prose that happens to have
    /// line breaks.
    static let maxItemLength = 80

    /// The pasted text rewritten as markdown, or nil when it should go in
    /// untouched. A trailing newline is dropped either way — the caller is
    /// inserting onto a line of its own.
    public static func format(_ text: String) -> String? {
        let lines = splitLines(text)
        guard lines.count >= 2 else { return nil }
        if let table = pipeTable(lines) { return table }
        if let list = bulletedList(lines) { return list }
        return nil
    }

    /// A tab-separated grid — what a spreadsheet or a terminal table puts on
    /// the pasteboard — as a pipe table with a divider under the first row.
    /// Every row has to have the same number of cells, or it is not a table.
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

    /// Short lines, one item each, none already marked up — a shopping list
    /// typed into a chat, a column copied out of a sheet. Prefixed `- `.
    /// Any blank line, long line, or line that is already a list item,
    /// heading, or rule means the text is something else, and it goes in
    /// as-is.
    static func bulletedList(_ lines: [String]) -> String? {
        guard lines.allSatisfy(isPlainItem) else { return nil }
        return lines.map { "- " + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }

    static func isPlainItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= maxItemLength else { return false }
        guard SmartEditing.nextListMarker(for: trimmed) == nil,
            !SmartEditing.isHorizontalRuleTrigger(trimmed),
            trimmed.firstMatch(of: /^#{1,6}\s/) == nil
        else { return false }
        return true
    }

    /// Lines on any newline convention, trailing blank lines dropped so a
    /// copy that ends in a newline is still a list.
    static func splitLines(_ text: String) -> [String] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        return lines
    }
}
