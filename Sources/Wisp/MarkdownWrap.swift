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

        wrap(in: textView, range: selectedRange, markers: markers)
    }

    /// Put `markers` around `range`, leaving the inner content selected so a
    /// second pass nests rather than starting over.
    ///
    /// Split out of `toggle` because typing a delimiter over a selection wants
    /// this half and not the unwrap half: ⌘B is a command and may toggle, but
    /// typing a character is an insertion, and having `"` swallow the quotes
    /// off `"foo"` is not what the keypress meant.
    static func wrap(in textView: NSTextView, range: NSRange, markers: Markers) {
        let inner = (textView.string as NSString).substring(with: range)
        let wrapped = markers.open + inner + markers.close
        guard textView.replaceText(in: range, with: wrapped) else { return }
        textView.setSelectedRange(NSRange(
            location: range.location + (markers.open as NSString).length,
            length: (inner as NSString).length
        ))
    }

    /// What typing `typed` over a selection wraps it in, or nil for a
    /// character that means nothing here.
    ///
    /// Doubled for `*`, `=`, and `~` because that is the emphasis those
    /// characters are reached for — a lone `*` is italic, but `_` already
    /// covers italic, `=` alone is not markup at all, and `~~` is the
    /// strikethrough Obsidian writes. `'` and `"` aren't markup either; they
    /// are the other thing a selection gets wrapped in.
    static func surroundMarkers(for typed: String) -> Markers? {
        switch typed {
        case "`", "_", "'", "\"": return Markers(typed)
        case "*", "=", "~": return Markers(typed + typed)
        default: return nil
        }
    }
}
