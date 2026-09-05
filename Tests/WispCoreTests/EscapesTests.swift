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

@Suite("Escapes: Marks.isLive")
struct EscapesIsLiveTests {
    @Test("An unescaped code span is live")
    func unescapedCodeSpanIsLive() {
        let text = "`code`" as NSString
        let run = NSRange(location: 0, length: text.length)
        let marks = Escapes.scan(text)
        #expect(marks.isLive(run, closeLength: 1))
    }

    @Test("A backslash before the opening backtick makes the span not live")
    func backslashBeforeOpeningBacktickIsNotLive() {
        let text = "\\`code`" as NSString
        let run = text.range(of: "`code`")
        let marks = Escapes.scan(text)
        #expect(!marks.isLive(run, closeLength: 1))
    }

    /// The half a naive "check the start only" implementation would miss:
    /// the backslash sits on the closing delimiter, not the opening one.
    @Test("A backslash before the closing backtick makes the span not live")
    func backslashBeforeClosingBacktickIsNotLive() {
        let text = "`code\\`" as NSString
        let run = NSRange(location: 0, length: text.length)
        let marks = Escapes.scan(text)
        #expect(!marks.isLive(run, closeLength: 1))
    }

    @Test("An unescaped bold run is live")
    func unescapedBoldIsLive() {
        let text = "**bold**" as NSString
        let run = NSRange(location: 0, length: text.length)
        let marks = Escapes.scan(text)
        #expect(marks.isLive(run, closeLength: 2))
    }

    @Test("A backslash before the opening bold delimiter makes the run not live")
    func backslashBeforeOpeningBoldIsNotLive() {
        let text = "\\**bold**" as NSString
        let run = text.range(of: "**bold**")
        let marks = Escapes.scan(text)
        #expect(!marks.isLive(run, closeLength: 2))
    }

    @Test("A backslash before the closing bold delimiter makes the run not live")
    func backslashBeforeClosingBoldIsNotLive() {
        let text = "**bold\\**" as NSString
        let run = NSRange(location: 0, length: text.length)
        let marks = Escapes.scan(text)
        #expect(!marks.isLive(run, closeLength: 2))
    }

    @Test("An unescaped highlight run is live")
    func unescapedHighlightIsLive() {
        let text = "==marked==" as NSString
        let run = NSRange(location: 0, length: text.length)
        let marks = Escapes.scan(text)
        #expect(marks.isLive(run, closeLength: 2))
    }

    @Test("A backslash before the opening highlight delimiter makes the run not live")
    func backslashBeforeOpeningHighlightIsNotLive() {
        let text = "\\==marked==" as NSString
        let run = text.range(of: "==marked==")
        let marks = Escapes.scan(text)
        #expect(!marks.isLive(run, closeLength: 2))
    }

    @Test("An unescaped underline run is live")
    func unescapedUnderlineIsLive() {
        let text = "<u>x</u>" as NSString
        let run = NSRange(location: 0, length: text.length)
        let marks = Escapes.scan(text)
        #expect(marks.isLive(run, closeLength: 4))
    }

    /// `<u>` opens with 3 characters but `</u>` closes with 4 — the case that
    /// pins the asymmetric-delimiter handling.
    @Test("A backslash before the opening underline delimiter makes the run not live")
    func backslashBeforeOpeningUnderlineIsNotLive() {
        let text = "\\<u>x</u>" as NSString
        let run = text.range(of: "<u>x</u>")
        let marks = Escapes.scan(text)
        #expect(!marks.isLive(run, closeLength: 4))
    }

    /// The escape sits on the closing `</u>` here, not the opening `<u>`, so
    /// only the correct `closeLength` locates it. Passing 1 instead (as if a
    /// single `<` closed the run) checks the wrong offset and flips the
    /// answer, which is what makes the parameter demonstrably load-bearing
    /// rather than decorative.
    @Test("Passing the wrong closeLength for an escaped closing underline delimiter flips the answer")
    func wrongCloseLengthFlipsAnswerForEscapedClosingUnderline() {
        let text = "<u>x\\</u>" as NSString
        let run = NSRange(location: 0, length: text.length)
        let marks = Escapes.scan(text)
        #expect(!marks.isLive(run, closeLength: 4))
        #expect(marks.isLive(run, closeLength: 1))
    }

    @Test("Backslashes elsewhere in the text don't affect an untouched code span")
    func backslashesElsewhereDoNotAffectUntouchedSpan() {
        let text = "\\*x* `code` trailing" as NSString
        let run = text.range(of: "`code`")
        let marks = Escapes.scan(text)
        #expect(!marks.isEmpty)
        #expect(marks.isLive(run, closeLength: 1))
    }

    @Test("Marks.none reports any range as live, the no-backslashes fast path")
    func noneMarksReportsAnyRangeAsLive() {
        #expect(Escapes.Marks.none.isLive(NSRange(location: 0, length: 0), closeLength: 0))
        #expect(Escapes.Marks.none.isLive(NSRange(location: 1_000, length: 50), closeLength: 10))
    }

    /// Backslashes present elsewhere in the text (so the real check runs,
    /// not the `isEmpty` fast path) with the run itself sitting at offset 0,
    /// exercising the low end of the `range.location + range.length -
    /// closeLength` arithmetic.
    @Test("A run starting at offset 0 stays live when nothing on it is escaped")
    func runAtOffsetZeroIsLive() {
        let text = "`code` \\*x*" as NSString
        let run = text.range(of: "`code`")
        #expect(run.location == 0)
        let marks = Escapes.scan(text)
        #expect(!marks.isEmpty)
        #expect(marks.isLive(run, closeLength: 1))
    }

    /// Same as above but at the other boundary: the run ends exactly at
    /// `text.length`, so the closing offset lands on the last valid index.
    @Test("A run ending at the very end of the text stays live when nothing on it is escaped")
    func runAtEndOfTextIsLive() {
        let text = "\\*x* some text `code`" as NSString
        let run = text.range(of: "`code`")
        #expect(run.location + run.length == text.length)
        let marks = Escapes.scan(text)
        #expect(!marks.isEmpty)
        #expect(marks.isLive(run, closeLength: 1))
    }
}
