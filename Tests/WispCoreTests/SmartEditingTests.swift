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
