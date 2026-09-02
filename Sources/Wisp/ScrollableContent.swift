import AppKit
import SwiftUI

/// One scroll gesture, from the wheel or from a key.
enum ScrollCommand {
    case lineUp, lineDown
    case pageUp, pageDown
    case top, bottom
}

/// Hosts SwiftUI content inside a real `NSScrollView`.
///
/// SwiftUI's own `ScrollView` would give the wheel for free, but nothing
/// else: it has no scroll-position binding before macOS 14, and the help
/// page has no focusable content for the arrow keys to act on. An
/// `NSScrollView` scrolls with the wheel like any other document *and*
/// exposes a clip view that a key monitor can drive directly.
struct ScrollableContent<Content: View>: NSViewRepresentable {
    /// Bumped by the owner to request `command`. A token rather than a
    /// direct call because the view is only reachable from `updateNSView`.
    var commandToken: Int
    var command: ScrollCommand
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        // Scrollers are hidden, so leave the elastic bounce on — it is the
        // only remaining feedback that you have reached an end.
        scrollView.verticalScrollElasticity = .allowed

        let hosting = NSHostingView(rootView: content())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hosting

        // Width is pinned to the clip view and height is left to the
        // content's intrinsic size — the one arrangement that makes a
        // hosting view scroll rather than squash. This is the case the
        // usual `sizingOptions = []` advice does *not* apply to: here the
        // self-sizing height is exactly what is wanted.
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        ])

        context.coordinator.lastToken = commandToken
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        (scrollView.documentView as? NSHostingView<Content>)?.rootView = content()
        guard context.coordinator.lastToken != commandToken else { return }
        context.coordinator.lastToken = commandToken
        Self.apply(command, to: scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var lastToken: Int = 0
    }

    /// How far an arrow key moves. A line of help text plus its spacing —
    /// arrows are for nudging the last row into view, not for travelling.
    private static var lineStep: CGFloat { 28 }
    /// Kept on screen across a page turn, so there is an overlap to read
    /// back into rather than a jump cut.
    private static var pageOverlap: CGFloat { 40 }

    private static func apply(_ command: ScrollCommand, to scrollView: NSScrollView) {
        guard let document = scrollView.documentView else { return }
        let visible = scrollView.contentView.bounds
        // Nothing to scroll — a short help page on a tall panel.
        let maxY = max(0, document.frame.height - visible.height)
        guard maxY > 0 else { return }

        let page = max(visible.height - pageOverlap, visible.height / 2)
        var y = visible.origin.y
        switch command {
        case .lineUp: y -= lineStep
        case .lineDown: y += lineStep
        case .pageUp: y -= page
        case .pageDown: y += page
        case .top: y = 0
        case .bottom: y = maxY
        }

        let clamped = min(max(y, 0), maxY)
        scrollView.contentView.scroll(to: NSPoint(x: visible.origin.x, y: clamped))
        // The clip view moved on its own, so the scroll view has to be told
        // before it will redraw or report the new position.
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
