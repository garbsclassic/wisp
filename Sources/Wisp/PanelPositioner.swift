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
    ///
    /// `size` is asked per screen, since a panel sized as a share of the
    /// screen has to be sized for the one it lands on — which, for a saved
    /// position under `monitor: primary`, needn't be the target.
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

    /// Changes the size without moving the top edge — wherever the panel is
    /// now, including somewhere it was dragged to since it was placed — sized
    /// for the screen it's on.
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

    /// Forgets the saved spot, and moves a panel that's on screen back to the
    /// default one straight away.
    func reset(_ panel: NSWindow, size: (CGRect) -> CGSize) {
        save(nil)
        placedTopLeft = nil
        if panel.isVisible { place(panel, size: size) }
    }
}
