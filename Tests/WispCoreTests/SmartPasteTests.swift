import Foundation
import Testing

@testable import WispCore

@Suite("SmartPaste: format")
struct SmartPasteFormatTests {
    /// Columns narrower than three characters are still padded to three, so
    /// the divider never shrinks below a readable width.
    @Test("A tab-separated grid becomes a pipe table, columns padded to a minimum of three")
    func tableFromTabs() {
        #expect(
            SmartPaste.format("a\tb\nc\td\n")
                == "| a   | b   |\n| --- | --- |\n| c   | d   |")
    }

    @Test("Cells are trimmed and padded to the column's widest cell")
    func tableCellsPaddedAndTrimmed() {
        #expect(
            SmartPaste.format(" a \t bb \n ccc \t d \n")
                == "| a   | bb  |\n| --- | --- |\n| ccc | d   |")
    }

    @Test("A literal pipe in a cell is escaped")
    func tablePipeEscaped() {
        #expect(
            SmartPaste.format("a|b\tc\nd\te\n")
                == "| a\\|b | c   |\n| ---- | --- |\n| d    | e   |")
    }

    @Test("The divider's dashes are never narrower than three, even for one-character cells")
    func tableDividerMinimumWidth() {
        #expect(
            SmartPaste.format("a\tb\nc\td\n")?.contains("| --- | --- |") == true
        )
    }

    /// A ragged row isn't a table, but a tab-separated line is still short
    /// enough plain text, so it falls through to the list check instead.
    @Test("A ragged row falls through to the list check rather than nil")
    func raggedRowFallsThroughToList() {
        #expect(SmartPaste.format("a\tb\nc\td\te\n") == "- a\tb\n- c\td\te")
    }

    @Test("Plain multi-line text becomes a bulleted list")
    func plainLinesBecomeList() {
        #expect(SmartPaste.format("milk\neggs\n") == "- milk\n- eggs")
    }

    @Test("List items are trimmed of surrounding whitespace")
    func listItemsTrimmed() {
        #expect(SmartPaste.format("  milk  \n eggs \n") == "- milk\n- eggs")
    }

    @Test("A single line is not a list or a table")
    func singleLineYieldsNil() {
        #expect(SmartPaste.format("milk") == nil)
        #expect(SmartPaste.format("milk\n") == nil)
    }

    @Test("A blank line in the middle disqualifies the paste")
    func blankLineInMiddleYieldsNil() {
        #expect(SmartPaste.format("milk\n\neggs\n") == nil)
    }

    @Test("A line over 80 characters disqualifies the paste")
    func overlongLineYieldsNil() {
        let long = String(repeating: "x", count: 81)
        #expect(SmartPaste.format("milk\n\(long)\n") == nil)
    }

    @Test("A line at exactly 80 characters still qualifies")
    func eightyCharacterLineQualifies() {
        let eighty = String(repeating: "x", count: 80)
        #expect(SmartPaste.format("milk\n\(eighty)\n") == "- milk\n- \(eighty)")
    }

    @Test(
        "Lines already marked up disqualify the paste",
        arguments: [
            "- item\nmore\n",
            "* item\nmore\n",
            "1. item\nmore\n",
            "- [ ] item\nmore\n",
            "# heading\nmore\n",
            "---\nmore\n",
        ]
    )
    func alreadyMarkedUpYieldsNil(text: String) {
        #expect(SmartPaste.format(text) == nil)
    }

    @Test("CRLF and CR newlines are normalised the same as LF")
    func alternateNewlinesNormalised() {
        #expect(SmartPaste.format("milk\r\neggs\r\n") == "- milk\n- eggs")
        #expect(SmartPaste.format("milk\reggs\r") == "- milk\n- eggs")
        #expect(
            SmartPaste.format("a\tb\r\nc\td\r\n")
                == "| a   | b   |\n| --- | --- |\n| c   | d   |")
    }

    @Test("Trailing blank lines, including whitespace-only ones, are dropped before judging")
    func trailingBlankLinesDropped() {
        #expect(SmartPaste.format("milk\neggs\n\n") == "- milk\n- eggs")
        #expect(SmartPaste.format("milk\neggs\n   \n") == "- milk\n- eggs")
        #expect(
            SmartPaste.format("a\tb\nc\td\n\n")
                == "| a   | b   |\n| --- | --- |\n| c   | d   |")
    }
}

@Suite("SmartPaste: pipeTable")
struct SmartPastePipeTableTests {
    /// `pipeTable` itself doesn't require two rows — `format` guards that
    /// before calling in, since a lone row is trivially "consistent".
    @Test("A single row is still a well-formed, if degenerate, table")
    func singleRowIsATable() {
        #expect(SmartPaste.pipeTable(["a\tb"]) == "| a   | b   |\n| --- | --- |")
    }

    @Test("Rows with only one cell are not a table")
    func oneCellRowsAreNil() {
        #expect(SmartPaste.pipeTable(["a", "b"]) == nil)
    }

    @Test("Rows with differing cell counts are not a table")
    func mismatchedWidthsAreNil() {
        #expect(SmartPaste.pipeTable(["a\tb", "c\td\te"]) == nil)
    }
}

@Suite("SmartPaste: bulletedList")
struct SmartPasteBulletedListTests {
    @Test("Any disqualified line makes the whole thing nil")
    func oneBadLineDisqualifiesAll() {
        #expect(SmartPaste.bulletedList(["milk", ""]) == nil)
        #expect(SmartPaste.bulletedList(["milk", "- eggs"]) == nil)
    }
}

@Suite("SmartPaste: isPlainItem")
struct SmartPasteIsPlainItemTests {
    @Test("An empty or whitespace-only line is not a plain item")
    func blankIsNotPlain() {
        #expect(!SmartPaste.isPlainItem(""))
        #expect(!SmartPaste.isPlainItem("   "))
    }

    @Test("A line at the max length is plain, one past it is not")
    func lengthBoundary() {
        #expect(SmartPaste.isPlainItem(String(repeating: "x", count: SmartPaste.maxItemLength)))
        #expect(!SmartPaste.isPlainItem(String(repeating: "x", count: SmartPaste.maxItemLength + 1)))
    }

    @Test(
        "Already-marked-up lines are not plain items",
        arguments: ["- item", "* item", "1. item", "- [ ] item", "# heading", "---"]
    )
    func markedUpIsNotPlain(line: String) {
        #expect(!SmartPaste.isPlainItem(line))
    }

    @Test("An ordinary sentence is a plain item")
    func ordinarySentenceIsPlain() {
        #expect(SmartPaste.isPlainItem("Buy milk"))
    }
}

@Suite("SmartPaste: splitLines")
struct SmartPasteSplitLinesTests {
    @Test("Newline conventions are normalised to a single array of lines")
    func normalisation() {
        #expect(SmartPaste.splitLines("a\nb") == ["a", "b"])
        #expect(SmartPaste.splitLines("a\r\nb") == ["a", "b"])
        #expect(SmartPaste.splitLines("a\rb") == ["a", "b"])
    }

    @Test("Trailing blank and whitespace-only lines are dropped, interior ones are kept")
    func trailingBlanksDropped() {
        #expect(SmartPaste.splitLines("a\nb\n") == ["a", "b"])
        #expect(SmartPaste.splitLines("a\nb\n\n   \n") == ["a", "b"])
        #expect(SmartPaste.splitLines("a\n\nb\n") == ["a", "", "b"])
    }

    /// The lone line an empty string produces is itself whitespace-only, so
    /// the trailing-blank trim removes it too, down to an empty array.
    @Test("An empty string trims away to no lines at all")
    func emptyString() {
        #expect(SmartPaste.splitLines("") == [])
    }
}
