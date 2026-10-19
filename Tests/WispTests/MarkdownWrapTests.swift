import AppKit
import Testing

@testable import Wisp

@Suite("MarkdownWrap", .serialized)
@MainActor
struct MarkdownWrapTests {
    private let formats: [MarkdownWrap.Markers] = [
        .bold, .italic, .highlight, .underline, .strikethrough, .code,
    ]

    @Test("Repeated formatting toggles preserve the selected text and surrounding Unicode")
    func togglesInnerSelection() {
        let original = "👋 café 🐈 end"
        let selection = (original as NSString).range(of: "café 🐈")
        for markers in formats {
            let view = NSTextView()
            view.string = original
            view.setSelectedRange(selection)

            for _ in 0..<2 {
                MarkdownWrap.toggle(in: view, markers: markers)
                #expect(view.string == "👋 \(markers.open)café 🐈\(markers.close) end")
                #expect(view.selectedRange() == NSRange(
                    location: selection.location + (markers.open as NSString).length,
                    length: selection.length))

                MarkdownWrap.toggle(in: view, markers: markers)
                #expect(view.string == original)
                #expect(view.selectedRange() == selection)
            }
        }
    }

    @Test("Selecting the markers still unwraps the text")
    func togglesFullSelection() {
        for markers in formats {
            let view = NSTextView()
            view.string = markers.open + "word" + markers.close
            view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))

            MarkdownWrap.toggle(in: view, markers: markers)

            #expect(view.string == "word")
            #expect(view.selectedRange() == NSRange(location: 0, length: 4))
        }
    }

    @Test("Unpaired surrounding markers are not removed")
    func keepsUnpairedMarkers() {
        for original in ["**word", "word**", "**word_", "**word x**"] {
            let view = NSTextView()
            view.string = original
            let selection = (original as NSString).range(of: "word")
            view.setSelectedRange(selection)

            MarkdownWrap.toggle(in: view, markers: .bold)

            #expect(view.string == (original as NSString).replacingCharacters(
                in: selection, with: "**word**"))
        }
    }

    @Test("Typing a delimiter still wraps rather than toggling")
    func typedDelimiterAlwaysWraps() {
        let view = NSTextView()
        view.string = "**word**"
        let selection = NSRange(location: 2, length: 4)

        MarkdownWrap.wrap(in: view, range: selection, markers: .bold)

        #expect(view.string == "****word****")
        #expect(view.selectedRange() == NSRange(location: 4, length: 4))
    }

    @Test("Formatting at the caret inserts a marker pair")
    func insertsAtCaret() {
        for markers in formats {
            let view = NSTextView()
            view.string = "ab"
            view.setSelectedRange(NSRange(location: 1, length: 0))

            MarkdownWrap.toggle(in: view, markers: markers)

            #expect(view.string == "a" + markers.open + markers.close + "b")
            #expect(view.selectedRange() == NSRange(
                location: 1 + (markers.open as NSString).length, length: 0))
        }
    }
}
