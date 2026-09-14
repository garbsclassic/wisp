import Foundation
import Testing

@testable import WispCore

@Suite("CaretPosition")
struct CaretPositionTests {
    @Test("Offset zero is line one, column one")
    func start() {
        let position = CaretPosition(in: "hello", at: 0)
        #expect(position.line == 1)
        #expect(position.column == 1)
    }

    @Test("An offset mid first line counts characters from the line start")
    func midFirstLine() {
        let position = CaretPosition(in: "hello world", at: 6)
        #expect(position.line == 1)
        #expect(position.column == 7)
    }

    @Test("The first character after a newline is line two, column one")
    func startOfSecondLine() {
        let position = CaretPosition(in: "alpha\nbeta", at: 6)
        #expect(position.line == 2)
        #expect(position.column == 1)
    }

    @Test("A caret after a trailing newline is on the line past the last one")
    func endWithTrailingNewline() {
        let position = CaretPosition(in: "alpha\nbeta\n", at: 11)
        #expect(position.line == 3)
        #expect(position.column == 1)
    }

    @Test("An emoji before the caret counts as one column, not one per UTF-16 unit")
    func emojiCountsAsOneColumn() {
        // 🎉 is two UTF-16 code units but a single Character.
        let position = CaretPosition(in: "🎉x", at: (("🎉x" as NSString).length))
        #expect(position.line == 1)
        #expect(position.column == 3)
    }

    @Test("An offset past the end clamps to the end of the text")
    func offsetPastEndClamps() {
        let text = "alpha\nbeta"
        let clamped = CaretPosition(in: text, at: 1000)
        let atEnd = CaretPosition(in: text, at: (text as NSString).length)
        #expect(clamped == atEnd)
    }

    @Test("A negative offset clamps to the start of the text")
    func negativeOffsetClamps() {
        let clamped = CaretPosition(in: "alpha", at: -5)
        let atStart = CaretPosition(in: "alpha", at: 0)
        #expect(clamped == atStart)
    }
}
