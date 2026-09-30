import Foundation

/// Typing shortcuts that rewrite what was just typed and take it back on the next press. The
/// caller passes back where it made a rewrite, so a hand-typed `—` or `---` is left alone.
extension SmartEditing {
    /// A just-typed `--` becomes `—`. Not at a line start, where `---` is coming; not in code or a
    /// table; and not after `<` `!` `|` `:`, which start `<!--`, arrows, and alignment rows.
    public static func emDashEdit(in text: NSString, cursor: Int) -> LineEdits.Edit? {
        let line = LineEdits.lineRange(in: text, at: cursor)
        let pair = NSRange(location: cursor - 2, length: 2)
        guard pair.location >= line.location, cursor <= text.length,
            text.character(at: pair.location) == hyphen,
            text.character(at: pair.location + 1) == hyphen
        else { return nil }

        // Something other than whitespace before the pair.
        let head = NSRange(location: line.location, length: pair.location - line.location)
        guard head.length > 0,
            text.rangeOfCharacter(
                from: CharacterSet.whitespaces.inverted, options: [], range: head
            ).location != NSNotFound
        else { return nil }
        guard !"-—<!|:".utf16.contains(text.character(at: pair.location - 1)) else { return nil }
        if let kind = MarkdownBlocks(text).line(at: line.location)?.kind,
            kind.isCode || kind == .tableRow
        {
            return nil
        }
        guard MarkdownBlocks.codeSpans(in: text, over: head, escapes: Escapes.scan(text)).open == nil
        else { return nil }

        return LineEdits.Edit(
            range: pair, replacement: "—", selection: NSRange(location: pair.location + 1, length: 0))
    }

    /// A `-` or `>` right after the `—` `emDashEdit` made gives back `---` or `-->`. Nil once
    /// the caret or the dash has moved.
    public static func emDashRevert(
        in text: NSString, cursor: Int, autoDash: Int?, typed: String
    ) -> LineEdits.Edit? {
        guard typed == "-" || typed == ">",
            let autoDash, cursor == autoDash + 1, autoDash < text.length,
            text.character(at: autoDash) == emDash
        else { return nil }
        let replacement = "--" + typed
        return LineEdits.Edit(
            range: NSRange(location: autoDash, length: 1), replacement: replacement,
            selection: NSRange(location: autoDash + 3, length: 0))
    }

    /// A third `-` on a line holding only `--` makes it a rule without waiting for ↵. Nil under
    /// a paragraph, where the dashes underline a heading, and in code.
    public static func ruleOnThirdDash(in text: NSString, cursor: Int) -> LineEdits.Edit? {
        let line = LineEdits.lineRange(in: text, at: cursor)
        guard cursor - line.location == 2, MarkdownBlocks.contentEnd(of: line, in: text) == cursor,
            text.character(at: line.location) == hyphen,
            text.character(at: line.location + 1) == hyphen
        else { return nil }
        let blocks = MarkdownBlocks(text)
        if blocks.line(at: line.location)?.kind.isCode == true { return nil }
        if line.location > 0,
            case .text(paragraphStart: .some) = blocks.line(at: line.location - 1)?.kind
        {
            return nil
        }
        return .insert(
            horizontalRule + "\n", replacing: NSRange(location: line.location, length: 2))
    }

    /// The third ↵ in a row after text inserts a rule with a blank line on each side; the blank
    /// above keeps it from underlining the text. Nil in code, under a rule, or after two blanks.
    public static func ruleOnReturn(in text: NSString, cursor: Int) -> LineEdits.Edit? {
        let line = LineEdits.lineRange(in: text, at: cursor)
        guard LineEdits.contentLength(of: line, in: text) == 0, line.location >= 2 else {
            return nil
        }
        let blocks = MarkdownBlocks(text)
        let blank = LineEdits.lineRange(in: text, at: line.location - 1)
        guard blank.location >= 1,
            blocks.line(at: blank.location)?.kind == .blank,
            let above = blocks.line(at: blank.location - 1)?.kind
        else { return nil }

        // Fence and frontmatter lines are never `.blank`, so only indented code is left to refuse.
        guard above != .blank, above != .rule, !above.isCode else { return nil }

        return LineEdits.Edit(
            range: NSRange(location: cursor, length: 0), replacement: "---\n\n",
            selection: NSRange(location: cursor + 5, length: 0))
    }

    /// The next ↵ turns that rule into a blank line, as four plain ↵ would have. Nil once the
    /// caret or the rule has changed.
    public static func ruleRevert(in text: NSString, cursor: Int, autoRule: Int?) -> LineEdits.Edit? {
        let inserted = "---\n\n" as NSString
        guard let autoRule, cursor == autoRule + inserted.length,
            NSMaxRange(NSRange(location: autoRule, length: inserted.length)) <= text.length,
            text.substring(with: NSRange(location: autoRule, length: inserted.length))
                == inserted as String
        else { return nil }
        return LineEdits.Edit(
            range: NSRange(location: autoRule, length: 3), replacement: "",
            selection: NSRange(location: cursor - 3, length: 0))
    }

    private static let hyphen = unichar(0x2D)
    private static let emDash = unichar(0x2014)
}
