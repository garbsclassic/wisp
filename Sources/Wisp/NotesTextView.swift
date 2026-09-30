import AppKit
import Carbon.HIToolbox
import WispCore

/// The notes body: a subclass so ⌘C, ⌘X, and ⌘V can take the whole line when nothing is
/// selected, built by hand so `NotesLayoutManager` is part of the stack.
final class NotesTextView: NSTextView {
    /// Read from the config on every change.
    var indentUnit: String = Indent().unit
    /// Mirrors `smartPaste` in the config; read on every ⌘V.
    var smartPaste: Bool = true
    /// So the context menu's spelling toggle flips the setting, not just this view.
    var onToggleSpellcheck: (() -> Void)?

    /// Cached per edit: AppKit asks once per misspelled word, and classifying the note each time
    /// took seconds on a long note.
    private var codeRanges: [NSRange]?
    private var storageObserver: (any NSObjectProtocol)?

    /// How the caret moves and blinks. Applied on the next reposition.
    var caretStyle: Caret {
        get { caret.style }
        set {
            caret.style = newValue
            refreshCaret(animated: false)
        }
    }

    private let caret = CaretLayer()

    /// Set while `draw` runs, so `setFrameSize` can tell a resize mid-draw.
    private var isDrawing = false
    private var resizedWhileDrawing = false

    /// A move with a length change is an edit and isn't animated, so the caret never lags a key.
    private var lengthAtLastCaretUpdate = 0

    /// Tracked by hand: `shouldDrawInsertionPoint` was seen answering true through a focus loss.
    private var hasFocus = false
    private var keyWindowObservers: [any NSObjectProtocol] = []

    /// In this order: a container on a layout manager not yet attached to storage lays out nothing.
    static func makeScrollView() -> (scrollView: NSScrollView, textView: NotesTextView) {
        let storage = NSTextStorage()
        let layoutManager = NotesLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NotesTextView(frame: .zero, textContainer: container)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize.zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.storageObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
        ) { [weak textView] note in
            guard let edited = note.object as? NSTextStorage,
                  edited.editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated { textView?.codeRanges = nil }
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    // MARK: Caret

    /// Off in favour of `CaretLayer`; returning false stops AppKit's blink timer.
    override var shouldDrawInsertionPoint: Bool { false }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {}

    /// Called wherever AppKit's caret would move or repaint, so it's the one hook the layer needs.
    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
        refreshCaret(animated: true)
    }

    /// Insurance for a reflow that misses the hook above; a no-op when the rect holds.
    override func setFrameSize(_ newSize: NSSize) {
        if isDrawing, newSize != frame.size { resizedWhileDrawing = true }
        super.setFrameSize(newSize)
        refreshCaret(animated: false)
    }

    /// TextKit 1 can resize the view inside its own draw, and the redisplay that resize asks for is
    /// lost, leaving stale lines after ⌘X. Asked for again on the next run-loop turn.
    override func draw(_ dirtyRect: NSRect) {
        isDrawing = true
        super.draw(dirtyRect)
        isDrawing = false
        if resizedWhileDrawing {
            resizedWhileDrawing = false
            DispatchQueue.main.async { [weak self] in self?.needsDisplay = true }
        }
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        hasFocus = true
        refreshCaret(animated: false)
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        hasFocus = false
        refreshCaret(animated: false)
        return true
    }

    /// The panel losing key takes the caret with it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyWindowObservers.forEach(NotificationCenter.default.removeObserver)
        keyWindowObservers = []
        if let window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                keyWindowObservers.append(
                    NotificationCenter.default.addObserver(
                        forName: name, object: window, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated { self?.refreshCaret(animated: false) }
                    })
            }
        }
        refreshCaret(animated: false)
    }

    private var caretIsWanted: Bool {
        hasFocus && isEditable && selectedRange().length == 0
            && window?.isKeyWindow == true
    }

    private func refreshCaret(animated: Bool) {
        let length = (string as NSString).length
        let edited = length != lengthAtLastCaretUpdate
        lengthAtLastCaretUpdate = length

        guard caretIsWanted, let layoutManager, let textContainer else {
            caret.update(to: nil, color: insertionPointColor, animated: false)
            return
        }
        if caret.layer.superlayer !== layer {
            wantsLayer = true
            layer?.addSublayer(caret.layer)
        }
        // An empty range gives the insertion point. Not `firstRect`, which clips to the visible
        // rect and shortened a caret half past the bottom edge.
        var count = 0
        guard
            let rects = layoutManager.rectArray(
                forCharacterRange: selectedRange(),
                withinSelectedCharacterRange: selectedRange(),
                in: textContainer, rectCount: &count),
            count > 0
        else {
            caret.update(to: nil, color: insertionPointColor, animated: false)
            return
        }
        var frame = rects[0].offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        // Centred on the boundary, then snapped to pixels so a 1x display doesn't smear it.
        frame.origin.x -= CaretLayer.width / 2
        frame.size.width = CaretLayer.width
        if let font {
            // The fragment's leading sits above the glyphs, so a full-height caret towers over the
            // caps. This one sits midway between the fragment and a tight caret.
            let baseline = frame.maxY + font.descender
            let tightTop = baseline - font.capHeight - (font.ascender - font.capHeight) / 2
            let tightBottom = baseline - font.descender / 2
            let top = (frame.minY + tightTop) / 2
            let bottom = (frame.maxY + tightBottom) / 2
            frame.origin.y = top
            frame.size.height = bottom - top
        }
        frame = backingAlignedRect(frame, options: .alignAllEdgesNearest)
        caret.update(to: frame, color: insertionPointColor, animated: animated && !edited)
    }

    // MARK: Whole-line copy, cut, and paste

    /// Keeps Cut and Copy enabled with no selection, or their key equivalents never fire.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) || item.action == #selector(cut(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    /// With nothing selected, copies the whole line, newline included.
    override func copy(_ sender: Any?) {
        guard selectedRange().length == 0 else {
            super.copy(sender)
            return
        }
        let line = LineEdits.lineForClipboard(in: string as NSString, selection: selectedRange())
        writeToPasteboard(line.string)
    }

    /// With nothing selected, cuts the line, keeping the column on the line that moves up.
    override func cut(_ sender: Any?) {
        guard selectedRange().length == 0 else {
            super.cut(sender)
            return
        }
        let text = string as NSString
        let line = LineEdits.lineForClipboard(in: text, selection: selectedRange())
        writeToPasteboard(line.string)
        apply(LineEdits.cutLine(in: text, selection: selectedRange()))
    }

    /// A whole-line copy pastes above the current line. Other text onto a blank line goes through
    /// `SmartPaste`; anything else is an ordinary paste.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let selection = selectedRange()
        guard selection.length == 0, let pasted = pasteboard.string(forType: .string) else {
            super.paste(sender)
            return
        }
        let text = string as NSString
        if pasteboard.types?.contains(Self.wholeLineType) == true {
            apply(LineEdits.pasteLine(in: text, selection: selection, line: pasted))
            return
        }
        let line = LineEdits.lineRange(in: text, at: selection.location)
        if smartPaste, !isSourceView, LineEdits.contentLength(of: line, in: text) == 0,
            let formatted = SmartPaste.format(pasted)
        {
            apply(.insert(formatted, replacing: selection))
            return
        }
        super.paste(sender)
    }

    /// Marks a whole-line copy, as VS Code and JetBrains do; a second type on the same entry, so it
    /// is cleared with the text.
    private static let wholeLineType = NSPasteboard.PasteboardType("quest.uponre.wisp.whole-line")

    private func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: Self.wholeLineType)
    }

    // MARK: Keymap edits

    // Called by `AppDelegate.perform`, inside the key event that asked.

    /// ⌘B, ⌘I, and the other inline formats.
    func toggleWrap(_ markers: MarkdownWrap.Markers) {
        performEdit { MarkdownWrap.toggle(in: self, markers: markers) }
    }

    /// ⌘D.
    func duplicateSelection() {
        apply(LineEdits.duplicate(in: string as NSString, selection: selectedRange()))
    }

    /// ⌘↩ / ⌘⇧↩.
    func openLine(below: Bool) {
        apply(LineEdits.openLine(in: string as NSString, selection: selectedRange(), below: below))
    }

    /// ⌥↑ / ⌥↓.
    func moveLines(by delta: Int) {
        let edit = LineEdits.moveLines(
            in: string as NSString, selection: selectedRange(), by: delta)
        guard !edit.isNoOp else { return }
        apply(edit)
    }

    /// ⌘L.
    func toggleBulletedList() {
        apply(LineEdits.toggleBulletedList(in: string as NSString, selection: selectedRange()))
    }

    /// ⌘⇧L.
    func toggleChecklist() {
        apply(LineEdits.toggleChecklist(in: string as NSString, selection: selectedRange()))
    }

    /// Set between a hand-rolled edit's replacement and its selection, when `textDidChange` would
    /// renumber against the old selection; the edit renumbers itself afterwards.
    private(set) var isApplyingEdit = false

    /// One hand-rolled edit, renumbered once its selection is set, in the same undo group.
    func performEdit(_ body: () -> Void) {
        let wasApplying = isApplyingEdit
        isApplyingEdit = true
        body()
        isApplyingEdit = wasApplying
        if !wasApplying { renumberLists() }
    }

    /// Every ordered run back in sequence as one change, back to front, shifting the caret by what
    /// changed ahead of it. `blocks` saves reclassifying the text.
    @discardableResult
    func renumberLists(blocks: MarkdownBlocks? = nil) -> Bool {
        // Renumbering mid-undo would land on the redo stack and make the step a no-op.
        guard !isApplyingEdit,
            undoManager?.isUndoing != true, undoManager?.isRedoing != true,
            let textStorage
        else { return false }
        let edits = SmartEditing.renumber(in: string as NSString, blocks: blocks)
        guard !edits.isEmpty,
            shouldChangeText(
                inRanges: edits.map { NSValue(range: $0.range) },
                replacementStrings: edits.map(\.replacement))
        else { return false }
        isApplyingEdit = true
        defer { isApplyingEdit = false }
        var selection = selectedRange()
        textStorage.beginEditing()
        for edit in edits.reversed() {
            textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
            let delta = (edit.replacement as NSString).length - edit.range.length
            if edit.range.location < selection.location {
                selection.location += delta
            } else if edit.range.location < NSMaxRange(selection) {
                selection.length += delta
            }
        }
        textStorage.endEditing()
        didChangeText()
        setSelectedRange(selection)
        return true
    }

    /// ⌫ at an item's text start removes the marker; ⌫ in the leading indent removes a level.
    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        let text = string as NSString
        if selection.length == 0,
            let edit = SmartEditing.backspaceAtItemStart(in: text, cursor: selection.location) {
            apply(edit)
            return
        }
        if let edit = LineEdits.backspaceInIndent(
            in: text, selection: selection, unit: indentUnit) {
            apply(edit)
            return
        }
        super.deleteBackward(sender)
    }

    /// A click on a drawn box toggles it; a click beside it places the caret. A multi-click's later
    /// clicks are swallowed, or `super` would select the hidden marker.
    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
        guard modifiers.isEmpty, let index = checklistBoxIndex(under: event)
        else { return super.mouseDown(with: event) }
        if event.clickCount == 1,
            let edit = SmartEditing.toggledChecklist(
                in: string as NSString, lineAt: index, selection: selectedRange())
        {
            apply(edit)
        }
    }

    /// The arrow over a box. AppKit sets the I-beam in `mouseMoved`; `cursorUpdate` covers entry.
    override func mouseMoved(with event: NSEvent) {
        guard checklistBoxIndex(under: event) != nil else { return super.mouseMoved(with: event) }
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard checklistBoxIndex(under: event) != nil else { return super.cursorUpdate(with: event) }
        NSCursor.arrow.set()
    }

    /// Raw mode shows the `[ ]` as text, and text is for placing a caret in.
    private var isSourceView: Bool {
        (layoutManager as? NotesLayoutManager)?.isSourceView ?? false
    }

    /// The index of the checklist line whose drawn box is under the pointer.
    private func checklistBoxIndex(under event: NSEvent) -> Int? {
        guard !isSourceView, let layoutManager, let container = textContainer else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let inContainer = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let text = string as NSString
        guard text.length > 0 else { return nil }
        let index = layoutManager.characterIndex(
            for: inContainer, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        let line = LineEdits.lineRange(in: text, at: index)
        guard let item = SmartEditing.listItem(lineRange: line, in: text), item.marker.isChecklist
        else { return nil }
        let glyphs = layoutManager.glyphRange(
            forCharacterRange: item.markerRange, actualCharacterRange: nil)
        let box = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        return box.contains(inContainer) ? index : nil
    }

    /// ⇥ shifts whole lines on a list item or a selection, and otherwise inserts at the caret.
    func handleTab() {
        let selection = selectedRange()
        let text = string as NSString
        guard selection.length > 0 || isInListItem(selection, in: text) else {
            apply(.insert(indentUnit, replacing: selection))
            return
        }
        apply(LineEdits.indent(in: text, selection: selection, unit: indentUnit))
    }

    /// ⇧⇥ takes back mid-line whitespace before a bare caret, or else outdents the block.
    func handleBacktab() {
        let text = string as NSString
        let selection = selectedRange()
        if let edit = LineEdits.outdentAtCursor(
            in: text, selection: selection, unit: indentUnit) {
            apply(edit)
            return
        }
        let edit = LineEdits.outdent(in: text, selection: selection, unit: indentUnit)
        // A flush block rewrites to itself; skipping it keeps the no-op off the undo stack.
        guard edit.replacement != text.substring(with: edit.range) else { return }
        apply(edit)
    }

    // MARK: Home and End

    /// Home and End go to the line, as in other editors, not the document. Caught as key events,
    /// since ⇧⌘↑ and ⇧⌘↓ share the document selectors.
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .numericPad])
        let shift = modifiers == .shift
        guard modifiers.isEmpty || shift else { return super.keyDown(with: event) }
        switch Int(event.keyCode) {
        case kVK_Home:
            shift ? moveToBeginningOfLineAndModifySelection(self) : moveToBeginningOfLine(self)
        case kVK_End:
            shift ? moveToEndOfLineAndModifySelection(self) : moveToEndOfLine(self)
        default:
            super.keyDown(with: event)
        }
    }

    /// On a list line the first stop is the item's text, then column 0. `super` runs first, since
    /// it knows about wrapped fragments.
    override func moveToBeginningOfLine(_ sender: Any?) {
        let cursor = selectedRange().location
        super.moveToBeginningOfLine(sender)
        guard let target = homeTarget(from: cursor) else { return }
        setSelectedRange(NSRange(location: target, length: 0))
    }

    /// Adjusted only from a bare cursor; with a selection, `super` knows which end anchors it.
    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        let before = selectedRange()
        super.moveToBeginningOfLineAndModifySelection(sender)
        guard before.length == 0, let target = homeTarget(from: before.location) else { return }
        setSelectedRange(
            NSRange(location: min(target, before.location), length: abs(before.location - target)))
    }

    private func homeTarget(from cursor: Int) -> Int? {
        let text = string as NSString
        guard selectedRange().location == LineEdits.lineRange(in: text, at: cursor).location
        else { return nil }
        return SmartEditing.homeTarget(in: text, cursor: cursor)
    }

    private func isInListItem(_ selection: NSRange, in text: NSString) -> Bool {
        let line = LineEdits.lineRange(in: text, at: selection.location)
        return SmartEditing.listItem(lineRange: line, in: text) != nil
    }

    /// Keeps spelling marks off code. Clearing passes straight through.
    override func setSpellingState(_ value: Int, range charRange: NSRange) {
        guard value != 0 else {
            super.setSpellingState(value, range: charRange)
            return
        }
        let text = string as NSString
        if codeRanges == nil { codeRanges = MarkdownBlocks(text).codeRanges(in: text) }
        var remaining = [charRange]
        for code in codeRanges ?? [] where NSIntersectionRange(code, charRange).length > 0 {
            remaining = remaining.flatMap { piece -> [NSRange] in
                let cut = NSIntersectionRange(piece, code)
                guard cut.length > 0 else { return [piece] }
                return [
                    NSRange(location: piece.location, length: cut.location - piece.location),
                    NSRange(location: NSMaxRange(cut), length: NSMaxRange(piece) - NSMaxRange(cut)),
                ].filter { $0.length > 0 }
            }
        }
        for piece in remaining { super.setSpellingState(value, range: piece) }
    }

    /// Checking only sees edited text, so this marks the whole note when it comes on. Spelling
    /// only, since the other types rewrite.
    func checkSpellingEverywhere() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            checkText(
                in: NSRange(location: 0, length: (string as NSString).length),
                types: NSTextCheckingResult.CheckingType.spelling.rawValue, options: [:])
        }
    }

    override func toggleContinuousSpellChecking(_ sender: Any?) {
        guard let onToggleSpellcheck else { return super.toggleContinuousSpellChecking(sender) }
        onToggleSpellcheck()
    }

    // Never rewrite a word behind you: these stay off whatever the context menu asks.
    override var isGrammarCheckingEnabled: Bool {
        get { false }
        set {}
    }
    override var isAutomaticSpellingCorrectionEnabled: Bool {
        get { false }
        set {}
    }
    override var isAutomaticQuoteSubstitutionEnabled: Bool {
        get { false }
        set {}
    }
    override var isAutomaticDashSubstitutionEnabled: Bool {
        get { false }
        set {}
    }
    override var isAutomaticTextReplacementEnabled: Bool {
        get { false }
        set {}
    }

    /// Runs an edit through the delegate and undo bookkeeping, and restores its selection.
    func apply(_ edit: LineEdits.Edit) {
        performEdit {
            guard replaceText(in: edit.range, with: edit.replacement) else { return }
            setSelectedRange(edit.selection)
            // Hand-rolled edits skip keyDown, which is what scrolls the caret into view.
            scrollRangeToVisible(edit.selection)
        }
    }
}
