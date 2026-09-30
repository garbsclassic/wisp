import Foundation
import Testing

@testable import WispCore

/// Applies an edit the way the text view does, so a test can assert on the
/// resulting document and caret position rather than on three ranges.
private func apply(_ edit: LineEdits.Edit, to text: String) -> (String, Int) {
    let mutable = NSMutableString(string: text)
    mutable.replaceCharacters(in: edit.range, with: edit.replacement)
    return (mutable as String, edit.selection.location)
}

@Suite("SmartEditing: em dash on the second `-`")
struct EmDashEditTests {
    /// Types the second `-` at `cursor`, as the keystroke does, then asks
    /// for the edit — so a test reads as the text before the key and the
    /// text after it.
    private func typed(_ text: String, cursor: Int) -> String {
        let typed = NSMutableString(string: text)
        typed.insert("-", at: cursor)
        return typed as String
    }

    private func edit(_ text: String, cursor: Int) -> LineEdits.Edit? {
        SmartEditing.emDashEdit(in: typed(text, cursor: cursor) as NSString, cursor: cursor + 1)
    }

    private func applied(_ text: String, cursor: Int) -> (String, Int)? {
        guard let e = edit(text, cursor: cursor) else { return nil }
        return apply(e, to: typed(text, cursor: cursor))
    }

    @Test("A dash right after a letter becomes an em dash")
    func afterLetter() {
        let result = applied("a-", cursor: 2)
        #expect(result?.0 == "a—")
        #expect(result?.1 == 2)
    }

    @Test("A dash after a space still converts — only the character before the dash matters")
    func afterSpace() {
        let result = applied("a -", cursor: 3)
        #expect(result?.0 == "a —")
        #expect(result?.1 == 3)
    }

    @Test("A dash alone at the start of the line has nothing before it to pair with")
    func aloneAtLineStart() {
        #expect(edit("-", cursor: 1) == nil)
    }

    @Test("A dash after only whitespace is still at the effective start of the line")
    func onlyWhitespaceBeforeDash() {
        #expect(edit("  -", cursor: 3) == nil)
    }

    @Test("A third dash in a row is left alone — `---` is on its way to a rule")
    func thirdDashInARow() {
        #expect(edit("a--", cursor: 3) == nil)
    }

    @Test("A dash after `!` doesn't convert — `<!--` opens an HTML comment")
    func afterBang() {
        #expect(edit("<!-", cursor: 3) == nil)
    }

    @Test("A dash after `|` doesn't convert — it's a table alignment row")
    func afterPipe() {
        #expect(edit("a|-", cursor: 3) == nil)
    }

    @Test("A dash after `:` doesn't convert — it's a table alignment row")
    func afterColon() {
        #expect(edit(":-", cursor: 2) == nil)
    }

    @Test("A dash inside a fenced code block doesn't convert")
    func insideFencedCode() {
        let text = "```\na-\n```"
        // The dash sits right after "a" on the fenced block's second line.
        #expect(edit(text, cursor: 6) == nil)
    }

    @Test("A dash inside frontmatter doesn't convert")
    func insideFrontmatter() {
        let text = "---\ntitle: a-\n---"
        // Right after the "a-" on the frontmatter's second line.
        #expect(edit(text, cursor: 13) == nil)
    }

    @Test("A dash inside an open inline code span doesn't convert")
    func insideCodeSpan() {
        #expect(edit("`c-", cursor: 3) == nil)
    }

    @Test("A dash after a code span has already closed converts normally")
    func afterClosedCodeSpan() {
        let result = applied("`c` d-", cursor: 6)
        #expect(result?.0 == "`c` d—")
        #expect(result?.1 == 6)
    }

    @Test("An escaped backtick doesn't open a code span, so the dash after it converts")
    func afterEscapedBacktick() {
        let result = applied("\\`c-", cursor: 4)
        #expect(result?.0 == "\\`c—")
        #expect(result?.1 == 4)
    }

    @Test("A dash on a later line converts using that line's own offsets")
    func onALaterLine() {
        let result = applied("one\ntwo-", cursor: 8)
        #expect(result?.0 == "one\ntwo—")
        #expect(result?.1 == 8)
    }

    @Test("A dash in a table row doesn't convert")
    func inTableRow() {
        let text = "| a | b |\n| - | - |\n| a | b-"
        // Right after "b" on the table's data row.
        #expect(edit(text, cursor: text.count) == nil)
    }
}

@Suite("SmartEditing: em dash revert")
struct EmDashRevertTests {
    private func edit(_ text: String, cursor: Int, autoDash: Int?, typed: String) -> LineEdits.Edit? {
        SmartEditing.emDashRevert(in: text as NSString, cursor: cursor, autoDash: autoDash, typed: typed)
    }

    private func applied(
        _ text: String, cursor: Int, autoDash: Int?, typed: String
    ) -> (String, Int)? {
        guard let e = edit(text, cursor: cursor, autoDash: autoDash, typed: typed) else { return nil }
        return apply(e, to: text)
    }

    @Test("A `-` right after the auto-made em dash turns it back into `---`")
    func revertsToTripleDash() {
        let result = applied("a—", cursor: 2, autoDash: 1, typed: "-")
        #expect(result?.0 == "a---")
        #expect(result?.1 == 4)
    }

    @Test("A `>` right after the auto-made em dash turns it into `-->`, closing a comment")
    func revertsToCommentCloser() {
        let result = applied("a—", cursor: 2, autoDash: 1, typed: ">")
        #expect(result?.0 == "a-->")
        #expect(result?.1 == 4)
    }

    @Test("No stored dash location means there's nothing to revert")
    func noAutoDash() {
        #expect(edit("a—", cursor: 2, autoDash: nil, typed: "-") == nil)
    }

    @Test("Once the caret has moved off the dash, a later `-` just types")
    func caretMovedAway() {
        #expect(edit("a—b", cursor: 3, autoDash: 1, typed: "-") == nil)
    }

    @Test("Once the em dash is gone, a `-` in its old spot is not a revert")
    func dashNoLongerThere() {
        #expect(edit("ab", cursor: 2, autoDash: 1, typed: "-") == nil)
    }

    @Test("Any other typed character leaves the em dash alone")
    func otherCharacterTyped() {
        #expect(edit("a—", cursor: 2, autoDash: 1, typed: "x") == nil)
    }
}

@Suite("SmartEditing: rule on return")
struct RuleOnReturnTests {
    private func edit(_ text: String, cursor: Int) -> LineEdits.Edit? {
        SmartEditing.ruleOnReturn(in: text as NSString, cursor: cursor)
    }

    private func applied(_ text: String, cursor: Int) -> (String, Int)? {
        guard let e = edit(text, cursor: cursor) else { return nil }
        return apply(e, to: text)
    }

    @Test("The third ↵ in a row after prose inserts a rule set off by blank lines")
    func thirdReturnAfterProse() {
        let result = applied("text\n\n", cursor: 6)
        #expect(result?.0 == "text\n\n---\n\n")
        #expect(result?.1 == 11)
    }

    @Test(
        "A list item, heading, or quote above the blank line qualifies just like prose",
        arguments: [
            ("- item\n\n", 8, "- item\n\n---\n\n", 13),
            ("# H\n\n", 5, "# H\n\n---\n\n", 10),
            ("> q\n\n", 5, "> q\n\n---\n\n", 10),
        ] as [(String, Int, String, Int)]
    )
    func nonProseBlocksAboveQualify(text: String, cursor: Int, expected: String, caret: Int) {
        let result = applied(text, cursor: cursor)
        #expect(result?.0 == expected)
        #expect(result?.1 == caret)
    }

    @Test("With the caret mid-document, only the text after the insertion point moves down")
    func caretInMiddleOfDocument() {
        let result = applied("text\n\n\nnext", cursor: 6)
        #expect(result?.0 == "text\n\n---\n\n\nnext")
        #expect(result?.1 == 11)
    }

    @Test("A non-empty current line is not a third ↵ at all")
    func caretLineIsNotEmpty() {
        #expect(edit("text\n\nnope", cursor: 8) == nil)
    }

    @Test("Only one ↵ so far — no blank line above — is an ordinary paragraph break")
    func noBlankLineAbove() {
        #expect(edit("text\n", cursor: 5) == nil)
    }

    @Test("More than one blank line above means this isn't the third ↵ after prose")
    func twoBlankLinesAbove() {
        #expect(edit("text\n\n\n", cursor: 7) == nil)
    }

    @Test("A rule already sits above the blank line")
    func ruleAlreadyAbove() {
        #expect(edit("---\n\n", cursor: 5) == nil)
    }

    @Test("Inside an open fenced code block, this is never the edit")
    func insideFencedCode() {
        #expect(edit("```\ntext\n\n\n", cursor: 11) == nil)
    }

    @Test("Inside frontmatter, this is never the edit")
    func insideFrontmatter() {
        // A blank line between the frontmatter's content and its closing `---`.
        #expect(edit("---\nprose\n\n\n---\n", cursor: 11) == nil)
    }

    @Test("Under indented code, this is never the edit")
    func underIndentedCode() {
        #expect(edit("    code\n\n", cursor: 10) == nil)
    }
}

@Suite("SmartEditing: rule revert")
struct RuleRevertTests {
    private func edit(_ text: String, cursor: Int, autoRule: Int?) -> LineEdits.Edit? {
        SmartEditing.ruleRevert(in: text as NSString, cursor: cursor, autoRule: autoRule)
    }

    private func applied(_ text: String, cursor: Int, autoRule: Int?) -> (String, Int)? {
        guard let e = edit(text, cursor: cursor, autoRule: autoRule) else { return nil }
        return apply(e, to: text)
    }

    @Test("A fourth ↵ right after the auto-made rule turns it back into a blank line")
    func revertsRuleToBlankLine() {
        let result = applied("text\n\n---\n\n", cursor: 11, autoRule: 6)
        #expect(result?.0 == "text\n\n\n\n")
        #expect(result?.1 == 8)
    }

    @Test("No stored rule location means there's nothing to revert")
    func noAutoRule() {
        #expect(edit("text\n\n---\n\n", cursor: 11, autoRule: nil) == nil)
    }

    @Test("Once the caret has moved off the rule, a later ↵ is not a revert")
    func caretMovedAway() {
        #expect(edit("text\n\n---\n\nnext", cursor: 15, autoRule: 6) == nil)
    }

    @Test("Once the rule text has changed, this is no longer a revert")
    func ruleTextChanged() {
        #expect(edit("text\n\nabcde", cursor: 11, autoRule: 6) == nil)
    }

    @Test("A stored location too close to the end of the text is safely rejected")
    func autoRuleNearDocumentEnd() {
        #expect(edit("text\n\n--", cursor: 8, autoRule: 6) == nil)
    }
}

@Suite("SmartEditing: rule on the third dash")
struct RuleOnThirdDashTests {
    /// `|` marks the caret, which sits just after the `--` already typed: the third `-` has not
    /// landed yet.
    private func edit(_ marked: String) -> LineEdits.Edit? {
        let parts = marked.components(separatedBy: "|")
        return SmartEditing.ruleOnThirdDash(
            in: parts.joined() as NSString, cursor: (parts[0] as NSString).length)
    }

    private func pressed(_ marked: String) -> String? {
        guard let e = edit(marked) else { return nil }
        let (text, caret) = apply(e, to: marked.replacingOccurrences(of: "|", with: ""))
        return (text as NSString).replacingCharacters(
            in: NSRange(location: caret, length: 0), with: "|")
    }

    @Test(
        "A third dash after a lone `--` makes the line a rule, with the caret on the next line",
        arguments: [
            ("--|", "---\n|"),
            ("--|\nnext", "---\n|\nnext"),
            ("text\n\n--|", "text\n\n---\n|"),
            ("# H\n--|", "# H\n---\n|"),
            ("> q\n--|", "> q\n---\n|"),
            ("```\nx\n```\n--|", "```\nx\n```\n---\n|"),
        ] as [(String, String)]
    )
    func firesOnLoneDashPair(marked: String, expected: String) {
        #expect(pressed(marked) == expected)
    }

    @Test("Only the two dashes are replaced")
    func replacesOnlyTheDashes() {
        let e = edit("text\n\n--|")
        #expect(e?.range == NSRange(location: 6, length: 2))
        #expect(e?.replacement == "---\n")
        #expect(e?.selection == NSRange(location: 10, length: 0))
    }

    @Test(
        "Text before the cursor other than exactly `--` is not a rule",
        arguments: ["-|", "|", "-|-", "---|", "a--|", " --|", "- -|", "--a|", "\t--|"]
    )
    func notExactlyTwoDashes(marked: String) {
        #expect(edit(marked) == nil)
    }

    @Test(
        "Anything after the cursor on the line stops the rule",
        arguments: ["--|x", "--| ", "--|-", "--|\t"]
    )
    func textAfterCursor(marked: String) {
        #expect(edit(marked) == nil)
    }

    @Test("Under paragraph text the dashes are a setext underline, so no rule")
    func underParagraph() {
        #expect(edit("text\n--|") == nil)
        #expect(edit("one\ntwo\n--|") == nil)
    }

    @Test("Inside a fenced code block the dashes are code")
    func insideFence() {
        #expect(edit("```\n--|") == nil)
        #expect(edit("```\nx\n--|\n```") == nil)
    }

    @Test("Inside frontmatter the dashes are text")
    func insideFrontmatter() {
        #expect(edit("---\ntitle: a\n--|\n---\n") == nil)
    }

    @Test(
        "In a CRLF note the cursor before the \\r still counts as the end of the line",
        arguments: [
            ("--|\r\n", "---\n|\r\n"),
            ("text\r\n\r\n--|\r\n", "text\r\n\r\n---\n|\r\n"),
        ] as [(String, String)]
    )
    func crlf(marked: String, expected: String) {
        #expect(pressed(marked) == expected)
    }

    @Test("In a CRLF note a setext underline and trailing text still stop the rule")
    func crlfStillRefuses() {
        #expect(edit("text\r\n--|\r\n") == nil)
        #expect(edit("--|x\r\n") == nil)
    }

    @Test("Offsets count UTF-16 units, so an emoji above does not shift the edit")
    func emojiAbove() {
        #expect(pressed("😀\n\n--|") == "😀\n\n---\n|")
    }
}
