import Foundation
import Testing

@testable import WispCore

/// Applies an edit the way the text view does, so a test can assert on the
/// resulting document rather than on three ranges.
private func apply(_ edit: LineEdits.Edit, to text: String) -> String {
    let mutable = NSMutableString(string: text)
    mutable.replaceCharacters(in: edit.range, with: edit.replacement)
    return mutable as String
}

@Suite("LineEdits — duplicate")
struct DuplicateTests {
    @Test("An empty selection duplicates the whole line")
    func wholeLine() {
        let text = "alpha\nbeta\ngamma"
        let edit = LineEdits.duplicate(
            in: text as NSString, selection: NSRange(location: 8, length: 0))
        #expect(apply(edit, to: text) == "alpha\nbeta\nbeta\ngamma")
    }

    @Test("The cursor rides onto the copy, keeping its column")
    func cursorFollowsTheCopy() {
        let text = "alpha\nbeta\ngamma"
        // Column 2 of "beta", which starts at 6.
        let edit = LineEdits.duplicate(
            in: text as NSString, selection: NSRange(location: 8, length: 0))
        // "alpha\nbeta\n" is 11 characters; column 2 of the copy is 13.
        #expect(edit.selection == NSRange(location: 13, length: 0))
    }

    @Test("A last line with no trailing newline gains one before the copy")
    func lastLineWithoutNewline() {
        let text = "alpha\nbeta"
        let edit = LineEdits.duplicate(
            in: text as NSString, selection: NSRange(location: 10, length: 0))
        #expect(apply(edit, to: text) == "alpha\nbeta\nbeta")
        #expect(edit.selection == NSRange(location: 15, length: 0))
    }

    @Test("Duplicating an empty document leaves a blank line")
    func emptyDocument() {
        let edit = LineEdits.duplicate(in: "" as NSString, selection: NSRange(location: 0, length: 0))
        #expect(apply(edit, to: "") == "\n")
    }

    @Test("A selection is copied in after itself, and the copy is selected")
    func selection() {
        let text = "alpha beta"
        let selection = NSRange(location: 0, length: 5)
        let edit = LineEdits.duplicate(in: text as NSString, selection: selection)
        #expect(apply(edit, to: text) == "alphaalpha beta")
        #expect(edit.selection == NSRange(location: 5, length: 5))
    }

    @Test("Duplicating twice compounds rather than doubling")
    func repeatedDuplicate() {
        var text = "ab"
        var selection = NSRange(location: 0, length: 2)
        for _ in 0..<2 {
            let edit = LineEdits.duplicate(in: text as NSString, selection: selection)
            text = apply(edit, to: text)
            selection = edit.selection
        }
        #expect(text == "ababab")
    }
}

@Suite("LineEdits — whole-line copy and cut")
struct LineClipboardTests {
    @Test("Copy takes the line with its newline")
    func copyIncludesNewline() {
        let text = "alpha\nbeta\n"
        let line = LineEdits.lineForClipboard(
            in: text as NSString, selection: NSRange(location: 7, length: 0))
        #expect(line.string == "beta\n")
    }

    @Test("A last line without a newline still copies as a line")
    func copyAppendsMissingNewline() {
        let text = "alpha\nbeta"
        let line = LineEdits.lineForClipboard(
            in: text as NSString, selection: NSRange(location: 7, length: 0))
        #expect(line.string == "beta\n")
    }

    @Test("Cut removes the line and holds the column on the one below")
    func cutHoldsColumn() {
        let text = "alpha\nbeta\ngamma"
        let edit = LineEdits.cutLine(
            in: text as NSString, selection: NSRange(location: 8, length: 0))
        #expect(apply(edit, to: text) == "alpha\ngamma")
        // Column 2 of "gamma", which now starts at 6.
        #expect(edit.selection == NSRange(location: 8, length: 0))
    }

    @Test("Cutting onto a shorter line clamps to its end")
    func cutClampsColumn() {
        let text = "alphabet\nxy\n"
        let edit = LineEdits.cutLine(
            in: text as NSString, selection: NSRange(location: 7, length: 0))
        #expect(apply(edit, to: text) == "xy\n")
        #expect(edit.selection == NSRange(location: 2, length: 0))
    }

    @Test("Cutting the last line leaves the cursor at the end")
    func cutLastLine() {
        let text = "alpha\nbeta"
        let edit = LineEdits.cutLine(
            in: text as NSString, selection: NSRange(location: 8, length: 0))
        #expect(apply(edit, to: text) == "alpha\n")
        #expect(edit.selection == NSRange(location: 6, length: 0))
    }

    @Test("Paste inserts above the caret's line and rides the caret down with it")
    func pasteInsertsAboveTheCurrentLine() {
        let text = "alpha\nbeta\n"
        let edit = LineEdits.pasteLine(
            in: text as NSString, selection: NSRange(location: 8, length: 0), line: "xx\n")
        #expect(apply(edit, to: text) == "alpha\nxx\nbeta\n")
        #expect(edit.selection == NSRange(location: 11, length: 0))
    }

    @Test("Pasting on the first line inserts before it rather than at column zero of nothing")
    func pasteOnFirstLine() {
        let text = "alpha\nbeta\n"
        let edit = LineEdits.pasteLine(
            in: text as NSString, selection: NSRange(location: 0, length: 0), line: "xx\n")
        #expect(apply(edit, to: text) == "xx\nalpha\nbeta\n")
        #expect(edit.selection == NSRange(location: 3, length: 0))
    }

    @Test("Pasting above a last line without a trailing newline leaves the document shape alone")
    func pasteAboveLastLineWithoutNewline() {
        let text = "alpha\nbeta"
        let edit = LineEdits.pasteLine(
            in: text as NSString, selection: NSRange(location: 8, length: 0), line: "xx\n")
        #expect(apply(edit, to: text) == "alpha\nxx\nbeta")
        #expect(edit.selection == NSRange(location: 11, length: 0))
    }
}

@Suite("LineEdits — indent and outdent")
struct IndentEditTests {
    @Test("Tab on one line shifts it and the cursor together")
    func singleLine() {
        let text = "alpha\nbeta\n"
        let edit = LineEdits.indent(
            in: text as NSString, selection: NSRange(location: 8, length: 0), unit: "  ")
        #expect(apply(edit, to: text) == "alpha\n  beta\n")
        #expect(edit.selection == NSRange(location: 10, length: 0))
    }

    @Test("A selection indents every line it touches")
    func multipleLines() {
        let text = "one\ntwo\nthree\n"
        let edit = LineEdits.indent(
            in: text as NSString, selection: NSRange(location: 1, length: 6), unit: "  ")
        #expect(apply(edit, to: text) == "  one\n  two\nthree\n")
    }

    @Test("A selection ending on a line boundary leaves the next line alone")
    func trailingNewlineExcluded() {
        let text = "one\ntwo\nthree\n"
        // Selects "one\n" exactly — the newline included.
        let edit = LineEdits.indent(
            in: text as NSString, selection: NSRange(location: 0, length: 4), unit: "  ")
        #expect(apply(edit, to: text) == "  one\ntwo\nthree\n")
    }

    @Test("Tabs indent with a tab when that is the configured unit")
    func tabUnit() {
        let text = "alpha\n"
        let edit = LineEdits.indent(
            in: text as NSString, selection: NSRange(location: 0, length: 0), unit: "\t")
        #expect(apply(edit, to: text) == "\talpha\n")
    }

    @Test("Outdent removes one level")
    func outdentOneLevel() {
        let text = "    alpha\n"
        let edit = LineEdits.outdent(
            in: text as NSString, selection: NSRange(location: 6, length: 0), unit: "  ")
        #expect(apply(edit, to: text) == "  alpha\n")
        #expect(edit.selection == NSRange(location: 4, length: 0))
    }

    @Test("Outdent leaves an already-flush line alone")
    func outdentFlushLine() {
        let text = "alpha\n"
        let edit = LineEdits.outdent(
            in: text as NSString, selection: NSRange(location: 2, length: 0), unit: "  ")
        #expect(apply(edit, to: text) == "alpha\n")
        #expect(edit.selection == NSRange(location: 2, length: 0))
    }

    @Test("A partial indent outdents by what is actually there")
    func outdentPartialIndent() {
        let text = " alpha\n"
        let edit = LineEdits.outdent(
            in: text as NSString, selection: NSRange(location: 3, length: 0), unit: "  ")
        #expect(apply(edit, to: text) == "alpha\n")
        #expect(edit.selection == NSRange(location: 2, length: 0))
    }

    @Test("A cursor inside the removed whitespace lands on the first surviving character")
    func cursorInsideRemovedWhitespace() {
        let text = "    alpha\n"
        let edit = LineEdits.outdent(
            in: text as NSString, selection: NSRange(location: 1, length: 0), unit: "  ")
        #expect(edit.selection == NSRange(location: 0, length: 0))
    }

    @Test("Outdent takes one tab where the line is tab-indented")
    func outdentTab() {
        let text = "\t\talpha\n"
        let edit = LineEdits.outdent(
            in: text as NSString, selection: NSRange(location: 3, length: 0), unit: "  ")
        #expect(apply(edit, to: text) == "\talpha\n")
    }

    @Test("Indent then outdent is a round trip over a block")
    func roundTrip() {
        let text = "one\n  two\nthree\n"
        let selection = NSRange(location: 0, length: 14)
        let indented = LineEdits.indent(in: text as NSString, selection: selection, unit: "  ")
        let once = apply(indented, to: text)
        let outdented = LineEdits.outdent(
            in: once as NSString, selection: indented.selection, unit: "  ")
        #expect(apply(outdented, to: once) == text)
    }
}

@Suite("LineEdits — outdent at cursor")
struct OutdentAtCursorTests {
    @Test("Mid-line spaces exactly the unit's width are removed entirely")
    func removesTheFullUnit() throws {
        let text = "foo  bar"
        let edit = try #require(
            LineEdits.outdentAtCursor(
                in: text as NSString, selection: NSRange(location: 5, length: 0), unit: "  "))
        #expect(apply(edit, to: text) == "foobar")
        #expect(edit.selection == NSRange(location: 3, length: 0))
    }

    @Test("Fewer spaces before the cursor than the unit removes only what is there")
    func removesWhatIsThere() throws {
        let text = "foo bar"
        let edit = try #require(
            LineEdits.outdentAtCursor(
                in: text as NSString, selection: NSRange(location: 4, length: 0), unit: "  "))
        #expect(apply(edit, to: text) == "foobar")
        #expect(edit.selection == NSRange(location: 3, length: 0))
    }

    @Test("More spaces before the cursor than the unit removes exactly the unit's width")
    func removesOnlyTheUnitWidth() throws {
        let text = "foo    bar"
        let edit = try #require(
            LineEdits.outdentAtCursor(
                in: text as NSString, selection: NSRange(location: 7, length: 0), unit: "  "))
        #expect(apply(edit, to: text) == "foo  bar")
        #expect(edit.selection == NSRange(location: 5, length: 0))
    }

    @Test("A mid-line tab is removed whole, regardless of the configured unit width")
    func removesOneTab() throws {
        let text = "foo\tbar"
        let edit = try #require(
            LineEdits.outdentAtCursor(
                in: text as NSString, selection: NSRange(location: 4, length: 0), unit: "    "))
        #expect(apply(edit, to: text) == "foobar")
        #expect(edit.selection == NSRange(location: 3, length: 0))
    }

    @Test("A mixed tab-then-spaces run gives up only the spaces, never the tab")
    func mixedRunKeepsTheTab() throws {
        let text = "foo\t  bar"
        let edit = try #require(
            LineEdits.outdentAtCursor(
                in: text as NSString, selection: NSRange(location: 6, length: 0), unit: "    "))
        #expect(apply(edit, to: text) == "foo\tbar")
        #expect(edit.selection == NSRange(location: 4, length: 0))
    }

    @Test("A cursor inside the line's leading indent is not this edit")
    func cursorInsideLeadingIndent() {
        let text = "  foo"
        let edit = LineEdits.outdentAtCursor(
            in: text as NSString, selection: NSRange(location: 1, length: 0), unit: "  ")
        #expect(edit == nil)
    }

    @Test("A cursor at the end of the line's leading indent is not this edit")
    func cursorAtEndOfLeadingIndent() {
        let text = "  foo"
        let edit = LineEdits.outdentAtCursor(
            in: text as NSString, selection: NSRange(location: 2, length: 0), unit: "  ")
        #expect(edit == nil)
    }

    @Test("A cursor at column zero is not this edit")
    func cursorAtColumnZero() {
        let text = "foo"
        let edit = LineEdits.outdentAtCursor(
            in: text as NSString, selection: NSRange(location: 0, length: 0), unit: "  ")
        #expect(edit == nil)
    }

    @Test("A line of only whitespace is entirely leading indent, even at its end")
    func wholeLineIsWhitespace() {
        let text = "   "
        let edit = LineEdits.outdentAtCursor(
            in: text as NSString, selection: NSRange(location: 3, length: 0), unit: "  ")
        #expect(edit == nil)
    }

    @Test("A non-empty selection is not this edit")
    func nonEmptySelection() {
        let text = "foo  bar"
        let edit = LineEdits.outdentAtCursor(
            in: text as NSString, selection: NSRange(location: 3, length: 2), unit: "  ")
        #expect(edit == nil)
    }

    @Test("The line-start check is against the cursor's own line, not the document start")
    func secondLineOfMultilineText() throws {
        let text = "first\nfoo  bar"
        let edit = try #require(
            LineEdits.outdentAtCursor(
                in: text as NSString, selection: NSRange(location: 11, length: 0), unit: "  "))
        #expect(apply(edit, to: text) == "first\nfoobar")
        #expect(edit.selection == NSRange(location: 9, length: 0))
    }

    @Test("A single-tab unit removes only one space from a mid-line run of spaces")
    func singleTabUnitOnSpaces() throws {
        let text = "foo   bar"
        let edit = try #require(
            LineEdits.outdentAtCursor(
                in: text as NSString, selection: NSRange(location: 6, length: 0), unit: "\t"))
        #expect(apply(edit, to: text) == "foo  bar")
        #expect(edit.selection == NSRange(location: 5, length: 0))
    }

    @Test("A single-tab unit still removes a whole mid-line tab")
    func singleTabUnitOnATab() throws {
        let text = "foo\tbar"
        let edit = try #require(
            LineEdits.outdentAtCursor(
                in: text as NSString, selection: NSRange(location: 4, length: 0), unit: "\t"))
        #expect(apply(edit, to: text) == "foobar")
        #expect(edit.selection == NSRange(location: 3, length: 0))
    }
}

@Suite("LineEdits — backspace in indent")
struct BackspaceInIndentTests {
    @Test("Caret after four spaces removes one level, leaving two")
    func fourSpacesRemovesOneLevel() throws {
        let text = "    foo"
        let edit = try #require(
            LineEdits.backspaceInIndent(
                in: text as NSString, selection: NSRange(location: 4, length: 0), unit: "  "))
        #expect(apply(edit, to: text) == "  foo")
        #expect(edit.selection == NSRange(location: 2, length: 0))
    }

    @Test("Caret after three spaces removes two, leaving one")
    func threeSpacesRemovesTwo() throws {
        let text = "   foo"
        let edit = try #require(
            LineEdits.backspaceInIndent(
                in: text as NSString, selection: NSRange(location: 3, length: 0), unit: "  "))
        #expect(apply(edit, to: text) == " foo")
        #expect(edit.selection == NSRange(location: 1, length: 0))
    }

    @Test("Caret after one space removes just that space")
    func oneSpaceRemovesOne() throws {
        let text = " foo"
        let edit = try #require(
            LineEdits.backspaceInIndent(
                in: text as NSString, selection: NSRange(location: 1, length: 0), unit: "  "))
        #expect(apply(edit, to: text) == "foo")
        #expect(edit.selection == NSRange(location: 0, length: 0))
    }

    @Test("Caret after a tab removes just the tab")
    func afterTabRemovesTheTab() throws {
        let text = "\tfoo"
        let edit = try #require(
            LineEdits.backspaceInIndent(
                in: text as NSString, selection: NSRange(location: 1, length: 0), unit: "  "))
        #expect(apply(edit, to: text) == "foo")
        #expect(edit.selection == NSRange(location: 0, length: 0))
    }

    @Test("A tab followed by two spaces gives up only the spaces")
    func tabThenSpacesKeepsTheTab() throws {
        let text = "\t  foo"
        let edit = try #require(
            LineEdits.backspaceInIndent(
                in: text as NSString, selection: NSRange(location: 3, length: 0), unit: "  "))
        #expect(apply(edit, to: text) == "\tfoo")
        #expect(edit.selection == NSRange(location: 1, length: 0))
    }

    @Test("A caret at column zero is not this edit")
    func caretAtColumnZero() {
        let text = "foo"
        let edit = LineEdits.backspaceInIndent(
            in: text as NSString, selection: NSRange(location: 0, length: 0), unit: "  ")
        #expect(edit == nil)
    }

    @Test("A caret after non-whitespace text is not this edit")
    func caretAfterNonWhitespace() {
        let text = "  ab"
        let edit = LineEdits.backspaceInIndent(
            in: text as NSString, selection: NSRange(location: 4, length: 0), unit: "  ")
        #expect(edit == nil)
    }

    @Test("A caret in whitespace that follows text is not this edit")
    func caretInTrailingWhitespace() {
        let text = "ab  "
        let edit = LineEdits.backspaceInIndent(
            in: text as NSString, selection: NSRange(location: 4, length: 0), unit: "  ")
        #expect(edit == nil)
    }

    @Test("A non-empty selection is not this edit")
    func nonEmptySelection() {
        let text = "    foo"
        let edit = LineEdits.backspaceInIndent(
            in: text as NSString, selection: NSRange(location: 2, length: 2), unit: "  ")
        #expect(edit == nil)
    }

    @Test("Works on a second line, where the line start is not offset zero")
    func secondLine() throws {
        let text = "first\n    foo"
        let edit = try #require(
            LineEdits.backspaceInIndent(
                in: text as NSString, selection: NSRange(location: 10, length: 0), unit: "  "))
        #expect(apply(edit, to: text) == "first\n  foo")
        #expect(edit.selection == NSRange(location: 8, length: 0))
    }
}

@Suite("LineEdits — move lines")
struct MoveLinesTests {
    @Test("Moving up swaps with the line above")
    func up() {
        let text = "one\ntwo\nthree\n"
        let edit = LineEdits.moveLines(
            in: text as NSString, selection: NSRange(location: 5, length: 0), by: -1)
        #expect(apply(edit, to: text) == "two\none\nthree\n")
    }

    @Test("Moving down swaps with the line below")
    func down() {
        let text = "one\ntwo\nthree\n"
        let edit = LineEdits.moveLines(
            in: text as NSString, selection: NSRange(location: 1, length: 0), by: 1)
        #expect(apply(edit, to: text) == "two\none\nthree\n")
    }

    @Test("The cursor rides the line it moved")
    func cursorRides() {
        let text = "one\ntwo\nthree\n"
        // Column 1 of "two".
        let edit = LineEdits.moveLines(
            in: text as NSString, selection: NSRange(location: 5, length: 0), by: -1)
        // "two" is now first, so column 1 of it is offset 1.
        #expect(edit.selection == NSRange(location: 1, length: 0))
    }

    @Test("A multi-line selection moves as a block")
    func block() {
        let text = "one\ntwo\nthree\nfour\n"
        let edit = LineEdits.moveLines(
            in: text as NSString, selection: NSRange(location: 4, length: 8), by: 1)
        #expect(apply(edit, to: text) == "one\nfour\ntwo\nthree\n")
    }

    @Test("A last line with no trailing newline still moves")
    func lastLineWithoutNewline() {
        let text = "one\ntwo"
        let edit = LineEdits.moveLines(
            in: text as NSString, selection: NSRange(location: 5, length: 0), by: -1)
        #expect(apply(edit, to: text) == "two\none")
    }

    @Test("Moving into a line with no trailing newline keeps the document shape")
    func intoLastLine() {
        let text = "one\ntwo"
        let edit = LineEdits.moveLines(
            in: text as NSString, selection: NSRange(location: 0, length: 0), by: 1)
        #expect(apply(edit, to: text) == "two\none")
    }

    @Test("At either edge it is a no-op, not a wrap-around")
    func edges() {
        let text = "one\ntwo\n"
        let atTop = LineEdits.moveLines(
            in: text as NSString, selection: NSRange(location: 0, length: 0), by: -1)
        #expect(atTop.isNoOp)
        #expect(apply(atTop, to: text) == text)

        let atBottom = LineEdits.moveLines(
            in: text as NSString, selection: NSRange(location: 5, length: 0), by: 1)
        #expect(atBottom.isNoOp)
        #expect(apply(atBottom, to: text) == text)
    }

    @Test("Up then down returns the document to where it started")
    func roundTrip() {
        let text = "one\ntwo\nthree\n"
        let up = LineEdits.moveLines(
            in: text as NSString, selection: NSRange(location: 9, length: 0), by: -1)
        let once = apply(up, to: text)
        let down = LineEdits.moveLines(in: once as NSString, selection: up.selection, by: 1)
        #expect(apply(down, to: once) == text)
    }
}

@Suite("LineEdits — toggle bulleted list item")
struct ToggleBulletedListItemTests {
    @Test("A plain line becomes a bullet")
    func setOne() {
        let text = "alpha\n"
        let edit = LineEdits.toggleBulletedList(
            in: text as NSString, selection: NSRange(location: 2, length: 0))
        #expect(apply(edit, to: text) == "- alpha\n")
    }

    @Test("A bullet line loses its marker")
    func unsetOne() {
        let text = "- alpha\n"
        let edit = LineEdits.toggleBulletedList(
            in: text as NSString, selection: NSRange(location: 4, length: 0))
        #expect(apply(edit, to: text) == "alpha\n")
    }

    @Test("Indentation survives in both directions")
    func keepsIndent() {
        let set = LineEdits.toggleBulletedList(
            in: "    alpha\n" as NSString, selection: NSRange(location: 6, length: 0))
        #expect(apply(set, to: "    alpha\n") == "    - alpha\n")

        let unset = LineEdits.toggleBulletedList(
            in: "    - alpha\n" as NSString, selection: NSRange(location: 8, length: 0))
        #expect(apply(unset, to: "    - alpha\n") == "    alpha\n")
    }

    @Test("A block that is entirely bullets is unset")
    func unsetBlock() {
        let text = "- one\n- two\n"
        let edit = LineEdits.toggleBulletedList(
            in: text as NSString, selection: NSRange(location: 0, length: 11))
        #expect(apply(edit, to: text) == "one\ntwo\n")
    }

    @Test("A mixed block becomes a list rather than losing its markers")
    func mixedBlockBecomesList() {
        let text = "- one\ntwo\n"
        let edit = LineEdits.toggleBulletedList(
            in: text as NSString, selection: NSRange(location: 0, length: 9))
        #expect(apply(edit, to: text) == "- - one\n- two\n")
    }

    @Test("Set then unset is a round trip")
    func roundTrip() {
        let text = "alpha\nbeta\n"
        let selection = NSRange(location: 0, length: 10)
        let set = LineEdits.toggleBulletedList(in: text as NSString, selection: selection)
        let once = apply(set, to: text)
        #expect(once == "- alpha\n- beta\n")
        let unset = LineEdits.toggleBulletedList(in: once as NSString, selection: set.selection)
        #expect(apply(unset, to: once) == text)
    }

    @Test("An ordered item is left alone — it is not a bullet")
    func ordered() {
        let text = "1. alpha\n"
        let edit = LineEdits.toggleBulletedList(
            in: text as NSString, selection: NSRange(location: 4, length: 0))
        #expect(apply(edit, to: text) == "- 1. alpha\n")
    }

    @Test("A task item counts as a list item — it unsets too")
    func taskItemUnsets() {
        let text = "- [ ] foo\n"
        let edit = LineEdits.toggleBulletedList(
            in: text as NSString, selection: NSRange(location: 4, length: 0))
        #expect(apply(edit, to: text) == "foo\n")
    }

    @Test("A block of a bullet and a task is all-items, and unsets both")
    func mixedBulletAndTaskUnsets() {
        let text = "- a\n- [ ] b\n"
        let edit = LineEdits.toggleBulletedList(
            in: text as NSString, selection: NSRange(location: 0, length: 11))
        #expect(apply(edit, to: text) == "a\nb\n")
    }
}

@Suite("LineEdits — toggle task items")
struct ToggleTaskItemsTests {
    @Test("A plain line gains a whole task marker, and the caret rides past it")
    func plainLine() {
        let text = "foo"
        let edit = LineEdits.toggleTaskItems(
            in: text as NSString, selection: NSRange(location: 3, length: 0))
        #expect(apply(edit, to: text) == "- [ ] foo")
        #expect(edit.selection == NSRange(location: 9, length: 0))
    }

    @Test("An indented plain line keeps its indent ahead of the marker")
    func indentedPlainLine() {
        let text = "  foo"
        let edit = LineEdits.toggleTaskItems(
            in: text as NSString, selection: NSRange(location: 5, length: 0))
        #expect(apply(edit, to: text) == "  - [ ] foo")
    }

    @Test("A bullet keeps its marker and only gains the box")
    func bullet() {
        let text = "- foo"
        let edit = LineEdits.toggleTaskItems(
            in: text as NSString, selection: NSRange(location: 2, length: 0))
        #expect(apply(edit, to: text) == "- [ ] foo")
    }

    @Test("An ordered item trades its number for a bullet — a box can't show a number")
    func ordered() {
        let text = "  1. foo"
        let edit = LineEdits.toggleTaskItems(
            in: text as NSString, selection: NSRange(location: 5, length: 0))
        #expect(apply(edit, to: text) == "  - [ ] foo")
    }

    @Test("An all-unchecked block gets checked")
    func allUncheckedBlockGetsChecked() {
        let text = "- [ ] a\n- [ ] b"
        let edit = LineEdits.toggleTaskItems(
            in: text as NSString, selection: NSRange(location: 0, length: text.count))
        #expect(apply(edit, to: text) == "- [x] a\n- [x] b")
    }

    @Test("A mixed-state block gets checked — checking wins over unchecking")
    func mixedStateBlockGetsChecked() {
        let text = "- [x] a\n- [ ] b"
        let edit = LineEdits.toggleTaskItems(
            in: text as NSString, selection: NSRange(location: 0, length: text.count))
        #expect(apply(edit, to: text) == "- [x] a\n- [x] b")
    }

    @Test("An all-checked block gets unchecked")
    func allCheckedBlockGetsUnchecked() {
        let text = "- [x] a\n- [x] b"
        let edit = LineEdits.toggleTaskItems(
            in: text as NSString, selection: NSRange(location: 0, length: text.count))
        #expect(apply(edit, to: text) == "- [ ] a\n- [ ] b")
    }

    @Test("A block mixing a task with a non-task line leaves the task untouched")
    func mixedTaskAndPlainLeavesTaskAlone() {
        let text = "- [x] a\nb"
        let edit = LineEdits.toggleTaskItems(
            in: text as NSString, selection: NSRange(location: 0, length: text.count))
        #expect(apply(edit, to: text) == "- [x] a\n- [ ] b")
    }

    @Test("An empty selection only touches its own line")
    func emptySelectionTouchesOneLine() {
        let text = "foo\nbar\n"
        let edit = LineEdits.toggleTaskItems(
            in: text as NSString, selection: NSRange(location: 5, length: 0))
        #expect(apply(edit, to: text) == "foo\n- [ ] bar\n")
    }

    @Test("A non-empty selection maps to a non-empty selection afterwards")
    func selectionSurvivesAsARange() {
        let text = "one\ntwo\n"
        let edit = LineEdits.toggleTaskItems(
            in: text as NSString, selection: NSRange(location: 0, length: 7))
        #expect(apply(edit, to: text) == "- [ ] one\n- [ ] two\n")
        #expect(edit.selection == NSRange(location: 6, length: 13))
    }
}
