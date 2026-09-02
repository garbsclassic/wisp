import SwiftUI
import WispCore

/// The heading strip along the top of the panel — every `#` heading in the
/// note, click to jump.
///
/// Scrolls horizontally, and says so: once the list is wider than the bar,
/// an ellipsis appears at the trailing edge. The scroll view is doing the
/// clipping, which is load-bearing rather than incidental — laying the row
/// out at its natural width and clipping it by hand propagates that width
/// up through `NSHostingView` and the panel grows to fit it. Measured at
/// 3952pt across on the first attempt.
struct HeaderBar: View {
    let headings: [Heading]
    let onJump: (Heading) -> Void
    @Environment(\.palette) private var palette

    /// The row's full width, and the bar it has to fit in. The first
    /// overflowing the second is what puts the ellipsis up.
    @State private var contentWidth: CGFloat = 0
    @State private var slotWidth: CGFloat = 0

    private var isTruncated: Bool { contentWidth > slotWidth + 0.5 }

    var body: some View {
        if headings.isEmpty {
            // Nothing to show — keep the slot empty so the panel just looks
            // like before the headings feature existed.
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
                    // Opaque, so it masks the half-drawn heading it lands
                    // on rather than sitting on top of it.
                    Text("…")
                        .padding(.leading, 6)
                        .background(Color(palette.chrome))
                }
            }
            .padding(.leading, Metrics.chromeInsetX)
            // Stops short of the panel edge so a long list doesn't run
            // under the save indicator.
            .padding(.trailing, Metrics.headerTrailingInset)
            .font(Typography.ui(Metrics.chromeSize))
            .foregroundStyle(Color(palette.muted))
            .background(Color(palette.chrome))
        }
    }

    private var headingRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(headings.enumerated()), id: \.element.id) { index, heading in
                if index > 0 {
                    Text("·")
                        .foregroundStyle(Color(palette.rule))
                        .padding(.horizontal, 10)
                }
                Button(action: { onJump(heading) }) {
                    Text(heading.name)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Jump to “\(heading.name)”")
            }
        }
    }
}

protocol WidthPreference: PreferenceKey where Value == CGFloat {}

extension WidthPreference {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The heading row's own width, and the bar it has to fit in.
///
/// Two keys, not one used twice. Preferences propagate *up* the tree, so a
/// single key read at both levels means the outer reader also sees the
/// inner value — and with a `max` reduction the slot silently reports the
/// content's width, making `isTruncated` permanently false.
private struct ContentWidthKey: WidthPreference {}
private struct SlotWidthKey: WidthPreference {}

extension View {
    /// Reports this view's laid-out width into `width`, under `key`.
    ///
    /// In a `.background`, so the reader takes its size from the view
    /// rather than imposing one — a bare `GeometryReader` is greedy in both
    /// axes and would stretch the bar to fill the panel.
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
