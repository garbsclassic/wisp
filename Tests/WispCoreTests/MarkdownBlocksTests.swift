import Foundation
import Testing

@testable import WispCore

@Suite("MarkdownBlocks: line kinds")
struct MarkdownBlocksKindTests {
    private func kind(_ text: String, at offset: Int) -> MarkdownBlocks.Kind? {
        let ns = text as NSString
        return MarkdownBlocks(ns).line(at: offset)?.kind
    }

    @Test("A blank line is .blank")
    func blank() {
        #expect(kind("\n", at: 0) == .blank)
    }

    @Test("A fresh paragraph line carries its own start as paragraphStart")
    func freshParagraphText() {
        #expect(kind("para", at: 0) == .text(paragraphStart: 0))
    }

    @Test("Text directly under a list item is an owned continuation, paragraphStart nil")
    func ownedTextAfterListItem() {
        let text = "- item\nmore"
        let offset = ("- item\n" as NSString).length
        #expect(kind(text, at: offset) == .text(paragraphStart: nil))
    }

    @Test("A dash-marked line is .listItem")
    func listItem() {
        #expect(kind("- item", at: 0) == .listItem)
    }

    @Test("A `>`-led line is .quote")
    func quote() {
        #expect(kind("> hi", at: 0) == .quote)
    }

    @Test("A `|`-led line is .tableRow")
    func tableRow() {
        #expect(kind("| a | b |", at: 0) == .tableRow)
    }

    @Test("A `#` line is .heading, carrying the hash count as its level")
    func heading() {
        #expect(kind("## Title", at: 0) == .heading(level: 2))
    }

    @Test("`---` under paragraph text is .setextUnderline, carrying the paragraph's start")
    func setextUnderline() {
        let text = "Text\n---"
        let offset = ("Text\n" as NSString).length
        #expect(kind(text, at: offset) == .setextUnderline(level: 2, paragraphStart: 0))
    }

    @Test("`---` with no paragraph open above it is .rule")
    func rule() {
        #expect(kind("---", at: 0) == .rule)
    }

    @Test("An opening ``` line is .fence, distinct from the .fencedCode line it opens")
    func fenceVersusFencedCode() {
        let text = "```\ncode\n```"
        let openOffset = 0
        let codeOffset = ("```\n" as NSString).length
        let closeOffset = ("```\ncode\n" as NSString).length
        #expect(kind(text, at: openOffset) == .fence)
        #expect(kind(text, at: codeOffset) == .fencedCode)
        #expect(kind(text, at: closeOffset) == .fence)
    }

    @Test("A four-space line with no paragraph open above it is .indentedCode")
    func indentedCodeWithNoOpenParagraph() {
        #expect(kind("    code", at: 0) == .indentedCode)
    }
}

@Suite("MarkdownBlocks: line(at:)")
struct MarkdownBlocksLineAtTests {
    @Test("line(at:) finds the first and last offset of a line, and nil past the end")
    func firstLastAndPastEnd() {
        let ns = "a\nbcd" as NSString
        let blocks = MarkdownBlocks(ns)
        let firstLine = blocks.line(at: 0)
        let secondLine = blocks.line(at: 2)

        #expect(firstLine?.range == NSRange(location: 0, length: 2))
        #expect(blocks.line(at: 1)?.range == firstLine?.range)
        #expect(secondLine?.range == NSRange(location: 2, length: 3))
        #expect(blocks.line(at: 4)?.range == secondLine?.range)
        #expect(blocks.line(at: 5) == nil)
    }
}

@Suite("MarkdownBlocks: frontmatter")
struct MarkdownBlocksFrontmatterTests {
    @Test("Frontmatter is stripped from heading extraction, and its closing `---` isn't a rule")
    func frontmatterExcludesHeadingsAndItsCloserIsntARule() {
        let text = """
            ---
            title: Groceries
            tags: [home]
            ---

            # Real heading
            """
        let ns = text as NSString
        let blocks = MarkdownBlocks(ns)

        #expect(text.extractHeadings().map(\.name) == ["Real heading"])

        let closingDashesOffset = ("---\ntitle: Groceries\ntags: [home]\n" as NSString).length
        #expect(blocks.line(at: 0)?.kind == .frontmatter)
        #expect(blocks.line(at: closingDashesOffset)?.kind == .frontmatter)
    }

    @Test("`---` immediately followed by a closing `---` is frontmatter")
    func minimalFrontmatter() {
        let ns = "---\n---" as NSString
        let blocks = MarkdownBlocks(ns)
        #expect(blocks.line(at: 0)?.kind == .frontmatter)
        #expect(blocks.line(at: 4)?.kind == .frontmatter)
    }

    @Test("A `---` first line with no closing `---` isn't frontmatter")
    func unclosedFirstLineIsntFrontmatter() {
        let ns = "---\ntitle: Groceries\ntags: [home]" as NSString
        #expect(MarkdownBlocks(ns).line(at: 0)?.kind != .frontmatter)
    }

    @Test("A YAML `...` doesn't close frontmatter: the `---` is a rule, and later headings parse")
    func ellipsisDoesNotCloseFrontmatter() {
        let text = "---\nthinking about it\n...\n# H"
        let ns = text as NSString
        #expect(MarkdownBlocks(ns).line(at: 0)?.kind == .rule)
        #expect(text.extractHeadings().map(\.name) == ["H"])
    }

    @Test("A `---` pair not on the note's first line isn't frontmatter")
    func notOnFirstLineIsntFrontmatter() {
        let text = "\n---\ntitle\n---"
        let ns = text as NSString
        let blocks = MarkdownBlocks(ns)
        let firstDashesOffset = ("\n" as NSString).length
        #expect(blocks.line(at: firstDashesOffset)?.kind == .rule)

        let headings = text.extractHeadings()
        #expect(headings.map(\.name) == ["title"])
        #expect(headings.map(\.level) == [2])
    }
}

@Suite("MarkdownBlocks: inline triple backticks")
struct MarkdownBlocksInlineBackticksTests {
    @Test("Backticks with a closing run later on the line are inline code, not a fence opener")
    func inlineBackticksAreNotAFenceOpener() {
        let text = "```ls -la``` lists files\n# Later\n\n---\n## Another"
        let headings = text.extractHeadings()
        #expect(headings.map(\.name) == ["Later", "Another"])

        let ns = text as NSString
        let dashesOffset = ("```ls -la``` lists files\n# Later\n\n" as NSString).length
        #expect(MarkdownBlocks(ns).line(at: dashesOffset)?.kind == .rule)
    }

    @Test("A genuine fenced code block with an info string still opens and closes as a fence")
    func infoStringFenceStillFences() {
        let text = "```swift\ncode\n```"
        let ns = text as NSString
        let blocks = MarkdownBlocks(ns)
        #expect(blocks.line(at: 0)?.kind == .fence)
        let codeOffset = ("```swift\n" as NSString).length
        #expect(blocks.line(at: codeOffset)?.kind == .fencedCode)
        let closeOffset = ("```swift\ncode\n" as NSString).length
        #expect(blocks.line(at: closeOffset)?.kind == .fence)
    }
}

@Suite("MarkdownBlocks: setext heading after a closing fence")
struct MarkdownBlocksSetextAfterFenceTests {
    @Test("A paragraph and underline after a closed fence still form a setext heading")
    func setextHeadingAfterClosingFence() {
        let text = "```\ncode\n```\nPara\n---"
        let headings = text.extractHeadings()
        #expect(headings.count == 1)
        #expect(headings[0].name == "Para")
        #expect(headings[0].level == 2)
    }
}

@Suite("MarkdownBlocks: runs of setext underlines")
struct MarkdownBlocksSetextRunTests {
    /// Guards against the old per-line walk, which was exponential on a run of `===` and took
    /// minutes at 30 lines.
    @Test("Forty lines of `==========` give twenty level-1 headings", .timeLimit(.minutes(1)))
    func fortyEqualsLinesGiveTwentyHeadings() {
        let line = String(repeating: "=", count: 10)
        let text = Array(repeating: line, count: 40).joined(separator: "\n")
        let headings = text.extractHeadings()
        #expect(headings.count == 20)
        #expect(headings.allSatisfy { $0.level == 1 })
    }
}

@Suite("MarkdownBlocks: scale")
struct MarkdownBlocksScaleTests {
    /// A correctness check, not a timing assertion — the time limit only guards against a
    /// regression back to the old quadratic-or-worse per-line scan.
    @Test("A ~3000-line note of headings, lists, fences, and rules gives the expected count",
        .timeLimit(.minutes(1)))
    func largeNoteHeadingCount() {
        let iterations = 250
        var lines: [String] = []
        for i in 0..<iterations {
            lines += [
                "# Heading \(i)",
                "",
                "- item \(i)",
                "",
                "para \(i)",
                "---",
                "",
                "```",
                "code \(i)",
                "```",
                "---",
                "",
            ]
        }
        #expect(lines.count == 3000)

        let text = lines.joined(separator: "\n")
        let headings = text.extractHeadings()
        #expect(headings.count == 500)
        #expect(headings.filter { $0.level == 1 }.count == 250)
        #expect(headings.filter { $0.level == 2 }.count == 250)
        #expect(headings.first?.name == "Heading 0")
        #expect(headings.last?.name == "para 249")
    }
}

@Suite("MarkdownBlocks: CRLF line endings")
struct MarkdownBlocksCRLFTests {
    private func kind(_ text: String, at offset: Int) -> MarkdownBlocks.Kind? {
        let ns = text as NSString
        return MarkdownBlocks(ns).line(at: offset)?.kind
    }

    @Test("Text, a blank line, and a rule classify the same under CRLF as under LF")
    func textBlankAndRuleUnderCRLF() {
        let text = "a\r\n\r\n---\r\n"
        #expect(kind(text, at: 0) == .text(paragraphStart: 0))
        #expect(kind(text, at: ("a\r\n" as NSString).length) == .blank)
        #expect(kind(text, at: ("a\r\n\r\n" as NSString).length) == .rule)
    }

    @Test("A `\\r\\n`-closed fence still closes, so the heading after it is found")
    func fenceClosesUnderCRLF() {
        let text = "```\r\ncode\r\n```\r\n# After\r\n"
        #expect(text.extractHeadings().map(\.name) == ["After"])
    }

    @Test("Frontmatter under CRLF is stripped the same as under LF")
    func frontmatterUnderCRLF() {
        let text = "---\r\ntitle: Groceries\r\n---\r\n\r\n# Real heading\r\n"
        let ns = text as NSString
        #expect(MarkdownBlocks(ns).line(at: 0)?.kind == .frontmatter)
        #expect(text.extractHeadings().map(\.name) == ["Real heading"])
    }

    @Test("A setext underline's marker length excludes the `\\r`, under CRLF")
    func setextMarkerLengthExcludesCR() throws {
        let h = try #require("Para\r\n---\r\n".extractHeadings().first)
        #expect(h.level == 2)
        #expect(h.name == "Para")
        #expect(h.marker.length == 3)
    }

    @Test("A heading's name and end exclude a trailing `\\r`")
    func headingNameAndEndExcludeCR() throws {
        let text = "# After\r\nbody\r\n"
        let h = try #require(text.extractHeadings().first)
        #expect(h.name == "After")
        #expect(h.end == ("# After" as NSString).length)
    }
}

@Suite("MarkdownBlocks: indented fences")
struct MarkdownBlocksIndentedFenceTests {
    private func kind(_ text: String, at offset: Int) -> MarkdownBlocks.Kind? {
        let ns = text as NSString
        return MarkdownBlocks(ns).line(at: offset)?.kind
    }

    @Test(
        "A fence indented with a tab or four spaces opens and closes, and hides what's inside",
        arguments: ["\t", "    "]
    )
    func indentedFence(indent: String) {
        let text = "\(indent)```\n# not\n---\n\(indent)```\n# yes"
        let codeOffset = ("\(indent)```\n" as NSString).length
        let closeOffset = ("\(indent)```\n# not\n---\n" as NSString).length
        #expect(kind(text, at: 0) == .fence)
        #expect(kind(text, at: codeOffset) == .fencedCode)
        #expect(kind(text, at: closeOffset) == .fence)
        #expect(text.extractHeadings().map(\.name) == ["yes"])
    }

    @Test("A tab-indented closer closes a flush opener")
    func tabIndentedCloser() {
        let text = "```\ncode\n\t```\n# after"
        #expect(text.extractHeadings().map(\.name) == ["after"])
    }

    @Test("An item's indented text after its nested fence stays the item's, so `---` is a rule")
    func listStaysOpenAcrossNestedFence() {
        let text = "- item\n\t```\n\tcode\n\t```\n\tmore\n---"
        let moreOffset = ("- item\n\t```\n\tcode\n\t```\n" as NSString).length
        let ruleOffset = ("- item\n\t```\n\tcode\n\t```\n\tmore\n" as NSString).length
        #expect(kind(text, at: moreOffset) == .text(paragraphStart: nil))
        #expect(kind(text, at: ruleOffset) == .rule)
    }

    @Test("A tab-indented line that isn't a fence is still indented code")
    func tabIndentedTextIsIndentedCode() {
        #expect(kind("\tcode", at: 0) == .indentedCode)
    }
}

@Suite("MarkdownBlocks: loose lists")
struct MarkdownBlocksLooseListTests {
    private func kind(_ text: String, at offset: Int) -> MarkdownBlocks.Kind? {
        let ns = text as NSString
        return MarkdownBlocks(ns).line(at: offset)?.kind
    }

    @Test("An indented line after a blank stays owned list text, not indented code")
    func indentedLineAfterBlankStaysOwnedText() {
        let text = "- item\n\n    code-looking\n---"
        let offset = ("- item\n\n" as NSString).length
        #expect(kind(text, at: offset) == .text(paragraphStart: nil))
    }

    @Test("A rule after an item's loose continuation is still a rule, not a setext underline")
    func ruleAfterLooseContinuationStaysARule() {
        let text = "- item\n\n  more text for the item\n---"
        let offset = ("- item\n\n  more text for the item\n" as NSString).length
        #expect(kind(text, at: offset) == .rule)
    }
}
