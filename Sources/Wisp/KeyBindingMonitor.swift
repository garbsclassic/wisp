import AppKit
import WispCore

/// Dispatches every configurable chord, matching on the physical key code
/// rather than on the character the key produced.
///
/// This exists because `NSMenuItem.keyEquivalent` cannot carry an
/// Option-modified letter. AppKit matches an equivalent against the event's
/// characters, and macOS composes `⌥L` into `¬` before it gets there — so a
/// menu item asking for "l" plus `.option` never matches, and the `¬` lands
/// in the note instead. Arrows and ⌘-chords do work through the menu, but a
/// keymap where some chords are bindable and others silently type garbage
/// is not a keymap. Key codes have neither problem: they are positions on
/// the keyboard, and no modifier changes them.
///
/// The menu keeps its items for the standard editing commands, which still
/// reach the responder chain; the keymap's own actions carry no equivalents
/// there, so nothing can fire twice.
@MainActor
final class KeyBindingMonitor {
    /// Whether the panel is focused, for gating panel-scoped actions —
    /// the same predicate `validateMenuItem` used, asked of the same place.
    private let isPanelFocused: () -> Bool
    private let perform: (KeymapAction) -> Void
    private var monitor: Any?
    /// Parsed once per config load, not per keystroke: this runs on every
    /// key the app sees.
    private var bindings: [(chord: KeyChord, action: KeymapAction)] = []

    init(
        isPanelFocused: @escaping () -> Bool,
        perform: @escaping (KeymapAction) -> Void
    ) {
        self.isPanelFocused = isPanelFocused
        self.perform = perform
    }

    /// (Re)builds the binding table and starts listening. Called at launch
    /// and again whenever the config changes.
    ///
    /// No teardown: the monitor lives as long as the app does, and the one
    /// owner is `AppDelegate`. A `deinit` couldn't touch it anyway — it is
    /// `Any?`, which a nonisolated deinit may not read off a `@MainActor`
    /// type.
    func apply(_ keymap: Keymap) {
        // Flat-mapped, not compact-mapped: an action can carry several
        // chords (F1 *and* ⌘/), and each of them has to match.
        bindings = KeymapAction.allCases.flatMap { action in
            // `summon` is Carbon's, and global; it must keep working while
            // another app is frontmost, which a local monitor never sees.
            guard action != .summon else { return [(chord: KeyChord, action: KeymapAction)]() }
            return keymap.parsedChords(for: action).map { (chord: $0, action: action) }
        }
        start()
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.action(for: event) else { return event }
            if action.isPanelScoped, !self.isPanelFocused() { return event }
            self.perform(action)
            // Swallowed, or the key would also reach the text view — which
            // is the `¬` problem this class exists to avoid.
            return nil
        }
    }

    private func action(for event: NSEvent) -> KeymapAction? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = HotKey.carbonModifiers(from: flags)
        return bindings.first {
            $0.chord.keyCode == UInt32(event.keyCode) && $0.chord.carbonModifiers == modifiers
        }?.action
    }
}
