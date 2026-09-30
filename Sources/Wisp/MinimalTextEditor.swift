import SwiftUI
import AppKit
import WispCore

extension NSTextView {
    /// Replace `range` with `replacement` through the `shouldChangeText` /
    /// `didChangeText` bookkeeping AppKit's own edit path uses — required for
    /// undo grouping and delegate notifications to fire on a hand-rolled
    /// edit. Returns false, performing no edit, if the delegate refuses.
    @discardableResult
    func replaceText(in range: NSRange, with replacement: String) -> Bool {
        guard shouldChangeText(in: range, replacementString: replacement) else { return false }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        return true
    }
}

struct MinimalTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// The caret's UTF-16 offset, written on every selection change for the
    /// footer's line:column and the heading jumps.
    @Binding var caretOffset: Int
    var focusToken: Int
    var scrollToken: Int
    var scrollTarget: Int
    var findHighlightToken: Int
    var findHighlightRange: NSRange
    var style: BodyStyle
    var smartPaste: Bool
    /// Applied on the text view directly; no restyle, since it changes
    /// nothing in the storage.
    var caret: Caret
    /// Applied on the text view directly, like `caret`.
    var spellcheck: Bool
    /// The text view's own Check Spelling While Typing item routes here, so
    /// the model — and the footer — stay the one source of truth.
    var onToggleSpellcheck: () -> Void

    /// Everything the body's attributes depend on besides the text itself.
    /// Compared in `updateNSView`, since the resolved attributes live in the
    /// storage and nothing re-derives them on their own when one moves.
    struct BodyStyle: Equatable {
        var theme: Theme
        /// The live text scale. `Typography` applies it; it is here so a
        /// change restyles the body, whose fonts are resolved `NSFont`s.
        var fontScale: Double
        var indent: Indent
        /// ⌘↩. Every styling pass is skipped and the body is set in the code
        /// face, so the screen shows the file.
        var isSourceView: Bool
        /// Drawing only: the rule's line and the blank lines around it are
        /// styled the same either way.
        var rule: RuleStyle
    }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = NotesTextView.makeScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = false

        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = Self.baseFont(isSourceView: style.isSourceView)
        textView.defaultParagraphStyle = Self.makeParagraphStyle()
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = false
        textView.isContinuousSpellCheckingEnabled = spellcheck
        textView.onToggleSpellcheck = onToggleSpellcheck
        if spellcheck { textView.checkSpellingEverywhere() }
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.smartPaste = smartPaste
        textView.caretStyle = caret
        textView.string = text

        context.coordinator.syncedText = text
        context.coordinator.style = style
        Self.restyle(textView, style: style)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NotesTextView else { return }
        let coordinator = context.coordinator
        // Against the last text either side handed over rather than against
        // `textView.string`: the two share storage after an edit, which makes
        // this free, where comparing the bridged storage costs a full scan on
        // every body pass.
        if text != coordinator.syncedText {
            // Assigning `.string` throws away every attribute in the
            // storage, so the incoming text arrives unstyled. The layout
            // manager draws rules and bullets from the *text*, but what
            // hides the characters they stand in for is the styling pass.
            textView.string = text
            coordinator.syncedText = text
            Self.restyle(textView, style: style)
        }
        let previous = coordinator.style
        if previous != style {
            coordinator.style = style
            var ruleOnly = previous
            ruleOnly.rule = style.rule
            if ruleOnly == style {
                (textView.layoutManager as? NotesLayoutManager)?.ruleStyle = style.rule
                textView.needsDisplay = true
            } else {
                Self.restyle(textView, style: style)
                // The match background is a storage attribute the restyle
                // leaves alone, so repaint it in the incoming theme's color.
                if previous.theme != style.theme { applyFindHighlight(to: textView, scroll: false) }
            }
        }
        if textView.caretStyle != caret {
            textView.caretStyle = caret
        }
        if textView.isContinuousSpellCheckingEnabled != spellcheck {
            textView.isContinuousSpellCheckingEnabled = spellcheck
            if spellcheck { textView.checkSpellingEverywhere() }
        }
        textView.smartPaste = smartPaste
        if coordinator.lastFocusToken != focusToken {
            coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        if coordinator.lastScrollToken != scrollToken {
            coordinator.lastScrollToken = scrollToken
            let target = scrollTarget
            DispatchQueue.main.async {
                let length = (textView.string as NSString).length
                let safe = max(0, min(target, length))
                let range = NSRange(location: safe, length: 0)
                textView.scrollRangeToVisible(range)
                textView.setSelectedRange(range)
                textView.window?.makeFirstResponder(textView)
            }
        }
        if coordinator.lastFindHighlightToken != findHighlightToken {
            coordinator.lastFindHighlightToken = findHighlightToken
            applyFindHighlight(to: textView, scroll: true)
        }
    }

    /// The face the whole body is set in. Raw mode takes the code family,
    /// which is what makes "this is the file" legible at a glance rather
    /// than something you have to infer from the absence of bold.
    static func baseFont(isSourceView: Bool) -> NSFont {
        isSourceView
            ? Typography.codeFont(Metrics.bodySize) : Typography.notesFont(Metrics.bodySize)
    }

    private static func makeParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Metrics.bodyLineHeightMultiple
        return paragraph
    }

    /// Paints the current find match. `scroll` is false when repainting
    /// for a theme change — the match hasn't moved, so pulling the view
    /// to it would be jarring.
    private func applyFindHighlight(to textView: NSTextView, scroll: Bool) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        let palette = Palette.for(style.theme)
        let range = findHighlightRange
        let hasMatch = range.length > 0 && NSMaxRange(range) <= full.length
        // Closed before the scroll below, which lays out glyphs — TextKit
        // throws if that happens while the storage is mid-edit.
        storage.beginEditing()
        // Use a real storage background attribute (not a temporary layout
        // attribute): storage mutations always trigger a redraw, so the
        // highlight clears deterministically. It is never written to disk —
        // we save `.string`.
        storage.removeAttribute(.backgroundColor, range: full)
        // `==marked==` shares the attribute, so it is repainted before the
        // match goes on top. Without this, opening Find erases every
        // highlight in the note. Not in source view, where there is no
        // `==marked==` to put back — only the match itself is painted.
        if !style.isSourceView {
            let marks = Escapes.scan(storage.string)
            Self.styleHighlights(
                in: storage, palette: palette, masked: marks.masking(storage.string) as NSString)
        }
        if hasMatch {
            storage.addAttribute(.backgroundColor, value: palette.findHighlight, range: range)
        }
        storage.endEditing()

        if hasMatch, scroll { textView.scrollRangeToVisible(range) }
    }

    /// Everything the body is drawn with: the text view's colors, the layout
    /// manager's marks, and the storage's attributes.
    static func restyle(_ textView: NotesTextView, style: BodyStyle) {
        let palette = Palette.for(style.theme)
        let font = baseFont(isSourceView: style.isSourceView)
        textView.indentUnit = style.indent.unit
        textView.textColor = palette.text
        textView.insertionPointColor = palette.text
        textView.selectedTextAttributes = [
            .backgroundColor: palette.selection
        ]
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: palette.text,
            .paragraphStyle: makeParagraphStyle(),
        ]
        if let lm = textView.layoutManager as? NotesLayoutManager {
            lm.ruleColor = palette.rule
            lm.bulletColor = palette.text
            lm.bulletFont = font
            lm.indentWidth = style.indent.width
            lm.indentUnit = style.indent.unit
            lm.guideColor = palette.faint
            lm.isSourceView = style.isSourceView
            lm.ruleStyle = style.rule
            lm.seamColor = palette.faint
        }
        if let storage = textView.textStorage { restyleStorage(storage, style: style) }
    }

    /// The storage's half of `restyle`, and all an edit needs. `blocks`, when
    /// the caller already classified the text, saves doing it again.
    static func restyleStorage(
        _ storage: NSTextStorage, style: BodyStyle, blocks: MarkdownBlocks? = nil
    ) {
        let palette = Palette.for(style.theme)
        let font = baseFont(isSourceView: style.isSourceView)
        // One `processEditing` for the whole pass, rather than one per
        // attribute, each invalidating layout on its own.
        storage.beginEditing()
        defer { storage.endEditing() }
        resetBaseAttributes(
            in: storage, font: font, color: palette.text, paragraph: makeParagraphStyle())
        guard !style.isSourceView else {
            // `resetBaseAttributes` leaves `.backgroundColor` alone, since
            // the find match rides on it and a restyle must not wipe the
            // match. Nothing repaints `==marked==` in source view, so it has
            // to go here or an amber wash survives into a mode whose whole
            // point is that nothing is styled.
            storage.removeAttribute(
                .backgroundColor, range: NSRange(location: 0, length: storage.length))
            return
        }
        restyleContent(
            in: storage, baseFont: font, indent: style.indent, palette: palette,
            blocks: blocks ?? MarkdownBlocks(storage.string as NSString))
    }

    /// Wipes the whole storage back to plain body text, so a content pass
    /// can run against a known state.
    ///
    /// `.kern`, `.underlineStyle`, `.strikethroughStyle`, and `.horizontalRule` are *removed*
    /// rather than overwritten: none has a base value to reset to, and each is set on ranges that
    /// move as the text is edited — a marker's kern would otherwise stay on whatever character
    /// ends up at that offset, and a `<u>` rule would outlive the markers that asked for it.
    /// `.backgroundColor` stays, since the find match rides on it.
    static func resetBaseAttributes(
        in storage: NSTextStorage, font: NSFont, color: NSColor, paragraph: NSParagraphStyle
    ) {
        let range = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.kern, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.removeAttribute(.horizontalRule, range: range)
        storage.addAttributes(
            [.font: font, .foregroundColor: color, .paragraphStyle: paragraph], range: range)
    }

    /// Everything that depends on the text's own content, in the order the
    /// attributes have to land: structural passes first, then the inline
    /// ones that read whatever font the structure left behind.
    ///
    /// Always run over the whole storage against a freshly reset base, so a
    /// line that *stopped* being a rule or a list item loses the styling it
    /// had.
    ///
    /// Headings come from the storage's own `MarkdownBlocks` rather than
    /// from `EditorModel.headings`, so the styling always describes the text
    /// it is applied to.
    private static func restyleContent(
        in storage: NSTextStorage, baseFont: NSFont, indent: Indent, palette: Palette,
        blocks: MarkdownBlocks
    ) {
        let ns = storage.string as NSString
        let marks = Escapes.scan(ns)
        let widths = Widths(font: baseFont)
        styleLists(in: storage, widths: widths, indent: indent, palette: palette)
        styleHeadings(
            in: storage, baseFont: baseFont, palette: palette, headings: blocks.headings(in: ns))
        styleInlineMarkup(in: storage, baseFont: baseFont, palette: palette, marks: marks)
        // Last: `***` and `_ _ _` also match the inline emphasis patterns, which would paint
        // over the clear that hides a rule's characters.
        styleHorizontalRules(in: storage, baseFont: baseFont, blocks: blocks)
    }

    /// Apply bold, a per-level size, and a per-level colour to each heading: a `#` line, or a
    /// paragraph through its `===` or `---` underline. The marker that makes it a heading is
    /// dimmed. Plain text on disk; these are per-range attributes so the heading reads as a
    /// section title without leaving plain-text mode.
    private static func styleHeadings(
        in storage: NSTextStorage, baseFont: NSFont, palette: Palette, headings: [Heading]
    ) {
        // One font per level: a note repeats a handful of levels, and each is a descriptor
        // lookup.
        var fonts: [Int: NSFont] = [:]
        for heading in headings {
            let font = fonts[heading.level] ?? headingFont(level: heading.level, baseFont: baseFont)
            fonts[heading.level] = font
            let color = palette.headings[heading.level - 1]
            let styleRange = NSRange(
                location: heading.lineStart, length: heading.end - heading.lineStart)
            storage.addAttribute(.font, value: font, range: styleRange)
            storage.addAttribute(.foregroundColor, value: color, range: styleRange)
            storage.addAttribute(.foregroundColor, value: palette.faint, range: heading.marker)
        }
    }

    private static func headingFont(level: Int, baseFont: NSFont) -> NSFont {
        let scaledSize = baseFont.pointSize * Metrics.headingRatios[level - 1]
        let boldDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: boldDescriptor, size: scaledSize) ?? baseFont
    }

    /// Give every list line a hanging indent, and hide the `-` / `*` / `+`
    /// or `- [ ]` so `NotesLayoutManager` can draw a glyph in the space it
    /// reserved.
    ///
    /// The measurements come from the rendered text rather than from a
    /// points-per-character guess: the head indent has to land exactly
    /// where the content starts, or a wrapped line sits a hair off the one
    /// above it. Ordered markers stay visible — `1.` is its own content.
    ///
    /// A continuation line — whitespace out to the item's content column,
    /// what ⇧↵ writes — is pulled to that same column. Inter is
    /// proportional, so the spaces on their own land a hair off it.
    private static func styleLists(
        in storage: NSTextStorage, widths: Widths, indent: Indent, palette: Palette
    ) {
        let ns = storage.string as NSString
        let total = ns.length
        var lineStart = 0
        var previous: (item: SmartEditing.ListItem, line: NSRange, contentOffset: CGFloat)?
        while lineStart < total {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            defer { lineStart = lineRange.location + lineRange.length }
            guard let item = SmartEditing.listItem(lineRange: lineRange, in: ns) else {
                if let previous,
                    SmartEditing.isContinuation(
                        lineRange: lineRange, in: ns, of: previous.item, itemLine: previous.line)
                {
                    styleContinuation(
                        lineRange: lineRange, in: storage, widths: widths,
                        contentOffset: previous.contentOffset,
                        color: previous.item.marker == .checklist(checked: true) ? palette.muted : nil)
                } else {
                    previous = nil
                }
                continue
            }

            // The leading whitespace is indented by its own width on top of
            // rendering itself, so a nested item steps in twice as far as
            // its spaces alone would take it — a two-space unit in Inter is
            // eight points, which is not a visible nesting step. Everything
            // measured from here has to include it.
            let indentOffset = widths.of(
                ns.substring(with: NSRange(location: lineRange.location, length: item.indentWidth)))
            var contentOffset = indentOffset + widths.of(
                ns.substring(with: NSRange(
                    location: lineRange.location,
                    length: item.contentStart - lineRange.location)))

            if item.isMarkerHidden {
                storage.addAttribute(
                    .foregroundColor, value: NSColor.clear, range: item.markerRange)
                // `-`, `*`, and `+` have three different advances, and the
                // hidden character still reserves its own. Left alone, the
                // text after a `+` starts a hair right of the text after a
                // `-` — visible as a ragged left edge down a mixed list.
                // Kerning the marker out to the width of the glyph that
                // replaces it makes every bullet line start at the same x.
                // Kern is per character, so a five-character `- [ ]` takes
                // a fifth of the difference on each.
                // A checklist reserves the drawn box's side, the same whether
                // ticked or not, so checking one doesn't shift its text.
                let glyphWidth =
                    item.glyph(indentWidth: indent.width).map(widths.of)
                    ?? NotesLayoutManager.checklistBoxSide(for: widths.font)
                let markerWidth = widths.of(ns.substring(with: item.markerRange))
                let kern = glyphWidth - markerWidth
                storage.addAttribute(
                    .kern, value: kern / CGFloat(item.markerRange.length), range: item.markerRange)
                contentOffset += kern
            }
            if item.marker == .checklist(checked: true) {
                let content = NSRange(
                    location: item.contentStart,
                    length: NSMaxRange(lineRange) - item.contentStart)
                storage.addAttribute(.foregroundColor, value: palette.muted, range: content)
            }
            previous = (item, lineRange, contentOffset)

            let paragraph = makeParagraphStyle()
            paragraph.firstLineHeadIndent = indentOffset
            // Wrapped lines hang to where the content starts, so a long
            // item reads as one block rather than sliding back under its
            // own bullet.
            paragraph.headIndent = contentOffset
            storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        }
    }

    /// The line's leading whitespace is kerned down to nothing and the
    /// paragraph indented to the content column instead. Subtracting its
    /// width from the indent would do for a bullet, but a checklist's column
    /// sits *left* of where six spaces end — the hidden `- [ ]` is kerned
    /// to a glyph narrower than itself — and an indent can't go negative.
    private static func styleContinuation(
        lineRange: NSRange, in storage: NSTextStorage, widths: Widths, contentOffset: CGFloat,
        color: NSColor?
    ) {
        if let color { storage.addAttribute(.foregroundColor, value: color, range: lineRange) }
        let ns = storage.string as NSString
        var index = lineRange.location
        while index < NSMaxRange(lineRange),
            ns.character(at: index) == 0x20 || ns.character(at: index) == 0x09
        {
            let character = ns.substring(with: NSRange(location: index, length: 1))
            storage.addAttribute(
                .kern, value: -widths.of(character), range: NSRange(location: index, length: 1))
            index += 1
        }
        let paragraph = makeParagraphStyle()
        paragraph.firstLineHeadIndent = contentOffset
        paragraph.headIndent = contentOffset
        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
    }

    /// Advance widths in one font, remembered for one pass: every list line
    /// measures its indent and marker, and a note repeats the same few.
    private final class Widths {
        let font: NSFont
        private var cache: [String: CGFloat] = [:]

        init(font: NSFont) { self.font = font }

        func of(_ text: String) -> CGFloat {
            guard !text.isEmpty else { return 0 }
            if let width = cache[text] { return width }
            let width = NSAttributedString(string: text, attributes: [.font: font]).size().width
            cache[text] = width
            return width
        }
    }

    /// Render markdown emphasis with font traits, and `==marked==` with a
    /// background. Stays plain on disk — the markers remain visible, the
    /// same bargain the rest of the rendering makes.
    ///
    /// Both spellings of each form are read (`**`/`__`, `*`/`_`) even
    /// though ⌘B and ⌘I only ever *write* one, so a note pasted in from
    /// anywhere renders the way its author meant.
    private static func styleInlineMarkup(
        in storage: NSTextStorage, baseFont: NSFont, palette: Palette, marks: Escapes.Marks
    ) {
        // Every pass scans the text with its escaped characters blanked, so
        // an escaped marker can neither open a run nor close one. Ranges
        // carry straight over to the storage — see `Escapes.Marks.masking`.
        let text = marks.masking(storage.string) as NSString

        for range in Inline.bold.ranges(in: text) {
            applyTrait(.bold, over: range, in: storage, baseFont: baseFont)
        }
        for range in Inline.boldUnderscores.ranges(in: text) where isFreestanding(range, in: text) {
            applyTrait(.bold, over: range, in: storage, baseFont: baseFont)
        }
        // Italic: a single marker, skipping any match that touches another
        // of the same marker on either side — that would mean the match is
        // the inside of a bold run.
        for range in Inline.italic.ranges(in: text) where !isAdjacent(to: "*", range, in: text) {
            applyTrait(.italic, over: range, in: storage, baseFont: baseFont)
        }
        for range in Inline.italicUnderscores.ranges(in: text)
        where !isAdjacent(to: "_", range, in: text) && isFreestanding(range, in: text) {
            applyTrait(.italic, over: range, in: storage, baseFont: baseFont)
        }
        // `` `code` ``: a whole different family, so it replaces the font
        // rather than merging a trait into it. Sized off whatever is already
        // at that offset, which is what lets a span inside a heading keep
        // the heading's size. Triple-backtick fences are left alone —
        // `[^`\n]+` can't match across the second backtick of a fence.
        for range in Inline.code.ranges(in: text) {
            let size = currentFont(in: storage, at: range.location, fallback: baseFont).pointSize
            storage.addAttribute(
                .font, value: Typography.codeFont(atResolvedSize: size), range: range)
        }
        // `<u>…</u>`: an attribute rather than a symbolic trait, so it
        // can't go through `applyTrait` with the others.
        for range in Inline.underline.ranges(in: text) {
            storage.addAttribute(
                .underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        // `~~struck~~`, and `~struck~` too: GFM allows either, and a single
        // tilde is what Notion accepts when typing. The doubled runs are
        // blanked out of the text the single pass reads rather than filtered
        // by adjacency the way italic is: a match the filter rejects has
        // still been consumed, so `~~a~~ and ~b~` lost `~b~` to a rejected
        // `~ and ~`. Blanking keeps every offset where it was.
        let masked = NSMutableString(string: text)
        for range in Inline.doubleTildes.ranges(in: text) {
            storage.addAttribute(
                .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            masked.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        let singles = masked.copy() as! NSString
        for range in Inline.singleTildes.ranges(in: singles)
        where !isAdjacent(to: "~", range, in: singles) {
            storage.addAttribute(
                .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        styleHighlights(in: storage, palette: palette, masked: text)

        // Last, so nothing above can repaint over it. A backslash that
        // escaped something is syntax rather than content, and reads as such
        // without being hidden — the same bargain every other marker here
        // makes. `\\` paints only the first of the two.
        for offset in marks.backslashes {
            storage.addAttribute(
                .foregroundColor, value: palette.faint,
                range: NSRange(location: offset, length: 1))
        }
    }

    /// `==marked==` runs, painted with a background, over text already
    /// masked by `Escapes.Marks.masking`.
    ///
    /// Separate from the rest of the inline pass because the find bar has
    /// to be able to re-run just this: both features want
    /// `.backgroundColor` and there is no second background attribute to
    /// keep them apart.
    static func styleHighlights(in storage: NSTextStorage, palette: Palette, masked: NSString) {
        for range in Inline.highlight.ranges(in: masked) {
            storage.addAttribute(.backgroundColor, value: palette.highlight, range: range)
        }
    }

    /// The inline patterns, compiled once rather than on every restyle — they
    /// run over the whole note on every keystroke.
    private enum Inline {
        static let bold = pattern(#"\*\*([^*\n]+)\*\*"#)
        static let boldUnderscores = pattern(#"__([^_\n]+)__"#)
        static let italic = pattern(#"\*([^*\n]+)\*"#)
        static let italicUnderscores = pattern(#"_([^_\n]+)_"#)
        static let code = pattern(#"`([^`\n]+)`"#)
        static let underline = pattern(#"<u>([^<\n]+)</u>"#)
        static let doubleTildes = pattern(#"~~([^~\n]+)~~"#)
        static let singleTildes = pattern(#"~([^~\n]+)~"#)
        static let highlight = pattern(#"==([^=\n]+)=="#)

        private static func pattern(_ source: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: source)
        }
    }

    /// True when the run isn't butted against a word character on either
    /// side.
    ///
    /// This is what keeps `foo_bar_baz` from rendering `_bar_` in italics —
    /// a real hazard in a notes app that ends up holding identifiers and
    /// file names. CommonMark draws the same distinction for `_` and not
    /// for `*`, which is why only the underscore forms consult it.
    private static func isFreestanding(_ range: NSRange, in text: NSString) -> Bool {
        !isWordCharacter(at: range.location - 1, in: text)
            && !isWordCharacter(at: NSMaxRange(range), in: text)
    }

    /// Whether the character — the whole grapheme — at `index` is a letter
    /// or a number. False off either end.
    private static func isWordCharacter(at index: Int, in text: NSString) -> Bool {
        guard index >= 0, index < text.length,
            let character = text.substring(
                with: text.rangeOfComposedCharacterSequence(at: index)).first
        else { return false }
        return character.isLetter || character.isNumber
    }

    /// True when `marker` sits immediately outside either end of the run,
    /// which means this match is the inside of a doubled (bold) one.
    private static func isAdjacent(to marker: Unicode.Scalar, _ range: NSRange, in text: NSString)
        -> Bool
    {
        let unit = unichar(marker.value)
        if range.location > 0, text.character(at: range.location - 1) == unit { return true }
        return NSMaxRange(range) < text.length && text.character(at: NSMaxRange(range)) == unit
    }

    private static func applyTrait(
        _ traits: NSFontDescriptor.SymbolicTraits,
        over range: NSRange,
        in storage: NSTextStorage,
        baseFont: NSFont
    ) {
        let current = currentFont(in: storage, at: range.location, fallback: baseFont)
        storage.addAttribute(.font, value: traitFont(current, traits: traits), range: range)
    }

    private static func currentFont(in storage: NSTextStorage, at location: Int, fallback: NSFont) -> NSFont {
        guard location < storage.length else { return fallback }
        return (storage.attributes(at: location, effectiveRange: nil)[.font] as? NSFont) ?? fallback
    }

    private static func traitFont(_ base: NSFont, traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let merged = base.fontDescriptor.symbolicTraits.union(traits)
        let descriptor = base.fontDescriptor.withSymbolicTraits(merged)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    /// Hides every rule line's characters with a `.clear` foreground and tags the line with
    /// `.horizontalRule`, which `NotesLayoutManager` reads to draw the full-width rule without
    /// classifying the note again.
    ///
    /// A blank line directly above a rule is set 1.1em tall and one directly below 0.5em — ems of
    /// the body's point size — rather than the ~1.7em a blank line takes at the body's leading,
    /// so the rule sits close to the text it divides. Uneven because the leading sits above each
    /// text line's glyphs; these put the rule midway between the ink on either side.
    private static func styleHorizontalRules(
        in storage: NSTextStorage, baseFont: NSFont, blocks: MarkdownBlocks
    ) {
        let ns = storage.string as NSString
        let lines = blocks.lines
        let above = blankLineStyle(height: baseFont.pointSize * 1.1)
        let below = blankLineStyle(height: baseFont.pointSize * 0.5)

        for (index, line) in lines.enumerated() where line.kind == .rule {
            let content = NSRange(
                location: line.range.location,
                length: MarkdownBlocks.contentEnd(of: line.range, in: ns) - line.range.location)
            storage.addAttributes(
                [.foregroundColor: NSColor.clear, .horizontalRule: true], range: content)

            for (neighbour, style) in [(index - 1, above), (index + 1, below)]
            where lines.indices.contains(neighbour) {
                let blank = lines[neighbour]
                guard blank.kind == .blank, blank.range.length > 0 else { continue }
                storage.addAttribute(.paragraphStyle, value: style, range: blank.range)
            }
        }
    }

    private static func blankLineStyle(height: CGFloat) -> NSParagraphStyle {
        let style = makeParagraphStyle()
        style.lineHeightMultiple = 1
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        return style
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, caretOffset: $caretOffset, style: style)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var lastFocusToken: Int = 0
        var lastScrollToken: Int = 0
        var lastFindHighlightToken: Int = 0
        /// The style the storage was last painted in. Read by the delegate
        /// callbacks below as well as by `updateNSView`: source view also
        /// turns off the smart editing that *rewrites the file* — `---`→rule —
        /// since looking at the raw text is the one time that is least
        /// welcome. List continuation stays: it is typing assistance, not
        /// rendering.
        var style: BodyStyle
        /// The text last handed across, in either direction.
        var syncedText = ""
        /// Where the last `--` → `—` and third-↵ rule landed, so the next
        /// press of the same key can take them back, and where each left
        /// the caret. Cleared as soon as the caret leaves that spot.
        var lastAutoDash: (at: Int, caret: Int)?
        var lastAutoRule: (at: Int, caret: Int)?

        let caretOffset: Binding<Int>

        init(text: Binding<String>, caretOffset: Binding<Int>, style: BodyStyle) {
            self.text = text
            self.caretOffset = caretOffset
            self.style = style
        }

        /// Deferred a turn: a reload assigns `.string` from inside
        /// `updateNSView`, which moves the selection, and SwiftUI defers or
        /// drops a binding written mid-update.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selection = textView.selectedRange()
            let offset = selection.location
            if let dash = lastAutoDash, selection != NSRange(location: dash.caret, length: 0) {
                lastAutoDash = nil
            }
            if let rule = lastAutoRule, selection != NSRange(location: rule.caret, length: 0) {
                lastAutoRule = nil
            }
            DispatchQueue.main.async { [caretOffset] in
                if caretOffset.wrappedValue != offset { caretOffset.wrappedValue = offset }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NotesTextView,
                let storage = textView.textStorage
            else { return }
            let blocks = MarkdownBlocks(storage.string as NSString)
            // Hand-rolled edits go through `performEdit`, so the renumber
            // they may trigger waits for the caret they set. AppKit's own
            // edits renumber from here, with the selection already where
            // the keystroke left it. A renumber is an edit of its own, whose
            // `textDidChange` hands over and restyles the result.
            if textView.renumberLists(blocks: blocks) { return }

            syncedText = textView.string
            text.wrappedValue = syncedText
            MinimalTextEditor.restyleStorage(storage, style: style, blocks: blocks)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let notes = textView as? NotesTextView else { return false }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                return handleEnter(in: notes)
            // Tab and ⇧Tab: indent/outdent a list item or a selected block,
            // rather than moving focus out of the editor.
            case #selector(NSResponder.insertTab(_:)):
                notes.handleTab()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                notes.handleBacktab()
                return true
            default:
                return false
            }
        }

        /// Typed text that rewrites itself: a delimiter over a selection wraps
        /// it, `--` becomes `—`, and a third `-` on a line of `--` becomes a
        /// rule without waiting for ↵.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            // Only a keystroke counts, never a programmatic replace — and
            // `replacementString` alone cannot tell the two apart. Every
            // hand-rolled edit in the app re-enters this delegate with
            // whatever text it is putting back, and plenty of those are one
            // character: ⌘L unsetting `- *` puts back `*`, and AppKit's own
            // undo restores exactly the character you replaced.
            //
            // `hasMarkedText` additionally excludes an IME mid-composition,
            // where the character is a half-finished word rather than a
            // request to rewrite anything.
            guard let notes = textView as? NotesTextView,
                let typed = replacementString, !textView.hasMarkedText(),
                let event = NSApp.currentEvent, event.type == .keyDown, event.characters == typed
            else { return true }

            if affectedCharRange.length > 0 {
                guard let markers = MarkdownWrap.surroundMarkers(for: typed) else { return true }
                notes.performEdit {
                    MarkdownWrap.wrap(in: notes, range: affectedCharRange, markers: markers)
                }
                return false
            }

            // Source view skips the rest: these rewrite the line, and the
            // point of source view is to see what the line actually is.
            guard !style.isSourceView, typed == "-" || typed == ">" else { return true }
            let text = notes.string as NSString
            let cursor = affectedCharRange.location
            if let revert = SmartEditing.emDashRevert(
                in: text, cursor: cursor, autoDash: lastAutoDash?.at, typed: typed)
            {
                lastAutoDash = nil
                notes.apply(revert)
                return false
            }
            guard typed == "-" else { return true }
            if let rule = SmartEditing.ruleOnThirdDash(in: text, cursor: cursor) {
                notes.apply(rule)
                return false
            }
            // The dash types as usual and the pair is swapped a turn later,
            // in an undo group of its own — so ⌘Z takes back the substitution
            // and leaves the `--` that was typed, the way macOS autocorrect
            // does.
            let typedCaret = cursor + 1
            DispatchQueue.main.async { [weak self, weak notes] in
                guard let self, let notes,
                    notes.selectedRange() == NSRange(location: typedCaret, length: 0),
                    let edit = SmartEditing.emDashEdit(
                        in: notes.string as NSString, cursor: typedCaret)
                else { return }
                notes.breakUndoCoalescing()
                notes.apply(edit)
                self.lastAutoDash = (edit.range.location, edit.selection.location)
            }
            return true
        }

        private func handleEnter(in notes: NotesTextView) -> Bool {
            let text = notes.string as NSString
            let selection = notes.selectedRange()
            // ⇧↵ reaches here as a plain `insertNewline:` — AppKit binds no
            // selector to the shifted key — so the modifier is read off the
            // event.
            let isShifted = NSApp.currentEvent.map {
                $0.type == .keyDown && $0.modifierFlags.contains(.shift)
            } ?? false

            if selection.length == 0, !style.isSourceView, !isShifted {
                if let revert = SmartEditing.ruleRevert(
                    in: text, cursor: selection.location, autoRule: lastAutoRule?.at)
                {
                    lastAutoRule = nil
                    notes.apply(revert)
                    return true
                }
                if let edit = SmartEditing.ruleOnReturn(in: text, cursor: selection.location) {
                    notes.apply(edit)
                    lastAutoRule = (edit.range.location, edit.selection.location)
                    return true
                }
            }

            guard let edit = SmartEditing.returnEdit(
                in: text, selection: selection, shifted: isShifted, unit: style.indent.unit)
            else { return false }
            notes.apply(edit)
            return true
        }
    }
}

extension NSRegularExpression {
    /// Every match's whole range, left to right and non-overlapping, except
    /// one whose delimiters are only part of a character a reader sees — the
    /// `*` of a `*️⃣` keycap, or a `*` under a combining accent. The patterns
    /// match UTF-16 units, where a delimiter has to be a whole character.
    /// Each pattern's one group is the content between its delimiters.
    fileprivate func ranges(in text: NSString) -> [NSRange] {
        matches(in: text as String, range: NSRange(location: 0, length: text.length))
            .filter { match in
                let content = match.range(at: 1)
                let delimiters =
                    Array(match.range.location..<content.location)
                    + Array(NSMaxRange(content)..<NSMaxRange(match.range))
                return delimiters.allSatisfy {
                    text.rangeOfComposedCharacterSequence(at: $0).length == 1
                }
            }
            .map(\.range)
    }
}
