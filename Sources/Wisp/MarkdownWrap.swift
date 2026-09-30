import AppKit

@MainActor
enum MarkdownWrap {
    /// A pair for `<u>…</u>`; every other marker closes itself.
    struct Markers: Equatable {
        let open: String
        let close: String

        init(_ open: String, _ close: String? = nil) {
            self.open = open
            self.close = close ?? open
        }

        static let bold = Markers("**")
        /// `_word_`; `*word*` renders as italic too.
        static let italic = Markers("_")
        static let highlight = Markers("==")
        /// HTML, as Obsidian's underline command inserts.
        static let underline = Markers("<u>", "</u>")
        /// `~~`, as Obsidian writes and Notion exports.
        static let strikethrough = Markers("~~")
        static let code = Markers("`")
    }

    /// With no selection, inserts the pair around the caret; a wrapped selection is unwrapped, and
    /// any other is wrapped.
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

    /// Wraps without unwrapping, for a delimiter typed over a selection: `"` over `"foo"`
    /// shouldn't strip its quotes. The inner text stays selected.
    static func wrap(in textView: NSTextView, range: NSRange, markers: Markers) {
        let inner = (textView.string as NSString).substring(with: range)
        let wrapped = markers.open + inner + markers.close
        guard textView.replaceText(in: range, with: wrapped) else { return }
        textView.setSelectedRange(NSRange(
            location: range.location + (markers.open as NSString).length,
            length: (inner as NSString).length
        ))
    }

    /// What typing `typed` over a selection wraps it in. `*`, `=`, and `~` double: `_` already
    /// covers italic, and a lone `=` or `~` isn't markup.
    static func surroundMarkers(for typed: String) -> Markers? {
        switch typed {
        case "`", "_", "'", "\"": return Markers(typed)
        case "*", "=", "~": return Markers(typed + typed)
        default: return nil
        }
    }
}
