import AppKit
import SwiftUI
import WispCore

/// The keyboard reference, as a page over the note: pinned header and footer around an
/// `NSTextView` body (see `HelpBody`).
struct HelpOverlay: View {
    @Environment(\.palette) private var palette
    let document: HelpDocument
    let findHighlightToken: Int
    let findHighlightRange: NSRange
    let focusToken: Int
    let onClose: () -> Void

    /// The header link last clicked; the token lets a second click on it scroll again.
    @State private var jumpSection = 0
    @State private var jumpToken = 0

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                labels: document.sections.map(\.title),
                onJump: { index in
                    jumpSection = index
                    jumpToken &+= 1
                },
                trailingInset: Metrics.chromeInsetX
            )
            .overlay(alignment: .bottom) { hairline }

            HelpBody(
                document: document,
                style: style,
                stickyFill: stickyFill,
                selectionColor: palette.selection,
                findHighlightColor: palette.findHighlight,
                findHighlightToken: findHighlightToken,
                findHighlightRange: findHighlightRange,
                focusToken: focusToken,
                jumpSection: jumpSection,
                jumpToken: jumpToken
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            chrome {
                Text("scroll with ↑ · ↓ · mouse wheel")
                Spacer()
                GlyphButton(symbol: "xmark", help: "Close   ⎋", action: onClose)
            }
            .overlay(alignment: .top) { hairline }
        }
        // Near-opaque, so the note shows faintly behind a modal page.
        .background(Color(palette.panel).opacity(0.97))
    }

    /// On the app's own insets, so the bar doesn't shift as the page crossfades in.
    @ViewBuilder
    private func chrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .lineLimit(1)
        .padding(.horizontal, Metrics.chromeInsetX)
        .padding(.vertical, Metrics.chromeInsetY)
        // Leading: a full-width row with no spacer centres itself otherwise.
        .frame(maxWidth: .infinity, alignment: .leading)
        .chromeBar()
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
