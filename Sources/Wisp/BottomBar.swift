import SwiftUI
import WispCore

struct FooterBar: View {
    let caret: CaretPosition
    let wordCount: Int
    let onDecreaseFontScale: () -> Void
    let onIncreaseFontScale: () -> Void
    let themeSetting: ThemeSetting
    let isSourceView: Bool
    /// Tooltips name their own chord, so a rebind shows up here without
    /// anyone remembering to edit a string.
    let keymap: Keymap
    let onCycleTheme: () -> Void
    let onToggleSourceView: () -> Void
    let onHelpClick: () -> Void
    /// A bad config key, an unparseable chord, or a font that isn't
    /// installed. Nil most of the time.
    let warning: String?
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 16) {
            // One label, not two: the row's spacing and the warning's
            // truncation both key off a single leading text.
            Text("\(caret.line):\(caret.column) · \(wordsLabel)")
                .font(Typography.ui(Metrics.chromeSize, tabularDigits: true))
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
                "questionmark", help: hint("Help", .help),
                action: onHelpClick)
            // Filled when on, the way the theme button swaps its glyph:
            // a footer control that says which way it is currently set.
            glyphButton(
                isSourceView ? "doc.plaintext.fill" : "doc.plaintext",
                help: hint(isSourceView ? "Rich text view" : "Source view", .sourceView),
                action: onToggleSourceView)
            glyphButton(
                themeIconName, help: hint(themeButtonHelp, .cycleTheme), action: onCycleTheme)
            // Two buttons rather than the old "Aa" cycle: the scale is
            // continuous now, and a single button can't express a range
            // you can move in both directions.
            glyphButton(
                "textformat.size.smaller", help: hint("Smaller font", .decreaseFontScale),
                action: onDecreaseFontScale)
            glyphButton(
                "textformat.size.larger", help: hint("Larger font", .increaseFontScale),
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

    private func glyphButton(
        _ symbol: String, help: String, action: @escaping () -> Void
    ) -> some View {
        GlyphButton(symbol: symbol, help: help, action: action)
    }

    private var themeIconName: String {
        switch themeSetting {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }

    private var themeButtonHelp: String {
        switch themeSetting.next {
        case .light: return "Light theme"
        case .dark: return "Dark theme"
        case .system: return "System theme"
        }
    }

    private var wordsLabel: String {
        wordCount == 1 ? "1 word" : "\(wordCount) words"
    }
}

/// Footer buttons share one shape: an SF Symbol in a fixed box, so the
/// row's spacing doesn't rag as the icons change. Hovering lifts the glyph
/// from `muted` to `text` — a fade rather than a snap, since the footer is
/// the quietest part of the panel and a hard flip there reads as a flicker.
private struct GlyphButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typography.ui(Metrics.chromeSize))
                .frame(width: Metrics.footerButtonWidth, height: Metrics.footerButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(isHovered ? palette.text : palette.muted))
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .help(help)
    }
}
