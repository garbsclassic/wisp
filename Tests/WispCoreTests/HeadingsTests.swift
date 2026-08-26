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
