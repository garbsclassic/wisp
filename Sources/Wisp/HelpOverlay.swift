import AppKit
import Carbon.HIToolbox
import SwiftUI
import WispCore

struct HelpOverlay: View {
    @Environment(\.palette) private var palette
    /// The live keymap, not hardcoded glyphs — every chord on this page is
    /// configurable, so a constant would be wrong for anyone who changed
    /// one. `key(_:)` below renders each on demand.
    let keymap: Keymap
    let onDismiss: () -> Void

    @State private var monitor: Any?
    @State private var scrollToken: Int = 0
    @State private var scrollCommand: ScrollCommand = .lineDown

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

            // Framed to the content column rather than the whole panel, so
            // the backdrop survives as real gutters either side — an
            // NSScrollView eats every click that lands on it, and without
            // the gutters there would be no "outside" left to click.
            ScrollableContent(commandToken: scrollToken, command: scrollCommand) {
                helpContent
            }
            .frame(maxWidth: 640)
        }
        .onAppear { startListening() }
        .onDisappear { stopListening() }
    }

    /// The page itself. Split out so `body` is the backdrop plus the
    /// scroller, and this stays a plain column that sizes to its content.
    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Open / dismiss", items: [
                (key(.summon), "summon or dismiss the panel"),
                (key(.find), "find in your notes (↵ / ⇧↵ to step)"),
                (key(.help), "show or hide this page"),
                ("Esc", "dismiss"),
                ("Click outside", "dismiss"),
                ("⌘Q", "quit Wisp"),
            ])
            section("Format", items: [
                (pair(.bold, .italic), "bold  /  italic — **text** and _text_"),
                (key(.highlight), "highlight — ==text=="),
                (pair(.increaseFontScale, .decreaseFontScale), "larger  /  smaller text"),
                (key(.resetFontScale), "back to your default text size"),
            ])
            section("Editing", items: [
                (key(.duplicateLine), "duplicate the line, or the selection"),
                (pair(.moveLineUp, .moveLineDown), "move the line or selection"),
                (key(.toggleListItem), "make the line a list item, or unmake it"),
                ("⌘C  /  ⌘X", "with nothing selected, the whole line"),
                ("⇥  /  ⇧⇥", "indent  /  outdent the line or selection"),
            ])
            section("Smart editing — type and press Enter", items: [
                ("-   *   +", "bulleted list, auto-continues"),
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
                (key(.settings), "open Settings… (closes the panel)"),
                (key(.refresh), "re-read settings and the note from disk"),
                ("Set Shortcut…", "rebind the global hotkey"),
                ("Launch at Login", "start automatically at login"),
                ("Scratchpad Folder…", "any folder — iCloud Drive, Dropbox for sync"),
                ("Reveal Note in Finder", "show scratchpad.md in Finder"),
            ])

            // No longer "click anywhere": the page scrolls now, and a
            // click inside a scrollable region that dismisses it is
            // hostile once there is anything below the fold.
            Text("Scroll with the wheel, ↑ ↓, ⇞ ⇟, or ⌘↑ ⌘↓. Click outside or press Esc to close.")
                .font(Typography.ui(Metrics.chromeSize))
                .foregroundStyle(Color(palette.muted))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.vertical, 36)
    }

    // MARK: Keyboard scrolling

    /// The panel is key while the overlay is up, so a local monitor sees
    /// these before the notes view does. Esc is deliberately not handled —
    /// it falls through to `FloatingPanel.onCancel`, which is what closes
    /// the overlay.
    private func startListening() {
        stopListening()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let command = Self.command(for: event) else { return event }
            scrollCommand = command
            scrollToken &+= 1
            return nil
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private static func command(for event: NSEvent) -> ScrollCommand? {
        let shift = event.modifierFlags.contains(.shift)
        // ⌘↑ / ⌘↓ are the macOS-wide "jump to the ends" chord, and Home and
        // End are the same thing on a keyboard that has them.
        let jump = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_UpArrow: return jump ? .top : .lineUp
        case kVK_DownArrow: return jump ? .bottom : .lineDown
        case kVK_PageUp: return .pageUp
        case kVK_PageDown: return .pageDown
        case kVK_Home: return .top
        case kVK_End: return .bottom
        case kVK_Space: return shift ? .pageUp : .pageDown
        default: return nil
        }
    }

    /// One chord, as a person reads it.
    private func key(_ action: KeymapAction) -> String { keymap.display(action) }

    /// Two related chords on one row — "⌘B  /  ⌘I".
    private func pair(_ first: KeymapAction, _ second: KeymapAction) -> String {
        "\(key(first))  /  \(key(second))"
    }

    @ViewBuilder
    private func section(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.ui(Metrics.chromeSize, weight: .medium))
                .foregroundStyle(Color(palette.muted))
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.bottom, 2)
            ForEach(items, id: \.0) { item in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(item.0)
                        .font(Typography.ui(Metrics.labelSize, weight: .medium))
                        .foregroundStyle(Color(palette.muted))
                        .frame(width: 180, alignment: .leading)
                    Text(item.1)
                        .font(Typography.ui(Metrics.rowSize))
                        .foregroundStyle(Color(palette.text))
                }
            }
        }
    }
}
