import AppKit

@MainActor
enum MarkdownWrap {
    /// What goes either side of the selection.
    ///
    /// A pair rather than one string because underline is `<u>…</u>`: HTML,
    /// since markdown has no underline and `__` is already bold here. Every
    /// other marker Wisp inserts is its own closer, which is what the
    /// one-argument initializer is for.
    struct Markers: Equatable {
        let open: String
        let close: String

        init(_ open: String, _ close: String? = nil) {
            self.open = open
            self.close = close ?? open
        }
    }

    /// Toggle `markers` around the text view's current selection.
    ///
    /// - Empty selection: inserts `marker + marker` with the cursor between
    ///   the two halves.
    /// - Selection already wrapped (starts and ends with the marker):
    ///   unwraps, leaving just the inner content selected.
    /// - Otherwise: wraps the selection, keeping the inner content selected
    ///   so the user can immediately re-toggle or keep typing.
    static func toggle(in textView: NSTextView, markers: Markers) {
        let nsString = textView.string as NSString
        let selectedRange = textView.selectedRange()
        let openLen = (markers.open as NSString).length
        let closeLen = (markers.close as NSString).length

        if selectedRange.length == 0 {
            let combined = markers.open + markers.close
            guard textView.replaceText(in: selectedRange, with: combined) else { return }
            let newCursor = selectedRange.location + openLen
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            return
        }

        let selectedText = nsString.substring(with: selectedRange)
        let totalLen = (selectedText as NSString).length

        if totalLen >= openLen + closeLen,
           selectedText.hasPrefix(markers.open),
           selectedText.hasSuffix(markers.close) {
            let inner = (selectedText as NSString).substring(with: NSRange(
                location: openLen,
                length: totalLen - openLen - closeLen
            ))
            guard textView.replaceText(in: selectedRange, with: inner) else { return }
            textView.setSelectedRange(NSRange(
                location: selectedRange.location,
                length: (inner as NSString).length
            ))
            return
        }

        let wrapped = markers.open + selectedText + markers.close
        guard textView.replaceText(in: selectedRange, with: wrapped) else { return }
        textView.setSelectedRange(NSRange(
            location: selectedRange.location + openLen,
            length: (selectedText as NSString).length
        ))
    }
}
