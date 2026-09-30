import AppKit

/// The help page's content and typesetting, pure functions of the keymap so they test without a
/// window. Rows read chords from the live keymap; the literal ones have nothing to bind.
public struct HelpDocument: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        /// A middot joins separate actions; a slash joins one action's aliases.
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

        func group(_ actions: KeymapAction...) -> String {
            actions.map(chord).joined(separator: " · ")
        }

        return HelpDocument(sections: [
            Section("Wisp", [
                Row(chord(.summon), "tap to pin · hold to peek · tap again to dismiss"),
                Row(chord(.resetPosition), "reset panel position"),
                Row("⌘↑ · ⌘↓", "move to beginning · end"),
                Row(chord(.refresh), "refresh"),
                Row(chord(.reveal), "reveal note in finder"),
                Row(
                    group(.increaseFontScale, .decreaseFontScale, .resetFontScale),
                    "larger · smaller · reset font"),
                Row(chord(.settings), "settings"),
            ]),
            Section("Edit", [
                Row(chord(.find), "find… — ↵ · ⇧↵ to step"),
                Row("↵ · ⇧↵", "find next · previous"),
                Row(chord(.duplicateLine), "duplicate line or selection"),
                Row(group(.openLineBelow, .openLineAbove), "new line below · above"),
                Row("⌘← · ↖", "start of list text · then of line"),
                Row("⌘→ · ↘", "end of line"),
                Row(group(.previousHeading, .nextHeading), "previous · next heading"),
                Row(chord(.spellcheck), "check spelling as you type"),
            ]),
            Section("Format", [
                Row(chord(.bulletedList), "toggle bulleted list"),
                Row(chord(.checklist), "toggle checklist · check it off"),
                Row(group(.moveLineUp, .moveLineDown), "move line or selection"),
                // Split in two: six chords overflow the key gutter.
                Row(group(.bold, .highlight, .italic), "bold · highlight · italic"),
                Row(
                    group(.underline, .strikethrough, .code),
                    "underline · strikethrough · code"),
                Row("⇥ · ⇧⇥ · ⌫", "increase · decrease indentation — ⌫ inside it"),
                Row("⇧↵", "continue an item on a new line"),
                Row("` · _ · ' · \" · ** · == · ~~", "wrap selection"),
                Row(chord(.sourceView), "source view — raw text"),
            ]),
            Section("Insert", [
                Row("- · * · +", "bulleted list"),
                Row("1. · 1) · A. · a.", "numbered list"),
                Row("- [ ]", "checklist — click the box to check it"),
                Row("# · ## · ###", "headings — or === · --- under a line"),
                Row("--- · *** · ___", "horizontal rule"),
                Row("↵ ↵ ↵", "rule after a paragraph — ↵ again removes it"),
                Row("--", "em dash — - or > again gives back --- or -->"),
                Row("⌘V on a blank line", "grid → table, lines → list"),
            ]),
        ])
    }
}

/// Resolved fonts rather than sizes, so rendering never reaches into main-actor `Typography`.
public struct HelpTextStyle: Equatable {
    public var rowFont: NSFont
    public var sectionFont: NSFont
    public var keyColor: NSColor
    public var detailColor: NSColor
    public var sectionColor: NSColor

    /// Shared with the sticky header, so its copy lands exactly on the real title.
    public var sectionTitleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: sectionFont,
            .foregroundColor: sectionColor,
            .kern: sectionFont.pointSize * Metrics.helpSectionTracking,
        ]
    }

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

    /// In multiples of the row size, so the columns keep their proportions as the scale moves.
    public var keyColumnWidth: CGFloat { rowFont.pointSize * Metrics.helpKeyColumnRatio }
    public var columnGap: CGFloat { rowFont.pointSize * Metrics.helpColumnGapRatio }
    public var detailIndent: CGFloat { keyColumnWidth + columnGap }
}

/// A typeset help page. The sticky header turns the title ranges into y positions.
public struct RenderedHelp {
    public let attributed: NSAttributedString
    /// Index-aligned to `HelpDocument.sections`.
    public let sectionTitleRanges: [NSRange]
}

extension HelpDocument {
    /// Exactly the text `render` produces, so find can search it and highlight the same ranges.
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
            var attributes = style.sectionTitleAttributes
            attributes[.paragraphStyle] = Self.sectionParagraphStyle(isFirst: index == 0)
            output.append(NSAttributedString(string: title + "\n", attributes: attributes))
            // Stops before the newline, or the sticky header would sit a fragment low.
            titleRanges.append(NSRange(location: start, length: (title as NSString).length))

            let rowStyle = Self.rowParagraphStyle(style: style)
            for row in section.rows {
                // The leading tab carries the key to the right-aligned stop.
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

    /// The first section's gap is the container inset; see `Metrics.helpRowSpacing`.
    private static func sectionParagraphStyle(isFirst: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = isFirst ? 0 : Metrics.chromeInsetY
        style.paragraphSpacing = Metrics.chromeInsetY
        return style
    }

    private static func rowParagraphStyle(style: HelpTextStyle) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        // `headIndent` repeats the left stop so a wrapped description lines up under itself.
        paragraph.tabStops = [
            NSTextTab(textAlignment: .right, location: style.keyColumnWidth),
            NSTextTab(textAlignment: .left, location: style.detailIndent),
        ]
        paragraph.headIndent = style.detailIndent
        // Beyond the gutter, so no default stop can catch a tab.
        paragraph.defaultTabInterval = style.detailIndent
        paragraph.paragraphSpacingBefore = Metrics.helpRowSpacing
        paragraph.paragraphSpacing = Metrics.helpRowSpacing
        paragraph.lineBreakMode = .byWordWrapping
        return paragraph
    }
}
