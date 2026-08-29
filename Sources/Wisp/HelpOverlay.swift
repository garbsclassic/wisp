import SwiftUI
import WispCore

struct HelpOverlay: View {
    @Environment(\.palette) private var palette
    /// The live summon chord, not a hardcoded one — it's configurable in
    /// two places (wisp.jsonc and Set Shortcut…), so printing a constant
    /// here would be wrong for anyone who changed it.
    let summonChord: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Tap-anywhere-to-dismiss surface. Near-opaque panel color so
            // the help text is clearly readable; the editor fades to
            // barely visible behind, which signals "modal mode" without
            // competing for attention.
            Rectangle()
                .fill(Color(palette.panel).opacity(0.97))
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 18) {
                section("Open / dismiss", items: [
                    (summonChord, "summon or dismiss the panel"),
                    ("⌘F", "find in your notes (↵ / ⇧↵ to step)"),
                    ("Esc", "dismiss"),
                    ("Click outside", "dismiss"),
                    ("⌘Q", "quit Wisp"),
                ])
                section("Format", items: [
                    ("⌘B  /  ⌘I", "bold  /  italic (toggle)"),
                    ("⌘1  /  ⌘2  /  ⌘3", "text size"),
                ])
                section("Smart editing — type and press Enter", items: [
                    ("-   *   +", "unordered list, auto-continues"),
                    ("1.    A.    a.", "ordered list, auto-increments"),
                    ("# / ## / ###", "headings (jump from top bar)"),
                    ("---", "horizontal rule (no Enter needed)"),
                ])
                section("Emoji shortcodes", items: [
                    (":)   :(", "🙂  🙁"),
                    (":rocket:   :fire:   :heart:", "🚀  🔥  ❤️"),
                    (":check:   :x:   :star:", "✅  ❌  ⭐"),
                    (":bulb:   :warning:", "💡  ⚠️"),
                ])
                section("Settings — in the menu bar menu", items: [
                    ("⌘,", "open Settings…"),
                    ("Refresh", "re-read settings and the note from disk"),
                    ("Set Shortcut…", "rebind the global hotkey"),
                    ("Launch at Login", "start automatically at login"),
                    ("Scratchpad Folder…", "any folder — iCloud Drive, Dropbox for sync"),
                    ("Reveal Note in Finder", "show scratchpad.md in Finder"),
                ])

                Text("Click anywhere or press Esc to close.")
                    .font(Typography.ui(11))
                    .foregroundStyle(Color(palette.muted))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.ui(11, weight: .medium))
                .foregroundStyle(Color(palette.muted))
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.bottom, 2)
            ForEach(items, id: \.0) { item in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(item.0)
                        .font(Typography.ui(12, weight: .medium))
                        .foregroundStyle(Color(palette.muted))
                        .frame(width: 180, alignment: .leading)
                    Text(item.1)
                        .font(Typography.ui(13))
                        .foregroundStyle(Color(palette.text))
                }
            }
        }
    }
}
