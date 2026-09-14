import Foundation
import Testing

@testable import WispCore

@Suite("Escapes: scanning")
struct EscapesScanningTests {
    @Test("A single escape at the start of the text marks the backslash and its target")
    func singleEscapeAtStart() {
        let marks = Escapes.scan("\\`")
        #expect(marks.backslashes == [0])
        #expect(marks.escaped == [1])
    }

    @Test("Offsets are absolute across the whole text, not reset per line")
    func offsetsAreAbsoluteAcrossLines() {
        let text = "First line.\nSecond \\*line* here." as NSString
        // Locate the pair rather than hand-counting, so the test can't drift
        // from the fixture if the surrounding text ever changes.
        let backslash = text.range(of: "\\*").location
        let marks = Escapes.scan(text)
        #expect(marks.backslashes == [backslash])
        #expect(marks.escaped == [backslash + 1])
    }

    @Test(
        "Every member of the escapable set is recognized after a backslash",
        arguments: Array(Escapes.escapable)
    )
    func everyEscapableCharacterIsRecognized(character: Character) {
        let marks = Escapes.scan("\\\(character)")
        #expect(marks.backslashes == [0])
        #expect(marks.escaped == [1])
    }

    @Test(
        "A backslash before a character outside the escapable set is inert",
        arguments: [
            "\\a",
            "\\ ",
            "\\\n",  // a real newline character, not the two-character escape sequence
        ]
    )
    func backslashBeforeNonEscapableCharacterIsInert(text: String) {
        #expect(Escapes.scan(text) == .none)
    }
}

@Suite("Escapes: consecutive backslashes")
struct EscapesConsecutiveBackslashesTests {
    @Test("A doubled backslash marks only the first one")
    func doubledBackslashMarksOnlyTheFirst() {
        let marks = Escapes.scan("\\\\")
        #expect(marks.backslashes == [0])
        #expect(marks.escaped == [1])
    }

    /// The first pair consumes itself entirely, so the third backslash is
    /// free to go on and escape the backtick.
    @Test("A third backslash after a consumed pair escapes the following character")
    func thirdBackslashEscapesAfterPairIsConsumed() {
        let text = String(repeating: "\\", count: 3) + "`"
        let marks = Escapes.scan(text)
        #expect(marks.backslashes == [0, 2])
        #expect(marks.escaped == [1, 3])
    }

    @Test("Four backslashes form two independent pairs")
    func fourBackslashesFormTwoPairs() {
        let text = String(repeating: "\\", count: 4)
        let marks = Escapes.scan(text)
        #expect(marks.backslashes == [0, 2])
        #expect(marks.escaped == [1, 3])
    }

    @Test("A trailing backslash with nothing after it to escape is inert")
    func trailingBackslashIsInert() {
        #expect(Escapes.scan("hello\\") == .none)
    }
}

@Suite("Escapes: edge cases")
struct EscapesEdgeCaseTests {
    @Test("Empty and single-character text produce no marks")
    func emptyAndSingleCharacterProduceNoMarks() {
        #expect(Escapes.scan("") == .none)
        #expect(Escapes.scan("").isEmpty)
        #expect(Escapes.scan("a") == .none)
        #expect(Escapes.scan("a").isEmpty)
    }

    @Test("Offsets count UTF-16 units, not Characters, across a surrogate pair")
    func offsetsCountUTF16UnitsNotCharacters() {
        let text = "🚀\\`"
        // The emoji is one Character but two UTF-16 units; a Character-based
        // index would put the escape at offset 1 instead of 2.
        #expect(text.count == 3)
        let marks = Escapes.scan(text)
        #expect(marks.backslashes == [2])
        #expect(marks.escaped == [3])
    }
}

@Suite("Escapes: Marks and overload parity")
struct EscapesMarksTests {
    @Test("isEscaped agrees with the escaped set, including for an offset nobody marked")
    func isEscapedAgreesWithEscapedSet() {
        let marks = Escapes.scan("\\`")
        #expect(marks.isEscaped(1) == marks.escaped.contains(1))
        #expect(marks.isEscaped(1))
        #expect(!marks.isEscaped(0))
        #expect(!marks.isEscaped(50))
    }

    @Test(
        "The String and NSString overloads agree",
        arguments: ["\\`", "\\\\", "hello\\", "🚀\\*world", "no escapes here", ""]
    )
    func stringAndNSStringOverloadsAgree(text: String) {
        #expect(Escapes.scan(text) == Escapes.scan(text as NSString))
    }
}

@Suite("Escapes: Marks.masking")
struct EscapesMaskingTests {
    @Test("Every escaped character is blanked, and only those")
    func blanksEscapedCharacters() {
        let text = "\\`code\\` and \\*x*"
        #expect(Escapes.scan(text).masking(text) == "\\ code\\  and \\ x*")
    }

    @Test("Offsets are unchanged, so a masked range is a range into the original")
    func preservesOffsets() {
        let text = "a \\~ b ~c~ 🎉 \\_d"
        let masked = Escapes.scan(text).masking(text)
        #expect((masked as NSString).length == (text as NSString).length)
        #expect((masked as NSString).range(of: "~c~") == (text as NSString).range(of: "~c~"))
    }

    /// The reason masking exists: a scanner that found `~a\~` and threw it
    /// away had eaten the opener that ` b~` needed.
    @Test("An escaped closer no longer swallows the run that starts inside it")
    func escapedCloserDoesNotSwallow() {
        let text = "~a\\~ b~ c"
        let masked = Escapes.scan(text).masking(text)
        let runs = masked.matches(of: /~([^~\n]+)~/).map { NSRange($0.range, in: masked) }
        #expect(runs == [(text as NSString).range(of: "~a\\~ b~")])
    }

    @Test("Marks.none hands the text back untouched, the no-backslashes fast path")
    func noneIsIdentity() {
        #expect(Escapes.Marks.none.masking("`code` *x*") == "`code` *x*")
    }

    @Test("The two-backslash pair blanks its second half, so it cannot escape a third character")
    func doubleBackslash() {
        let text = "\\\\*x*"
        #expect(Escapes.scan(text).masking(text) == "\\ *x*")
    }
}
