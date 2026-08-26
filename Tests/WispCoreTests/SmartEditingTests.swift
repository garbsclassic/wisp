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
