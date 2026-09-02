import SwiftUI
import WispCore

struct BottomBar: View {
    let wordCount: Int
    let onDecreaseFontScale: () -> Void
    let onIncreaseFontScale: () -> Void
    let themePreference: ThemePreference
    let onCycleTheme: () -> Void
    let onHelpClick: () -> Void
    /// A bad config key, an unparseable chord, or a font that isn't
    /// installed. Nil most of the time.
    let warning: String?
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 16) {
            Text(wordsLabel)
                .monospacedDigit()
            if let warning {
                // Truncated rather than wrapped: the footer is one line
                // tall, and the full text is a hover away.
                Text(warning)
                    .foregroundStyle(Color(palette.danger))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(warning)
            }
            Spacer()
            glyphButton(
                "questionmark", help: "Keyboard shortcuts and formatting (⌘/)",
                action: onHelpClick)
            glyphButton(themeIconName, help: themeButtonHelp, action: onCycleTheme)
            // Two buttons rather than the old "Aa" cycle: the scale is
            // continuous now, and a single button can't express a range
            // you can move in both directions.
            glyphButton(
                "textformat.size.smaller", help: "Smaller text (⌘-)",
                action: onDecreaseFontScale)
            glyphButton(
                "textformat.size.larger", help: "Larger text (⌘=)",
                action: onIncreaseFontScale)
            Text("esc to close")
        }
        .font(Typography.ui(Metrics.chromeSize))
        .foregroundStyle(Color(palette.muted))
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    /// Footer buttons share one shape: an SF Symbol in a fixed box, so
    /// the row's spacing doesn't rag as the icons change.
    @ViewBuilder
    private func glyphButton(
        _ symbol: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typography.ui(Metrics.chromeSize))
                .frame(width: Metrics.footerButtonWidth, height: Metrics.footerButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(help)
    }

    private var themeIconName: String {
        switch themePreference {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }

    private var themeButtonHelp: String {
        switch themePreference.next {
        case .light: return "Switch to light theme"
        case .dark: return "Switch to dark theme"
        case .system: return "Follow system appearance"
        }
    }

    private var wordsLabel: String {
        wordCount == 1 ? "1 word" : "\(wordCount) words"
    }
}
