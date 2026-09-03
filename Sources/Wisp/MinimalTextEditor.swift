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
    @Binding var headings: [Heading]
    var focusToken: Int
    var scrollToken: Int
    var scrollTarget: Int
    var wrapToken: Int
    var wrapMarkers: MarkdownWrap.Markers
    var duplicateToken: Int
    var listItemToken: Int
    var moveLineToken: Int
    var moveLineDelta: Int
    var findHighlightToken: Int
    var findHighlightRange: NSRange
    /// The live text scale. Compared in `updateNSView` rather than assumed
    /// constant: the body's font lives in `NSTextStorage` as a resolved
    /// `NSFont`, so unlike the SwiftUI chrome nothing re-resolves it when
    /// the scale moves. Before this was the compared value, a scale change
    /// left the body at its old size until the next keystroke restyled it.
    var fontScale: Double
    var indent: Indent
    var theme: Theme

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = NotesTextView.makeScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = false

        let font = Typography.notesFont(Metrics.bodySize)

        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = font
        textView.defaultParagraphStyle = Self.makeParagraphStyle()
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.indentUnit = indent.unit
        textView.string = text

        Self.applyPalette(
            Palette.for(theme), to: textView, font: font, headings: headings, indent: indent)

        context.coordinator.lastFontScale = fontScale
        context.coordinator.lastIndent = indent
        context.coordinator.lastTheme = theme
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NotesTextView else { return }
        if textView.string != text {
            // Assigning `.string` throws away every attribute in the
            // storage, so the incoming text arrives unstyled. The layout
            // manager draws rules and bullets from the *text*, but what
            // hides the characters they stand in for is the styling pass —
            // without this a note reloaded from disk showed a `-` sitting
            // under its own bullet, and `---` under its own rule.
            textView.string = text
            restyle(textView)
        }
        // Both change what the storage's attributes have to say, and both
        // re-run the same full restyle, so they share one branch.
        if context.coordinator.lastFontScale != fontScale
            || context.coordinator.lastIndent != indent
        {
            context.coordinator.lastFontScale = fontScale
            context.coordinator.lastIndent = indent
            textView.indentUnit = indent.unit
            restyle(textView)
        }
        if context.coordinator.lastTheme != theme {
            context.coordinator.lastTheme = theme
            restyle(textView)
            // The match background is a storage attribute and applyPalette
            // merges rather than replaces, so repaint it in the incoming
            // theme's color instead of leaving the outgoing one behind.
            applyFindHighlight(to: textView, scroll: false)
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        if context.coordinator.lastScrollToken != scrollToken {
            context.coordinator.lastScrollToken = scrollToken
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
        if context.coordinator.lastFindHighlightToken != findHighlightToken {
            context.coordinator.lastFindHighlightToken = findHighlightToken
            applyFindHighlight(to: textView, scroll: true)
        }
        if context.coordinator.lastWrapToken != wrapToken {
            context.coordinator.lastWrapToken = wrapToken
            if textView.window?.firstResponder === textView {
                MarkdownWrap.toggle(in: textView, markers: wrapMarkers)
            }
        }
        if context.coordinator.lastDuplicateToken != duplicateToken {
            context.coordinator.lastDuplicateToken = duplicateToken
            if textView.window?.firstResponder === textView {
                textView.duplicateSelection()
            }
        }
        if context.coordinator.lastListItemToken != listItemToken {
            context.coordinator.lastListItemToken = listItemToken
            if textView.window?.firstResponder === textView {
                textView.toggleListItem()
            }
        }
        if context.coordinator.lastMoveLineToken != moveLineToken {
            context.coordinator.lastMoveLineToken = moveLineToken
            if textView.window?.firstResponder === textView {
                textView.moveLines(by: moveLineDelta)
            }
        }
    }

    private func restyle(_ textView: NotesTextView) {
        Self.applyPalette(
            Palette.for(theme), to: textView, font: Typography.notesFont(Metrics.bodySize),
            headings: headings, indent: indent)
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
        let palette = Palette.for(theme)
        // Use a real storage background attribute (not a temporary layout
        // attribute): storage mutations always trigger a redraw, so the
        // highlight clears deterministically. It is never written to disk —
        // we save `.string`.
        storage.removeAttribute(.backgroundColor, range: full)
        // `==marked==` shares the attribute, so it is repainted before the
        // match goes on top. Without this, opening Find erases every
        // highlight in the note.
        Self.styleHighlights(in: storage, palette: palette)

        let range = findHighlightRange
        guard range.length > 0, NSMaxRange(range) <= full.length else { return }
        storage.addAttribute(.backgroundColor, value: palette.findHighlight, range: range)
        if scroll { textView.scrollRangeToVisible(range) }
    }

    private static func applyPalette(
        _ palette: Palette,
        to textView: NotesTextView,
        font: NSFont,
        headings: [Heading],
        indent: Indent
    ) {
        let paragraph = makeParagraphStyle()
        textView.textColor = palette.text
        textView.insertionPointColor = palette.accent
        textView.selectedTextAttributes = [
            .backgroundColor: palette.selection
        ]
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: palette.text,
            .paragraphStyle: paragraph,
        ]
        if let lm = textView.layoutManager as? NotesLayoutManager {
            lm.ruleColor = palette.rule
            lm.bulletColor = palette.text
            lm.bulletFont = font
            lm.indentWidth = indent.width
        }
        if let storage = textView.textStorage {
            resetBaseAttributes(
                in: storage, font: font, color: palette.text, paragraph: paragraph)
            restyleContent(
                in: storage, baseFont: font, headings: headings, indent: indent, palette: palette)
        }
    }

    /// Wipes the whole storage back to plain body text, so a content pass
    /// can run against a known state.
    ///
    /// `.kern`, `.underlineStyle` and `.backgroundColor` are *removed* rather
    /// than overwritten: none has a base value to reset to, and each is set
    /// on ranges that move as the text is edited — a marker's kern would
    /// otherwise stay on whatever character ends up at that offset, and a
    /// `==` highlight or a `<u>` rule would outlive the markers that asked
    /// for it.
    static func resetBaseAttributes(
        in storage: NSTextStorage, font: NSFont, color: NSColor, paragraph: NSParagraphStyle
    ) {
        let range = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.kern, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        storage.addAttributes(
            [.font: font, .foregroundColor: color, .paragraphStyle: paragraph], range: range)
    }

    /// Everything that depends on the text's own content, in the order the
    /// attributes have to land: structural passes first, then the inline
    /// ones that read whatever font the structure left behind.
    ///
    /// Always run over the whole storage against a freshly reset base, so a
    /// line that *stopped* being a rule or a list item loses the styling it
    /// had. Cheap at scratchpad sizes.
    static func restyleContent(
        in storage: NSTextStorage, baseFont: NSFont, headings: [Heading], indent: Indent,
        palette: Palette
    ) {
        styleHorizontalRules(in: storage)
        styleLists(in: storage, baseFont: baseFont, indent: indent)
        styleHeadings(in: storage, baseFont: baseFont, headings: headings)
        styleInlineMarkup(in: storage, baseFont: baseFont, palette: palette)
    }

    /// Apply bold + scaled font to lines that begin with a markdown heading
    /// marker (`#` through `######`). Plain text on disk; this is just a
    /// per-range font attribute so the heading reads as a section title
    /// without leaving plain-text mode.
    private static func styleHeadings(in storage: NSTextStorage, baseFont: NSFont, headings: [Heading]) {
        let ns = storage.string as NSString
        for heading in headings {
            let font = headingFont(level: heading.level, baseFont: baseFont)
            var styleRange = ns.lineRange(for: NSRange(location: heading.lineStart, length: 0))
            if styleRange.length > 0,
               ns.character(at: styleRange.location + styleRange.length - 1) == 0x0A {
                styleRange.length -= 1
            }
            storage.addAttribute(.font, value: font, range: styleRange)
        }
    }

    private static func headingFont(level: Int, baseFont: NSFont) -> NSFont {
        let baseSize = baseFont.pointSize
        let scaledSize: CGFloat
        switch level {
        case 1: scaledSize = baseSize * Metrics.headingLevel1Ratio
        case 2: scaledSize = baseSize * Metrics.headingLevel2Ratio
        default: scaledSize = baseSize
        }
        let boldDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: boldDescriptor, size: scaledSize) ?? baseFont
    }

    /// Give every list line a hanging indent, and hide the `-` / `*` / `+`
    /// so `NotesLayoutManager` can draw a bullet in the space it reserved.
    ///
    /// The measurements come from the rendered text rather than from a
    /// points-per-character guess: the head indent has to land exactly
    /// where the content starts, or a wrapped line sits a hair off the one
    /// above it. Ordered markers stay visible — `1.` is its own content.
    private static func styleLists(
        in storage: NSTextStorage, baseFont: NSFont, indent: Indent
    ) {
        let ns = storage.string as NSString
        let total = ns.length
        var lineStart = 0
        while lineStart < total {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            defer { lineStart = lineRange.location + lineRange.length }
            guard let item = SmartEditing.listItem(lineRange: lineRange, in: ns) else { continue }

            var contentOffset = width(
                of: ns.substring(with: NSRange(
                    location: lineRange.location,
                    length: item.contentStart - lineRange.location)),
                font: baseFont)

            if item.marker == .bullet {
                storage.addAttribute(
                    .foregroundColor, value: NSColor.clear, range: item.markerRange)
                // `-`, `*`, and `+` have three different advances, and the
                // hidden character still reserves its own. Left alone, the
                // text after a `+` starts a hair right of the text after a
                // `-` — visible as a ragged left edge down a mixed list.
                // Kerning the marker out to the width of the glyph that
                // replaces it makes every bullet line start at the same x.
                let glyph = SmartEditing.bulletGlyph(depth: item.depth(indentWidth: indent.width))
                let markerWidth = width(
                    of: ns.substring(with: item.markerRange), font: baseFont)
                let kern = width(of: glyph, font: baseFont) - markerWidth
                storage.addAttribute(.kern, value: kern, range: item.markerRange)
                contentOffset += kern
            }

            let paragraph = makeParagraphStyle()
            paragraph.firstLineHeadIndent = width(
                of: ns.substring(with: NSRange(
                    location: lineRange.location,
                    length: item.markerRange.location - lineRange.location)),
                font: baseFont)
            // Wrapped lines hang to where the content starts, so a long
            // item reads as one block rather than sliding back under its
            // own bullet.
            paragraph.headIndent = contentOffset
            storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        }
    }

    private static func width(of text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    /// Render markdown emphasis with font traits, and `==marked==` with a
    /// background. Stays plain on disk — the markers remain visible, the
    /// same bargain the rest of the rendering makes.
    ///
    /// Both spellings of each form are read (`**`/`__`, `*`/`_`) even
    /// though ⌘B and ⌘I only ever *write* one, so a note pasted in from
    /// anywhere renders the way its author meant.
    private static func styleInlineMarkup(
        in storage: NSTextStorage, baseFont: NSFont, palette: Palette
    ) {
        let text = storage.string
        for match in text.matches(of: /\*\*([^*\n]+)\*\*/) {
            applyTrait(.bold, over: match.range, in: storage, text: text, baseFont: baseFont)
        }
        for match in text.matches(of: /__([^_\n]+)__/) where isFreestanding(match.range, in: text) {
            applyTrait(.bold, over: match.range, in: storage, text: text, baseFont: baseFont)
        }
        // Italic: a single marker, skipping any match that touches another
        // of the same marker on either side — that would mean the match is
        // the inside of a bold run. Swift Regex literals have no lookbehind,
        // so this filters after matching instead.
        for match in text.matches(of: /\*([^*\n]+)\*/)
        where !isAdjacent(to: "*", match.range, in: text) {
            applyTrait(.italic, over: match.range, in: storage, text: text, baseFont: baseFont)
        }
        for match in text.matches(of: /_([^_\n]+)_/)
        where !isAdjacent(to: "_", match.range, in: text) && isFreestanding(match.range, in: text) {
            applyTrait(.italic, over: match.range, in: storage, text: text, baseFont: baseFont)
        }
        // `` `code` ``: a whole different family, so it replaces the font
        // rather than merging a trait into it. Sized off whatever is already
        // at that offset, which is what lets a span inside a heading keep
        // the heading's size. Triple-backtick fences are left alone —
        // `[^`\n]+` can't match across the second backtick of a fence.
        for match in text.matches(of: /`([^`\n]+)`/) {
            let range = NSRange(match.range, in: text)
            let size = currentFont(in: storage, at: range.location, fallback: baseFont).pointSize
            storage.addAttribute(
                .font, value: Typography.codeFont(atResolvedSize: size), range: range)
        }
        // `<u>…</u>`: an attribute rather than a symbolic trait, so it
        // can't go through `applyTrait` with the others.
        for match in text.matches(of: /<u>([^<\n]+)<\/u>/) {
            storage.addAttribute(
                .underlineStyle, value: NSUnderlineStyle.single.rawValue,
                range: NSRange(match.range, in: text))
        }
        styleHighlights(in: storage, palette: palette)
    }

    /// `==marked==` runs, painted with a background.
    ///
    /// Separate from the rest of the inline pass because the find bar has
    /// to be able to re-run just this: both features want
    /// `.backgroundColor` and there is no second background attribute to
    /// keep them apart.
    static func styleHighlights(in storage: NSTextStorage, palette: Palette) {
        let text = storage.string
        for match in text.matches(of: /==([^=\n]+)==/) {
            storage.addAttribute(
                .backgroundColor, value: palette.highlight,
                range: NSRange(match.range, in: text))
        }
    }

    /// True when the run isn't butted against a word character on either
    /// side.
    ///
    /// This is what keeps `foo_bar_baz` from rendering `_bar_` in italics —
    /// a real hazard in a notes app that ends up holding identifiers and
    /// file names. CommonMark draws the same distinction for `_` and not
    /// for `*`, which is why only the underscore forms consult it.
    private static func isFreestanding(_ range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if before.isLetter || before.isNumber { return false }
        }
        if range.upperBound < text.endIndex {
            let after = text[range.upperBound]
            if after.isLetter || after.isNumber { return false }
        }
        return true
    }

    /// True when `marker` sits immediately outside either end of the run,
    /// which means this match is the inside of a doubled (bold) one.
    private static func isAdjacent(
        to marker: Character, _ range: Range<String.Index>, in text: String
    ) -> Bool {
        if range.lowerBound > text.startIndex,
            text[text.index(before: range.lowerBound)] == marker {
            return true
        }
        if range.upperBound < text.endIndex, text[range.upperBound] == marker { return true }
        return false
    }

    private static func applyTrait(
        _ traits: NSFontDescriptor.SymbolicTraits,
        over range: Range<String.Index>,
        in storage: NSTextStorage,
        text: String,
        baseFont: NSFont
    ) {
        let nsRange = NSRange(range, in: text)
        let current = currentFont(in: storage, at: nsRange.location, fallback: baseFont)
        storage.addAttribute(.font, value: traitFont(current, traits: traits), range: nsRange)
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

    /// Walks the storage line-by-line; for any line whose entire
    /// content is HR markers (the new `---` form, or the legacy
    /// `─` x N form from pre-0.1.38 files), set the foreground to
    /// `.clear` so the characters are invisible. The full-width
    /// rule is then drawn by `NotesLayoutManager`.
    private static func styleHorizontalRules(in storage: NSTextStorage) {
        let ns = storage.string as NSString
        let total = ns.length
        var lineStart = 0
        while lineStart < total {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            if SmartEditing.isHorizontalRuleLine(
                lineRange: lineRange, in: ns
            ) {
                var contentRange = lineRange
                if contentRange.length > 0,
                   ns.character(at: contentRange.location + contentRange.length - 1) == 0x0A {
                    contentRange.length -= 1
                }
                if contentRange.length > 0 {
                    storage.addAttribute(
                        .foregroundColor,
                        value: NSColor.clear,
                        range: contentRange
                    )
                }
            }
            lineStart = lineRange.location + lineRange.length
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, headings: $headings)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        /// Kept as a live binding rather than a `lastXToken`-style cached
        /// copy so `textDidChange` can read the fresh value mid-callback
        /// (below) without re-running `extractHeadings()` itself. This
        /// relies on `EditorModel.text`'s `didSet` recomputing `headings`
        /// synchronously and unconditionally — true today because the
        /// header bar needs it live on every keystroke too, but worth
        /// re-checking here if that ever changes.
        var headings: Binding<[Heading]>
        var lastFocusToken: Int = 0
        var lastScrollToken: Int = 0
        var lastWrapToken: Int = 0
        var lastDuplicateToken: Int = 0
        var lastListItemToken: Int = 0
        var lastMoveLineToken: Int = 0
        var lastFindHighlightToken: Int = 0
        var lastFontScale: Double = 1
        var lastIndent: Indent = Indent()
        var lastTheme: Theme = .dark

        init(text: Binding<String>, headings: Binding<[Heading]>) {
            self.text = text
            self.headings = headings
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string

            // Emoji shortcode replacement runs first — it may rewrite a
            // chunk of text, after which we restyle against the result.
            EmojiReplace.replaceIfMatched(in: textView)

            // Live-restyle: reset font, foreground, and paragraph style to
            // base across the storage, then re-apply the content passes.
            // Resetting first is what lets a line that stopped being an HR
            // or a list item lose the styling it had.
            if let storage = textView.textStorage {
                let baseFont = Typography.notesFont(Metrics.bodySize)
                let palette = Palette.for(lastTheme)
                MinimalTextEditor.resetBaseAttributes(
                    in: storage, font: baseFont, color: palette.text,
                    paragraph: MinimalTextEditor.makeParagraphStyle())
                MinimalTextEditor.restyleContent(
                    in: storage, baseFont: baseFont, headings: headings.wrappedValue,
                    indent: lastIndent, palette: palette)
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return handleEnter(in: textView)
            }
            // Tab and ⇧Tab: indent/outdent a list item or a selected block,
            // rather than moving focus out of the editor.
            if let notes = textView as? NotesTextView {
                if commandSelector == #selector(NSResponder.insertTab(_:)) {
                    notes.handleTab()
                    return true
                }
                if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                    notes.handleBacktab()
                    return true
                }
            }
            return false
        }

        /// Intercept typed text. Used to convert `---` to a horizontal rule
        /// the moment the third hyphen is typed — no need for Enter.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            // Only single-char `-` insertions count. Pastes (multi-char) and
            // undo restorations have different replacement strings, so they
            // skip this path naturally.
            guard replacementString == "-",
                  affectedCharRange.length == 0
            else { return true }

            let s = textView.string as NSString
            let insertAt = affectedCharRange.location
            let lineRange = s.lineRange(for: NSRange(location: insertAt, length: 0))

            let beforeCursor = s.substring(with: NSRange(
                location: lineRange.location,
                length: insertAt - lineRange.location
            ))
            var lineEnd = lineRange.location + lineRange.length
            if lineEnd > lineRange.location, s.character(at: lineEnd - 1) == 0x0A {
                lineEnd -= 1
            }
            let afterCursor = s.substring(with: NSRange(
                location: insertAt,
                length: lineEnd - insertAt
            ))

            // Trigger only when the line up to the cursor is exactly "--" and
            // the rest of the line is empty — i.e., user is finishing "---"
            // at the end of a fresh line, not editing inside content.
            guard beforeCursor == "--", afterCursor.isEmpty else { return true }

            let twoDashRange = NSRange(location: lineRange.location, length: 2)
            replaceWithHorizontalRule(in: textView, range: twoDashRange)
            return false  // suppress the typed "-"
        }

        private func handleEnter(in textView: NSTextView) -> Bool {
            let s = textView.string as NSString
            let cursor = textView.selectedRange().location
            let lineRange = s.lineRange(for: NSRange(location: cursor, length: 0))
            var lineEnd = lineRange.location + lineRange.length
            if lineEnd > lineRange.location, s.character(at: lineEnd - 1) == 0x0A {
                lineEnd -= 1
            }
            let line = s.substring(with: NSRange(
                location: lineRange.location,
                length: lineEnd - lineRange.location
            ))

            // Fallback path: catches `---` that arrived via paste, where the
            // typed-character interceptor above wouldn't fire.
            if SmartEditing.isHorizontalRuleTrigger(line) {
                let replaceRange = NSRange(
                    location: lineRange.location,
                    length: lineEnd - lineRange.location
                )
                replaceWithHorizontalRule(in: textView, range: replaceRange)
                return true
            }

            guard let marker = SmartEditing.nextListMarker(for: line) else {
                return false
            }

            if marker.isEmpty {
                let stripRange = NSRange(
                    location: lineRange.location,
                    length: cursor - lineRange.location
                )
                replace(in: textView, range: stripRange, with: "\n")
            } else {
                let insert = "\n" + marker
                replace(in: textView, range: NSRange(location: cursor, length: 0), with: insert)
            }
            return true
        }

        /// Replace `range` with the horizontal-rule string + newline and
        /// move the cursor past it. The HR characters are stored as
        /// plain `---` (markdown standard); the visible full-width
        /// line is drawn by NotesLayoutManager, while the
        /// `---` characters themselves are rendered with a clear
        /// foreground so only the line shows.
        private func replaceWithHorizontalRule(in textView: NSTextView, range: NSRange) {
            let replacement = SmartEditing.horizontalRule + "\n"
            replace(in: textView, range: range, with: replacement)
            let hrLength = (SmartEditing.horizontalRule as NSString).length
            let hrRange = NSRange(location: range.location, length: hrLength)
            textView.textStorage?.addAttribute(
                .foregroundColor,
                value: NSColor.clear,
                range: hrRange
            )
        }

        private func replace(in textView: NSTextView, range: NSRange, with replacement: String) {
            guard textView.replaceText(in: range, with: replacement) else { return }
            let newCursor = range.location + (replacement as NSString).length
            let newRange = NSRange(location: newCursor, length: 0)
            textView.setSelectedRange(newRange)
            // Hand-rolled edits bypass NSTextView's keyDown path, so its
            // built-in "scroll caret into view" doesn't fire. Without
            // this, hitting Enter at the bottom edge leaves the new
            // line off-screen until the user scrolls manually.
            textView.scrollRangeToVisible(newRange)
        }
    }
}
