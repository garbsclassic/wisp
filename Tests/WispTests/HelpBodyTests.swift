import AppKit
import Testing
import WispCore

@testable import Wisp

@Suite("HelpBody")
@MainActor
struct HelpBodyTests {
    @Test("Initial active match is painted, including a zero token")
    func initialHighlight() throws {
        let body = makeBody()
        let view = body.makeView(coordinator: body.makeCoordinator())
        #expect(highlight(in: view, at: body.findHighlightRange.location) == .yellow)
    }

    @Test("Theme and font changes retain the active match and scroll offset")
    func restyleRetainsHighlight() throws {
        var body = makeBody()
        let coordinator = body.makeCoordinator()
        let view = body.makeView(coordinator: coordinator)
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 160)
        view.layoutSubtreeIfNeeded()
        view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 100))
        let offset = view.scrollView.contentView.bounds.origin.y
        try #require(offset > 0)

        body.style.keyColor = .white
        body.style.detailColor = .lightGray
        body.findHighlightColor = .orange
        body.updateView(view, coordinator: coordinator)
        #expect(highlight(in: view, at: body.findHighlightRange.location) == .orange)
        #expect(view.scrollView.contentView.bounds.origin.y == offset)

        body.style.rowFont = .systemFont(ofSize: 20)
        body.updateView(view, coordinator: coordinator)
        #expect(highlight(in: view, at: body.findHighlightRange.location) == .orange)
        #expect(view.scrollView.contentView.bounds.origin.y == offset)
    }

    @Test("Replacing help content repaints the current match without a new find token")
    func replacingDocumentRetainsHighlight() {
        var body = makeBody()
        let coordinator = body.makeCoordinator()
        let view = body.makeView(coordinator: coordinator)
        body.document = HelpDocument(
            sections: [.init(id: "replaced", "Replaced", [.init("key", "detail")])])
        body.updateView(view, coordinator: coordinator)
        #expect(highlight(in: view, at: body.findHighlightRange.location) == .yellow)
    }

    private func makeBody() -> HelpBody {
        HelpBody(
            document: HelpDocument.make(keymap: WispConfig().keymap),
            style: HelpTextStyle(
                rowFont: .systemFont(ofSize: 14), sectionFont: .systemFont(ofSize: 14),
                keyColor: .black, detailColor: .gray, sectionColor: .blue),
            stickyFill: .white, selectionColor: .cyan, findHighlightColor: .yellow,
            findHighlightToken: 0, findHighlightRange: NSRange(location: 0, length: 4),
            focusToken: 0, jumpSection: 0, jumpToken: 0)
    }

    private func highlight(in view: HelpBodyView, at location: Int) -> NSColor? {
        view.textView.textStorage?.attribute(
            .backgroundColor, at: location, effectiveRange: nil) as? NSColor
    }
}
