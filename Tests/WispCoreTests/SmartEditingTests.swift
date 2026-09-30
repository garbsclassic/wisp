import Foundation
import Testing

@testable import WispCore

@Suite("SmartEditing: horizontal rule")
struct HorizontalRuleTests {
    /// CommonMark's thematic break: three or more of one of `-`, `*`, `_`, with spaces or tabs
    /// between. Box-drawing `───` is text, as Obsidian renders it.
    @Test(
        "A rendered rule line is three or more of one repeated marker character",
        arguments: [
            ("---", true),
            ("----", true),
            ("***", true),
            ("___", true),
            ("* * *", true),
            ("_ _ _", true),
            ("- - -", true),
            ("-- -", true),
            ("   ---", true),
            ("--- ", true),
            ("*****", true),
            ("--", false),
            ("", false),
            ("---x", false),
            ("x---", false),
            ("    ---", false),
            ("-*-", false),
            ("**", false),
            ("-- ", false),
            ("───", false),
            (String(repeating: "─", count: 40), false),
            ("---" + String(repeating: "─", count: 5), false),
        ]
    )
    func renderedLine(line: String, expected: Bool) {
        #expect(SmartEditing.isHorizontalRuleLine(line) == expected)
    }

    @Test("A trailing newline does not disqualify a rule line")
    func trailingNewline() {
        let ns = "---\n" as NSString
        #expect(
            SmartEditing.isHorizontalRuleLine(
                lineRange: NSRange(location: 0, length: ns.length), in: ns
            )
        )
    }

    // MARK: Setext underlines

    private func isRule(_ text: String, at offset: Int) -> Bool {
        let ns = text as NSString
        let line = LineEdits.lineRange(in: ns, at: offset)
        return SmartEditing.isHorizontalRuleLine(lineRange: line, in: ns)
    }

    private func isSetext(_ text: String, at offset: Int) -> Bool {
        let ns = text as NSString
        let line = LineEdits.lineRange(in: ns, at: offset)
        return SmartEditing.isSetextUnderline(lineRange: line, in: ns)
    }

    private func isRuleAtEnd(_ text: String) -> Bool {
        isRule(text, at: (text as NSString).length - 1)
    }

    private func isSetextAtEnd(_ text: String) -> Bool {
        isSetext(text, at: (text as NSString).length - 1)
    }

    @Test(
        "Three dashes are a rule, not an underline, with nothing plain above to underline",
        arguments: ["---", "\n---", "# H\n---"]
    )
    func ruleWithNothingToUnderline(text: String) {
        #expect(isRuleAtEnd(text))
        #expect(!isSetextAtEnd(text))
    }

    @Test("A rule line ends the paragraph, so two rules in a row are both rules")
    func twoConsecutiveRuleLines() {
        // Off the first line: `---` there opens frontmatter.
        let ns = "\n---\n---" as NSString
        #expect(
            SmartEditing.isHorizontalRuleLine(
                lineRange: LineEdits.lineRange(in: ns, at: 1), in: ns))
        #expect(
            SmartEditing.isHorizontalRuleLine(
                lineRange: LineEdits.lineRange(in: ns, at: 5), in: ns))
    }

    @Test(
        "A rule under a list item, quote, table row, or indented code stays a rule",
        arguments: [
            "- item\n---",
            "- [ ] checklist\n---",
            "1. one\n---",
            "> quote\n---",
            "| a | b |\n---",
            "    code\n---",
        ]
    )
    func ruleUnderNonParagraphBlock(text: String) {
        #expect(isRuleAtEnd(text))
        #expect(!isSetextAtEnd(text))
    }

    @Test(
        "A rule inside an unclosed fence is code; one after a closed fence stays a rule",
        arguments: [
            ("```\n---\n```\n---", "```"),
            ("~~~\n---\n~~~\n---", "~~~"),
        ] as [(String, String)]
    )
    func ruleInsideThenAfterFence(text: String, fence: String) {
        let ns = text as NSString
        let insideDashes = LineEdits.lineRange(in: ns, at: (fence as NSString).length + 1)
        let afterDashes = LineEdits.lineRange(in: ns, at: ns.length - 1)
        #expect(!SmartEditing.isHorizontalRuleLine(lineRange: insideDashes, in: ns))
        #expect(SmartEditing.isHorizontalRuleLine(lineRange: afterDashes, in: ns))
    }

    @Test("A tilde fence doesn't close a backtick fence")
    func tildeDoesNotCloseBacktickFence() {
        let ns = "```\n~~~\n---" as NSString
        let dashes = LineEdits.lineRange(in: ns, at: ns.length - 1)
        #expect(SmartEditing.isInsideFence(lineStart: dashes.location, in: ns))
        #expect(!SmartEditing.isHorizontalRuleLine(lineRange: dashes, in: ns))
    }

    @Test("A shorter closing fence doesn't close a longer one")
    func shorterFenceDoesNotClose() {
        let ns = "````\n---\n```\n---" as NSString
        let lastDashes = LineEdits.lineRange(in: ns, at: ns.length - 1)
        #expect(SmartEditing.isInsideFence(lineStart: lastDashes.location, in: ns))
        #expect(!SmartEditing.isHorizontalRuleLine(lineRange: lastDashes, in: ns))
    }

    @Test("A bare closing fence closes an opener that carried an info string")
    func infoStringOpenerClosesWithBareFence() {
        let ns = "```swift\n```\n---" as NSString
        let dashes = LineEdits.lineRange(in: ns, at: ns.length - 1)
        #expect(!SmartEditing.isInsideFence(lineStart: dashes.location, in: ns))
        #expect(SmartEditing.isHorizontalRuleLine(lineRange: dashes, in: ns))
    }

    @Test("A rule inside an unclosed fence with text above it is neither a rule nor an underline")
    func ruleInsideUnclosedFenceIsPlainCode() {
        let ns = "```\nText\n---" as NSString
        let dashes = LineEdits.lineRange(in: ns, at: ns.length - 1)
        #expect(!SmartEditing.isHorizontalRuleLine(lineRange: dashes, in: ns))
        #expect(!SmartEditing.isSetextUnderline(lineRange: dashes, in: ns))
    }

    @Test(
        "A rule under a list item's continuation line or lazy line stays a rule",
        arguments: ["- item\n  more\n---", "- item\nlazy\n---"]
    )
    func ruleUnderListContinuation(text: String) {
        #expect(isRuleAtEnd(text))
        #expect(!isSetextAtEnd(text))
    }

    @Test("A box-drawing underline is plain text — neither a rule nor a setext underline")
    func boxDrawingUnderlineIsPlainText() {
        #expect(!isRuleAtEnd("Text\n───"))
        #expect(!isSetextAtEnd("Text\n───"))
    }

    @Test("Two dashes are too short to be either a rule or an underline")
    func tooShortToBeEither() {
        #expect(!isRuleAtEnd("Text\n--"))
        #expect(!isSetextAtEnd("Text\n--"))
    }
}

@Suite("SmartEditing: setextLevel")
struct SetextLevelTests {
    private func level(_ text: String) -> Int? {
        let ns = text as NSString
        let line = LineEdits.lineRange(in: ns, at: ns.length - 1)
        return SmartEditing.setextLevel(lineRange: line, in: ns)
    }

    private func isRule(_ text: String) -> Bool {
        let ns = text as NSString
        let line = LineEdits.lineRange(in: ns, at: ns.length - 1)
        return SmartEditing.isHorizontalRuleLine(lineRange: line, in: ns)
    }

    @Test(
        "Under paragraph text, a run of `*` or `_`, or a space-separated dash run, is a rule",
        arguments: ["Text\n***", "Text\n___", "Text\n- - -"]
    )
    func nonPlainDashRunsUnderParagraphAreRulesNotUnderlines(text: String) {
        #expect(level(text) == nil)
        #expect(isRule(text))
    }

    @Test("Two equals signs are too short to be a heading underline, and never a rule")
    func tooShortEqualsIsNeither() {
        #expect(level("Text\n==") == nil)
        #expect(!isRule("Text\n=="))
    }

    @Test("Equals signs with nothing plain above them are neither a rule nor a heading underline")
    func equalsAloneIsNeither() {
        #expect(level("===") == nil)
        #expect(!isRule("==="))
    }
}

@Suite("SmartEditing: list continuation")
struct ListMarkerTests {
    @Test(
        "A rule-shaped line doesn't continue as a list, star- or dash-separated alike",
        arguments: ["* * *", "- - -"]
    )
    func ruleShapedLineIsNotAList(line: String) {
        #expect(SmartEditing.nextListMarker(for: line) == nil)
    }

    @Test(
        "Numeric markers increment, including across a digit boundary",
        arguments: [("1. foo", "2. "), ("9. foo", "10. "), ("99. foo", "100. ")]
    )
    func numeric(line: String, marker: String) {
        #expect(SmartEditing.nextListMarker(for: line) == marker)
    }

    @Test(
        "Alphabetic markers advance one letter and stop at the end of the alphabet",
        arguments: [
            ("A. foo", "B. "),
            ("Y. foo", "Z. "),
            ("Z. foo", nil),
            ("a. foo", "b. "),
            ("y. foo", "z. "),
            ("z. foo", nil),
        ] as [(String, String?)]
    )
    func alphabetic(line: String, marker: String?) {
        #expect(SmartEditing.nextListMarker(for: line) == marker)
    }

    /// "" signals leaving the list; nil means the line was never a list item.
    @Test("An empty item yields the exit signal, not a marker")
    func emptyItemExits() {
        #expect(SmartEditing.nextListMarker(for: "- ") == "")
        #expect(SmartEditing.nextListMarker(for: "1. ") == "")
    }

    @Test("Non-list lines yield nil", arguments: ["Just some text", "", "-foo"])
    func nonList(line: String) {
        #expect(SmartEditing.nextListMarker(for: line) == nil)
    }

    @Test(
        "Unordered markers carry their leading indentation",
        arguments: [("  - foo", "  - "), ("\t* foo", "\t* "), ("   + foo", "   + ")]
    )
    func indentedUnordered(line: String, marker: String) {
        #expect(SmartEditing.nextListMarker(for: line) == marker)
    }

    @Test(
        "A `)` numeric marker continues with `)`, indent and all",
        arguments: [("1) foo", "2) "), ("9) foo", "10) "), ("  3) foo", "  4) ")]
    )
    func parenNumeric(line: String, marker: String) {
        #expect(SmartEditing.nextListMarker(for: line) == marker)
    }
}

@Suite("List items")
struct ListItemTests {
    private func parse(_ line: String) -> SmartEditing.ListItem? {
        let ns = line as NSString
        return SmartEditing.listItem(
            lineRange: NSRange(location: 0, length: ns.length), in: ns)
    }

    @Test("Bullet markers", arguments: ["- item", "* item", "+ item"])
    func bullets(line: String) {
        let item = parse(line)
        #expect(item?.marker == .bullet)
        #expect(item?.markerRange == NSRange(location: 0, length: 1))
        #expect(item?.contentStart == 2)
    }

    @Test("Ordered markers", arguments: ["1. item", "12. item", "1) item", "A. item", "a. item"])
    func ordered(line: String) {
        #expect(parse(line)?.marker == .ordered)
    }

    @Test("The marker range covers the digits and the dot")
    func orderedMarkerRange() {
        #expect(parse("12. item")?.markerRange == NSRange(location: 0, length: 3))
    }

    @Test("A `)` marker's range covers the digits and the parenthesis")
    func parenMarkerRange() {
        let item = parse("12) item")
        #expect(item?.markerRange == NSRange(location: 0, length: 3))
        #expect(item?.contentStart == 4)
    }

    @Test("Leading whitespace is measured, not consumed")
    func indentWidth() {
        let item = parse("    - item")
        #expect(item?.indentWidth == 4)
        #expect(item?.markerRange == NSRange(location: 4, length: 1))
        #expect(item?.contentStart == 6)
    }

    @Test("Depth counts levels against the configured indent width")
    func depth() {
        #expect(parse("- a")?.depth(indentWidth: 2) == 0)
        #expect(parse("  - a")?.depth(indentWidth: 2) == 1)
        #expect(parse("    - a")?.depth(indentWidth: 2) == 2)
        // A hand-typed odd indent rounds down rather than resetting.
        #expect(parse("   - a")?.depth(indentWidth: 2) == 1)
    }

    @Test("Not list items", arguments: [
        "-word", "plain text", "1.item", "ab. item", "*bold*", "", "-", "#  heading",
        "1)item", "a) item", "A) item",
    ])
    func rejected(line: String) {
        #expect(parse(line) == nil)
    }

    @Test("A horizontal rule is not a bullet whose content is dashes")
    func horizontalRule() {
        #expect(parse("---") == nil)
        #expect(parse("-----") == nil)
    }

    @Test("A star-separated rule is not a bullet whose content is `* *`")
    func starSeparatedRuleIsNotABullet() {
        #expect(parse("* * *") == nil)
    }

    @Test("A setext `---` under a paragraph is not a bullet either")
    func setextUnderlineIsNotABullet() {
        let ns = "Text\n---" as NSString
        let line = LineEdits.lineRange(in: ns, at: ns.length - 1)
        #expect(SmartEditing.listItem(lineRange: line, in: ns) == nil)
    }

    @Test("A trailing newline doesn't change the parse")
    func trailingNewline() {
        #expect(parse("- item\n")?.contentStart == 2)
    }

    @Test("Glyphs cycle rather than clamping past the last one")
    func glyphs() {
        #expect(SmartEditing.bulletGlyph(depth: 0) == "•")
        #expect(SmartEditing.bulletGlyph(depth: 1) == "◦")
        #expect(SmartEditing.bulletGlyph(depth: 2) == "▪")
        #expect(SmartEditing.bulletGlyph(depth: 3) == "•")
        #expect(SmartEditing.bulletGlyph(depth: 7) == "◦")
        // A negative depth doesn't trap.
        #expect(SmartEditing.bulletGlyph(depth: -1) == "▪")
    }
}

@Suite("SmartEditing: home")
struct HomeTargetTests {
    private func target(_ text: String, cursor: Int) -> Int? {
        SmartEditing.homeTarget(in: text as NSString, cursor: cursor)
    }

    @Test(
        "Home lands on content start from wherever the cursor sits ahead of it",
        arguments: [
            ("- item", 4, 2),
            ("- item", 0, 2),
            ("- item", 1, 2),  // after the marker
            ("1. item", 5, 3),
            ("1. item", 0, 3),
            ("A. item", 0, 3),
            ("a. item", 0, 3),
            ("  - item", 6, 4),
            ("  - item", 0, 4),
            ("  - item", 2, 4),  // on the marker
        ] as [(String, Int, Int)]
    )
    func toContentStart(line: String, cursor: Int, expected: Int) {
        #expect(target(line, cursor: cursor) == expected)
    }

    @Test("A second Home press from content start goes to column 0")
    func toColumnZero() {
        #expect(target("- item", cursor: 2) == 0)
    }

    @Test("An indented item's column 0 is the line start, before the indent")
    func indentedColumnZero() {
        #expect(target("  - item", cursor: 4) == 0)
    }

    @Test("Non-list lines yield nil", arguments: ["plain text", "-word"])
    func nonList(line: String) {
        #expect(target(line, cursor: 0) == nil)
    }

    @Test("An empty document yields nil")
    func emptyDocument() {
        #expect(target("", cursor: 0) == nil)
    }

    @Test("Offsets are document-absolute when the list line isn't the first")
    func laterLine() {
        let text = "para\n- item\nmore\n"
        // The second line starts at 5; its content starts at 7.
        #expect(target(text, cursor: 9) == 7)  // mid-line
        #expect(target(text, cursor: 7) == 5)  // at content start -> line start
        #expect(target(text, cursor: 5) == 7)  // at column 0 -> content start
    }

    @Test("The last line works the same without a trailing newline")
    func lastLineWithoutTrailingNewline() {
        let text = "para\n- item"
        #expect(target(text, cursor: 9) == 7)  // mid-line
        #expect(target(text, cursor: 7) == 5)  // at content start -> line start
        #expect(target(text, cursor: 5) == 7)  // at column 0 -> content start
    }
}

@Suite("SmartEditing: next list marker")
struct NextListMarkerTests {
    @Test("A checklist's next box is always unchecked, whichever way this one goes")
    func checklistAlwaysUnchecked() {
        #expect(SmartEditing.nextListMarker(for: "- [ ] foo") == "- [ ] ")
        #expect(SmartEditing.nextListMarker(for: "- [x] foo") == "- [ ] ")
        #expect(SmartEditing.nextListMarker(for: "  * [X] foo") == "  * [ ] ")
    }
}

@Suite("SmartEditing: checklists")
struct ChecklistListItemTests {
    private func parse(_ line: String) -> SmartEditing.ListItem? {
        let ns = line as NSString
        return SmartEditing.listItem(
            lineRange: NSRange(location: 0, length: ns.length), in: ns)
    }

    @Test("An unchecked checklist")
    func unchecked() {
        let item = parse("- [ ] foo")
        #expect(item?.marker == .checklist(checked: false))
        #expect(item?.markerRange == NSRange(location: 0, length: 5))
        #expect(item?.contentStart == 6)
        #expect(item?.indentWidth == 0)
    }

    @Test("An indented, checked checklist")
    func indentedChecked() {
        let item = parse("  - [x] foo")
        #expect(item?.marker == .checklist(checked: true))
        #expect(item?.markerRange == NSRange(location: 2, length: 5))
        #expect(item?.contentStart == 8)
        #expect(item?.indentWidth == 2)
    }

    @Test("Any run of whitespace between the bullet and the box is allowed")
    func tabBeforeBox() {
        let text = "-\t[ ] foo" as NSString
        let item = SmartEditing.listItem(lineRange: NSRange(location: 0, length: text.length), in: text)
        #expect(item?.marker == .checklist(checked: false))
        #expect(item?.markerRange == NSRange(location: 0, length: 5))
        #expect(item?.contentStart == 6)
        #expect(SmartEditing.nextListMarker(for: "-\t[ ] foo") == "- [ ] ")
    }

    @Test("An uppercase X checks the box too")
    func uppercaseChecked() {
        #expect(parse("- [X] foo")?.marker == .checklist(checked: true))
    }

    @Test("A box with no space after it is a plain bullet, box included in content")
    func boxWithNoTrailingSpace() {
        let item = parse("- [ ]foo")
        #expect(item?.marker == .bullet)
        #expect(item?.contentStart == 2)
    }

    @Test("A box alone at the end of the line is a plain bullet")
    func boxAloneAtEndOfLine() {
        let item = parse("- [ ]")
        #expect(item?.marker == .bullet)
        #expect(item?.contentStart == 2)
    }

    @Test("An invalid box character is not a checklist")
    func invalidBoxCharacter() {
        #expect(parse("- [y] foo")?.marker == .bullet)
    }

    @Test("Only bullets get boxes — an ordered marker with brackets is still ordered")
    func orderedWithBracketsStaysOrdered() {
        #expect(parse("1. [ ] foo")?.marker == .ordered)
    }

    @Test("The checklist state index is the character inside the box")
    func checklistStateIndex() {
        #expect(parse("- [x] foo")?.checklistStateIndex == 3)
        #expect(parse("- foo")?.checklistStateIndex == nil)
    }

    @Test("Only a bullet typesets a glyph; a checklist's box is drawn, an ordered marker is content")
    func glyph() {
        #expect(parse("- [ ] foo")?.glyph(indentWidth: 2) == nil)
        #expect(parse("- [x] foo")?.glyph(indentWidth: 2) == nil)
        #expect(parse("- foo")?.glyph(indentWidth: 2) == "•")
        #expect(parse("1. foo")?.glyph(indentWidth: 2) == nil)
    }
}

@Suite("SmartEditing: backspace at item start")
struct BackspaceAtItemStartTests {
    private func edit(_ text: String, cursor: Int) -> LineEdits.Edit? {
        SmartEditing.backspaceAtItemStart(in: text as NSString, cursor: cursor)
    }

    private func applied(_ text: String, cursor: Int) -> (String, NSRange)? {
        guard let e = edit(text, cursor: cursor) else { return nil }
        let ns = NSMutableString(string: text)
        ns.replaceCharacters(in: e.range, with: e.replacement)
        return (ns as String, e.selection)
    }

    @Test("A bullet's marker and following space are removed")
    func bullet() {
        let result = applied("- item", cursor: 2)
        #expect(result?.0 == "item")
        #expect(result?.1 == NSRange(location: 0, length: 0))
    }

    @Test("The indent survives, only the marker goes")
    func indentedBullet() {
        let result = applied("  - item", cursor: 4)
        #expect(result?.0 == "  item")
        #expect(result?.1 == NSRange(location: 2, length: 0))
    }

    @Test("A checklist's whole marker, box included, is removed")
    func checklist() {
        let result = applied("- [ ] item", cursor: 6)
        #expect(result?.0 == "item")
        #expect(result?.1 == NSRange(location: 0, length: 0))
    }

    @Test("An ordered marker is removed the same way")
    func ordered() {
        let result = applied("3. item", cursor: 3)
        #expect(result?.0 == "item")
    }

    @Test("Anywhere else on the line, this is not the edit", arguments: [0, 1, 4])
    func elsewhereOnLine(cursor: Int) {
        #expect(edit("- item", cursor: cursor) == nil)
    }

    @Test("A non-list line yields nil")
    func nonList() {
        #expect(edit("plain text", cursor: 3) == nil)
    }

    @Test("Offsets are document-absolute on a later line")
    func laterLine() {
        let result = applied("para\n  - item\n", cursor: 9)
        #expect(result?.0 == "para\n  item\n")
        #expect(result?.1 == NSRange(location: 7, length: 0))
    }

    @Test("An empty item is emptied entirely")
    func emptyItem() {
        let result = applied("- ", cursor: 2)
        #expect(result?.0 == "")
    }
}

@Suite("SmartEditing: continuation line")
struct ContinuationLineTests {
    private func line(_ text: String, cursor: Int) -> String? {
        SmartEditing.continuationLine(in: text as NSString, cursor: cursor)
    }

    @Test("At content start, the same padding applies")
    func atContentStart() {
        #expect(line("- item", cursor: 2) == "\n  ")
    }

    @Test("On a continuation line, the same padding as the item it belongs to")
    func fromContinuationLine() {
        #expect(line("  - item\n    more", cursor: 17) == "\n    ")
        #expect(line("- [ ] checklist\n      more", cursor: 26) == "\n      ")
    }

    @Test("On a fresh, whitespace-only continuation line the caret is already past the whitespace")
    func fromFreshContinuationLine() {
        #expect(line("- item\n  ", cursor: 9) == "\n  ")
    }
}

@Suite("SmartEditing: is continuation")
struct IsContinuationTests {
    private func check(_ text: String) -> Bool {
        let ns = text as NSString
        let itemLine = ns.lineRange(for: NSRange(location: 0, length: 0))
        guard let item = SmartEditing.listItem(lineRange: itemLine, in: ns) else {
            fatalError("first line of \(text) is not a list item")
        }
        let secondLine = ns.lineRange(for: NSRange(location: NSMaxRange(itemLine), length: 0))
        return SmartEditing.isContinuation(
            lineRange: secondLine, in: ns, of: item, itemLine: itemLine)
    }

    @Test("Whitespace reaching the content column is a continuation")
    func reachesColumn() {
        #expect(check("- item\n  more\n"))
    }

    @Test("One space short of the column is not a continuation")
    func shortOfColumn() {
        #expect(!check("- item\n more\n"))
    }

    @Test("A blank line is never a continuation")
    func blankLine() {
        #expect(!check("- item\n\n"))
    }

    @Test("More whitespace than the column still counts")
    func moreThanColumn() {
        #expect(check("- item\n     deeper\n"))
    }

    @Test("An indented item's own, deeper column is honored")
    func indentedItemColumn() {
        #expect(check("  - item\n    more\n"))
    }

    @Test("A whitespace-only line reaching the column is a continuation — it is what ⇧↵ writes")
    func whitespaceOnly() {
        #expect(check("- item\n  \n"))
        #expect(check("- item\n  "))
        #expect(!check("- item\n \n"))
    }
}

@Suite("SmartEditing: toggled checklist")
struct ToggledChecklistTests {
    private func toggled(_ text: String, at index: Int, selection: NSRange = NSRange(location: 0, length: 0)) -> (String, NSRange)? {
        guard let e = SmartEditing.toggledChecklist(in: text as NSString, lineAt: index, selection: selection)
        else { return nil }
        let ns = NSMutableString(string: text)
        ns.replaceCharacters(in: e.range, with: e.replacement)
        return (ns as String, e.selection)
    }

    @Test("Checking an unchecked checklist")
    func check() {
        #expect(toggled("- [ ] a", at: 0)?.0 == "- [x] a")
    }

    @Test("Unchecking a checked checklist")
    func uncheck() {
        #expect(toggled("- [x] a", at: 0)?.0 == "- [ ] a")
    }

    @Test("An uppercase checked box unchecks too")
    func uncheckUppercase() {
        #expect(toggled("- [X] a", at: 0)?.0 == "- [ ] a")
    }

    @Test("A bullet line has no box to toggle")
    func bulletYieldsNil() {
        #expect(toggled("- a", at: 0) == nil)
    }

    @Test("Works from any index on the line, not just its start")
    func fromMidLine() {
        #expect(toggled("- [ ] a", at: 6)?.0 == "- [x] a")
    }

    @Test("The selection passes through untouched")
    func selectionUnchanged() {
        let selection = NSRange(location: 6, length: 1)
        #expect(toggled("- [ ] a", at: 0, selection: selection)?.1 == selection)
    }
}

@Suite("SmartEditing: continuedItem")
struct ContinuedItemTests {
    private func result(_ text: String, lineAt offset: Int) -> (marker: SmartEditing.ListItem.Marker, line: NSRange)? {
        let ns = text as NSString
        let lineRange = LineEdits.lineRange(in: ns, at: offset)
        guard let found = SmartEditing.continuedItem(lineRange: lineRange, in: ns) else { return nil }
        return (found.item.marker, found.line)
    }

    @Test("A continuation one level up finds the item")
    func directContinuation() {
        let text = "- item\n  more\n"
        let ns = text as NSString
        let secondLine = LineEdits.lineRange(in: ns, at: 7)
        let found = SmartEditing.continuedItem(lineRange: secondLine, in: ns)
        #expect(found?.line == NSRange(location: 0, length: 7))
    }

    @Test("A continuation two lines down walks over the first continuation")
    func walksOverContinuation() {
        let text = "- item\n  more\n  even more\n"
        let ns = text as NSString
        let thirdLine = LineEdits.lineRange(in: ns, at: 14)
        let found = SmartEditing.continuedItem(lineRange: thirdLine, in: ns)
        #expect(found?.line == NSRange(location: 0, length: 7))
    }

    @Test("One space short of the content column is not a continuation")
    func shortOfColumn() {
        let text = "- item\n more\n"
        let ns = text as NSString
        let secondLine = LineEdits.lineRange(in: ns, at: 7)
        #expect(SmartEditing.continuedItem(lineRange: secondLine, in: ns) == nil)
    }

    @Test("A blank line breaks the chain")
    func blankLineBreaksChain() {
        let text = "- item\n\n  more\n"
        let ns = text as NSString
        let thirdLine = LineEdits.lineRange(in: ns, at: 8)
        #expect(SmartEditing.continuedItem(lineRange: thirdLine, in: ns) == nil)
    }

    @Test("A flush non-list line breaks the chain")
    func flushLineBreaksChain() {
        let text = "- item\nplain\n  more\n"
        let ns = text as NSString
        let thirdLine = LineEdits.lineRange(in: ns, at: 13)
        #expect(SmartEditing.continuedItem(lineRange: thirdLine, in: ns) == nil)
    }

    @Test("A list line itself is not a continuation")
    func listLineYieldsNil() {
        let text = "- item\n  more\n"
        let ns = text as NSString
        let firstLine = LineEdits.lineRange(in: ns, at: 0)
        #expect(SmartEditing.continuedItem(lineRange: firstLine, in: ns) == nil)
    }

    @Test("The first line of the document has nothing above it")
    func firstLineYieldsNil() {
        let text = "plain\n"
        let ns = text as NSString
        let firstLine = LineEdits.lineRange(in: ns, at: 0)
        #expect(SmartEditing.continuedItem(lineRange: firstLine, in: ns) == nil)
    }

    @Test("A nested item is found at its own, deeper column")
    func nestedItem() {
        let text = "  - nested\n    more\n"
        let ns = text as NSString
        let secondLine = LineEdits.lineRange(in: ns, at: 11)
        let found = SmartEditing.continuedItem(lineRange: secondLine, in: ns)
        #expect(found?.line == NSRange(location: 0, length: 11))
    }

    @Test("The nearest item wins, not an ancestor further up")
    func nearestItemWins() {
        let text = "- a\n  - b\n    more\n"
        let ns = text as NSString
        let thirdLine = LineEdits.lineRange(in: ns, at: 10)
        let found = SmartEditing.continuedItem(lineRange: thirdLine, in: ns)
        #expect(found?.line == NSRange(location: 4, length: 6))
    }

    @Test("A checklist is found like any other")
    func checklist() {
        let text = "- [ ] checklist\n      more\n"
        let ns = text as NSString
        let secondLine = LineEdits.lineRange(in: ns, at: 16)
        let found = SmartEditing.continuedItem(lineRange: secondLine, in: ns)
        #expect(found?.line == NSRange(location: 0, length: 16))
        #expect(found?.item.marker.isChecklist == true)
    }
}

@Suite("SmartEditing: renumber")
struct RenumberTests {
    private func apply(_ text: String) -> String {
        let ns = NSMutableString(string: text)
        let edits = SmartEditing.renumber(in: ns)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            ns.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return ns as String
    }

    @Test("An already-sequential run yields no edits")
    func alreadySequential() {
        let text = "1. a\n2. b\n3. c\n"
        #expect(SmartEditing.renumber(in: text as NSString).isEmpty)
        #expect(apply(text) == text)
    }

    @Test("A gap in the sequence is closed")
    func gapClosed() {
        #expect(apply("1. a\n2. b\n5. c\n") == "1. a\n2. b\n3. c\n")
    }

    @Test("The first item's value is kept as the run's start")
    func firstValueKept() {
        #expect(apply("3. a\n7. b\n") == "3. a\n4. b\n")
    }

    @Test("Repeated markers are put in sequence")
    func repeatedMarkers() {
        #expect(apply("1. a\n1. b\n1. c\n") == "1. a\n2. b\n3. c\n")
    }

    @Test("A width change from single to double digits is handled")
    func widthGrows() {
        let text = "9. a\n9. b\n"
        let edits = SmartEditing.renumber(in: text as NSString)
        #expect(edits.count == 1)
        #expect(edits.first?.range == NSRange(location: 5, length: 1))
        #expect(edits.first?.replacement == "10")
        #expect(apply(text) == "9. a\n10. b\n")
    }

    @Test("Nested items don't break the parent run")
    func nestedDoesNotBreakParent() {
        #expect(
            apply("1. a\n  1. x\n  5. y\n7. b\n")
                == "1. a\n  1. x\n  2. y\n2. b\n")
    }

    @Test("Continuation and indented lines don't break the run")
    func continuationDoesNotBreak() {
        #expect(apply("1. a\n   more\n5. b\n") == "1. a\n   more\n2. b\n")
    }

    @Test("A blank line ends the run")
    func blankLineEndsRun() {
        let text = "1. a\n\n5. b\n"
        #expect(apply(text) == text)
    }

    @Test("A flush non-list line ends the run")
    func flushLineEndsRun() {
        let text = "1. a\nplain\n5. b\n"
        #expect(apply(text) == text)
    }

    @Test("A bullet at the same depth ends the run")
    func bulletEndsRun() {
        let text = "1. a\n- x\n5. b\n"
        #expect(apply(text) == text)
    }

    @Test("A shallower item ends a deeper run")
    func shallowerItemEndsDeeperRun() {
        let text = "  1. a\n- x\n  5. b\n"
        #expect(apply(text) == text)
    }

    @Test("A change of kind starts a new run rather than continuing")
    func changeOfKindStartsNewRun() {
        let text = "1. a\nA. b\n5. c\n"
        #expect(apply(text) == text)
    }

    @Test("Uppercase alpha runs are renumbered")
    func uppercaseAlphaRun() {
        #expect(apply("A. a\nC. b\n") == "A. a\nB. b\n")
    }

    @Test("Lowercase alpha runs are renumbered")
    func lowercaseAlphaRun() {
        #expect(apply("a. a\nc. b\n") == "a. a\nb. b\n")
    }

    @Test("Past Z there is nothing to count with, so it is left as typed")
    func pastZUnchanged() {
        let text = "Z. a\nZ. b\n"
        #expect(apply(text) == text)
    }

    @Test("The last line, with no trailing newline, is still renumbered")
    func noTrailingNewline() {
        #expect(apply("1. a\n5. b") == "1. a\n2. b")
    }

    @Test("An empty document yields no edits")
    func emptyDocument() {
        #expect(SmartEditing.renumber(in: "" as NSString).isEmpty)
    }

    @Test("A marker too long to be a count is left alone and ends the run")
    func longMarkerEndsRun() {
        let text = "9223372036854775807. a\n5. b\n"
        #expect(apply(text) == text)
        let text2 = "1. a\n99999999999999999999. b\n7. c\n"
        #expect(apply(text2) == text2)
        let nine = "1. a\n999999999. b\n7. c\n"
        #expect(apply(nine) == "1. a\n2. b\n3. c\n")
    }

    @Test("Two interleaved depths keep separate counters")
    func interleavedDepthsSeparateCounters() {
        #expect(
            apply("1. a\n  1. x\n2. b\n  1. y\n  5. z\n")
                == "1. a\n  1. x\n2. b\n  1. y\n  2. z\n")
    }

    @Test("A fenced code block's `1.` lines are untouched; the run after it still renumbers")
    func fencedCodeIsSkippedButTheRunAfterItStillRenumbers() {
        let text = "```md\n1. first\n1. second\n1. third\n```\n1. a\n1. b"
        let prefix = "```md\n1. first\n1. second\n1. third\n```\n1. a\n" as NSString
        let edits = SmartEditing.renumber(in: text as NSString)
        #expect(edits.count == 1)
        #expect(edits.first?.range == NSRange(location: prefix.length, length: 1))
        #expect(edits.first?.replacement == "2")
        #expect(apply(text) == "```md\n1. first\n1. second\n1. third\n```\n1. a\n2. b")
    }

    @Test("Repeated markers inside frontmatter yield no edits")
    func frontmatterIsSkipped() {
        let text = "---\n1. x\n1. y\n---\n"
        #expect(SmartEditing.renumber(in: text as NSString).isEmpty)
        #expect(apply(text) == text)
    }

    @Test("`)` markers are put in sequence and keep their `)`")
    func parenMarkersRenumber() {
        #expect(apply("1) a\n1) b\n1) c\n") == "1) a\n2) b\n3) c\n")
    }

    @Test("A change of delimiter starts a new run")
    func delimiterChangeStartsNewRun() {
        let text = "1. a\n1) b\n"
        #expect(apply(text) == text)
        #expect(apply("1. a\n2. b\n5) c\n9) d\n") == "1. a\n2. b\n5) c\n6) d\n")
    }
}

@Suite("SmartEditing: guideDepth")
struct GuideDepthTests {
    private func depth(_ text: String, at offset: Int, indentWidth: Int = 2) -> Int? {
        let ns = text as NSString
        let lineRange = LineEdits.lineRange(in: ns, at: offset)
        return SmartEditing.guideDepth(lineRange: lineRange, in: ns, indentWidth: indentWidth)
    }

    @Test("A list item's depth matches its indent level")
    func listItemDepth() {
        #expect(depth("- a\n", at: 0) == 0)
        #expect(depth("  - b\n", at: 0) == 1)
        #expect(depth("    - c\n", at: 0) == 2)
    }

    @Test("A continuation line takes its item's depth")
    func continuationDepth() {
        let text = "- a\n  cont\n"
        #expect(depth(text, at: 4) == 0)
    }

    @Test("A blank line between two list lines takes the shallower depth")
    func blankBetweenListLinesTakesShallower() {
        #expect(depth("  - a\n\n    - b\n", at: 6) == 1)
        #expect(depth("    - a\n\n  - b\n", at: 8) == 1)
        #expect(depth("  - a\n\n  - b\n", at: 6) == 1)
    }

    @Test("A whitespace-only line between list lines counts as blank")
    func whitespaceOnlyLineCountsAsBlank() {
        let text = "  - a\n   \n    - b\n"
        #expect(depth(text, at: 6) == 1)
    }

    @Test("Two consecutive blank lines between list lines both get the depth")
    func twoConsecutiveBlankLines() {
        let text = "  - a\n\n\n    - b\n"
        #expect(depth(text, at: 6) == 1)
        #expect(depth(text, at: 7) == 1)
    }

    @Test("A blank line followed by prose is outside the list")
    func blankFollowedByProseIsNil() {
        let text = "  - a\n\nprose\n"
        #expect(depth(text, at: 6) == nil)
    }

    @Test("A blank line with no list line above is outside the list")
    func blankWithNoListAboveIsNil() {
        let text = "\n  - a\n"
        #expect(depth(text, at: 0) == nil)
    }

    @Test("A blank line at the document end is outside the list")
    func blankAtDocumentEndIsNil() {
        let text = "  - a\n\n"
        #expect(depth(text, at: 6) == nil)
    }

    @Test("An ordinary prose line is outside the list")
    func proseLineIsNil() {
        #expect(depth("just prose\n", at: 0) == nil)
    }
}

@Suite("SmartEditing: ancestors")
struct AncestorsTests {
    private func ancestors(
        _ text: String, at offset: Int, depth: Int, indentWidth: Int = 2
    ) -> [(item: SmartEditing.ListItem, line: NSRange)?] {
        let ns = text as NSString
        let lineRange = LineEdits.lineRange(in: ns, at: offset)
        return SmartEditing.ancestors(of: lineRange, depth: depth, in: ns, indentWidth: indentWidth)
    }

    @Test("A direct child has one slot pointing to the parent's line")
    func directChild() {
        let text = "- p\n  - c\n"
        let ns = text as NSString
        let parentLine = LineEdits.lineRange(in: ns, at: 0)
        let result = ancestors(text, at: 4, depth: 1)
        #expect(result.count == 1)
        #expect(result[0]?.line == parentLine)
    }

    @Test("Three levels of nesting fill one slot per ancestor")
    func threeLevels() {
        let text = "- a\n  - b\n    - c\n"
        let ns = text as NSString
        let lineA = LineEdits.lineRange(in: ns, at: 0)
        let lineB = LineEdits.lineRange(in: ns, at: 4)
        let result = ancestors(text, at: 10, depth: 2)
        #expect(result.count == 2)
        #expect(result[0]?.line == lineA)
        #expect(result[1]?.line == lineB)
    }

    @Test("A sibling's deeper subtree is skipped on the walk up")
    func siblingSubtreeSkipped() {
        let text = "- a\n  - b\n    - bb\n  - c\n"
        let ns = text as NSString
        let lineA = LineEdits.lineRange(in: ns, at: 0)
        let result = ancestors(text, at: 19, depth: 1)
        #expect(result.count == 1)
        #expect(result[0]?.line == lineA)
    }

    @Test("A blank line and a continuation line between parent and child don't break the walk")
    func blankAndContinuationDoNotBreakWalk() {
        let text = "- p\n  more\n\n  - c\n"
        let ns = text as NSString
        let parentLine = LineEdits.lineRange(in: ns, at: 0)
        let result = ancestors(text, at: 12, depth: 1)
        #expect(result.count == 1)
        #expect(result[0]?.line == parentLine)
    }

    @Test("A hand-typed jump of two levels hangs every slot under the one parent")
    func jumpOfTwoLevels() {
        let text = "- a\n    - c\n"
        let ns = text as NSString
        let lineA = LineEdits.lineRange(in: ns, at: 0)
        let result = ancestors(text, at: 4, depth: 2)
        #expect(result.count == 2)
        #expect(result[0]?.line == lineA)
        #expect(result[1]?.line == lineA)
    }

    @Test("A prose line above the child breaks the walk")
    func proseLineBreaksWalk() {
        let text = "- a\nprose\n  - c\n"
        let result = ancestors(text, at: 10, depth: 1)
        #expect(result.count == 1)
        #expect(result[0] == nil)
    }

    @Test("Depth zero yields an empty array")
    func depthZeroYieldsEmpty() {
        let result = ancestors("- a\n  - c\n", at: 4, depth: 0)
        #expect(result.isEmpty)
    }

    @Test("Nothing above the first line yields a single nil slot")
    func noLinesAboveYieldsNilSlot() {
        let result = ancestors("- a\n", at: 0, depth: 1)
        #expect(result.count == 1)
        #expect(result[0] == nil)
    }
}

@Suite("SmartEditing: return edit")
struct ReturnEditTests {
    /// Fixtures mark the caret with `|`, or the selection with a pair of them, and expectations
    /// mark where the caret lands, so a case reads as the text before the key and the text after.
    private func parse(_ marked: String) -> (text: String, selection: NSRange) {
        let parts = marked.components(separatedBy: "|")
        let start = (parts[0] as NSString).length
        let length = parts.count == 3 ? (parts[1] as NSString).length : 0
        return (parts.joined(), NSRange(location: start, length: length))
    }

    private func edit(
        _ marked: String, shifted: Bool = false, unit: String = "  "
    ) -> LineEdits.Edit? {
        let (text, selection) = parse(marked)
        return SmartEditing.returnEdit(
            in: text as NSString, selection: selection, shifted: shifted, unit: unit)
    }

    private func pressed(_ marked: String, shifted: Bool = false, unit: String = "  ") -> String? {
        guard let edit = edit(marked, shifted: shifted, unit: unit) else { return nil }
        let result = NSMutableString(string: parse(marked).text)
        result.replaceCharacters(in: edit.range, with: edit.replacement)
        #expect(edit.selection.length == 0)
        result.insert("|", at: edit.selection.location)
        return result as String
    }

    @Test(
        "⇧↵ inside an item's text starts a continuation line at the content column",
        arguments: [
            ("- ab|", "- ab\n  |"),
            ("- a|b", "- a\n  |b"),
            ("1. ab|", "1. ab\n   |"),
            ("10. ab|", "10. ab\n    |"),
            ("- [ ] ab|", "- [ ] ab\n      |"),
            ("  - ab|", "  - ab\n    |"),
            ("\t- ab|", "\t- ab\n\t  |"),
            ("- a\n  b|", "- a\n  b\n  |"),
        ] as [(String, String)]
    )
    func shiftedContinuation(marked: String, expected: String) {
        #expect(pressed(marked, shifted: true) == expected)
    }

    @Test("⇧↵ over a selection in an item's text replaces the selection")
    func shiftedReplacesSelection() {
        #expect(pressed("- a|b|c", shifted: true) == "- a\n  |c")
    }

    @Test("⇧↵ before an item's content is a plain ↵, which moves the item down")
    func shiftedBeforeContent() {
        #expect(pressed("-| a", shifted: true) == "\n|- a")
    }

    @Test("⇧↵ on a continuation line before its whitespace ends is left to AppKit")
    func shiftedInContinuationIndent() {
        #expect(edit("- a\n|  b", shifted: true) == nil)
    }

    @Test(
        "⇧↵ off a list line is the same as ↵",
        arguments: [
            ("plain|", nil),
            ("  ind|", "  ind\n  |"),
        ] as [(String, String?)]
    )
    func shiftedOffList(marked: String, expected: String?) {
        #expect(pressed(marked, shifted: true) == expected)
        #expect(pressed(marked, shifted: false) == expected)
    }

    @Test(
        "↵ before an item's content moves the item down intact, caret at the start of the line",
        arguments: [
            ("|- a", "\n|- a"),
            ("-| a", "\n|- a"),
            ("  |- a", "\n|  - a"),
            ("12.| a", "\n|12. a"),
            ("|- ", "\n|- "),
            ("para\n|- a", "para\n\n|- a"),
        ] as [(String, String)]
    )
    func beforeItemContent(marked: String, expected: String) {
        #expect(pressed(marked) == expected)
    }

    @Test("A selection before an item's content is replaced, and the next marker follows it")
    func selectionInMarker() {
        #expect(pressed("|- |a") == "\n- |a")
    }

    @Test(
        "↵ on a continuation line past its whitespace starts the owning item's next marker",
        arguments: [
            ("- a\n  |b", "- a\n  \n- |b"),
            ("- a\n  b|", "- a\n  b\n- |"),
            ("1. a\n   b|", "1. a\n   b\n2. |"),
            ("- [ ] a\n      b|", "- [ ] a\n      b\n- [ ] |"),
            ("- [x] a\n      b|", "- [x] a\n      b\n- [ ] |"),
            ("  - a\n    b|", "  - a\n    b\n  - |"),
            ("- a\n  b\n  c|", "- a\n  b\n  c\n- |"),
        ] as [(String, String)]
    )
    func continuationLine(marked: String, expected: String) {
        #expect(pressed(marked) == expected)
    }

    @Test("↵ on a continuation line with the caret inside its whitespace only carries that much")
    func continuationLineBeforeWhitespaceEnds() {
        #expect(edit("- a\n|  b") == nil)
        #expect(pressed("- a\n | b") == "- a\n \n | b")
    }

    @Test(
        "↵ at the end of an item with text continues the list",
        arguments: [
            ("- a|", "- a\n- |"),
            ("* a|", "* a\n* |"),
            ("+ a|", "+ a\n+ |"),
            ("1. a|", "1. a\n2. |"),
            ("9. a|", "9. a\n10. |"),
            ("1) a|", "1) a\n2) |"),
            ("a. a|", "a. a\nb. |"),
            ("A. a|", "A. a\nB. |"),
            ("- [ ] a|", "- [ ] a\n- [ ] |"),
            ("- [x] done|", "- [x] done\n- [ ] |"),
            ("  - a|", "  - a\n  - |"),
            ("\t1. a|", "\t1. a\n\t2. |"),
            ("- ab|c", "- ab\n- |c"),
            ("- a|\nnext", "- a\n- |\nnext"),
            ("x\n- a|", "x\n- a\n- |"),
        ] as [(String, String)]
    )
    func itemWithText(marked: String, expected: String) {
        #expect(pressed(marked) == expected)
    }

    @Test("↵ after the last letter marker has no next marker, so it is left to AppKit")
    func lastLetterMarker() {
        #expect(edit("Z. a|") == nil)
    }

    @Test(
        "↵ on an empty flush-left item leaves the list in place, with no new line",
        arguments: [
            ("- |", "|"),
            ("1. |", "|"),
            ("1) |", "|"),
            ("- [ ] |", "|"),
            ("x\n- |", "x\n|"),
            ("- |\nnext", "|\nnext"),
        ] as [(String, String)]
    )
    func emptyFlushLeftItem(marked: String, expected: String) {
        #expect(pressed(marked) == expected)
    }

    @Test(
        "↵ on an empty nested item moves it one level shallower, in place",
        arguments: [
            ("  - |", "  ", "- |"),
            ("    - |", "  ", "  - |"),
            ("   - |", "  ", " - |"),
            (" - |", "    ", "- |"),
            ("    - |", "    ", "- |"),
            ("\t- |", "  ", "- |"),
            ("\t\t- |", "  ", "\t- |"),
            ("\t- |", "\t", "- |"),
            ("  1. |", "  ", "1. |"),
            ("  - [ ] |", "  ", "- [ ] |"),
        ] as [(String, String, String)]
    )
    func emptyNestedItem(marked: String, unit: String, expected: String) {
        #expect(pressed(marked, unit: unit) == expected)
    }

    @Test(
        "↵ on an empty item with a selection past its line replaces line start to selection end",
        arguments: [
            ("- |\n|next", "\n|next"),
            ("|- |", "\n|"),
            ("x\n- |\nab|", "x\n\n|"),
            ("  - |\n|next", "\n|next"),
        ] as [(String, String)]
    )
    func emptyItemWithSelection(marked: String, expected: String) {
        #expect(pressed(marked) == expected)
    }

    @Test(
        "↵ on an indented non-list line carries the indent up to the caret",
        arguments: [
            ("  foo|", "  foo\n  |"),
            ("\tfoo|", "\tfoo\n\t|"),
            ("\t  foo|", "\t  foo\n\t  |"),
            ("  foo|bar", "  foo\n  |bar"),
            ("  |", "  \n  |"),
            (" |  foo", " \n |  foo"),
            ("  | foo", "  \n  | foo"),
            ("para\n\n  foo|", "para\n\n  foo\n  |"),
        ] as [(String, String)]
    )
    func indentedPlainLine(marked: String, expected: String) {
        #expect(pressed(marked) == expected)
    }

    @Test(
        "↵ on a flush-left plain line, or at column 0 of an indented one, is left to AppKit",
        arguments: ["plain|", "pl|ain", "|", "|  foo", "para\n|", "- - -|"]
    )
    func leftToAppKit(marked: String) {
        #expect(edit(marked) == nil)
    }

    @Test(
        "↵ over a selection replaces the selection along with the split",
        arguments: [
            ("- a|bc|d", "- a\n- |d"),
            ("  a|bc|d", "  a\n  |d"),
            ("1. a|bc|d", "1. a\n2. |d"),
        ] as [(String, String)]
    )
    func selectionInLine(marked: String, expected: String) {
        #expect(pressed(marked) == expected)
    }

    @Test("↵ over a selection on a flush-left plain line is left to AppKit")
    func selectionOnPlainLine() {
        #expect(edit("ab|cd|e") == nil)
    }

    @Test("↵ on an empty item in a CRLF note leaves the list, replacing only the marker")
    func crlfEmptyItem() {
        let result = edit("- |\r\n")
        #expect(result?.range == NSRange(location: 0, length: 2))
        #expect(result?.replacement == "")
        #expect(pressed("- |\r\n") == "|\r\n")
    }

    @Test(
        "↵ in a CRLF note reads each line without its \\r",
        arguments: [
            ("- a|\r\n", "- a\n- |\r\n"),
            ("  - |\r\n", "- |\r\n"),
            ("  foo|\r\n", "  foo\n  |\r\n"),
            ("- a\r\n  b|\r\n", "- a\r\n  b\n- |\r\n"),
            ("1. a|\r\nnext\r\n", "1. a\n2. |\r\nnext\r\n"),
        ] as [(String, String)]
    )
    func crlf(marked: String, expected: String) {
        #expect(pressed(marked) == expected)
    }

    @Test("Offsets count UTF-16 units, so an emoji before the caret does not shift the edit")
    func emojiBeforeCaret() {
        #expect(pressed("- 😀|") == "- 😀\n- |")
        #expect(pressed("  😀|") == "  😀\n  |")
    }
}
