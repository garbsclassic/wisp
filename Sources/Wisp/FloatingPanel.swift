import AppKit

/// A borderless NSPanel that can still take keyboard focus.
/// NSPanel refuses to become key when it has no titlebar; overriding
/// `canBecomeKey` lets the embedded text editor accept input anyway.
final class FloatingPanel: NSPanel {
    /// Called when the user presses Esc. Return true if the cancel was
    /// handled (e.g., a help overlay was dismissed), false to fall
    /// through to the default behavior (orderOut the panel).
    var onCancel: (() -> Bool)?

    /// Called once per hide, whoever ordered it out. Owners key their
    /// teardown to this rather than to individual dismiss call sites, so
    /// a hide added later can't skip it.
    var onHide: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// AppKit constrains a window's frame to keep it on the screen it opens
    /// on, which would nudge a panel saved partly off screen back to somewhere
    /// it wasn't left. `PanelPlacement` already refuses a position that isn't
    /// reachable, so the panel takes the frame it's given — the same as
    /// Clef's.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible
        super.orderOut(sender)
        if wasVisible { onHide?() }
    }

    override func cancelOperation(_ sender: Any?) {
        if onCancel?() == true { return }
        orderOut(nil)
    }
}
