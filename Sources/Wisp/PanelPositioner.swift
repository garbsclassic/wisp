import AppKit
import WispCore

// Kept identical in Wisp and Clef, bar the import: both panels are placed,
// remembered, and reset through this one type.

/// Places the panel, notices when it has been dragged, and remembers where.
///
/// Rules live in `PanelPlacement`; this is the AppKit half — which screens
/// exist, where the pointer is, and what the window's frame actually is.
///
/// The position is written on hide, never mid-drag: the only reader is the
/// next summon, so one write per showing is enough, and a slow drag can't
/// emit a burst of rewrites over someone's hand edits.
@MainActor
final class PanelPositioner {
    private let monitor: () -> MonitorTarget
    private let saved: () -> PanelPosition?
    private let save: (PanelPosition?) -> Void

    /// Where the panel was last put by us rather than by the user. Compared
    /// against on hide to tell a drag from a panel left where it opened.
    private var placedTopLeft: CGPoint?

    /// Closures rather than values because the config is live: a reload can
    /// change `monitor` or clear the saved position between two summons.
    init(
        monitor: @escaping () -> MonitorTarget,
        saved: @escaping () -> PanelPosition?,
        save: @escaping (PanelPosition?) -> Void
    ) {
        self.monitor = monitor
        self.saved = saved
        self.save = save
    }

    /// The visible frame to place against: the pointer's screen under
    /// `monitor: pointer`, otherwise the one holding the menu bar. That's
    /// `screens.first`, not `NSScreen.main` — `main` follows the key window,
    /// which for an accessory app tracks whatever app was frontmost.
    var targetScreen: CGRect {
        let screens = NSScreen.screens
        let pointer =
            monitor() == .pointer
            ? screens.first { $0.frame.contains(NSEvent.mouseLocation) } : nil
        return (pointer ?? screens.first)?.visibleFrame ?? .zero
    }

    /// Puts the panel where it was last left, or at the default spot.
    func place(_ panel: NSWindow, size: CGSize) {
        let size = PanelPlacement.fitted(size, to: targetScreen)
        let topLeft = PanelPlacement.topLeft(
            for: size, saved: saved()?.point, target: targetScreen,
            screens: NSScreen.screens.map(\.visibleFrame),
            followsTarget: monitor() == .pointer)
        panel.setFrame(PanelPlacement.frame(topLeft: topLeft, size: size), display: false)
        placedTopLeft = panel.frame.topLeft
    }

    /// Changes the size without moving the top edge — wherever the panel is
    /// now, including somewhere it was dragged to since it was placed.
    func resize(_ panel: NSWindow, to size: CGSize) {
        panel.setFrame(
            PanelPlacement.frame(topLeft: panel.frame.topLeft, size: size), display: true)
    }

    /// Remembers the panel's spot if it was dragged since it was placed.
    func saveIfMoved(_ panel: NSWindow) {
        let current = panel.frame.topLeft
        guard let placed = placedTopLeft, PanelPlacement.hasMoved(from: placed, to: current)
        else { return }
        save(PanelPosition(current))
        placedTopLeft = current
    }

    /// Forgets the saved spot, and moves a panel that's on screen back to the
    /// default one straight away.
    func reset(_ panel: NSWindow) {
        save(nil)
        placedTopLeft = nil
        if panel.isVisible { place(panel, size: panel.frame.size) }
    }
}
