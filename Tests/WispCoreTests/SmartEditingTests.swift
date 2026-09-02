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
