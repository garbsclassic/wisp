import AppKit
import WispCore

/// The notes body. A subclass rather than what
/// `NSTextView.scrollableTextView()` hands back, because ⌘C and ⌘X have to
/// be intercepted: the Edit menu's items target the first responder, so
/// falling back to the current line when nothing is selected can only
/// happen here.
///
/// Building the view by hand also lets `NotesLayoutManager` be installed
/// as part of the text stack instead of swapped in afterwards with
/// `replaceLayoutManager`.
final class NotesTextView: NSTextView {
    /// The live indent unit, read from the config on every change so Tab
    /// writes what `indent.style` and `indent.size` currently say.
    var indentUnit: String = Indent().unit

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

    // MARK: Whole-line copy and cut

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

    private func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: Duplicate, indent, outdent

    /// ⌘D, routed here from the Edit menu through the model's token.
    func duplicateSelection() {
        apply(LineEdits.duplicate(in: string as NSString, selection: selectedRange()))
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
    /// mean in a plain-text editor with no tab stops.
    func handleBacktab() {
        let edit = LineEdits.outdent(
            in: string as NSString, selection: selectedRange(), unit: indentUnit)
        // An already-flush block rewrites itself to itself; skipping it
        // keeps a no-op ⇧Tab out of the undo stack.
        guard edit.replacement != (string as NSString).substring(with: edit.range) else { return }
        apply(edit)
    }

    private func isInListItem(_ selection: NSRange, in text: NSString) -> Bool {
        let line = LineEdits.lineRange(in: text, at: selection.location)
        return SmartEditing.listItem(lineRange: line, in: text) != nil
    }

    /// Runs one `LineEdits.Edit` through the delegate/undo bookkeeping and
    /// restores the selection it names.
    private func apply(_ edit: LineEdits.Edit) {
        guard replaceText(in: edit.range, with: edit.replacement) else { return }
        setSelectedRange(edit.selection)
        // Hand-rolled edits bypass the keyDown path, so NSTextView's own
        // "scroll the caret into view" never fires.
        scrollRangeToVisible(edit.selection)
    }
}
