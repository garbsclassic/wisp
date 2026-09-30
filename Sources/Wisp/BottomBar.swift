import SwiftUI
import WispCore

/// What the footer's leading label reads.
enum FooterReadout {
    case position(CaretPosition, words: Int)
    /// Nil before the note has ever been written.
    case modified(Date?)
}

struct FooterBar: View {
    let readout: FooterReadout
    let onToggleReadout: () -> Void
    let fontScale: Double
    /// The percentage is a reset button only when ⌘0 would change something.
    let isDefaultFontScale: Bool
    let onDecreaseFontScale: () -> Void
    let onIncreaseFontScale: () -> Void
    let onResetFontScale: () -> Void
    let themeSetting: ThemeSetting
    let isSourceView: Bool
    let isSpellcheckOn: Bool
    /// Tooltips name their chord from here, so a rebind shows up.
    let keymap: Keymap
    let onCycleTheme: () -> Void
    let onToggleSourceView: () -> Void
    let onToggleSpellcheck: () -> Void
    let onHelpClick: () -> Void
    /// A bad config key, an unparseable chord, or a missing font.
    let warning: String?
    let onDismiss: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 16) {
            // One leading label, which the spacing and the warning's truncation key off.
            HoverTextButton(help: readoutHelp, action: onToggleReadout) {
                readoutLabel
            }
            if let warning {
                // One line; the full text is a hover away.
                Text(warning)
                    .foregroundStyle(Color(palette.danger))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(warning)
            }
            Spacer()
            zoom
            // Underlined when on, the squiggle it turns on.
            glyphButton(
                isSpellcheckOn ? "textformat.abc.dottedunderline" : "textformat.abc",
                help: hint(
                    isSpellcheckOn ? "Stop checking spelling" : "Check spelling",
                    .spellcheck),
                action: onToggleSpellcheck)
            // Filled when on, like the theme button's glyph.
            glyphButton(
                isSourceView ? "doc.plaintext.fill" : "doc.plaintext",
                help: hint(isSourceView ? "Rich text view" : "Source view", .sourceView),
                action: onToggleSourceView)
            glyphButton(
                themeIconName, help: hint(themeButtonHelp, .cycleTheme), action: onCycleTheme)
            glyphButton(
                "questionmark", help: hint("Help", .help),
                action: onHelpClick)
            glyphButton("xmark", help: "Close   ⎋", action: onDismiss)
        }
        .padding(.horizontal, Metrics.chromeInsetX)
        .padding(.vertical, Metrics.chromeInsetY)
        .frame(maxWidth: .infinity)
        .chromeBar()
    }

    /// `−  100%  +` as one control; the percentage resets.
    private var zoom: some View {
        HStack(spacing: 0) {
            glyphButton(
                "minus", help: hint("Smaller font", .decreaseFontScale),
                action: onDecreaseFontScale)
            HoverTextButton(
                help: hint("Reset font size", .resetFontScale), isEnabled: !isDefaultFontScale,
                action: onResetFontScale
            ) {
                // The widest value, hidden, so the row doesn't shift as digits drop.
                ZStack {
                    Text("888%").hidden()
                    Text("\(Int((fontScale * 100).rounded()))%")
                }
                .font(Typography.ui(Metrics.chromeSize, tabularDigits: true))
            }
            glyphButton(
                "plus", help: hint("Larger font", .increaseFontScale),
                action: onIncreaseFontScale)
        }
    }

    @ViewBuilder
    private var readoutLabel: some View {
        switch readout {
        case .position(let caret, let words):
            Text("\(caret.line):\(caret.column) · \(words == 1 ? "1 word" : "\(words) words")")
                .font(Typography.ui(Metrics.chromeSize, tabularDigits: true))
        case .modified(let date):
            if let date {
                // Its own clock, so `just now` moves on without a keystroke.
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text("last modified: \(RelativeTime.coarse(date, now: context.date))")
                }
            } else {
                Text("not saved yet")
            }
        }
    }

    private var readoutHelp: String {
        switch readout {
        case .position: return "Show when the note was last saved"
        case .modified: return "Show line, column, and word count"
        }
    }

    /// A tooltip and its first chord, spaced rather than parenthesised.
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
}

/// A footer control that fades from `muted` to `text` on hover. Disabled, it's plain text.
struct HoverTextButton<Label: View>: View {
    let help: String
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    var body: some View {
        Group {
            if isEnabled {
                Button(action: action) { label().contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(isHovered ? palette.text : palette.muted))
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                    .onHover { isHovered = $0 }
                    .pointerCursor()
                    .help(help)
            } else {
                label()
            }
        }
        // Clicking reset disables it under the pointer, where no hover exit arrives.
        .onChange(of: isEnabled) { enabled in
            guard !enabled, isHovered else { return }
            isHovered = false
            NSCursor.arrow.set()
        }
    }
}

/// An SF Symbol in a fixed box, so the footer's spacing doesn't rag.
struct GlyphButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        HoverTextButton(help: help, action: action) {
            Image(systemName: symbol)
                .font(Typography.ui(Metrics.chromeSize))
                .frame(width: Metrics.footerButtonWidth, height: Metrics.footerButtonHeight)
        }
    }
}
