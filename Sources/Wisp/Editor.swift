import AppKit
import SwiftUI
import WispCore

extension NSTextView {
    /// A hand-rolled edit through AppKit's `shouldChangeText` and `didChangeText`, for undo and the
    /// delegate. False, with no edit, when the delegate refuses.
    @discardableResult
    func replaceText(in range: NSRange, with replacement: String) -> Bool {
        guard isEditable, shouldChangeText(in: range, replacementString: replacement) else {
            return false
        }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        return true
    }
}

struct Editor: NSViewRepresentable {
    var document: DocumentAnalysis
    var onEdit: (DocumentAnalysis) -> Void
    var isEditable: Bool = true
    private var text: String { document.text }
    /// For the footer's line:column and the heading jumps.
    @Binding var caretOffset: Int
    var focusToken: Int
    var scrollToken: Int
    var scrollTarget: Int
    var findHighlightToken: Int
    var findHighlightRange: NSRange
    var style: BodyStyle
    var smartPaste: Bool
    /// Applied on the text view directly; it changes nothing in the storage.
    var caret: Caret
    /// Applied on the text view directly, like `caret`.
    var spellcheck: Bool
    /// The text view's spelling item routes here, so the model stays the source of truth.
    var onToggleSpellcheck: () -> Void

    /// What the body's attributes depend on besides the text, compared in `updateNSView` since
    /// nothing re-derives stored attributes on its own.
    struct BodyStyle: Equatable {
        var theme: Theme
        /// `Typography` applies it; here so a change restyles the body's resolved fonts.
        var fontScale: Double
        var fonts: FontSet = FontSet()
        var indent: Indent
        /// The raw text in the code face, with every styling pass skipped.
        var isSourceView: Bool
        /// Drawing only; the styling is the same either way.
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
        textView.isEditable = isEditable
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

        textView.adoptAnalysis(document)
        context.coordinator.syncedDocument = document
        context.coordinator.style = style
        Self.restyle(textView, style: style)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NotesTextView else { return }
        let coordinator = context.coordinator
        // Against the last hand-over rather than `textView.string`, which costs a full scan of the
        // bridged storage.
        coordinator.onEdit = onEdit
        textView.isEditable = isEditable
        if document !== coordinator.syncedDocument {
            let changed = coordinator.syncedDocument?.matches(text) != true
            if changed {
                textView.breakUndoCoalescing()
                textView.undoManager?.removeAllActions()
                textView.string = text
                coordinator.lastAutoDash = nil
                coordinator.lastAutoRule = nil
            }
            textView.adoptAnalysis(document)
            coordinator.syncedDocument = document
            if changed {
                Self.restyle(textView, style: style)
                applyFindHighlight(to: textView, scroll: false)
            }
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
                applyFindHighlight(to: textView, scroll: false)
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

    /// Raw mode takes the code family, so it reads as the file at a glance.
    static func baseFont(isSourceView: Bool) -> NSFont {
        isSourceView
            ? Typography.codeFont(Metrics.bodySize) : Typography.notesFont(Metrics.bodySize)
    }

    private static func makeParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Metrics.bodyLineHeightMultiple
        return paragraph
    }

    /// `scroll` is false for a theme change, where the match hasn't moved.
    private func applyFindHighlight(to textView: NotesTextView, scroll: Bool) {
        Self.applyFindHighlight(
            to: textView, range: findHighlightRange, theme: style.theme, scroll: scroll)
    }

    /// Temporary attributes draw above stored Markdown backgrounds without touching them.
    static func applyFindHighlight(
        to textView: NotesTextView, range: NSRange, theme: Theme, scroll: Bool
    ) {
        guard let manager = textView.layoutManager, let storage = textView.textStorage else {
            return
        }
        if let previous = textView.findHighlightRange {
            let end = min(NSMaxRange(previous), storage.length)
            if previous.location < end {
                manager.removeTemporaryAttribute(
                    .backgroundColor,
                    forCharacterRange: NSRange(
                        location: previous.location, length: end - previous.location))
            }
        }
        textView.findHighlightRange = nil
        guard range.location >= 0, range.length > 0,
            range.location <= storage.length, range.length <= storage.length - range.location
        else { return }
        manager.addTemporaryAttribute(
            .backgroundColor, value: Palette.for(theme).findHighlight, forCharacterRange: range)
        textView.findHighlightRange = range
        if scroll { textView.scrollRangeToVisible(range) }
    }

    /// The text view's colors, the layout manager's marks, and the storage's attributes.
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
        if let storage = textView.textStorage {
            let analysis = textView.documentAnalysis()
            restyleStorage(storage, style: style, analysis: analysis)
            textView.styledAnalysis = analysis
            textView.pendingCharacterEdit = nil
            textView.hasMultipleCharacterEdits = false
        }
    }

    /// Only a plain line with unchanged block context can take the local inline-only path.
    /// Structural edits, multi-edit transactions, and replacements use the full renderer.
    static func restyleAfterEdit(
        _ textView: NotesTextView, style: BodyStyle,
        analysis: DocumentAnalysis
    ) {
        guard let storage = textView.textStorage else { return }
        defer {
            textView.styledAnalysis = analysis
            textView.pendingCharacterEdit = nil
            textView.hasMultipleCharacterEdits = false
        }
        guard !style.isSourceView, !textView.hasMultipleCharacterEdits,
            let edit = textView.pendingCharacterEdit, let previous = textView.styledAnalysis,
            let range = proseRange(for: edit, from: previous, to: analysis)
        else {
            restyleStorage(storage, style: style, analysis: analysis)
            return
        }
        let slice = NSTextStorage(string: (analysis.text as NSString).substring(with: range))
        let font = baseFont(isSourceView: false)
        let palette = Palette.for(style.theme)
        resetBaseAttributes(
            in: slice, font: font, color: palette.text, paragraph: makeParagraphStyle())
        styleInlineMarkup(
            in: slice, baseFont: font, palette: palette, marks: Escapes.scan(slice.string))
        storage.beginEditing()
        resetBaseAttributes(
            in: storage, font: font, color: palette.text, paragraph: makeParagraphStyle(),
            range: range)
        slice.enumerateAttributes(in: NSRange(location: 0, length: slice.length)) {
            attributes, local, _ in
            storage.addAttributes(
                attributes,
                range: NSRange(
                    location: range.location + local.location, length: local.length))
        }
        storage.endEditing()
    }

    private static func proseRange(
        for edit: NotesTextView.CharacterEdit,
        from old: DocumentAnalysis, to new: DocumentAnalysis
    ) -> NSRange? {
        let before = old.text as NSString
        let after = new.text as NSString
        let oldLength = edit.range.length - edit.delta
        guard before.length > 0, after.length > 0, oldLength >= 0,
            let oldLine = old.blocks.line(at: min(edit.range.location, before.length - 1)),
            let newLine = new.blocks.line(at: min(edit.range.location, after.length - 1)),
            case .text(let oldStart?) = oldLine.kind,
            case .text(let newStart?) = newLine.kind, oldStart == newStart,
            oldLine.range.location == newLine.range.location,
            edit.range.location + oldLength
                <= MarkdownBlocks.contentEnd(of: oldLine.range, in: before),
            NSMaxRange(edit.range) <= MarkdownBlocks.contentEnd(of: newLine.range, in: after),
            !old.headings.contains(where: {
                $0.lineStart <= oldLine.range.location && $0.end >= oldLine.range.location
            }),
            !new.headings.contains(where: {
                $0.lineStart <= newLine.range.location && $0.end >= newLine.range.location
            })
        else { return nil }
        // Inline patterns exclude LF. Other line separators can permit cross-line matches.
        for (text, line) in [(before, oldLine), (after, newLine)] {
            // List rendering tracks continuations independently of block classification.
            let first = text.character(at: line.range.location)
            if first == 0x20 || first == 0x09 { return nil }
            if line.range.location > 0, text.character(at: line.range.location - 1) != 0x0A {
                return nil
            }
            if NSMaxRange(line.range) < text.length,
                text.character(at: NSMaxRange(line.range) - 1) != 0x0A
            {
                return nil
            }
        }
        return newLine.range
    }

    /// The storage's half of `restyle`, using the same revision as navigation and spelling.
    static func restyleStorage(
        _ storage: NSTextStorage, style: BodyStyle, analysis: DocumentAnalysis? = nil
    ) {
        let palette = Palette.for(style.theme)
        let font = baseFont(isSourceView: style.isSourceView)
        // One `processEditing` for the whole pass.
        storage.beginEditing()
        defer { storage.endEditing() }
        resetBaseAttributes(
            in: storage, font: font, color: palette.text, paragraph: makeParagraphStyle())
        guard !style.isSourceView else {
            return
        }
        restyleContent(
            in: storage, baseFont: font, indent: style.indent, palette: palette,
            analysis: analysis ?? DocumentAnalysis(storage.string))
    }

    /// Back to plain body text. Kern, underline, strikethrough, and `.horizontalRule` are removed
    /// rather than reset, since they sit on ranges that move with edits. Find uses temporary
    /// attributes, so Markdown backgrounds can be cleared with the other stored attributes.
    static func resetBaseAttributes(
        in storage: NSTextStorage, font: NSFont, color: NSColor, paragraph: NSParagraphStyle,
        range: NSRange? = nil
    ) {
        let range = range ?? NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.backgroundColor, range: range)
        storage.removeAttribute(.kern, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.removeAttribute(.horizontalRule, range: range)
        storage.addAttributes(
            [.font: font, .foregroundColor: color, .paragraphStyle: paragraph], range: range)
    }

    /// Structure first, then the inline passes that read the fonts it left. Headings come from the
    /// storage's own blocks, so they match the text being styled.
    private static func restyleContent(
        in storage: NSTextStorage, baseFont: NSFont, indent: Indent, palette: Palette,
        analysis: DocumentAnalysis
    ) {
        let ns = storage.string as NSString
        let marks = Escapes.scan(ns)
        let widths = Widths(font: baseFont)
        styleLists(in: storage, widths: widths, indent: indent, palette: palette)
        styleHeadings(
            in: storage, baseFont: baseFont, palette: palette, headings: analysis.headings)
        styleInlineMarkup(in: storage, baseFont: baseFont, palette: palette, marks: marks)
        // Last: `***` and `_ _ _` also match emphasis, which would repaint a rule's hidden marks.
        styleHorizontalRules(in: storage, baseFont: baseFont, blocks: analysis.blocks)
    }

    /// Bold, a per-level size and colour, and a dimmed marker, on each heading's range.
    private static func styleHeadings(
        in storage: NSTextStorage, baseFont: NSFont, palette: Palette, headings: [Heading]
    ) {
        // One font per level, since each is a descriptor lookup.
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

    /// A hanging indent for every list line, measured from rendered text so wrapped lines align,
    /// and a hidden marker for `NotesLayoutManager` to draw over. Continuation lines are pulled to
    /// the content column, since proportional spaces alone land a hair off.
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
                        color: previous.item.marker == .checklist(checked: true)
                            ? palette.muted : nil)
                } else {
                    previous = nil
                }
                continue
            }

            // The whitespace also indents by its own width, doubling the nesting step.
            let indentOffset = widths.of(
                ns.substring(with: NSRange(location: lineRange.location, length: item.indentWidth)))
            var contentOffset =
                indentOffset
                + widths.of(
                    ns.substring(
                        with: NSRange(
                            location: lineRange.location,
                            length: item.contentStart - lineRange.location)))

            if item.isMarkerHidden {
                storage.addAttribute(
                    .foregroundColor, value: NSColor.clear, range: item.markerRange)
                // Kerned to the drawn glyph's width, so `-`, `*`, and `+` lines start alike; a
                // checklist reserves the box's side, so ticking doesn't shift its text.
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
            // Wrapped lines hang to the content.
            paragraph.headIndent = contentOffset
            storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        }
    }

    /// Kerns the leading whitespace to nothing and indents to the content column, since a
    /// checklist's column can sit left of where its spaces end.
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

    /// Advance widths in one font, cached for one pass.
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

    /// Emphasis as font traits and `==marked==` as a background, markers left visible. Both
    /// spellings of each form are read, so a pasted note renders as written.
    private static func styleInlineMarkup(
        in storage: NSTextStorage, baseFont: NSFont, palette: Palette, marks: Escapes.Marks
    ) {
        // Escape-masked, so an escaped marker neither opens nor closes a run.
        let text = marks.masking(storage.string) as NSString

        Inline.bold.forEachRange(in: text) { range in
            applyTrait(.bold, over: range, in: storage, baseFont: baseFont)
        }
        Inline.boldUnderscores.forEachRange(in: text) { range in
            guard isFreestanding(range, in: text) else { return }
            applyTrait(.bold, over: range, in: storage, baseFont: baseFont)
        }
        // A match touching another marker is the inside of a bold run.
        Inline.italic.forEachRange(in: text) { range in
            guard !isAdjacent(to: "*", range, in: text) else { return }
            applyTrait(.italic, over: range, in: storage, baseFont: baseFont)
        }
        Inline.italicUnderscores.forEachRange(in: text) { range in
            guard !isAdjacent(to: "_", range, in: text), isFreestanding(range, in: text) else {
                return
            }
            applyTrait(.italic, over: range, in: storage, baseFont: baseFont)
        }
        // Replaces the font, sized off what's there so a span in a heading keeps its size.
        Inline.code.forEachRange(in: text) { range in
            let size = currentFont(in: storage, at: range.location, fallback: baseFont).pointSize
            storage.addAttribute(
                .font, value: Typography.codeFont(atResolvedSize: size), range: range)
        }
        // An attribute, not a trait, so not through `applyTrait`.
        Inline.underline.forEachRange(in: text) { range in
            storage.addAttribute(
                .underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        // `~` too, as GFM allows. Doubled runs are blanked for the single pass rather than
        // filtered, since a rejected match still consumes its text.
        var masked: NSMutableString?
        Inline.doubleTildes.forEachRange(in: text) { range in
            storage.addAttribute(
                .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            if masked == nil { masked = NSMutableString(string: text) }
            masked?.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        let singles: NSString = masked ?? text
        Inline.singleTildes.forEachRange(in: singles) { range in
            guard !isAdjacent(to: "~", range, in: singles) else { return }
            storage.addAttribute(
                .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        styleHighlights(in: storage, palette: palette, masked: text)

        // Last, so nothing repaints it: an escaping backslash reads as syntax.
        for offset in marks.backslashes {
            storage.addAttribute(
                .foregroundColor, value: palette.faint,
                range: NSRange(location: offset, length: 1))
        }
    }

    /// Stored Markdown backgrounds, independent of the temporary find match.
    static func styleHighlights(in storage: NSTextStorage, palette: Palette, masked: NSString) {
        Inline.highlight.forEachRange(in: masked) { range in
            storage.addAttribute(.backgroundColor, value: palette.highlight, range: range)
        }
    }

    /// Compiled once; they run over the whole note on every keystroke.
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

    /// Not butted against a word character, so `foo_bar_baz` isn't italic. CommonMark applies this
    /// to `_` only.
    private static func isFreestanding(_ range: NSRange, in text: NSString) -> Bool {
        !isWordCharacter(at: range.location - 1, in: text)
            && !isWordCharacter(at: NSMaxRange(range), in: text)
    }

    /// Whether the grapheme at `index` is a letter or number; false off either end.
    private static func isWordCharacter(at index: Int, in text: NSString) -> Bool {
        guard index >= 0, index < text.length,
            let character = text.substring(
                with: text.rangeOfComposedCharacterSequence(at: index)
            ).first
        else { return false }
        return character.isLetter || character.isNumber
    }

    /// A `marker` just outside the run means it's the inside of a doubled one.
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

    private static func currentFont(in storage: NSTextStorage, at location: Int, fallback: NSFont)
        -> NSFont
    {
        guard location < storage.length else { return fallback }
        return (storage.attributes(at: location, effectiveRange: nil)[.font] as? NSFont) ?? fallback
    }

    private static func traitFont(_ base: NSFont, traits: NSFontDescriptor.SymbolicTraits) -> NSFont
    {
        let merged = base.fontDescriptor.symbolicTraits.union(traits)
        let descriptor = base.fontDescriptor.withSymbolicTraits(merged)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    /// Hides rule characters and tags them for `NotesLayoutManager`. Blank lines beside a rule are
    /// 1.1em above and 0.5em below, centring it between the ink, since leading sits above glyphs.
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
        Coordinator(onEdit: onEdit, caretOffset: $caretOffset, style: style)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onEdit: (DocumentAnalysis) -> Void
        var lastFocusToken: Int = 0
        var lastScrollToken: Int = 0
        var lastFindHighlightToken: Int = 0
        /// The style last painted. Source view also turns off the edits that rewrite a line, but
        /// not list continuation.
        var style: BodyStyle
        /// The text last handed across, in either direction.
        var syncedDocument: DocumentAnalysis?
        /// Where the last auto dash and rule landed, for a take-back; cleared once the caret moves.
        var lastAutoDash: (at: Int, caret: Int)?
        var lastAutoRule: (at: Int, caret: Int)?

        let caretOffset: Binding<Int>

        init(
            onEdit: @escaping (DocumentAnalysis) -> Void, caretOffset: Binding<Int>,
            style: BodyStyle
        ) {
            self.onEdit = onEdit
            self.caretOffset = caretOffset
            self.style = style
        }

        /// Deferred a turn, since SwiftUI drops a binding written mid-update.
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
            guard let textView = notification.object as? NotesTextView else { return }
            let analysis = textView.documentAnalysis()
            // AppKit's own edits renumber here; a renumber's own `textDidChange` hands over and
            // restyles.
            if textView.renumberLists(blocks: analysis.blocks) { return }

            syncedDocument = analysis
            onEdit(analysis)
            Editor.restyleAfterEdit(textView, style: style, analysis: analysis)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let notes = textView as? NotesTextView else { return false }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                return handleEnter(in: notes)
            // Indent and outdent rather than moving focus.
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

        /// A delimiter over a selection wraps it, `--` becomes `—`, and `---` becomes a rule.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            // Keystrokes only: hand-rolled edits and undo re-enter here with single characters too,
            // and marked text is an IME mid-composition.
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

            // Source view shows the line as it is, so skip these.
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
            // Swapped a turn later in its own undo group, so ⌘Z gives back the typed `--`.
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
            // AppKit sends ⇧↵ as a plain `insertNewline:`, so read the modifier off the event.
            let isShifted =
                NSApp.currentEvent.map {
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

            guard
                let edit = SmartEditing.returnEdit(
                    in: text, selection: selection, shifted: isShifted, unit: style.indent.unit)
            else { return false }
            notes.apply(edit)
            return true
        }
    }
}

extension NSRegularExpression {
    /// Match ranges, skipping any whose delimiter is part of a larger grapheme, such as a `*️⃣`
    /// keycap. Each pattern's one group is the content.
    fileprivate func forEachRange(in text: NSString, _ body: (NSRange) -> Void) {
        withoutActuallyEscaping(body) { body in
            enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                match, _, _ in
                guard let match else { return }
                let content = match.range(at: 1)
                let opening = match.range.location..<content.location
                let closing = NSMaxRange(content)..<NSMaxRange(match.range)
                guard
                    opening.allSatisfy({ text.rangeOfComposedCharacterSequence(at: $0).length == 1 }
                    ),
                    closing.allSatisfy({ text.rangeOfComposedCharacterSequence(at: $0).length == 1 }
                    )
                else { return }
                body(match.range)
            }
        }
    }
}
