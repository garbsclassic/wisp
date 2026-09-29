import Foundation
import Testing

@testable import WispCore

@Suite("Headings parser")
struct HeadingsTests {
    @Test("Text with no headings yields none", arguments: ["", "hello world\nno headings"])
    func none(text: String) {
        #expect(text.extractHeadings().isEmpty)
    }

    @Test("A single heading carries name, level, and offset")
    func single() throws {
        let h = try #require("# Hello".extractHeadings().first)
        #expect(h.name == "Hello")
        #expect(h.level == 1)
        #expect(h.lineStart == 0)
    }

    @Test("Nesting levels come back in document order")
    func nested() {
        let nested = "# A\n## B\n### C".extractHeadings()
        #expect(nested.map(\.level) == [1, 2, 3])
        #expect(nested.map(\.name) == ["A", "B", "C"])
    }

    /// A `#` with no space is a tag, not a heading, and a heading with no
    /// title has nothing to navigate to.
    @Test("Malformed headings are skipped", arguments: ["#NoSpace", "# ", "##  "])
    func malformed(text: String) {
        #expect(text.extractHeadings().isEmpty)
    }

    @Test("Headings are picked out from surrounding prose")
    func mixedWithProse() {
        let mixed = """
            # First
            some prose
            ## Second
            more prose
            # Third
            """.extractHeadings()
        #expect(mixed.map(\.name) == ["First", "Second", "Third"])
        #expect(mixed.map(\.level) == [1, 2, 1])
    }

    @Test("Six hashes is the deepest level")
    func sixLevels() throws {
        let h = try #require("###### Six".extractHeadings().first)
        #expect(h.level == 6)
        #expect(h.name == "Six")
    }

    /// `id` is the line offset, so repeated titles still address distinct
    /// rows in the jump list.
    @Test("Duplicate titles keep distinct ids")
    func duplicateTitles() {
        let dupes = "# A\n# B\n# C".extractHeadings()
        #expect(Set(dupes.map(\.id)).count == 3)
    }
}

@Suite("Headings parser — setext headings")
struct SetextHeadingsTests {
    @Test("A paragraph underlined with `---` becomes a level-2 heading spanning both lines")
    func singleLineParagraph() {
        let text = "Text\n---"
        let headings = text.extractHeadings()
        #expect(headings.count == 1)
        #expect(headings[0].level == 2)
        #expect(headings[0].name == "Text")
        #expect(headings[0].lineStart == 0)
        #expect(headings[0].end == (text as NSString).length)
    }

    @Test(
        "A rule with nothing plain above it to underline yields no heading",
        arguments: ["---", "\n---"]
    )
    func ruleAloneYieldsNoHeading(text: String) {
        #expect(text.extractHeadings().isEmpty)
    }

    @Test("A rule below a heading yields only the ATX heading, not a second one")
    func ruleBelowHeadingYieldsOnlyTheATXHeading() {
        let headings = "# H\n---".extractHeadings()
        #expect(headings.count == 1)
        #expect(headings[0].name == "H")
        #expect(headings[0].level == 1)
    }

    @Test("Two rule lines in a row yield no heading")
    func twoRuleLinesYieldNoHeading() {
        #expect("---\n---".extractHeadings().isEmpty)
    }

    @Test(
        "A rule under a list item, quote, table row, fence, or indented code yields no heading",
        arguments: [
            "- item\n---",
            "- [ ] checklist\n---",
            "1. one\n---",
            "> quote\n---",
            "| a | b |\n---",
            "```\n---",
            "~~~\n---",
            "    code\n---",
        ]
    )
    func ruleUnderNonParagraphBlockYieldsNoHeading(text: String) {
        #expect(text.extractHeadings().isEmpty)
    }

    @Test("A rule inside an unclosed fence yields no heading, even with paragraph text above it")
    func ruleInsideUnclosedFenceYieldsNoHeading() {
        #expect("```\nText\n---".extractHeadings().isEmpty)
    }

    @Test(
        "A rule under a list item's continuation or lazy line yields no heading",
        arguments: ["- item\n  more\n---", "- item\nlazy\n---"]
    )
    func ruleUnderListContinuationYieldsNoHeading(text: String) {
        #expect(text.extractHeadings().isEmpty)
    }

    @Test("A multi-line paragraph's heading name joins its lines with a single space each")
    func multiLineParagraphName() {
        let headings = "one\ntwo\n---".extractHeadings()
        #expect(headings.count == 1)
        #expect(headings[0].name == "one two")
        #expect(headings[0].lineStart == 0)
    }

    @Test("A blank line breaks the paragraph, so the heading starts after it")
    func blankLineBreaksParagraph() {
        let text = "para\n\none\ntwo\n---"
        let headings = text.extractHeadings()
        #expect(headings.count == 1)
        #expect(headings[0].name == "one two")
        #expect(headings[0].lineStart == ("para\n\n" as NSString).length)
    }

    @Test("A box-drawing dash underline is plain text, not a heading underline")
    func boxDrawingUnderlineYieldsNoHeading() {
        #expect("Text\n───".extractHeadings().isEmpty)
    }

    @Test("Two dashes are too short to underline a heading")
    func twoDashesYieldsNoHeading() {
        #expect("Text\n--".extractHeadings().isEmpty)
    }

    @Test(
        "A paragraph underlined with `===` becomes a level-1 heading",
        arguments: ["Text\n===", "Text\n=== ", "Text\n   ==="]
    )
    func levelOneUnderline(text: String) {
        let headings = text.extractHeadings()
        #expect(headings.count == 1)
        #expect(headings[0].level == 1)
        #expect(headings[0].name == "Text")
    }

    @Test("Two equals signs neither underline a heading nor form a rule")
    func twoEqualsYieldsNoHeading() {
        #expect("Text\n==".extractHeadings().isEmpty)
    }

    @Test("Equals signs with nothing plain above them yield no heading")
    func equalsAloneYieldsNoHeading() {
        #expect("===".extractHeadings().isEmpty)
    }

    @Test("A level-1 heading directly followed by another paragraph and underline stays distinct")
    func consecutiveSetextHeadingsStayDistinct() {
        let headings = "Title\n===\nfoo\n---".extractHeadings()
        #expect(headings.map(\.name) == ["Title", "foo"])
        #expect(headings.map(\.level) == [1, 2])
    }

    @Test("A `===` line with nothing plain above it is paragraph text, not an underline")
    func leadingEqualsLineIsParagraphTextNotUnderline() {
        let text = "\n===\nfoo\n---"
        let headings = text.extractHeadings()
        #expect(headings.count == 1)
        #expect(headings[0].name == "=== foo")
        #expect(headings[0].level == 2)
        #expect(headings[0].lineStart == ("\n" as NSString).length)
    }

    @Test("Offsets are correct, and document order holds, when ATX and setext headings are mixed")
    func mixedATXAndSetextOrder() {
        let text = "# ATX\n\nPara\n---\n\n## Second"
        let headings = text.extractHeadings()
        #expect(headings.map(\.name) == ["ATX", "Para", "Second"])
        #expect(headings.map(\.level) == [1, 2, 2])
        #expect(headings[1].lineStart == ("# ATX\n\n" as NSString).length)
        #expect(headings[1].end == ("# ATX\n\nPara\n---" as NSString).length)
    }
}

@Suite("Headings — indented ATX headings")
struct HeadingsIndentedATXTests {
    @Test("Up to three leading spaces still make a `#` line a heading")
    func upToThreeLeadingSpacesIsStillAHeading() throws {
        let h = try #require("   # Title".extractHeadings().first)
        #expect(h.level == 1)
        #expect(h.name == "Title")
        #expect(h.marker == NSRange(location: 3, length: 1))
    }

    @Test("Four leading spaces makes a `#` line indented code, not a heading")
    func fourLeadingSpacesIsNotAHeading() {
        #expect("    # code".extractHeadings().isEmpty)
    }
}

@Suite("Headings — marker range")
struct HeadingMarkerTests {
    @Test("An ATX marker covers just the `#` run")
    func atxMarkerCoversHashRun() throws {
        let h = try #require("# Hello".extractHeadings().first)
        #expect(h.marker == NSRange(location: 0, length: 1))
    }

    @Test("A deeper ATX marker covers all of its hashes")
    func deeperAtxMarkerCoversAllHashes() throws {
        let h = try #require("## Two".extractHeadings().first)
        #expect(h.marker == NSRange(location: 0, length: 2))
    }

    @Test("An ATX marker not at offset 0 still starts at its own line")
    func atxMarkerNotAtOffsetZero() throws {
        let text = "prose\n### Deep"
        let h = try #require(text.extractHeadings().first)
        let lineStart = ("prose\n" as NSString).length
        #expect(h.marker == NSRange(location: lineStart, length: 3))
    }

    @Test("A setext `===` marker covers the whole underline line, without the newline")
    func setextLevelOneMarkerCoversWholeUnderline() throws {
        let h = try #require("Text\n===".extractHeadings().first)
        let underlineStart = ("Text\n" as NSString).length
        #expect(h.marker == NSRange(location: underlineStart, length: 3))
    }

    @Test("A setext `---` marker covers the whole underline line, without the newline")
    func setextLevelTwoMarkerCoversWholeUnderline() throws {
        let h = try #require("Text\n---".extractHeadings().first)
        let underlineStart = ("Text\n" as NSString).length
        #expect(h.marker == NSRange(location: underlineStart, length: 3))
    }

    @Test("A setext marker not at offset 0 covers only the underline, not the paragraph above it")
    func setextMarkerNotAtOffsetZero() throws {
        let text = "para\n\nText\n---"
        let h = try #require(text.extractHeadings().first)
        let underlineStart = ("para\n\nText\n" as NSString).length
        #expect(h.marker == NSRange(location: underlineStart, length: 3))
    }
}

@Suite("Headings parser — fenced code blocks")
struct HeadingsFencedCodeBlockTests {
    @Test(
        "An ATX-shaped line inside a fenced code block is not a heading",
        arguments: ["```\n# comment\n```", "~~~\n# comment\n~~~"]
    )
    func atxShapedLineInsideFenceYieldsNoHeading(text: String) {
        #expect(text.extractHeadings().isEmpty)
    }

    @Test("A heading after a closed fence with an info string is still found")
    func headingAfterClosedFenceWithInfoStringIsFound() throws {
        let text = "```bash\n# comment\n```\n# Real"
        let headings = text.extractHeadings()
        #expect(headings.count == 1)
        #expect(headings[0].name == "Real")
        #expect(headings[0].level == 1)
        let lineStart = ("```bash\n# comment\n```\n" as NSString).length
        #expect(headings[0].lineStart == lineStart)
    }

    @Test("A heading before a fence is kept while one inside it is dropped")
    func headingBeforeFenceIsKeptWhileOneInsideIsDropped() {
        let headings = "# Title\n```\n# comment\n```".extractHeadings()
        #expect(headings.map(\.name) == ["Title"])
    }

    @Test("An unclosed fence swallows every ATX-shaped line to the end of the note")
    func unclosedFenceYieldsNoHeadings() {
        #expect("```\n# a\n# b".extractHeadings().isEmpty)
    }

    @Test("A tilde line doesn't close a backtick fence, so the heading after it is what counts")
    func tildeLineDoesNotCloseBacktickFence() {
        let headings = "```\n~~~\n# inside\n```\n# after".extractHeadings()
        #expect(headings.map(\.name) == ["after"])
    }

    @Test("A setext heading before a fence is kept while an ATX line inside it is dropped")
    func setextHeadingBeforeFenceIsKeptWhileAtxLineInsideIsDropped() {
        let headings = "Para\n---\n```\n# code\n```".extractHeadings()
        #expect(headings.count == 1)
        #expect(headings[0].name == "Para")
        #expect(headings[0].level == 2)
    }
}

@Suite("Headings — before and after")
struct HeadingsNavigationTests {
    @Test("From a line between two headings, both neighbours are found")
    func betweenTwoHeadings() {
        let text = "# A\nprose\n## B\nmore prose\n### C"
        let headings = text.extractHeadings()
        // "more prose" starts right after "## B\n".
        let lineStart = ("# A\nprose\n## B\n" as NSString).length
        #expect(headings.heading(before: lineStart)?.name == "B")
        #expect(headings.heading(after: lineStart)?.name == "C")
    }

    @Test("From a heading's own line start, before is the previous heading, not itself")
    func ownLineStartLooksPastItself() throws {
        let text = "# A\n## B\n### C"
        let headings = text.extractHeadings()
        let b = try #require(headings.first { $0.name == "B" })
        #expect(headings.heading(before: b.lineStart)?.name == "A")
        #expect(headings.heading(after: b.lineStart)?.name == "C")
    }

    @Test("Before the first heading there is nothing above")
    func nilBeforeFirst() {
        let text = "# A\n## B"
        let headings = text.extractHeadings()
        let a = headings[0]
        #expect(headings.heading(before: a.lineStart) == nil)
    }

    @Test("After the last heading there is nothing below")
    func nilAfterLast() {
        let text = "# A\n## B"
        let headings = text.extractHeadings()
        let b = headings[1]
        #expect(headings.heading(after: b.lineStart) == nil)
    }

    @Test("Every level is a valid target, including a level-three heading")
    func everyLevelCounts() {
        let text = "# A\n## B\n### C\nprose"
        let headings = text.extractHeadings()
        let lineStart = ("# A\n## B\n### C\n" as NSString).length
        #expect(headings.heading(before: lineStart)?.name == "C")
        #expect(headings.heading(before: lineStart)?.level == 3)
    }

    /// `heading(before:)` from anywhere inside a setext heading, its underline included, skips
    /// that heading itself and lands on the ATX one above it.
    @Test("Before, from a setext heading's paragraph, underline, or the line after, and after")
    func aroundASetextHeading() {
        let text = "# A\nPara\n---\nbody"
        let headings = text.extractHeadings()

        let underlineStart = ("# A\nPara\n" as NSString).length
        let paraStart = ("# A\n" as NSString).length
        let bodyStart = ("# A\nPara\n---\n" as NSString).length
        #expect(headings.heading(before: underlineStart)?.name == "A")
        #expect(headings.heading(before: paraStart)?.name == "A")
        #expect(headings.heading(before: bodyStart)?.name == "Para")
        #expect(headings.heading(after: 0)?.name == "Para")
    }
}

@Suite("Headings — loose lists")
struct HeadingsLooseListTests {
    @Test(
        "A rule under a loose list item's indented continuation yields no heading",
        arguments: [
            "- item\n\n  more text for the item\n---",
            "- item\n\n    code-looking\n---",
        ]
    )
    func ruleUnderLooseContinuationYieldsNoHeading(text: String) {
        #expect(text.extractHeadings().isEmpty)
    }

    @Test("A flush-left paragraph after the blank ends the list, so its underline is a heading")
    func flushParagraphAfterBlankEndsListAndUnderlines() {
        let headings = "- item\n\nPara\n---".extractHeadings()
        #expect(headings.map(\.name) == ["Para"])
        #expect(headings.map(\.level) == [2])
    }

    @Test("Without a preceding list, an indented paragraph still underlines as a heading")
    func indentedParagraphWithoutAListStillUnderlines() {
        let headings = "Para\n\n  indented\n---".extractHeadings()
        #expect(headings.map(\.name) == ["indented"])
        #expect(headings.map(\.level) == [2])
    }
}
