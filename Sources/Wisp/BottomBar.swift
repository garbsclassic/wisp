import SwiftUI
import WispCore

struct BottomBar: View {
    let wordCount: Int
    let onDecreaseFontScale: () -> Void
    let onIncreaseFontScale: () -> Void
    let themePreference: ThemePreference
    /// Tooltips name their own chord, so a rebind shows up here without
    /// anyone remembering to edit a string.
    let keymap: Keymap
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
                "questionmark", help: hint("Keyboard shortcuts and formatting", .help),
                action: onHelpClick)
            glyphButton(
                themeIconName, help: hint(themeButtonHelp, .toggleTheme), action: onCycleTheme)
            // Two buttons rather than the old "Aa" cycle: the scale is
            // continuous now, and a single button can't express a range
            // you can move in both directions.
            glyphButton(
                "textformat.size.smaller", help: hint("Smaller text", .decreaseFontScale),
                action: onDecreaseFontScale)
            glyphButton(
                "textformat.size.larger", help: hint("Larger text", .increaseFontScale),
                action: onIncreaseFontScale)
            Text("esc to dismiss")
        }
        .font(Typography.ui(Metrics.chromeSize))
        .foregroundStyle(Color(palette.muted))
        .padding(.horizontal, Metrics.chromeInsetX)
        .padding(.vertical, Metrics.chromeInsetY)
        .frame(maxWidth: .infinity)
        .background(Color(palette.chrome))
    }

    /// A tooltip and the chord that does the same thing, separated by
    /// spaces rather than wrapped in parentheses — the chord is a second
    /// label, not an aside. One chord only: an alias list belongs on the
    /// help page, not in a hint. AppKit renders tooltips itself, so this
    /// cannot be two colors however much the chord wants to be muted.
    private func hint(_ label: String, _ action: KeymapAction) -> String {
        "\(label)   \(keymap.primaryDisplay(action))"
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
