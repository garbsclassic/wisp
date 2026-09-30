import AppKit
import WispCore

// Kept identical in Wisp and Clef, bar the import; a change here belongs in both.

/// The AppKit half of `PanelPlacement`: screens, pointer, and the real frame. The position is
/// written on hide, never mid-drag, so a slow drag can't rewrite the file over hand edits.
@MainActor
final class PanelPositioner {
    private let monitor: () -> MonitorTarget
    private let saved: () -> PanelPosition?
    private let save: (PanelPosition?) -> Void

    /// Where we last put the panel, to tell a drag from a panel left where it opened.
    private var placedTopLeft: CGPoint?

    /// Closures, since a config reload can change these between summons.
    init(
        monitor: @escaping () -> MonitorTarget,
        saved: @escaping () -> PanelPosition?,
        save: @escaping (PanelPosition?) -> Void
    ) {
        self.monitor = monitor
        self.saved = saved
        self.save = save
    }

    /// The pointer's screen under `monitor: pointer`, else the menu bar's: `screens.first`, since
    /// `NSScreen.main` follows the key window, which for an accessory app is another app's.
    var targetScreen: CGRect {
        let screens = NSScreen.screens
        let pointer =
            monitor() == .pointer
            ? screens.first { $0.frame.contains(NSEvent.mouseLocation) } : nil
        return (pointer ?? screens.first)?.visibleFrame ?? .zero
    }

    /// Where the panel was last left, or the default spot. `size` is asked per screen, since a
    /// saved position's screen needn't be the target.
    func place(_ panel: NSWindow, size: (CGRect) -> CGSize) {
        let target = targetScreen
        let screens = NSScreen.screens.map(\.visibleFrame)
        let saved = saved()?.point
        let follows = monitor() == .pointer
        let home = PanelPlacement.home(
            of: saved, size: size(target), target: target, screens: screens,
            followsTarget: follows)
        let fitted = PanelPlacement.fitted(size(home), to: home)
        let topLeft = PanelPlacement.topLeft(
            for: fitted, saved: saved, target: target, screens: screens, followsTarget: follows)
        panel.setFrame(PanelPlacement.frame(topLeft: topLeft, size: fitted), display: false)
        placedTopLeft = panel.frame.topLeft
    }

    /// Resizes for its current screen without moving the top edge.
    func resize(_ panel: NSWindow, to size: (CGRect) -> CGSize) {
        let screen =
            PanelPlacement.screen(under: panel.frame, in: NSScreen.screens.map(\.visibleFrame))
            ?? targetScreen
        let fitted = PanelPlacement.fitted(size(screen), to: screen)
        panel.setFrame(
            PanelPlacement.frame(topLeft: panel.frame.topLeft, size: fitted), display: true)
    }

    /// Remembers the panel's spot if it was dragged since it was placed.
    func saveIfMoved(_ panel: NSWindow) {
        let current = panel.frame.topLeft
        guard let placed = placedTopLeft, PanelPlacement.hasMoved(from: placed, to: current)
        else { return }
        save(PanelPosition(current))
        placedTopLeft = current
    }

    /// Forgets the saved spot, moving a visible panel back at once.
    func reset(_ panel: NSWindow, size: (CGRect) -> CGSize) {
        save(nil)
        placedTopLeft = nil
        if panel.isVisible { place(panel, size: size) }
    }
}
