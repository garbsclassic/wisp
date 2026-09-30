import AppKit

/// A borderless panel that can still become key, which NSPanel refuses without a titlebar.
final class FloatingPanel: MovablePanel {
    /// Esc. True when handled, such as by closing an overlay; false hides the panel.
    var onCancel: (() -> Bool)?

    /// Once per hide, whoever ordered it out, so a new hide path can't skip teardown.
    var onHide: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
