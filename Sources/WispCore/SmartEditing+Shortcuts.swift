import Foundation

/// Typing shortcuts that rewrite what was just typed, and take it back on
/// the next press of the same key: `--` for an em dash, a third ↵ for a
/// rule.
///
/// The take-back needs to know the rewrite happened — a `—` or `---` the
/// user wrote by hand is left alone — so the caller keeps the location it
/// made and passes it back in.
extension SmartEditing {
    /// A `--` just typed, ending at `cursor`: the pair becomes `—`. Nil
    /// where a double dash means something else: at the start of a line,
    /// where `---` is on its way to a rule; as part of a longer run; in
    /// code, frontmatter, or a table; and after `<`, `!`, `|`, or `:`,
    /// which start `<!--`, arrows, and table alignment rows.
    public static func emDashEdit(in text: NSString, cursor: Int) -> LineEdits.Edit? {
        let line = LineEdits.lineRange(in: text, at: cursor)
        let pair = NSRange(location: cursor - 2, length: 2)
        guard pair.location >= line.location, cursor <= text.length,
            text.character(at: pair.location) == hyphen,
            text.character(at: pair.location + 1) == hyphen
        else { return nil }

        // Something other than whitespace before the pair, and that
        // something isn't a dash or one of the characters that start a
        // different construct.
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

    /// A `-` or `>` typed at `cursor` right after the `—` that `emDashEdit`
    /// made at `autoDash`: the dash goes back to hyphens, as `---` or the
    /// `-->` that closes an HTML comment. Nil for any other key, once the
    /// caret has moved off it, or once the dash is gone, so a later `-`
    /// just types.
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

    /// A third `-` typed at `cursor` on a line that holds only `--`: the line
    /// becomes a rule with the caret past it, without waiting for ↵. Nil
    /// under paragraph text, where the dashes are a setext underline and the
    /// restyle makes the paragraph a heading, and in code or frontmatter,
    /// where they are text.
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

    /// ↵ on an empty line under exactly one blank line under prose — the
    /// third ↵ in a row after text: a rule, set off by a blank line on each
    /// side, with the caret below it. The blank above is what keeps the
    /// dashes from being a setext underline for the text.
    ///
    /// Two ↵ is an ordinary paragraph break and stays one. Nil in code and
    /// frontmatter, under a rule already, and after more than one blank.
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

        // Inside a fence or frontmatter the empty lines are code, not `.blank`, so the guard
        // above has already turned those away. An indented block ends at its blank line, so
        // that one is refused here.
        guard above != .blank, above != .rule, !above.isCode else { return nil }

        return LineEdits.Edit(
            range: NSRange(location: cursor, length: 0), replacement: "---\n\n",
            selection: NSRange(location: cursor + 5, length: 0))
    }

    /// The ↵ after `ruleOnReturn`: the rule it inserted at `autoRule`
    /// becomes a blank line, leaving what four plain ↵ would have — the
    /// text, three blank lines, and the caret on the next. Nil once the
    /// caret has moved or the rule has changed.
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
