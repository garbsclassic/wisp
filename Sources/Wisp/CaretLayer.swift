import AppKit
import WispCore

/// The caret, drawn as a Core Animation layer in place of AppKit's.
///
/// Both the move and the blink are animations the render server runs on
/// its own: no timer fires, no rect is dirtied, and the main thread does
/// nothing between caret moves. That makes it cheaper than the stock
/// caret, which wakes on an `NSTimer` every half second to repaint.
///
/// Owned by `NotesTextView`, which suppresses the stock caret and calls
/// `update` from the same hook AppKit uses to reposition its own.
final class CaretLayer {
    /// Width and corner radius match the modern AppKit indicator.
    static let width: CGFloat = 2

    /// Solid after every move, then a fade rather than a switch. Durations
    /// in seconds: 0.45 solid, 0.1 out, 0.35 off, 0.1 in.
    private static let blinkPeriod: CFTimeInterval = 1.0
    private static let blinkKey = "blink"

    let layer = CALayer()
    var style = Caret()

    /// Where the layer was last sent, so a refresh that lands on the same
    /// rect is a no-op rather than a snap that cuts an animation short.
    private var target: CGRect?

    init() {
        layer.cornerRadius = Self.width / 2
        layer.isHidden = true
        // Above the glyphs; the text view's own content draws at zero.
        layer.zPosition = 1
    }

    /// Moves the caret to `frame` — or hides it — animating the move when
    /// `animated` and the style allow. Restarts the blink so the caret is
    /// solid for a moment after every move, which is what keeps it solid
    /// while typing.
    func update(to frame: CGRect?, color: NSColor, animated: Bool) {
        guard let frame else {
            hide()
            return
        }
        let curve = animated ? style.motion.curve : nil
        let wasVisible = !layer.isHidden

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color.cgColor
        layer.isHidden = false
        CATransaction.commit()

        if frame != target {
            CATransaction.begin()
            // A caret appearing from nowhere has nowhere to slide from.
            if let curve, wasVisible {
                CATransaction.setAnimationDuration(curve.duration)
                CATransaction.setAnimationTimingFunction(curve.timing)
            } else {
                CATransaction.setDisableActions(true)
            }
            layer.frame = frame
            CATransaction.commit()
            target = frame
        }
        restartBlink()
    }

    private func hide() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.isHidden = true
        CATransaction.commit()
        // A hidden layer's animation still ticks on the render server.
        layer.removeAnimation(forKey: Self.blinkKey)
        target = nil
    }

    private func restartBlink() {
        layer.removeAnimation(forKey: Self.blinkKey)
        guard style.blink else {
            layer.opacity = 1
            return
        }
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 1, 0, 0, 1]
        blink.keyTimes = [0, 0.45, 0.55, 0.9, 1]
        blink.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        blink.duration = Self.blinkPeriod
        blink.repeatCount = .infinity
        layer.add(blink, forKey: Self.blinkKey)
    }
}

extension CaretMotion {
    struct Curve {
        let duration: CFTimeInterval
        let timing: CAMediaTimingFunction
    }

    /// Nil when the caret should teleport — `off`, or the system Reduce
    /// Motion setting, which wins over the file.
    var curve: Curve? {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return nil }
        switch self {
        case .snappy:
            return Curve(
                duration: 0.09,
                timing: CAMediaTimingFunction(controlPoints: 0.05, 0.7, 0.1, 1))
        case .gliding:
            return Curve(
                duration: 0.16,
                timing: CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1))
        case .off:
            return nil
        }
    }
}
