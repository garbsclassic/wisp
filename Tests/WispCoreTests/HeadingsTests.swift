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
}
