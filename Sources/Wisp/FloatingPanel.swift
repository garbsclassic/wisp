import AppKit

/// A borderless NSPanel that can still take keyboard focus.
/// NSPanel refuses to become key when it has no titlebar; overriding
/// `canBecomeKey` lets the embedded text editor accept input anyway.
final class FloatingPanel: NSPanel {
    /// Called when the user presses Esc. Return true if the cancel was
    /// handled (e.g., a help overlay was dismissed), false to fall
    /// through to the default behavior (orderOut the panel).
    var onCancel: (() -> Bool)?

    /// Called just before the panel orders itself out via the Esc
    /// fallback path, so owners can tear down state (e.g., the
    /// outside-click monitor) they keyed to visibility.
    var onWillHide: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if onCancel?() == true { return }
        onWillHide?()
        orderOut(nil)
    }
}
