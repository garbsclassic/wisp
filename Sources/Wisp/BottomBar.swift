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
    let isPanelVisible: Bool
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
            status
            Spacer(minLength: 0)
            controls
        }
        .padding(.horizontal, Metrics.chromeInsetX)
        .padding(.vertical, Metrics.chromeInsetY)
        .frame(maxWidth: .infinity)
        .chromeBar()
    }

    private var status: some View {
        HStack(spacing: 16) {
            HoverTextButton(help: readoutHelp, action: onToggleReadout) {
                readoutLabel.lineLimit(1).truncationMode(.tail)
            }
            if let warning {
                Text(warning)
                    .foregroundStyle(Color(nsColor: palette.danger))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(warning)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            zoom
            actions
        }
        .fixedSize()
    }

    private var actions: some View {
        HStack(spacing: 16) {
            glyphButton(
                isSpellcheckOn ? "textformat.abc.dottedunderline" : "textformat.abc",
                label: isSpellcheckOn ? "Stop checking spelling" : "Check spelling",
                shortcut: .spellcheck, action: onToggleSpellcheck)
            glyphButton(
                isSourceView ? "doc.plaintext.fill" : "doc.plaintext",
                label: isSourceView ? "Rich text view" : "Source view",
                shortcut: .sourceView, action: onToggleSourceView)
            glyphButton(
                themeIconName, label: themeButtonHelp,
                shortcut: .cycleTheme, action: onCycleTheme)
            glyphButton("questionmark", label: "Help", shortcut: .help, action: onHelpClick)
            GlyphButton(symbol: "xmark", label: "Close", help: "Close   ⎋", action: onDismiss)
        }
        .fixedSize()
    }

    /// `−  100%  +` as one control; the percentage resets.
    private var zoom: some View {
        HStack(spacing: 0) {
            glyphButton(
                "minus", label: "Smaller font", shortcut: .decreaseFontScale,
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
                .lineLimit(1)
                .fixedSize()
            }
            glyphButton(
                "plus", label: "Larger font", shortcut: .increaseFontScale,
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
                if isPanelVisible {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text("last modified: \(RelativeTime.coarse(date, now: context.date))")
                    }
                } else {
                    Text("last modified: \(RelativeTime.coarse(date, now: .now))")
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
        _ symbol: String, label: String, shortcut: KeymapAction, action: @escaping () -> Void
    ) -> some View {
        GlyphButton(symbol: symbol, label: label, help: hint(label, shortcut), action: action)
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
                    .foregroundStyle(Color(nsColor: isHovered ? palette.text : palette.muted))
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                    .onHover { isHovered = $0 }
                    .pointerCursor()
                    .help(help)
            } else {
                label()
            }
        }
        // Clicking reset disables it under the pointer, where no hover exit arrives.
        .onChange(of: isEnabled) { _, enabled in
            guard !enabled, isHovered else { return }
            isHovered = false
        }
    }
}

/// An icon with an action label and enough room for the configured font size.
struct GlyphButton: View {
    let symbol: String
    let label: String
    let help: String
    let action: () -> Void

    var body: some View {
        HoverTextButton(help: help, action: action) {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(Typography.ui(Metrics.chromeSize))
                .frame(minWidth: Metrics.footerButtonWidth, minHeight: Metrics.footerButtonHeight)
                .fixedSize()
        }
    }
}
