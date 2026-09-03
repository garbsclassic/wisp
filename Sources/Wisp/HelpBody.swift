import AppKit
import Carbon.HIToolbox
import SwiftUI
import WispCore

/// One scroll gesture, from a key. The wheel is the scroll view's own.
enum ScrollCommand {
    case lineUp, lineDown
    case pageUp, pageDown
    case top, bottom

    /// Nil for anything that isn't a scroll key, which is what tells the
    /// text view to hand the event on.
    init?(event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        // ⌘↑ / ⌘↓ are the macOS-wide "jump to the ends" chord, and Home and
        // End are the same thing on a keyboard that has them.
        let jump = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_UpArrow: self = jump ? .top : .lineUp
        case kVK_DownArrow: self = jump ? .bottom : .lineDown
        case kVK_PageUp: self = .pageUp
        case kVK_PageDown: self = .pageDown
        case kVK_Home: self = .top
        case kVK_End: self = .bottom
        case kVK_Space: self = shift ? .pageUp : .pageDown
        default: return nil
        }
    }

    /// How far an arrow key moves. A line of help text plus its spacing —
    /// arrows are for nudging the last row into view, not for travelling.
    private static let lineStep: CGFloat = 28
    /// Kept on screen across a page turn, so there is an overlap to read
    /// back into rather than a jump cut.
    private static let pageOverlap: CGFloat = 40

    @MainActor
    func apply(to scrollView: NSScrollView) {
        guard let document = scrollView.documentView else { return }
        let visible = scrollView.contentView.bounds
        // Nothing to scroll — a short help page on a tall panel.
        let maxY = max(0, document.frame.height - visible.height)
        guard maxY > 0 else { return }

        let page = max(visible.height - Self.pageOverlap, visible.height / 2)
        var y = visible.origin.y
        switch self {
        case .lineUp: y -= Self.lineStep
        case .lineDown: y += Self.lineStep
        case .pageUp: y -= page
        case .pageDown: y += page
        case .top: y = 0
        case .bottom: y = maxY
        }

        scrollView.contentView.scroll(
            to: NSPoint(x: visible.origin.x, y: min(max(y, 0), maxY)))
        // The clip view moved on its own, so the scroll view has to be told
        // before it will redraw or report the new position.
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// The help page's text. Read-only but selectable, which is the whole point
/// of it being an `NSTextView` at all: selection, ⌘A, ⌘C, and a string the
/// find bar can search all arrive through the responder chain, and none of
/// them reach the note underneath any more.
final class HelpDocumentTextView: NSTextView {
    /// Arrows and page keys scroll the page rather than walking an
    /// invisible insertion point down it. A selectable text view would
    /// otherwise move a caret nobody can see, scrolling only once it
    /// reached the edge of the viewport.
    override func keyDown(with event: NSEvent) {
        if let command = ScrollCommand(event: event), let scrollView = enclosingScrollView {
            command.apply(to: scrollView)
            return
        }
        super.keyDown(with: event)
    }
}

/// The section label that stays put while its section scrolls under it.
///
/// `NSTextView` has no way to pin a paragraph, so the pinned copy is a
/// separate view drawn over the top of the real one — opaque, so the row it
/// covers disappears cleanly rather than showing through.
private final class HelpStickyHeader: NSView {
    private let label = NSTextField(labelWithString: "")
    var fill: NSColor = .clear { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // `NSView.clipsToBounds` defaults to false, and AppKit will hand
        // `draw` a dirty rect larger than this view — so without this the
        // band's fill covers the entire page and everything under it reads
        // as washed out rather than hidden.
        clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: Metrics.chromeInsetX),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            label.topAnchor.constraint(
                equalTo: topAnchor, constant: Metrics.chromeInsetY),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        dirtyRect.intersection(bounds).fill()
    }

    func configure(title: String, style: HelpTextStyle) {
        label.attributedStringValue = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: style.sectionFont,
                .foregroundColor: style.sectionColor,
                .kern: style.sectionFont.pointSize * Metrics.helpSectionTracking,
            ])
    }

    /// Padding, label, padding — the same block the in-flow header occupies,
    /// so the pinned copy lands exactly on top of the real one at the moment
    /// it takes over.
    var contentHeight: CGFloat {
        Metrics.chromeInsetY * 2 + label.intrinsicContentSize.height
    }
}

/// Scroll view, text view, and the sticky header, assembled and kept in
/// step. Flipped so the header's y is measured from the top, which is the
/// direction it actually moves in.
final class HelpBodyView: NSView {
    let scrollView = NSScrollView()
    let textView: HelpDocumentTextView

    private let sticky = HelpStickyHeader()
    private var sectionTitles: [String] = []
    private var sectionTitleRanges: [NSRange] = []
    private var style: HelpTextStyle?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        // Assembled by hand rather than through `NSTextView(frame:)`: a
        // container added to a layout manager that isn't yet attached to
        // storage lays nothing out, and the order only holds when the pieces
        // are wired up explicitly.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        textView = HelpDocumentTextView(frame: .zero, textContainer: container)
        super.init(frame: frameRect)

        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.usesFindBar = false
        textView.textContainerInset = NSSize(
            width: Metrics.chromeInsetX, height: Metrics.chromeInsetY)

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .allowed

        addSubview(scrollView)
        addSubview(sticky)
        sticky.isHidden = true

        // Selector-based rather than block-based: the block API hands back
        // a token this view would have to store and tear down, and a token is
        // not something a nonisolated `deinit` may read off a main-actor type.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewBoundsChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @objc private func clipViewBoundsChanged() { updateSticky() }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        updateSticky()
    }

    /// Taking first responder is what redirects ⌘A, ⌘C, and the scroll keys
    /// away from the note behind the page — and this is the only hook that
    /// reliably fires with a window attached. `makeNSView` runs before the
    /// representable is mounted, so a `makeFirstResponder` scheduled from
    /// there finds `window` still nil and silently does nothing.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self.textView)
        }
    }

    /// Replaces the page. Destroys the selection, so callers only do this
    /// when the content or the styling has actually moved.
    ///
    /// The scroll offset is carried across: the one thing that re-renders
    /// mid-read is ⌘= / ⌘−, and being thrown back to the top of the page
    /// every time you change the text size is worse than the reflow it is
    /// there to show you.
    func setDocument(_ document: HelpDocument, style: HelpTextStyle, stickyFill: NSColor) {
        let offset = scrollView.contentView.bounds.origin.y
        let rendered = document.render(style: style)
        textView.textStorage?.setAttributedString(rendered.attributed)
        sectionTitles = document.sections.map(\.title)
        sectionTitleRanges = rendered.sectionTitleRanges
        self.style = style
        sticky.fill = stickyFill

        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let maxY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(offset, maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateSticky()
    }

    func setSelectionColor(_ color: NSColor) {
        textView.selectedTextAttributes = [.backgroundColor: color]
    }

    /// Paints the current find match, clearing any previous one. A storage
    /// attribute rather than a temporary layout one, for the same reason the
    /// notes view uses storage: a storage mutation always redraws.
    func applyFindHighlight(_ range: NSRange, color: NSColor) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.backgroundColor, range: full)
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        storage.addAttribute(.backgroundColor, value: color, range: range)
        textView.scrollRangeToVisible(range)
    }

    /// Which section is pinned, and how far the next one has pushed it.
    ///
    /// Positions come from the *used* rect of each title's first line
    /// fragment — the fragment rect itself carries the paragraph spacing
    /// above it, which would put every measurement a section-gap too high.
    private func updateSticky() {
        guard let style,
            let layoutManager = textView.layoutManager,
            let container = textView.textContainer,
            !sectionTitleRanges.isEmpty
        else {
            sticky.isHidden = true
            return
        }

        let scrollTop = scrollView.contentView.bounds.origin.y
        guard scrollTop > 0 else {
            sticky.isHidden = true
            return
        }

        layoutManager.ensureLayout(for: container)
        let blockTops = sectionTitleRanges.map { range -> CGFloat in
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
            let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            return used.minY + textView.textContainerInset.height - Metrics.chromeInsetY
        }

        guard let index = blockTops.lastIndex(where: { $0 <= scrollTop }) else {
            sticky.isHidden = true
            return
        }

        sticky.isHidden = false
        sticky.configure(title: sectionTitles[index], style: style)
        let height = sticky.contentHeight

        // The next section's block, once it is within a header's height of
        // the top, shoulders this one off the page rather than sliding under.
        var y: CGFloat = 0
        if index + 1 < blockTops.count {
            let next = blockTops[index + 1] - scrollTop
            if next < height { y = next - height }
        }
        sticky.frame = NSRect(x: 0, y: y, width: bounds.width, height: height)
    }
}

/// SwiftUI's handle on the page.
struct HelpBody: NSViewRepresentable {
    var document: HelpDocument
    var style: HelpTextStyle
    var stickyFill: NSColor
    var selectionColor: NSColor
    var findHighlightColor: NSColor
    var findHighlightToken: Int
    var findHighlightRange: NSRange
    var focusToken: Int

    func makeNSView(context: Context) -> HelpBodyView {
        let view = HelpBodyView()
        view.setDocument(document, style: style, stickyFill: stickyFill)
        view.setSelectionColor(selectionColor)
        context.coordinator.lastDocument = document
        context.coordinator.lastStyle = style
        context.coordinator.lastFindHighlightToken = findHighlightToken
        context.coordinator.lastFocusToken = focusToken
        // Focus on mount is `viewDidMoveToWindow`'s job — there is no window
        // to make a responder of yet. The token only handles re-focusing,
        // after the find bar has taken it away.
        return view
    }

    func updateNSView(_ view: HelpBodyView, context: Context) {
        if context.coordinator.lastDocument != document || context.coordinator.lastStyle != style {
            context.coordinator.lastDocument = document
            context.coordinator.lastStyle = style
            view.setDocument(document, style: style, stickyFill: stickyFill)
        }
        view.setSelectionColor(selectionColor)

        if context.coordinator.lastFindHighlightToken != findHighlightToken {
            context.coordinator.lastFindHighlightToken = findHighlightToken
            view.applyFindHighlight(findHighlightRange, color: findHighlightColor)
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            // Deferred for the same reason the find field's focus is: the
            // view is not in the window's responder chain during the update
            // pass that mounts it.
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view.textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var lastDocument: HelpDocument?
        var lastStyle: HelpTextStyle?
        var lastFindHighlightToken = 0
        var lastFocusToken = 0
    }
}
