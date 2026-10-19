import CoreGraphics
import Foundation

/// Imported once from the retired config keys; size is in points and position is the top-left.
public struct LegacyPanelGeometry: Decodable {
    // The old config accepted sizes from 200 points per side; recovery applies today's minimum.
    private static let minimumSide: Double = 200

    private struct Size: Decodable {
        let width: Double
        let height: Double
    }

    private struct Position: Decodable {
        let x: Double
        let y: Double
    }

    fileprivate let size: CGSize?
    fileprivate let position: CGPoint?

    private enum CodingKeys: String, CodingKey { case panel, position }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let panel = try? values.decode(Size.self, forKey: .panel)
        size = panel.flatMap {
            $0.width.isFinite && $0.height.isFinite
                && $0.width >= Self.minimumSide && $0.height >= Self.minimumSide
                ? CGSize(width: $0.width, height: $0.height) : nil
        }
        let point = try? values.decode(Position.self, forKey: .position)
        position = point.flatMap {
            $0.x.isFinite && $0.y.isFinite ? CGPoint(x: $0.x, y: $0.y) : nil
        }
    }
}

/// Initial placement and recovery for a borderless panel, independent of frame storage.
public enum PanelPlacement {
    public static let minimumSize = CGSize(width: 540, height: 640)
    public static let defaultSize = CGSize(width: 800, height: minimumSize.height)
    public static let topInset: CGFloat = 0.05
    public static let minVisible: CGFloat = 120

    public static func initialFrame(
        legacy: LegacyPanelGeometry?, target: CGRect, screens: [CGRect]
    ) -> CGRect {
        let size = legacy?.size ?? defaultSize
        let home = legacy?.position.flatMap {
            screen(under: frame(topLeft: $0, size: size), in: screens)
        } ?? target
        let fitted = fitted(size, to: home)
        let initial = frame(
            topLeft: legacy?.position ?? defaultTopLeft(for: fitted, on: home), size: fitted)
        return recoveredFrame(initial, target: target, screens: screens)
    }

    /// Leaves reachable frames alone; disconnected displays need a usable fallback.
    public static func recoveredFrame(
        _ frame: CGRect, target: CGRect, screens: [CGRect]
    ) -> CGRect {
        guard !screens.isEmpty, target.width > 0, target.height > 0 else { return frame }
        let valid =
            frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.size.width.isFinite && frame.size.height.isFinite
            && frame.size.width > 0 && frame.size.height > 0
        let home = valid ? (screen(under: frame, in: screens) ?? target) : target
        let size = fitted(
            valid
                ? CGSize(
                    width: max(frame.width, minimumSize.width),
                    height: max(frame.height, minimumSize.height))
                : defaultSize,
            to: home)
        if valid, frame.size == size, isReachable(frame, on: screens) { return frame }
        return self.frame(topLeft: defaultTopLeft(for: size, on: home), size: size)
    }

    /// Reset uses the usable screen's proportions, preserving the minimum where it fits.
    public static func resetFrame(on screen: CGRect) -> CGRect {
        let size = fitted(
            CGSize(
                width: max((screen.width * 0.4).rounded(), minimumSize.width),
                height: max((screen.height * 0.6).rounded(), minimumSize.height)),
            to: screen)
        return frame(topLeft: defaultTopLeft(for: size, on: screen), size: size)
    }

    public static func defaultTopLeft(for size: CGSize, on screen: CGRect) -> CGPoint {
        let size = fitted(size, to: screen)
        let top = screen.maxY - screen.height * topInset
        return CGPoint(
            x: (screen.minX + (screen.width - size.width) / 2).rounded(),
            y: min(max(top, screen.minY + size.height), screen.maxY).rounded())
    }

    /// The screen the frame overlaps most, including displays with negative coordinates.
    public static func screen(under frame: CGRect, in screens: [CGRect]) -> CGRect? {
        func area(_ screen: CGRect) -> CGFloat {
            let overlap = frame.intersection(screen)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        return screens.filter { area($0) > 0 }.max { area($0) < area($1) }
    }

    public static func frame(topLeft: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: topLeft.x.rounded(), y: (topLeft.y - size.height).rounded(),
            width: size.width, height: size.height)
    }

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
}

extension CGRect {
    public var topLeft: CGPoint { CGPoint(x: minX, y: maxY) }
}
