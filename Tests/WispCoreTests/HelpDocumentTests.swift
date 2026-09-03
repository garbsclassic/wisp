import AppKit
import Testing

@testable import WispCore

@Suite("HelpDocument")
struct HelpDocumentTests {
    /// Computed, not a stored static: `HelpTextStyle` holds `NSFont`s and so
    /// isn't `Sendable`, which a shared global would have to be.
    private static var style: HelpTextStyle {
        HelpTextStyle(
            rowFont: .systemFont(ofSize: 16),
            sectionFont: .systemFont(ofSize: 11.5),
            keyColor: .white,
            detailColor: .gray,
            sectionColor: .cyan
        )
    }

    /// The load-bearing invariant: find searches `plainText` and hands the
    /// resulting ranges straight to the text view, so the two strings have to
    /// agree character for character or every highlight lands off by however
    /// far they have drifted.
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

    /// The page reads the live keymap rather than printing the glyphs it was
    /// drawn with, so a rebind shows up without anyone editing a string.
    @Test("Rows carry the configured chord, not the default one")
    func rowsFollowTheKeymap() {
        let rebound = Keymap([.duplicateLine: "ctrl+shift+k"])
        let document = HelpDocument.make(keymap: rebound)
        let row = document.sections
            .flatMap(\.rows)
            .first { $0.detail == "duplicate line or selection" }

        #expect(row?.key == "⌃⇧K")
    }

    /// A hyperkey summon is the reason the glyph exists; this is the row it
    /// was added for.
    @Test("A hyperkey summon reaches the page as one glyph")
    func hyperkeySummon() {
        let document = HelpDocument.make(keymap: Keymap([.summon: "ctrl+opt+shift+cmd+."]))
        let row = document.sections.flatMap(\.rows).first { $0.detail == "summon · dismiss panel" }

        #expect(row?.key == "❖.")
    }

    /// The gutter is carried as a multiple of the row size, so the two
    /// columns keep their proportions when the text scale moves.
    @Test("The key gutter tracks the row font size")
    func gutterScales() {
        var doubled = Self.style
        doubled.rowFont = .systemFont(ofSize: 32)

        #expect(doubled.keyColumnWidth == Self.style.keyColumnWidth * 2)
        #expect(doubled.detailIndent > doubled.keyColumnWidth)
    }
}
