import CoreGraphics

// Kept identical in Wisp and Clef: both panels place, remember, and reset
// themselves by these rules, so a change here belongs in both.

/// Where the panel was last left, as its top-left corner in AppKit's global
/// coordinates (points, y growing upward).
///
/// The top edge rather than AppKit's bottom-left origin, because the top is
/// what stays put: a panel whose height changes — Clef's, per tab — hangs
/// from it, and a resized one grows downward from it.
public struct PanelPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }

    public var point: CGPoint { CGPoint(x: x, y: y) }
}

/// Pure placement rules for a floating panel, written against the screens'
/// visible frames so they test without a running `NSApplication`.
public enum PanelPlacement {
    /// How far below the top of the screen a default-placed panel's top edge
    /// sits, as a share of the visible height. Near the top, where something
    /// you glance at belongs, while still clearing the menu bar.
    public static let topInset: CGFloat = 0.05

    /// How much of a remembered frame has to overlap a screen, in both
    /// dimensions, for it to count as reachable. Enough to grab and drag back;
    /// less means it was left on a display that has since been unplugged.
    public static let minVisible: CGFloat = 120

    /// A drag shorter than this, in points, isn't one. AppKit pixel-aligns the
    /// frames it's handed, and nobody moves a window a single point on purpose.
    public static let moveTolerance: CGFloat = 1

    /// Centred horizontally, top edge `topInset` of the way down, rounded to
    /// whole points so the frame AppKit reports back matches the one it was
    /// given.
    public static func defaultTopLeft(for size: CGSize, on screen: CGRect) -> CGPoint {
        let size = fitted(size, to: screen)
        let top = screen.maxY - screen.height * topInset
        return CGPoint(
            x: (screen.minX + (screen.width - size.width) / 2).rounded(),
            y: min(max(top, screen.minY + size.height), screen.maxY).rounded())
    }

    /// Where a panel of `size` goes on summon.
    ///
    /// No saved position, or one that's no longer reachable on `screens`, gets
    /// the default spot on `target`. With `followsTarget` — `monitor:
    /// pointer` — a saved position is carried to `target`, keeping its place
    /// relative to the screen it was saved on; otherwise it's used as is,
    /// whichever screen that puts it on.
    public static func topLeft(
        for size: CGSize, saved: CGPoint?, target: CGRect, screens: [CGRect],
        followsTarget: Bool
    ) -> CGPoint {
        guard let saved, isReachable(frame(topLeft: saved, size: size), on: screens) else {
            return defaultTopLeft(for: size, on: target)
        }
        guard followsTarget else { return saved }

        let source = screens.first { $0.contains(saved) } ?? target
        return carried(saved, size: size, from: source, to: target)
    }

    /// The window frame for a top-left corner, in AppKit's bottom-left origin.
    public static func frame(topLeft: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: topLeft.x.rounded(), y: (topLeft.y - size.height).rounded(),
            width: size.width, height: size.height)
    }

    /// Caps `size` at the screen's own, so a panel sized on a larger display
    /// still opens whole on a smaller one.
    public static func fitted(_ size: CGSize, to screen: CGRect) -> CGSize {
        CGSize(width: min(size.width, screen.width), height: min(size.height, screen.height))
    }

    /// True when `frame` overlaps some screen by at least `minVisible` in both
    /// dimensions.
    public static func isReachable(_ frame: CGRect, on screens: [CGRect]) -> Bool {
        screens.contains { screen in
            let overlap = frame.intersection(screen)
            return !overlap.isNull && overlap.width >= minVisible
                && overlap.height >= minVisible
        }
    }

    /// Moves a top-left corner from one screen to another, keeping its
    /// position *relative to* the screen it came from: two thirds of the way
    /// across the free space on one display is two thirds across on the next,
    /// rather than the same absolute point, which on a smaller display can be
    /// off the edge entirely.
    public static func carried(
        _ topLeft: CGPoint, size: CGSize, from source: CGRect, to destination: CGRect
    ) -> CGPoint {
        let size = fitted(size, to: destination)
        // A panel as wide as its screen has no free space to be relative
        // within; the centre is as good an answer as any.
        func ratio(_ offset: CGFloat, _ slack: CGFloat) -> CGFloat {
            slack > 0 ? offset / slack : 0.5
        }
        let ratioX = ratio(topLeft.x - source.minX, source.width - size.width)
        let ratioY = ratio(source.maxY - topLeft.y, source.height - size.height)

        return CGPoint(
            x: (destination.minX + (destination.width - size.width) * ratioX).rounded(),
            y: (destination.maxY - (destination.height - size.height) * ratioY).rounded())
    }

    /// Whether the panel was dragged off the spot it was placed at.
    public static func hasMoved(from placed: CGPoint, to current: CGPoint) -> Bool {
        abs(placed.x - current.x) > moveTolerance || abs(placed.y - current.y) > moveTolerance
    }
}

extension CGRect {
    /// The top-left corner in AppKit's coordinates, where y grows upward.
    public var topLeft: CGPoint { CGPoint(x: minX, y: maxY) }
}
