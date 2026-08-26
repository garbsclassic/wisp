import SwiftUI

/// First-run welcome overlay. Shows three essential tips and a single
/// "Got it" affordance. Dismisses on click anywhere or Esc.
struct TourOverlay: View {
    @Environment(\.palette) private var palette
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(palette.panel).opacity(0.97))
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome to Wisp")
                    .font(Typography.ui(20, weight: .medium))
                    .foregroundStyle(Color(palette.text))
                    .padding(.bottom, 4)

                tip("⌥Space", "summon Wisp from anywhere on macOS")
                tip("Menu bar menu", "for shortcut, storage, and about")
                tip("Click the ? in the footer", "for shortcuts and formatting")

                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("Got it")
                            .font(Typography.ui(12, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(palette.border), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 36)
            .frame(maxWidth: 460, alignment: .leading)
        }
    }

    @ViewBuilder
    private func tip(_ key: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(Typography.ui(12, weight: .medium))
                .foregroundStyle(Color(palette.muted))
                .frame(minWidth: 160, alignment: .leading)
            Text(description)
                .font(Typography.ui(13))
                .foregroundStyle(Color(palette.text))
        }
    }
}
