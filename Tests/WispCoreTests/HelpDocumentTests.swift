import AppKit
import Testing

@testable import WispCore

@Suite("HelpDocument")
struct HelpDocumentTests {
    /// Computed, since `HelpTextStyle` holds `NSFont`s and a stored static must be `Sendable`.
    private static var style: HelpTextStyle {
        HelpTextStyle(
            rowFont: .systemFont(ofSize: 16),
            sectionFont: .systemFont(ofSize: 11.5),
            keyColor: .white,
            detailColor: .gray,
            sectionColor: .cyan
        )
    }

    /// Find searches `plainText` and highlights the same ranges in the rendered text.
    @Test("plainText is exactly what the renderer typesets")
    func plainTextMatchesRender() {
        let document = HelpDocument.make(keymap: Keymap())
        #expect(document.render(style: Self.style).attributed.string == document.plainText)
    }

    @Test("Section title ranges point at the uppercased titles")
    func sectionRanges() {
        let document = HelpDocument.make(keymap: Keymap())
        let rendered = document.render(style: Self.style)
        let text = rendered.attributed.string as NSString

        #expect(rendered.sectionTitleRanges.count == document.sections.count)
        for (section, range) in zip(document.sections, rendered.sectionTitleRanges) {
            #expect(text.substring(with: range) == section.title.uppercased())
        }
    }

    @Test("Rows carry the configured chord, including a row that joins several")
    func rowsFollowTheKeymap() {
        let rebound = Keymap([
            .reveal: "ctrl+shift+f", .underline: "ctrl+shift+u",
            .strikethrough: "ctrl+shift+x", .code: "ctrl+shift+e",
        ])
        let rows = HelpDocument.make(keymap: rebound).sections.flatMap(\.rows)

        #expect(rows.first { $0.detail == "reveal note in finder" }?.key == "⌃⇧F")

        let format = rows.first { $0.detail == "underline · strikethrough · code" }?.key
        #expect(format?.contains("⌃⇧U") == true)
        #expect(format?.contains("⌃⇧X") == true)
        // The row lists chords in the description's order.
        #expect(format?.hasSuffix("⌃⇧E") == true)
    }

    @Test("Every default row's key fits the key gutter")
    func keysFitTheGutter() {
        let style = Self.style
        let rows = HelpDocument.make(keymap: Keymap()).sections.flatMap(\.rows)
        for row in rows {
            let width = (row.key as NSString).size(withAttributes: [.font: style.rowFont]).width
            #expect(width <= style.keyColumnWidth, "\(row.key) is \(width)pt wide")
        }
    }

    @Test("The key gutter tracks the row font size")
    func gutterScales() {
        var doubled = Self.style
        doubled.rowFont = .systemFont(ofSize: 32)

        #expect(doubled.keyColumnWidth == Self.style.keyColumnWidth * 2)
        #expect(doubled.detailIndent > doubled.keyColumnWidth)
    }
}
