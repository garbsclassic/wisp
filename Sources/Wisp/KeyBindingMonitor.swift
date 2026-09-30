import AppKit
import WispCore

/// Dispatches every configurable chord by key code, since `keyEquivalent` can't match an
/// ⌥-letter: macOS composes `⌥L` into `¬` first. The menu carries no keymap equivalents, so
/// nothing fires twice.
@MainActor
final class KeyBindingMonitor {
    /// Gates panel-scoped actions.
    private let isPanelFocused: () -> Bool
    private let perform: (KeymapAction) -> Void
    private var monitor: Any?
    /// Parsed per config load rather than per keystroke.
    private var bindings: [(chord: KeyChord, action: KeymapAction)] = []

    init(
        isPanelFocused: @escaping () -> Bool,
        perform: @escaping (KeymapAction) -> Void
    ) {
        self.isPanelFocused = isPanelFocused
        self.perform = perform
    }

    /// Rebuilds the bindings and starts listening. No teardown: it lives as long as the app.
    func apply(_ keymap: Keymap) {
        // An action can carry several chords, and each one matches.
        bindings = KeymapAction.allCases.flatMap { action in
            // `summon` is Carbon's: a local monitor misses keys while another app is in front.
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
            // Swallowed, or the text view would type `¬`.
            return nil
        }
    }

    private func action(for event: NSEvent) -> KeymapAction? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = KeyChord.carbonModifiers(from: flags)
        return bindings.first {
            $0.chord.keyCode == UInt32(event.keyCode) && $0.chord.carbonModifiers == modifiers
        }?.action
    }
}
