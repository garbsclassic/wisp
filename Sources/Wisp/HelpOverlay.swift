import AppKit
import SwiftUI
import WispCore

/// The keyboard reference, as a full-bleed page over the note.
///
/// Three regions, per the handoff in `notes/designs/help/`: a pinned header,
/// a scrolling body, and a pinned footer. The body is an `NSTextView` rather
/// than a stack of `Text` views — see `HelpBody` for why.
struct HelpOverlay: View {
    @Environment(\.palette) private var palette
    /// The live keymap, not hardcoded glyphs — every chord on this page is
    /// configurable, so a constant would be wrong for anyone who changed
    /// one. `HelpDocument.make` reads them on the model's behalf.
    let document: HelpDocument
    let findHighlightToken: Int
    let findHighlightRange: NSRange
    let focusToken: Int

    var body: some View {
        VStack(spacing: 0) {
            chrome { Text("help") }
            .overlay(alignment: .bottom) { hairline }

            HelpBody(
                document: document,
                style: style,
                stickyFill: stickyFill,
                selectionColor: palette.selection,
                findHighlightColor: palette.findHighlight,
                findHighlightToken: findHighlightToken,
                findHighlightRange: findHighlightRange,
                focusToken: focusToken
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            chrome {
                Text("scroll with ↑ · ↓ · mouse wheel")
                Spacer()
                Text("esc to dismiss")
            }
            .overlay(alignment: .top) { hairline }
        }
        // Near-opaque rather than opaque: the note stays faintly visible
        // behind, which signals "modal mode" without competing for
        // attention.
        .background(Color(palette.panel).opacity(0.97))
    }

    /// Header and footer share one shape, and take the same insets as the
    /// app's own bars — the page crossfades onto them, and a bar that shifts
    /// by 8pt on the way in is more noticeable than one drawn 8pt off the
    /// mockup.
    @ViewBuilder
    private func chrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .font(Typography.ui(Metrics.chromeSize))
        .foregroundStyle(Color(palette.muted))
        .lineLimit(1)
        .padding(.horizontal, Metrics.chromeInsetX)
        .padding(.vertical, Metrics.chromeInsetY)
        // Leading, like the heading strip this bar replaces — a lone label
        // in a full-width row centres itself otherwise.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(palette.chrome))
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color(palette.border))
            .frame(height: 1)
    }

    private var style: HelpTextStyle {
        HelpTextStyle(
            rowFont: Typography.uiFont(Metrics.bodySize),
            sectionFont: Typography.uiFont(Metrics.bodySize * Metrics.helpSectionLabelRatio),
            keyColor: palette.text,
            detailColor: palette.muted,
            sectionColor: palette.accent
        )
    }

    /// The pinned section label has to hide the rows sliding under it, so it
    /// paints a shade *more* opaque than the page it sits on.
    private var stickyFill: NSColor {
        palette.panel.withAlphaComponent(0.98)
    }
}
