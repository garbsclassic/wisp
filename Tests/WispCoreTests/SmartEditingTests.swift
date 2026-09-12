import Foundation
import Testing

@testable import WispCore

@Suite("SmartEditing: horizontal rule")
struct HorizontalRuleTests {
    @Test("The trigger is exactly three dashes, whitespace allowed around it")
    func trigger() {
        #expect(SmartEditing.isHorizontalRuleTrigger("---"))
        #expect(SmartEditing.isHorizontalRuleTrigger("  ---  "))
        #expect(!SmartEditing.isHorizontalRuleTrigger("--"))
        #expect(!SmartEditing.isHorizontalRuleTrigger("----"))
        #expect(!SmartEditing.isHorizontalRuleTrigger("--- hello"))
        #expect(!SmartEditing.isHorizontalRuleTrigger("hello ---"))
        #expect(!SmartEditing.isHorizontalRuleTrigger(""))
    }

    @Test("The stored rule is markdown-standard")
    func constant() {
        #expect(SmartEditing.horizontalRule == "---")
    }

    /// The renderer's predicate is looser than the trigger: it also has to
    /// recognize lines already on disk, including the legacy `─` form.
    @Test(
        "A rendered rule line is three or more dashes or box-drawing dashes",
        arguments: [
            ("---", true),
            ("----", true),
            (String(repeating: "─", count: 40), true),
            ("---" + String(repeating: "─", count: 5), true),
            ("--", false),
            ("", false),
            ("---x", false),
            ("x---", false),
            ("-- -", false),
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
}

@Suite("SmartEditing: list continuation")
struct ListMarkerTests {
    @Test(
        "Unordered markers repeat",
        arguments: [("- foo", "- "), ("* foo", "* "), ("+ foo", "+ ")]
    )
    func unordered(line: String, marker: String) {
        #expect(SmartEditing.nextListMarker(for: line) == marker)
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

    /// An empty item is the signal to leave the list, so it returns "" —
    /// distinct from nil, which means "this was never a list".
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

    @Test("A numeric marker carries its leading indentation")
    func indentedNumeric() {
        #expect(SmartEditing.nextListMarker(for: "  3. foo") == "  4. ")
    }

    @Test(
        "Alphabetic markers carry their leading indentation, including at the end of the alphabet",
        arguments: [
            ("  B. foo", "  C. "),
            ("  y. foo", "  z. "),
            ("  Z. foo", nil),
            ("  z. foo", nil),
        ] as [(String, String?)]
    )
    func indentedAlphabetic(line: String, marker: String?) {
        #expect(SmartEditing.nextListMarker(for: line) == marker)
    }

    @Test("An indented empty item still yields the exit signal, indent and all")
    func indentedEmptyItemExits() {
        #expect(SmartEditing.nextListMarker(for: "  - ") == "")
        #expect(SmartEditing.nextListMarker(for: "\t2. ") == "")
    }

    @Test("Indentation alone does not make a line a list item")
    func indentationAloneIsNotAList() {
        #expect(SmartEditing.nextListMarker(for: "  foo") == nil)
    }
}

@Suite("SmartEditing: leading indent")
struct LeadingIndentTests {
    @Test(
        "Leading spaces and tabs are captured verbatim",
        arguments: [
            ("  foo", "  "),
            ("\tfoo", "\t"),
            (" \t foo", " \t "),
            ("foo", ""),
        ]
    )
    func indent(line: String, expected: String) {
        #expect(SmartEditing.leadingIndent(of: line) == expected)
    }

    @Test("A whitespace-only line returns the whole line")
    func wholeLineIsWhitespace() {
        #expect(SmartEditing.leadingIndent(of: "   ") == "   ")
    }

    @Test("An empty string has no leading indent")
    func empty() {
        #expect(SmartEditing.leadingIndent(of: "") == "")
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

    @Test("Ordered markers", arguments: ["1. item", "12. item", "A. item", "a. item"])
    func ordered(line: String) {
        #expect(parse(line)?.marker == .ordered)
    }

    @Test("The marker range covers the digits and the dot")
    func orderedMarkerRange() {
        #expect(parse("12. item")?.markerRange == NSRange(location: 0, length: 3))
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
    ])
    func rejected(line: String) {
        #expect(parse(line) == nil)
    }

    @Test("A horizontal rule is not a bullet whose content is dashes")
    func horizontalRule() {
        #expect(parse("---") == nil)
        #expect(parse("-----") == nil)
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
        // Never traps, however the depth was arrived at.
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
            // (line, cursor, expected content start)
            ("- item", 4, 2),  // mid-line
            ("- item", 0, 2),  // column 0
            ("- item", 1, 2),  // inside the marker's trailing whitespace
            ("1. item", 5, 3),  // ordered, mid-line
            ("1. item", 0, 3),  // ordered, column 0
            ("A. item", 0, 3),  // alphabetic ordered marker
            ("a. item", 0, 3),  // lowercase alphabetic ordered marker
            ("  - item", 6, 4),  // indented bullet, mid-line
            ("  - item", 0, 4),  // indented bullet, column 0 (before the indent)
            ("  - item", 2, 4),  // cursor sitting on the marker character itself
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

@Suite("SmartEditing: Enter before a list item's text")
struct NewlineBeforeItemTests {
    private func edit(_ text: String, cursor: Int) -> LineEdits.Edit? {
        SmartEditing.newlineBeforeItem(in: text as NSString, cursor: cursor)
    }

    private func applied(_ text: String, cursor: Int) -> (String, Int)? {
        guard let e = edit(text, cursor: cursor) else { return nil }
        let ns = NSMutableString(string: text)
        ns.replaceCharacters(in: e.range, with: e.replacement)
        return (ns as String, e.selection.location)
    }

    @Test(
        "Column 0, the indent, and the marker all move the item down intact",
        arguments: [
            ("- item", 0, "\n- item", 1),
            ("- item", 1, "\n- item", 1),
            ("  - item", 0, "\n  - item", 1),
            ("  - item", 2, "\n  - item", 1),
            ("  - item", 3, "\n  - item", 1),
            ("12. item", 2, "\n12. item", 1),
        ] as [(String, Int, String, Int)]
    )
    func beforeContent(text: String, cursor: Int, expected: String, caret: Int) {
        let result = applied(text, cursor: cursor)
        #expect(result?.0 == expected)
        #expect(result?.1 == caret)
    }

    @Test("At content start and beyond, the ordinary continuation applies")
    func atOrPastContent() {
        #expect(edit("- item", cursor: 2) == nil)
        #expect(edit("- item", cursor: 4) == nil)
    }

    @Test("Non-list lines yield nil", arguments: ["plain", "-word", "", "  indented"])
    func nonList(line: String) {
        #expect(edit(line, cursor: 0) == nil)
    }

    @Test("An empty item at column 0 moves down too, rather than being stripped")
    func emptyItem() {
        #expect(applied("- ", cursor: 0)?.0 == "\n- ")
    }

    @Test("Offsets are document-absolute on a later line")
    func laterLine() {
        let result = applied("para\n- item\n", cursor: 5)
        #expect(result?.0 == "para\n\n- item\n")
        #expect(result?.1 == 6)
    }
}

@Suite("SmartEditing: next list marker")
struct NextListMarkerTests {
    @Test("A task's next box is always unchecked, whichever way this one goes")
    func taskAlwaysUnchecked() {
        #expect(SmartEditing.nextListMarker(for: "- [ ] foo") == "- [ ] ")
        #expect(SmartEditing.nextListMarker(for: "- [x] foo") == "- [ ] ")
        #expect(SmartEditing.nextListMarker(for: "  * [X] foo") == "  * [ ] ")
    }

    @Test("An empty task line signals exit rather than continuing")
    func emptyTaskExits() {
        #expect(SmartEditing.nextListMarker(for: "- [ ] ") == "")
    }

    @Test("A box with nothing after it is a bullet whose content is the box")
    func unfinishedBoxIsPlainBullet() {
        #expect(SmartEditing.nextListMarker(for: "- [ ]") == "- ")
    }
}

@Suite("SmartEditing: task items")
struct TaskListItemTests {
    private func parse(_ line: String) -> SmartEditing.ListItem? {
        let ns = line as NSString
        return SmartEditing.listItem(
            lineRange: NSRange(location: 0, length: ns.length), in: ns)
    }

    @Test("An unchecked task")
    func unchecked() {
        let item = parse("- [ ] foo")
        #expect(item?.marker == .task(checked: false))
        #expect(item?.markerRange == NSRange(location: 0, length: 5))
        #expect(item?.contentStart == 6)
        #expect(item?.indentWidth == 0)
    }

    @Test("An indented, checked task")
    func indentedChecked() {
        let item = parse("  - [x] foo")
        #expect(item?.marker == .task(checked: true))
        #expect(item?.markerRange == NSRange(location: 2, length: 5))
        #expect(item?.contentStart == 8)
        #expect(item?.indentWidth == 2)
    }

    @Test("An uppercase X checks the box too")
    func uppercaseChecked() {
        #expect(parse("- [X] foo")?.marker == .task(checked: true))
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

    @Test("An invalid box character is not a task")
    func invalidBoxCharacter() {
        #expect(parse("- [y] foo")?.marker == .bullet)
    }

    @Test("Only bullets get boxes — an ordered marker with brackets is still ordered")
    func orderedWithBracketsStaysOrdered() {
        #expect(parse("1. [ ] foo")?.marker == .ordered)
    }

    @Test("The task state index is the character inside the box")
    func taskStateIndex() {
        #expect(parse("- [x] foo")?.taskStateIndex == 3)
        #expect(parse("- foo")?.taskStateIndex == nil)
    }

    @Test("isTask is true only for the task case")
    func isTask() {
        #expect(parse("- [ ] foo")?.marker.isTask == true)
        #expect(parse("- foo")?.marker.isTask == false)
        #expect(parse("1. foo")?.marker.isTask == false)
    }

    @Test("A task's glyph comes from SmartEditing.taskGlyph, unaffected by depth")
    func glyph() {
        #expect(parse("- [ ] foo")?.glyph(indentWidth: 2) == SmartEditing.taskGlyph(checked: false))
        #expect(parse("- [x] foo")?.glyph(indentWidth: 2) == SmartEditing.taskGlyph(checked: true))
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

    @Test("A task's whole marker, box included, is removed")
    func task() {
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

@Suite("SmartEditing: outdented empty item")
struct OutdentedEmptyItemTests {
    @Test("A four-space indent under a two-space unit drops one level")
    func fourUnderTwo() {
        #expect(SmartEditing.outdentedEmptyItem("    - ", unit: "  ") == "  - ")
    }

    @Test("A two-space indent under a two-space unit reaches the margin")
    func twoUnderTwo() {
        #expect(SmartEditing.outdentedEmptyItem("  - ", unit: "  ") == "- ")
    }

    @Test("A flush-left item has nothing left to outdent")
    func flushLeft() {
        #expect(SmartEditing.outdentedEmptyItem("- ", unit: "  ") == nil)
    }

    @Test("A leading tab is removed whole, regardless of the configured unit")
    func leadingTab() {
        #expect(SmartEditing.outdentedEmptyItem("\t- ", unit: "\t") == "- ")
    }

    @Test("Only one tab comes off a doubly-nested tab-indented item")
    func onlyOneTabComesOff() {
        #expect(SmartEditing.outdentedEmptyItem("\t\t1. ", unit: "\t") == "\t1. ")
    }

    @Test("Fewer spaces than the unit removes only what is actually there")
    func fewerSpacesThanUnit() {
        #expect(SmartEditing.outdentedEmptyItem(" - ", unit: "  ") == "- ")
    }

    @Test("More spaces than the unit removes only the unit's width")
    func moreSpacesThanUnit() {
        #expect(SmartEditing.outdentedEmptyItem("  - ", unit: "    ") == "- ")
    }
}

@Suite("SmartEditing: continuation line")
struct ContinuationLineTests {
    private func line(_ text: String, cursor: Int) -> String? {
        SmartEditing.continuationLine(in: text as NSString, cursor: cursor)
    }

    @Test("A flush bullet pads out to the content column")
    func flushBullet() {
        #expect(line("- item", cursor: 6) == "\n  ")
    }

    @Test("At content start, the same padding applies")
    func atContentStart() {
        #expect(line("- item", cursor: 2) == "\n  ")
    }

    @Test("Before the content, this is not the edit")
    func beforeContent() {
        #expect(line("- item", cursor: 1) == nil)
    }

    @Test("An indented bullet's indent is copied, then padded for the marker")
    func indentedBullet() {
        #expect(line("  - item", cursor: 8) == "\n    ")
    }

    @Test("A tab indent is copied verbatim, only the marker's width is spaces")
    func tabIndent() {
        #expect(line("\t- item", cursor: 7) == "\n\t  ")
    }

    @Test("A two-digit ordered marker pads to its own width")
    func orderedMarker() {
        #expect(line("12. item", cursor: 8) == "\n    ")
    }

    @Test("A task's box counts toward the padding width")
    func taskMarker() {
        #expect(line("- [ ] item", cursor: 10) == "\n      ")
    }

    @Test("A non-list line yields nil")
    func nonList() {
        #expect(line("plain text", cursor: 3) == nil)
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

    @Test("A whitespace-only line is not a continuation")
    func whitespaceOnly() {
        #expect(!check("- item\n  \n"))
    }
}

@Suite("SmartEditing: toggled task")
struct ToggledTaskTests {
    private func toggled(_ text: String, at index: Int, selection: NSRange = NSRange(location: 0, length: 0)) -> (String, NSRange)? {
        guard let e = SmartEditing.toggledTask(in: text as NSString, lineAt: index, selection: selection)
        else { return nil }
        let ns = NSMutableString(string: text)
        ns.replaceCharacters(in: e.range, with: e.replacement)
        return (ns as String, e.selection)
    }

    @Test("Checking an unchecked task")
    func check() {
        #expect(toggled("- [ ] a", at: 0)?.0 == "- [x] a")
    }

    @Test("Unchecking a checked task")
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
