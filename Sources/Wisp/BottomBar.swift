import SwiftUI
import WispCore

struct BottomBar: View {
    let wordCount: Int
    let fontSize: FontSize
    let onCycleFontSize: () -> Void
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
            Button(action: onHelpClick) {
                Image(systemName: "questionmark")
                    .font(Typography.ui(11))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Keyboard shortcuts and formatting")
            Button(action: onCycleTheme) {
                Image(systemName: themeIconName)
                    .font(Typography.ui(11))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help(themeButtonHelp)
            Button(action: onCycleFontSize) {
                Text("Aa")
                    .font(Typography.ui(indicatorSize, weight: .medium))
                    .frame(width: 30, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Cycle text size (⌘1 / ⌘2 / ⌘3)")
            Text("esc to close")
        }
        .font(Typography.ui(11))
        .foregroundStyle(Color(palette.muted))
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
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

    private var indicatorSize: CGFloat {
        switch fontSize {
        case .small: return 9
        case .medium: return 11
        case .large: return 13
        }
    }

    private var wordsLabel: String {
        wordCount == 1 ? "1 word" : "\(wordCount) words"
    }
}
