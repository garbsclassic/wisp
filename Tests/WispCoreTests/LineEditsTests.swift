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

@Suite("LineEdits — toggle list item")
struct ToggleListItemTests {
    @Test("A plain line becomes a bullet")
    func setOne() {
        let text = "alpha\n"
        let edit = LineEdits.toggleListItem(
            in: text as NSString, selection: NSRange(location: 2, length: 0))
        #expect(apply(edit, to: text) == "- alpha\n")
    }

    @Test("A bullet line loses its marker")
    func unsetOne() {
        let text = "- alpha\n"
        let edit = LineEdits.toggleListItem(
            in: text as NSString, selection: NSRange(location: 4, length: 0))
        #expect(apply(edit, to: text) == "alpha\n")
    }

    @Test("Indentation survives in both directions")
    func keepsIndent() {
        let set = LineEdits.toggleListItem(
            in: "    alpha\n" as NSString, selection: NSRange(location: 6, length: 0))
        #expect(apply(set, to: "    alpha\n") == "    - alpha\n")

        let unset = LineEdits.toggleListItem(
            in: "    - alpha\n" as NSString, selection: NSRange(location: 8, length: 0))
        #expect(apply(unset, to: "    - alpha\n") == "    alpha\n")
    }

    @Test("A block that is entirely bullets is unset")
    func unsetBlock() {
        let text = "- one\n- two\n"
        let edit = LineEdits.toggleListItem(
            in: text as NSString, selection: NSRange(location: 0, length: 11))
        #expect(apply(edit, to: text) == "one\ntwo\n")
    }

    @Test("A mixed block becomes a list rather than losing its markers")
    func mixedBlockBecomesList() {
        let text = "- one\ntwo\n"
        let edit = LineEdits.toggleListItem(
            in: text as NSString, selection: NSRange(location: 0, length: 9))
        #expect(apply(edit, to: text) == "- - one\n- two\n")
    }

    @Test("Set then unset is a round trip")
    func roundTrip() {
        let text = "alpha\nbeta\n"
        let selection = NSRange(location: 0, length: 10)
        let set = LineEdits.toggleListItem(in: text as NSString, selection: selection)
        let once = apply(set, to: text)
        #expect(once == "- alpha\n- beta\n")
        let unset = LineEdits.toggleListItem(in: once as NSString, selection: set.selection)
        #expect(apply(unset, to: once) == text)
    }

    @Test("An ordered item is left alone — it is not a bullet")
    func ordered() {
        let text = "1. alpha\n"
        let edit = LineEdits.toggleListItem(
            in: text as NSString, selection: NSRange(location: 4, length: 0))
        #expect(apply(edit, to: text) == "- 1. alpha\n")
    }
}
