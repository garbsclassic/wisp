import AppKit
import Carbon.HIToolbox
import SwiftUI
import WispCore

/// One scroll gesture, from a key. The wheel is the scroll view's own.
enum ScrollCommand {
    case lineUp, lineDown
    case pageUp, pageDown
    case top, bottom

    /// Nil hands the event on.
    init?(event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        // ⌘↑ / ⌘↓ jump to the ends, as Home and End do.
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

    /// About one row, for nudging rather than travelling.
    private static let lineStep: CGFloat = 28
    /// Kept on screen across a page turn, to read back into.
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
        // The clip view moved directly, so the scroll view must be told.
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// Read-only but selectable, so selection, ⌘A, ⌘C, and find go to the page, not the note behind.
final class HelpDocumentTextView: NSTextView {
    /// Scroll keys scroll the page rather than walking an invisible caret down it.
    override func keyDown(with event: NSEvent) {
        if let command = ScrollCommand(event: event), let scrollView = enclosingScrollView {
            command.apply(to: scrollView)
            return
        }
        super.keyDown(with: event)
    }
}

/// The section label pinned while its section scrolls: an opaque copy over the real one, since
/// `NSTextView` can't pin a paragraph.
private final class HelpStickyHeader: NSView {
    private let label = NSTextField(labelWithString: "")
    var fill: NSColor = .clear { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // AppKit can hand `draw` a dirty rect larger than the view, which would wash out the page.
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
            string: title.uppercased(), attributes: style.sectionTitleAttributes)
    }

    /// The same block the in-flow title occupies, so the copy lands exactly on it.
    var contentHeight: CGFloat {
        Metrics.chromeInsetY * 2 + label.intrinsicContentSize.height
    }
}

/// Scroll view, text view, and sticky header. Flipped, so the header's y runs from the top.
final class HelpBodyView: NSView {
    let scrollView = NSScrollView()
    let textView: HelpDocumentTextView

    private let sticky = HelpStickyHeader()
    private var sectionTitles: [String] = []
    private var sectionTitleRanges: [NSRange] = []
    private var style: HelpTextStyle?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        // Wired by hand: a container on a layout manager without storage lays out nothing.
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

        // Selector-based, since a block observer's token can't be read in a nonisolated `deinit`.
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

    /// First responder takes ⌘A, ⌘C, and the scroll keys from the note. Done here because
    /// `makeNSView` runs before there is a window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self.textView)
        }
    }

    /// Replaces the page, which clears the selection. Keeps the scroll offset, so ⌘= / ⌘− don't
    /// throw you back to the top.
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

    /// Paints the current find match as a storage attribute, which always redraws.
    func applyFindHighlight(_ range: NSRange, color: NSColor) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.backgroundColor, range: full)
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        storage.addAttribute(.backgroundColor, value: color, range: range)
        textView.scrollRangeToVisible(range)
    }

    /// Puts the section's label at the top edge, where the sticky copy takes over.
    func scrollToSection(_ index: Int) {
        let tops = sectionBlockTops()
        guard tops.indices.contains(index) else { return }
        let maxY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(tops[index], 0), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        // The link was a button; keep the scroll keys on the page.
        window?.makeFirstResponder(textView)
    }

    /// Where each section's label block starts. From the used rect, since the fragment rect
    /// includes the paragraph spacing above.
    private func sectionBlockTops() -> [CGFloat] {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer
        else { return [] }
        layoutManager.ensureLayout(for: container)
        return sectionTitleRanges.map { range in
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
            let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            return used.minY + textView.textContainerInset.height - Metrics.chromeInsetY
        }
    }

    /// Which section is pinned, and how far the next one has pushed it.
    private func updateSticky() {
        guard let style, !sectionTitleRanges.isEmpty else {
            sticky.isHidden = true
            return
        }

        let scrollTop = scrollView.contentView.bounds.origin.y
        guard scrollTop > 0 else {
            sticky.isHidden = true
            return
        }

        let blockTops = sectionBlockTops()
        guard let index = blockTops.lastIndex(where: { $0 <= scrollTop }) else {
            sticky.isHidden = true
            return
        }

        sticky.isHidden = false
        sticky.configure(title: sectionTitles[index], style: style)
        let height = sticky.contentHeight

        // The next section shoulders this one off rather than sliding under it.
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
    var jumpSection: Int
    var jumpToken: Int

    func makeNSView(context: Context) -> HelpBodyView {
        let view = HelpBodyView()
        view.setDocument(document, style: style, stickyFill: stickyFill)
        view.setSelectionColor(selectionColor)
        context.coordinator.lastDocument = document
        context.coordinator.lastStyle = style
        context.coordinator.lastFindHighlightToken = findHighlightToken
        context.coordinator.lastFocusToken = focusToken
        context.coordinator.lastJumpToken = jumpToken
        // Initial focus is `viewDidMoveToWindow`'s; the token re-focuses after find.
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
            // Deferred, as the find field's focus is: the view isn't in the responder chain yet.
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view.textView)
            }
        }
        if context.coordinator.lastJumpToken != jumpToken {
            context.coordinator.lastJumpToken = jumpToken
            view.scrollToSection(jumpSection)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var lastDocument: HelpDocument?
        var lastStyle: HelpTextStyle?
        var lastFindHighlightToken = 0
        var lastFocusToken = 0
        var lastJumpToken = 0
    }
}
