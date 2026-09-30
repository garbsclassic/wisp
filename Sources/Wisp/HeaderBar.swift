import SwiftUI
import WispCore

/// Links to the note's headings or the help page's sections, with an ellipsis on overflow. The
/// scroll view does the clipping, since clipping by hand grows the panel to the row's width.
struct HeaderBar: View {
    let labels: [String]
    /// Takes the clicked label's index into `labels`.
    let onJump: (Int) -> Void
    /// Clear at the trailing edge for the save dot; the help page has none.
    var trailingInset: CGFloat = Metrics.headerTrailingInset
    @Environment(\.palette) private var palette

    /// Content wider than the slot puts up the ellipsis.
    @State private var contentWidth: CGFloat = 0
    @State private var slotWidth: CGFloat = 0

    private var isTruncated: Bool { contentWidth > slotWidth + 0.5 }

    var body: some View {
        if labels.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                headingRow
                    .measuringWidth(ContentWidthKey.self, into: $contentWidth)
                    .padding(.vertical, Metrics.chromeInsetY)
            }
            .measuringWidth(SlotWidthKey.self, into: $slotWidth)
            .overlay(alignment: .trailing) {
                if isTruncated {
                    // Opaque, to mask the half-drawn heading under it.
                    Text("…")
                        .padding(.leading, 6)
                        .background(Color(palette.chrome))
                }
            }
            .padding(.leading, Metrics.chromeInsetX)
            .padding(.trailing, trailingInset)
            .chromeBar()
        }
    }

    private var headingRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                if index > 0 {
                    Text("·")
                        .foregroundStyle(Color(palette.rule))
                        .padding(.horizontal, 10)
                }
                Button(action: { onJump(index) }) {
                    // Accent on the headings, not the row, so the inherited `…` isn't a link.
                    Text(label)
                        .foregroundStyle(Color(palette.accent))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Jump to “\(label)”")
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
            .foregroundStyle(Color(palette.muted))
            .background(Color(palette.chrome))
    }
}

protocol WidthPreference: PreferenceKey where Value == CGFloat {}

extension WidthPreference {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Two keys, since preferences propagate up: one key read at both levels makes the slot report
/// the content's width, and the ellipsis never shows.
private struct ContentWidthKey: WidthPreference {}
private struct SlotWidthKey: WidthPreference {}

extension View {
    /// In a `.background`, since a bare `GeometryReader` would stretch the bar to fill the panel.
    fileprivate func measuringWidth<K: WidthPreference>(
        _ key: K.Type, into width: Binding<CGFloat>
    ) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: key, value: proxy.size.width)
            }
        )
        .onPreferenceChange(key) { width.wrappedValue = $0 }
    }
}
