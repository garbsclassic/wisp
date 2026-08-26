import SwiftUI
import WispCore

struct HeaderBar: View {
    let headings: [Heading]
    let onJump: (Heading) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        if headings.isEmpty {
            // Nothing to show — keep the slot empty so the panel just looks
            // like before the headings feature existed.
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
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
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
            }
            .font(Typography.ui(11))
            .foregroundStyle(Color(palette.muted))
        }
    }
}
