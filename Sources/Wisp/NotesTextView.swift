import AppKit
import Carbon.HIToolbox
import WispCore

/// The notes body. A subclass rather than what
/// `NSTextView.scrollableTextView()` hands back, because ⌘C, ⌘X, and ⌘V
/// have to be intercepted: the Edit menu's items target the first
/// responder, so falling back to the current line when nothing is selected
/// can only happen here.
///
/// Building the view by hand also lets `NotesLayoutManager` be installed
/// as part of the text stack instead of swapped in afterwards with
/// `replaceLayoutManager`.
final class NotesTextView: NSTextView {
    /// The live indent unit, read from the config on every change so Tab
    /// writes what `indent.style` and `indent.size` currently say.
    var indentUnit: String = Indent().unit

    /// How the caret moves and blinks. Applied on the next reposition.
    var caretStyle: Caret {
        get { caret.style }
        set {
            caret.style = newValue
            refreshCaret(animated: false)
        }
    }

    private let caret = CaretLayer()

    /// Text length at the last caret update. A move that arrives with a
    /// change here is an edit — typing, ⌫, paste, undo — and places the
    /// caret without animating, so nothing ever lags a keystroke.
    private var lengthAtLastCaretUpdate = 0

    /// Tracked by hand: `resignFirstResponder` runs while `window.firstResponder`
    /// still points here, and AppKit's own `shouldDrawInsertionPoint` was
    /// seen answering true through a focus loss.
    private var hasFocus = false
    private var keyWindowObservers: [any NSObjectProtocol] = []

    /// Builds the whole scroll view / storage / layout manager / container
    /// stack. The pieces have to be assembled in this order — a container
    /// added to a layout manager that isn't yet attached to storage lays
    /// nothing out.
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

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    // MARK: Caret

    /// AppKit's own caret is switched off in favour of `CaretLayer`.
    /// Returning false here is what stops the blink timer; the empty
    /// `drawInsertionPoint` covers the draw call in case it is made anyway.
    override var shouldDrawInsertionPoint: Bool { false }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {}

    /// AppKit calls this wherever its caret would move or repaint —
    /// selection, focus, key window, and text changes — which makes it the
    /// one hook the overlay needs.
    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
        refreshCaret(animated: true)
    }

    /// AppKit reaches the hook above on a resize too; this is insurance
    /// for a reflow that somehow doesn't, and a no-op when the rect holds.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshCaret(animated: false)
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

    /// The panel losing key — another app clicked with
    /// `dismissOnOutsideClick` off — takes the caret with it.
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

        guard caretIsWanted, let window else {
            caret.update(to: nil, color: insertionPointColor, animated: false)
            return
        }
        if caret.layer.superlayer !== layer {
            wantsLayer = true
            layer?.addSublayer(caret.layer)
        }
        // The `NSTextInputClient` contract: an empty range yields the
        // insertion point, the same rect the IME candidate window keys off.
        let onScreen = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        var frame = convert(window.convertFromScreen(onScreen), from: nil)
        // Centred on the boundary as AppKit's indicator is, then snapped to
        // device pixels so a 1x display doesn't smear it over three columns.
        frame.origin.x -= CaretLayer.width / 2
        frame.size.width = CaretLayer.width
        frame = backingAlignedRect(frame, options: .alignAllEdgesNearest)
        caret.update(to: frame, color: insertionPointColor, animated: animated && !edited)
    }

    // MARK: Whole-line copy, cut, and paste

    /// Keeps Cut and Copy enabled with an empty selection.
    ///
    /// `NSTextView` validates both against having a selection, and a
    /// disabled menu item's key equivalent never fires — so without this
    /// the overrides below are simply never called, and ⌘C silently does
    /// nothing rather than taking the line. Everything else is left to
    /// `super`.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) || item.action == #selector(cut(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    /// ⌘C with nothing selected copies the whole line, newline included,
    /// so the paste lands as a line rather than in the middle of one.
    override func copy(_ sender: Any?) {
        guard selectedRange().length == 0 else {
            super.copy(sender)
            return
        }
        let line = LineEdits.lineForClipboard(in: string as NSString, selection: selectedRange())
        writeToPasteboard(line.string)
    }

    /// ⌘X with nothing selected cuts the whole line and leaves the cursor
    /// at the same column on the line that moves up into its place.
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

    /// ⌘V of a line that ⌘C or ⌘X took whole, with nothing selected, puts
    /// it in above the current line rather than at the caret. Anything
    /// else — a selection to replace, a pasteboard another app wrote — is
    /// an ordinary paste.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard selectedRange().length == 0,
            pasteboard.types?.contains(Self.wholeLineType) == true,
            let line = pasteboard.string(forType: .string)
        else {
            super.paste(sender)
            return
        }
        apply(LineEdits.pasteLine(in: string as NSString, selection: selectedRange(), line: line))
    }

    /// Marks a pasteboard entry as a whole line, the way VS Code's
    /// `isFromEmptySelection` and JetBrains' custom flavor do. The marker is
    /// a second type on the same entry, so it cannot outlive the text:
    /// every writer clears the pasteboard before setting its own types, and
    /// the marker goes with it.
    private static let wholeLineType = NSPasteboard.PasteboardType("quest.uponre.wisp.whole-line")

    private func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: Self.wholeLineType)
    }

    // MARK: Duplicate, indent, outdent

    /// ⌘D, routed here from the Edit menu through the model's token.
    func duplicateSelection() {
        apply(LineEdits.duplicate(in: string as NSString, selection: selectedRange()))
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
    func toggleTaskItems() {
        apply(LineEdits.toggleTaskItems(in: string as NSString, selection: selectedRange()))
    }

    /// True while a hand-rolled edit is between its replacement and the
    /// selection it sets. `textDidChange` fires in the middle of that,
    /// when the selection is still the pre-edit one — the wrong thing to
    /// shift by a renumber — so the delegate holds off and the edit
    /// renumbers itself once its selection is in place. AppKit's own
    /// edits (typing, ⌫, paste) have already moved the selection by the
    /// time the delegate hears, and renumber straight from there.
    private(set) var isApplyingEdit = false

    /// Runs `body` as one hand-rolled edit: renumbering waits for the
    /// selection it sets. The first call's ⌘Z takes back the whole thing
    /// — the renumber lands in the same event, so the same undo group.
    func performEdit(_ body: () -> Void) {
        let wasApplying = isApplyingEdit
        isApplyingEdit = true
        body()
        isApplyingEdit = wasApplying
        if !wasApplying { renumberLists() }
    }

    /// Puts every ordered run back in sequence. Applied back to front so
    /// earlier ranges stay valid. The caret shifts by whatever changed
    /// width ahead of it. Re-entered through `didChangeText` while
    /// applying; the flag makes that a no-op.
    func renumberLists() {
        // Undo restores old markers through `didChangeText` too; putting
        // them back in sequence mid-undo would register onto the redo
        // stack and leave the step a visible no-op.
        guard !isApplyingEdit,
            undoManager?.isUndoing != true, undoManager?.isRedoing != true
        else { return }
        let edits = SmartEditing.renumber(in: string as NSString)
        guard !edits.isEmpty else { return }
        isApplyingEdit = true
        defer { isApplyingEdit = false }
        var selection = selectedRange()
        for edit in edits.reversed() {
            guard replaceText(in: edit.range, with: edit.replacement) else { continue }
            let delta = (edit.replacement as NSString).length - edit.range.length
            if edit.range.location < selection.location {
                selection.location += delta
            } else if edit.range.location < NSMaxRange(selection) {
                selection.length += delta
            }
        }
        setSelectedRange(selection)
    }

    /// ⌫ at the start of an item's text takes the marker off instead of
    /// the space after it, and ⌫ inside a line's leading indent takes a
    /// level off instead of a character. The two can't both match — one
    /// needs a marker before the caret, the other only whitespace.
    /// Everything else is `super`'s.
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

    /// A click on a task's box toggles it. The hit test is against the
    /// glyph's own rectangle rather than the character index under the
    /// mouse, so a click in the whitespace beside the box, or on the
    /// item's first word, still places the caret as it always did.
    ///
    /// The later clicks of a double- or triple-click on the box are
    /// swallowed: the first already toggled it, and `super` would select
    /// the hidden marker text under the glyph.
    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
        guard modifiers.isEmpty, let index = taskBoxIndex(under: event)
        else { return super.mouseDown(with: event) }
        if event.clickCount == 1,
            let edit = SmartEditing.toggledTask(
                in: string as NSString, lineAt: index, selection: selectedRange())
        {
            apply(edit)
        }
    }

    /// The arrow over a box, as over any control, rather than the I-beam
    /// text gets. AppKit sets the I-beam from `mouseMoved`, so the
    /// override has to win there; `cursorUpdate` covers the first entry
    /// into the view.
    override func mouseMoved(with event: NSEvent) {
        guard taskBoxIndex(under: event) != nil else { return super.mouseMoved(with: event) }
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard taskBoxIndex(under: event) != nil else { return super.cursorUpdate(with: event) }
        NSCursor.arrow.set()
    }

    /// Raw mode shows the `[ ]` as text, and text is for placing a caret in.
    private var isSourceView: Bool {
        (layoutManager as? NotesLayoutManager)?.isSourceView ?? false
    }

    /// The character index of the task line whose drawn box is under the
    /// event's mouse position, or nil when the pointer is anywhere else.
    /// The box's rectangle is the marker's reserved width by the line's
    /// full height, which is what `NotesLayoutManager` paints into.
    private func taskBoxIndex(under event: NSEvent) -> Int? {
        guard !isSourceView, let layoutManager, let container = textContainer else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let inContainer = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let text = string as NSString
        guard text.length > 0 else { return nil }
        let index = layoutManager.characterIndex(
            for: inContainer, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        let line = LineEdits.lineRange(in: text, at: index)
        guard let item = SmartEditing.listItem(lineRange: line, in: text), item.marker.isTask
        else { return nil }
        let glyphs = layoutManager.glyphRange(
            forCharacterRange: item.markerRange, actualCharacterRange: nil)
        let box = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        return box.contains(inContainer) ? index : nil
    }

    /// Tab. On a list item — or anywhere a selection spans — this shifts
    /// whole lines; with a bare cursor in ordinary prose it inserts one
    /// indent unit where the cursor is, which is what a Tab key is for.
    func handleTab() {
        let selection = selectedRange()
        let text = string as NSString
        guard selection.length > 0 || isInListItem(selection, in: text) else {
            apply(
                LineEdits.Edit(
                    range: selection, replacement: indentUnit,
                    selection: NSRange(
                        location: selection.location + (indentUnit as NSString).length, length: 0)))
            return
        }
        apply(LineEdits.indent(in: text, selection: selection, unit: indentUnit))
    }

    /// ⇧Tab always outdents — there is nothing else it could usefully
    /// mean in a plain-text editor with no tab stops. What it outdents is
    /// whichever of the two things `handleTab` might have indented: the
    /// whitespace just before a bare cursor mid-line, or failing that the
    /// whole block.
    func handleBacktab() {
        let text = string as NSString
        let selection = selectedRange()
        if let edit = LineEdits.outdentAtCursor(
            in: text, selection: selection, unit: indentUnit) {
            apply(edit)
            return
        }
        let edit = LineEdits.outdent(in: text, selection: selection, unit: indentUnit)
        // An already-flush block rewrites itself to itself; skipping it
        // keeps a no-op ⇧Tab out of the undo stack.
        guard edit.replacement != text.substring(with: edit.range) else { return }
        apply(edit)
    }

    // MARK: Home and End

    /// AppKit gives Home and End to the document — a scroll with no caret
    /// move bare, select-to-the-end with ⇧ — where every other editor
    /// gives them to the line. Caught here as key events rather than by
    /// overriding the document selectors, which ⇧⌘↑ and ⇧⌘↓ share and
    /// should keep. ⌥ and ⌘ variants fall through untouched.
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

    /// ⌘← and Home. On a list line the first stop is the item's text, past
    /// the marker; from there a second press goes to column 0. `super`
    /// runs first because it knows about wrapping: on a continuation
    /// fragment it stops at that fragment's start, which is already past
    /// the marker, and the smart stop only applies when it came back with
    /// the paragraph's own first column.
    override func moveToBeginningOfLine(_ sender: Any?) {
        let cursor = selectedRange().location
        super.moveToBeginningOfLine(sender)
        guard let target = homeTarget(from: cursor) else { return }
        setSelectedRange(NSRange(location: target, length: 0))
    }

    /// ⇧⌘←. Adjusted only from a bare cursor: with a selection already
    /// standing, which end is the anchor depends on how it was made, and
    /// `super` is the one that knows.
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

    /// Runs one `LineEdits.Edit` through the delegate/undo bookkeeping and
    /// restores the selection it names.
    private func apply(_ edit: LineEdits.Edit) {
        performEdit {
            guard replaceText(in: edit.range, with: edit.replacement) else { return }
            setSelectedRange(edit.selection)
            // Hand-rolled edits bypass the keyDown path, so NSTextView's own
            // "scroll the caret into view" never fires.
            scrollRangeToVisible(edit.selection)
        }
    }
}
