import SwiftUI

struct BottomBar: View {
    let wordCount: Int
    let fontSize: FontSize
    let onCycleFontSize: () -> Void
    let themePreference: ThemePreference
    let onCycleTheme: () -> Void
    let updateState: UpdateState
    let onUpdateClick: () -> Void
    let onHelpClick: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 16) {
            Text(wordsLabel)
                .monospacedDigit()
            Spacer()
            updateIndicator
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

    @ViewBuilder
    private var updateIndicator: some View {
        switch updateState {
        case .idle:
            EmptyView()
        case .available(let version, _):
            Button(action: onUpdateClick) {
                Text("↑ v\(version)")
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("New version available")
        case .downloading(let version):
            Text("↓ downloading v\(version)…")
        case .pending(let version):
            Button(action: onUpdateClick) {
                Text("↻ v\(version) ready — restart to apply")
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Restart Wisp to apply the update")
        }
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
