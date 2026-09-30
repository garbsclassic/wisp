import CoreGraphics

// Kept identical in Wisp and Clef; a change here belongs in both.

/// The panel's top-left in AppKit's global coordinates: the top edge, since a resized panel
/// hangs from it.
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

/// Placement rules over the screens' visible frames, testable without `NSApplication`.
public enum PanelPlacement {
    /// The default top edge's distance below the screen top, as a share of the visible height.
    public static let topInset: CGFloat = 0.05

    /// Overlap in both dimensions a saved frame needs to count as reachable: enough to grab.
    public static let minVisible: CGFloat = 120

    /// AppKit pixel-aligns frames, so a smaller difference isn't a drag.
    public static let moveTolerance: CGFloat = 1

    /// Centred, `topInset` down, on whole points so AppKit reports back the same frame.
    public static func defaultTopLeft(for size: CGSize, on screen: CGRect) -> CGPoint {
        let size = fitted(size, to: screen)
        let top = screen.maxY - screen.height * topInset
        return CGPoint(
            x: (screen.minX + (screen.width - size.width) / 2).rounded(),
            y: min(max(top, screen.minY + size.height), screen.maxY).rounded())
    }

    /// The default spot on `target` unless a saved position is still reachable. `followsTarget`
    /// (`monitor: pointer`) carries it to `target`, keeping its place relative to its screen.
    public static func topLeft(
        for size: CGSize, saved: CGPoint?, target: CGRect, screens: [CGRect],
        followsTarget: Bool
    ) -> CGPoint {
        guard let saved, isReachable(frame(topLeft: saved, size: size), on: screens) else {
            return defaultTopLeft(for: size, on: target)
        }
        guard followsTarget else { return saved }

        let source = screen(under: frame(topLeft: saved, size: size), in: screens) ?? target
        return carried(saved, size: size, from: source, to: target)
    }

    /// The screen `topLeft(…)` would put the panel on, judged at its size on `target`: a panel
    /// sized per screen needs the screen first.
    public static func home(
        of saved: CGPoint?, size: CGSize, target: CGRect, screens: [CGRect],
        followsTarget: Bool
    ) -> CGRect {
        guard !followsTarget, let saved else { return target }
        let frame = frame(topLeft: saved, size: size)
        guard isReachable(frame, on: screens) else { return target }
        return screen(under: frame, in: screens) ?? target
    }

    /// The screen `frame` overlaps most. `contains` would miss a corner flush on the top edge.
    public static func screen(under frame: CGRect, in screens: [CGRect]) -> CGRect? {
        func area(_ screen: CGRect) -> CGFloat {
            let overlap = frame.intersection(screen)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        return screens.filter { area($0) > 0 }.max { area($0) < area($1) }
    }

    /// The window frame for a top-left corner, in AppKit's bottom-left origin.
    public static func frame(topLeft: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: topLeft.x.rounded(), y: (topLeft.y - size.height).rounded(),
            width: size.width, height: size.height)
    }

    /// Caps `size` at the screen's, so a panel sized on a larger display opens whole.
    public static func fitted(_ size: CGSize, to screen: CGRect) -> CGSize {
        CGSize(width: min(size.width, screen.width), height: min(size.height, screen.height))
    }

    public static func isReachable(_ frame: CGRect, on screens: [CGRect]) -> Bool {
        screens.contains { screen in
            let overlap = frame.intersection(screen)
            return !overlap.isNull && overlap.width >= minVisible
                && overlap.height >= minVisible
        }
    }

    /// Keeps the corner's place relative to its screen's free space; the same absolute point
    /// could be off a smaller display.
    public static func carried(
        _ topLeft: CGPoint, size: CGSize, from source: CGRect, to destination: CGRect
    ) -> CGPoint {
        let size = fitted(size, to: destination)
        // A panel as wide as its screen has no slack; centre it.
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
