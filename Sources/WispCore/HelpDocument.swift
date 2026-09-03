import AppKit

/// The help page's content and its typesetting, as a value.
///
/// Both halves live here rather than in the view because both are pure
/// functions of a `Keymap` and a `Palette` — which makes them testable
/// without a window, and keeps `HelpBody` down to scrolling, selection,
/// and the sticky header.
///
/// Chords come from the live keymap, so a rebind shows up on the page
/// without anyone editing a string. The rows that are literals are the ones
/// with nothing to bind: AppKit's own keys (⌘↑, ⇥) and Wisp's smart-editing
/// triggers.
public struct HelpDocument: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        /// Right-aligned in the key gutter. Several alternatives for one
        /// idea are joined with a middot; an alias list for a single action
        /// arrives from `Keymap.display` joined with a slash.
        public let key: String
        public let detail: String

        public init(_ key: String, _ detail: String) {
            self.key = key
            self.detail = detail
        }
    }

    public struct Section: Equatable, Sendable {
        public let title: String
        public let rows: [Row]

        public init(_ title: String, _ rows: [Row]) {
            self.title = title
            self.rows = rows
        }
    }

    public let sections: [Section]

    public init(sections: [Section]) {
        self.sections = sections
    }

    public static func make(keymap: Keymap) -> HelpDocument {
        func chord(_ action: KeymapAction) -> String { keymap.display(action) }

        /// Distinct actions that read as one idea — "larger · smaller ·
        /// reset text". The middot separates *actions*; a slash inside any
        /// one of these separates that action's own aliases.
        func group(_ actions: KeymapAction...) -> String {
            actions.map(chord).joined(separator: " · ")
        }

        return HelpDocument(sections: [
            Section("Wisp", [
                Row(chord(.summon), "summon · dismiss panel"),
                Row("⌘↑ · ⌘↓", "move to beginning · end"),
                Row(chord(.refresh), "refresh"),
                Row(chord(.revealNote), "reveal note in finder"),
                Row(
                    group(.increaseFontScale, .decreaseFontScale, .resetFontScale),
                    "larger · smaller · reset text"),
                Row(chord(.settings), "settings"),
            ]),
            Section("Edit", [
                Row(chord(.find), "find… — ↵ · ⇧↵ to step"),
                Row("↵ · ⇧↵", "find next · previous"),
                Row(chord(.duplicateLine), "duplicate line or selection"),
            ]),
            Section("Format", [
                Row(chord(.toggleListItem), "toggle bullet list"),
                Row(group(.moveLineUp, .moveLineDown), "move line or selection"),
                Row(
                    group(.bold, .highlight, .italic, .underline, .code),
                    "bold · highlight · italic · underline · code"),
                Row("⇥ · ⇧⇥", "increase · decrease indentation"),
            ]),
            Section("Insert", [
                Row("- · * · +", "bulleted list"),
                Row("1. · A. · a.", "numbered list"),
                Row("# · ## · ###", "headings"),
                Row("---", "horizontal rule"),
                Row(":) · :rocket:", "emojis — 🙂 · 🚀 · etc"),
            ]),
        ])
    }
}

/// Everything the renderer needs that isn't content: two resolved faces,
/// three colors, and the geometry of the key gutter.
///
/// Fonts arrive resolved rather than as sizes so `HelpDocument` never has to
/// reach into `Typography`, which is `@MainActor` — the renderer stays a
/// plain function a test can call.
public struct HelpTextStyle: Equatable {
    public var rowFont: NSFont
    public var sectionFont: NSFont
    public var keyColor: NSColor
    public var detailColor: NSColor
    public var sectionColor: NSColor

    public init(
        rowFont: NSFont, sectionFont: NSFont,
        keyColor: NSColor, detailColor: NSColor, sectionColor: NSColor
    ) {
        self.rowFont = rowFont
        self.sectionFont = sectionFont
        self.keyColor = keyColor
        self.detailColor = detailColor
        self.sectionColor = sectionColor
    }

    /// The key gutter's right edge and the gap to the description, both in
    /// multiples of the row size so the two columns keep their proportions
    /// as the text scale moves.
    public var keyColumnWidth: CGFloat { rowFont.pointSize * Metrics.helpKeyColumnRatio }
    public var columnGap: CGFloat { rowFont.pointSize * Metrics.helpColumnGapRatio }
    public var detailIndent: CGFloat { keyColumnWidth + columnGap }
}

/// A typeset help page, plus where its section titles landed.
///
/// The ranges are what the sticky header needs: they turn into y positions
/// through the layout manager, which is the only way to know when one
/// section has scrolled far enough to hand off to the next.
public struct RenderedHelp {
    public let attributed: NSAttributedString
    /// Index-aligned to `HelpDocument.sections`.
    public let sectionTitleRanges: [NSRange]
}

extension HelpDocument {
    /// The page as plain text, character for character what `render` puts in
    /// the text storage — which is what lets find search this without a
    /// window, and hand back ranges the text view can highlight directly.
    /// `HelpDocumentTests` pins the two together.
    public var plainText: String {
        sections.map { section in
            section.title.uppercased() + "\n"
                + section.rows.map { "\t\($0.key)\t\($0.detail)\n" }.joined()
        }.joined()
    }

    public func render(style: HelpTextStyle) -> RenderedHelp {
        let output = NSMutableAttributedString()
        var titleRanges: [NSRange] = []

        for (index, section) in sections.enumerated() {
            let title = section.title.uppercased()
            let start = output.length
            output.append(
                NSAttributedString(
                    string: title + "\n",
                    attributes: [
                        .font: style.sectionFont,
                        .foregroundColor: style.sectionColor,
                        .kern: style.sectionFont.pointSize * Metrics.helpSectionTracking,
                        .paragraphStyle: Self.sectionParagraphStyle(isFirst: index == 0),
                    ]))
            // The trailing newline belongs to the paragraph, not the title —
            // a sticky header measuring the line break would sit a fragment
            // low.
            titleRanges.append(NSRange(location: start, length: (title as NSString).length))

            let rowStyle = Self.rowParagraphStyle(style: style)
            for row in section.rows {
                // Leading tab first: it is what carries the caret to the
                // right-aligned stop, so the key ends flush at the gutter.
                output.append(
                    NSAttributedString(
                        string: "\t" + row.key + "\t",
                        attributes: [
                            .font: style.rowFont,
                            .foregroundColor: style.keyColor,
                            .paragraphStyle: rowStyle,
                        ]))
                output.append(
                    NSAttributedString(
                        string: row.detail + "\n",
                        attributes: [
                            .font: style.rowFont,
                            .foregroundColor: style.detailColor,
                            .paragraphStyle: rowStyle,
                        ]))
            }
        }

        return RenderedHelp(attributed: output, sectionTitleRanges: titleRanges)
    }

    /// The first section takes none: its gap is in the text container's own
    /// inset, where AppKit can't decline to draw it. See the note on
    /// `Metrics.helpRowSpacing`.
    private static func sectionParagraphStyle(isFirst: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = isFirst ? 0 : Metrics.chromeInsetY
        style.paragraphSpacing = Metrics.chromeInsetY
        return style
    }

    private static func rowParagraphStyle(style: HelpTextStyle) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        // Right stop for the key, left stop for the description. `headIndent`
        // repeats the left stop so a description that wraps lines up under
        // itself rather than running back under the gutter.
        paragraph.tabStops = [
            NSTextTab(textAlignment: .right, location: style.keyColumnWidth),
            NSTextTab(textAlignment: .left, location: style.detailIndent),
        ]
        paragraph.headIndent = style.detailIndent
        // Past the last explicit stop AppKit falls back to this interval; put
        // it beyond the gutter so a stray default stop can't catch a tab.
        paragraph.defaultTabInterval = style.detailIndent
        paragraph.paragraphSpacingBefore = Metrics.helpRowSpacing
        paragraph.paragraphSpacing = Metrics.helpRowSpacing
        paragraph.lineBreakMode = .byWordWrapping
        return paragraph
    }
}
