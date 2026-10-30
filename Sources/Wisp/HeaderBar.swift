import SwiftUI
import WispCore

/// Links to the note's headings or the help page's sections, with an ellipsis on overflow. The
/// scroll view does the clipping, since clipping by hand grows the panel to the row's width.
struct HeaderBar<Item: Identifiable>: View {
    let items: [Item]
    let title: KeyPath<Item, String>
    let onJump: (Item) -> Void
    /// Clear at the trailing edge for the save dot; the help page has none.
    var trailingInset: CGFloat = Metrics.headerTrailingInset
    @Environment(\.palette) private var palette

    @State private var isTruncated = false

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal) {
                headingRow
                    .padding(.vertical, Metrics.chromeInsetY)
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.width > geometry.containerSize.width + 0.5
            } action: { _, overflows in
                isTruncated = overflows
            }
            .overlay(alignment: .trailing) {
                if isTruncated {
                    // Opaque, to mask the half-drawn heading under it.
                    Text("…")
                        .padding(.leading, 6)
                        .background(Color(nsColor: palette.chrome))
                }
            }
            .padding(.leading, Metrics.chromeInsetX)
            .padding(.trailing, trailingInset)
            .chromeBar()
        }
    }

    private var headingRow: some View {
        LazyHStack(spacing: 0) {
            ForEach(items) { item in
                HStack(spacing: 0) {
                    if item.id != items.first?.id {
                        Text("·")
                            .foregroundStyle(Color(nsColor: palette.rule))
                            .padding(.horizontal, 10)
                            .accessibilityHidden(true)
                    }
                    Button(action: { onJump(item) }) {
                        // Accent on headings, so the inherited `…` isn't a link.
                        Text(item[keyPath: title])
                            .foregroundStyle(Color(nsColor: palette.accent))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .help("Jump to “\(item[keyPath: title])”")
                }
            }
        }
    }
}

extension View {
    /// The chrome face in `muted` on the `chrome` fill, shared by every edge bar.
    func chromeBar() -> some View { modifier(ChromeBar()) }
}

private struct ChromeBar: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .font(Typography.ui(Metrics.chromeSize))
            .foregroundStyle(Color(nsColor: palette.muted))
            .background(Color(nsColor: palette.chrome))
    }
}
