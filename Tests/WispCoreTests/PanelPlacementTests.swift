import CoreGraphics
import Foundation
import Testing

@testable import WispCore

@Suite("PanelPlacement.defaultTopLeft")
struct DefaultTopLeftTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 800, height: 640)

    /// AppKit pixel-aligns whatever frame it's handed, so a fractional origin
    /// would come back changed and read as a drag.
    @Test("The result lands on whole points")
    func wholePoints() {
        let odd = CGRect(x: 0, y: 0, width: 1443, height: 907)
        let topLeft = PanelPlacement.defaultTopLeft(for: size, on: odd)
        #expect(topLeft.x == topLeft.x.rounded())
        #expect(topLeft.y == topLeft.y.rounded())
    }

    /// The origin is relative to the screen, not the global coordinate
    /// space — a second display to the right isn't a 1440-point offset.
    @Test("A screen with a non-zero origin is placed against its own bounds")
    func nonZeroOrigin() {
        let second = CGRect(x: 1440, y: 300, width: 1920, height: 1080)
        let topLeft = PanelPlacement.defaultTopLeft(for: size, on: second)
        #expect(topLeft.x == (second.minX + (second.width - size.width) / 2).rounded())
        #expect(topLeft.y == (second.maxY - second.height * PanelPlacement.topInset).rounded())
    }

    /// A panel larger than the screen still has to arrive whole and
    /// grabbable, rather than hanging off an edge.
    @Test("A size bigger than the screen is fitted onto it")
    func fittedToScreen() {
        let small = CGRect(x: 0, y: 0, width: 600, height: 400)
        let topLeft = PanelPlacement.defaultTopLeft(for: size, on: small)
        let fitted = PanelPlacement.fitted(size, to: small)
        let frame = PanelPlacement.frame(topLeft: topLeft, size: fitted)
        #expect(frame == small)
    }
}

@Suite("PanelPlacement.topLeft")
struct TopLeftTests {
    let size = CGSize(width: 800, height: 640)
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test("A nil saved position gives the default on the target")
    func nilSaved() {
        let topLeft = PanelPlacement.topLeft(
            for: size, saved: nil, target: primary, screens: [primary], followsTarget: false)
        #expect(topLeft == PanelPlacement.defaultTopLeft(for: size, on: primary))
    }

    /// Not following: a reachable saved point wins wherever it is, even when
    /// that's a screen other than the target.
    @Test("A reachable saved point that isn't following is returned unchanged, even off-target")
    func reachableNotFollowing() {
        let saved = CGPoint(x: 1600, y: 900)
        let topLeft = PanelPlacement.topLeft(
            for: size, saved: saved, target: primary, screens: [primary, secondary],
            followsTarget: false)
        #expect(topLeft == saved)
    }

    /// The display the point was saved on is no longer in `screens` — as if
    /// unplugged — so nothing on the current setup overlaps it enough.
    @Test("An unreachable saved point on an unplugged display gives the default on the target")
    func unpluggedDisplay() {
        let saved = CGPoint(x: 1600, y: 900)
        let topLeft = PanelPlacement.topLeft(
            for: size, saved: saved, target: primary, screens: [primary], followsTarget: false)
        #expect(topLeft == PanelPlacement.defaultTopLeft(for: size, on: primary))
    }

    /// `monitor: pointer` carries a reachable saved point to the target,
    /// relative to the screen it was actually saved on.
    @Test("followsTarget carries a reachable point to the target, relative to its source screen")
    func followsTarget() {
        let saved = CGPoint(x: 400, y: 800)
        let topLeft = PanelPlacement.topLeft(
            for: size, saved: saved, target: secondary, screens: [primary, secondary],
            followsTarget: true)
        #expect(topLeft == PanelPlacement.carried(saved, size: size, from: primary, to: secondary))
        #expect(topLeft != saved)
    }
}

@Suite("PanelPlacement.carried")
struct CarriedTests {
    @Test("The same corner of the source screen maps to the same corner of the destination")
    func sameCorner() {
        let size = CGSize(width: 800, height: 640)
        let source = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let destination = CGRect(x: 2000, y: 0, width: 1440, height: 900)
        let carried = PanelPlacement.carried(
            source.topLeft, size: size, from: source, to: destination)
        #expect(carried == destination.topLeft)
    }

    /// A quarter of the way across, three quarters down the free space on
    /// one display lands at the same fractions on the next.
    @Test("The relative position within the free space is kept")
    func relativePosition() {
        let size = CGSize(width: 800, height: 500)
        let source = CGRect(x: 0, y: 0, width: 1000, height: 900)
        let destination = CGRect(x: 0, y: 0, width: 2000, height: 1800)
        // Slack is 200 wide, 400 tall on the source: a quarter across, three
        // quarters down lands exactly on 50 and 600.
        let point = CGPoint(x: 50, y: 600)
        let carried = PanelPlacement.carried(point, size: size, from: source, to: destination)
        // Destination slack is 1200 wide, 1300 tall: the same quarter and
        // three-quarters land on 300 and 825.
        #expect(carried == CGPoint(x: 300, y: 825))
    }

    /// A panel exactly as wide (and tall) as its screen has no free space to
    /// be relative within; the centre is as good an answer as any.
    @Test("Zero slack gives the ratio 0.5")
    func zeroSlackGivesHalf() {
        let size = CGSize(width: 1440, height: 900)
        let source = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let destination = CGRect(x: 0, y: 0, width: 2000, height: 1200)
        let carried = PanelPlacement.carried(
            source.topLeft, size: size, from: source, to: destination)
        #expect(carried == CGPoint(x: 280, y: 1050))
    }
}

@Suite("PanelPlacement.frame")
struct FrameTests {
    @Test("The origin's y is the top minus the height, and both coordinates round")
    func originFromTopLeft() {
        let frame = PanelPlacement.frame(
            topLeft: CGPoint(x: 10.4, y: 500.6), size: CGSize(width: 800, height: 640))
        #expect(frame.origin.x == 10)
        #expect(frame.origin.y == -139)
        #expect(frame.size == CGSize(width: 800, height: 640))
    }
}

@Suite("PanelPlacement.isReachable")
struct IsReachableTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    @Test("An overlap of exactly minVisible in both dimensions is reachable")
    func exactlyAtBoundary() {
        let frame = CGRect(
            x: screen.maxX - PanelPlacement.minVisible, y: screen.maxY - PanelPlacement.minVisible,
            width: 300, height: 300)
        #expect(PanelPlacement.isReachable(frame, on: [screen]))
    }

    @Test("An overlap one point short of minVisible in either dimension is not reachable")
    func oneShortOfBoundary() {
        let frame = CGRect(
            x: screen.maxX - PanelPlacement.minVisible + 1,
            y: screen.maxY - PanelPlacement.minVisible + 1,
            width: 300, height: 300)
        #expect(!PanelPlacement.isReachable(frame, on: [screen]))
    }
}

@Suite("PanelPlacement.hasMoved")
struct HasMovedTests {
    let placed = CGPoint(x: 100, y: 100)

    @Test("A drag of exactly the tolerance in either axis is not a move")
    func atTolerance() {
        #expect(!PanelPlacement.hasMoved(from: placed, to: CGPoint(x: 101, y: 100)))
        #expect(!PanelPlacement.hasMoved(from: placed, to: CGPoint(x: 100, y: 99)))
    }

    @Test("Anything past the tolerance in either axis is a move")
    func beyondTolerance() {
        #expect(PanelPlacement.hasMoved(from: placed, to: CGPoint(x: 101.1, y: 100)))
        #expect(PanelPlacement.hasMoved(from: placed, to: CGPoint(x: 100, y: 98.9)))
    }
}

@Suite("PanelPlacement.screen(under:) and home(of:)")
struct ScreenUnderTests {
    static let laptop = CGRect(x: 0, y: 0, width: 1512, height: 944)
    static let external = CGRect(x: 1512, y: 0, width: 2560, height: 1415)
    static let size = CGSize(width: 800, height: 640)

    /// A panel dragged flush to the top of a screen has its top-left on that
    /// screen's `maxY`, which `CGRect.contains` counts as outside.
    @Test("A saved corner on a screen's top edge is still carried by monitor: pointer")
    func flushTopEdgeIsCarried() {
        let saved = CGPoint(x: 300, y: Self.laptop.maxY)
        let topLeft = PanelPlacement.topLeft(
            for: Self.size, saved: saved, target: Self.external,
            screens: [Self.laptop, Self.external], followsTarget: true)
        #expect(topLeft.x >= Self.external.minX)
        #expect(topLeft == PanelPlacement.carried(
            saved, size: Self.size, from: Self.laptop, to: Self.external))
    }

    @Test("The screen under a frame is the one it overlaps most")
    func largestOverlapWins() {
        let straddling = CGRect(x: 1312, y: 100, width: 800, height: 640)
        #expect(
            PanelPlacement.screen(under: straddling, in: [Self.laptop, Self.external])
                == Self.external)
        let offEverything = CGRect(x: -2000, y: 100, width: 800, height: 640)
        #expect(PanelPlacement.screen(under: offEverything, in: [Self.laptop]) == nil)
    }

    /// Under `monitor: primary` a saved position is used wherever it is, so
    /// a panel sized per screen has to be sized for that screen.
    @Test("A reachable saved position's home is the screen it's on, when not following")
    func homeIsWhereTheSavedPositionIs() {
        let saved = CGPoint(x: 100, y: 900)
        #expect(
            PanelPlacement.home(
                of: saved, size: Self.size, target: Self.external,
                screens: [Self.laptop, Self.external], followsTarget: false) == Self.laptop)
    }

    @Test("The home is the target when following, unsaved, or unreachable")
    func homeFallsBackToTarget() {
        let screens = [Self.laptop, Self.external]
        let onLaptop = CGPoint(x: 100, y: 900)
        #expect(
            PanelPlacement.home(
                of: onLaptop, size: Self.size, target: Self.external, screens: screens,
                followsTarget: true) == Self.external)
        #expect(
            PanelPlacement.home(
                of: nil, size: Self.size, target: Self.external, screens: screens,
                followsTarget: false) == Self.external)
        #expect(
            PanelPlacement.home(
                of: CGPoint(x: -5000, y: 900), size: Self.size, target: Self.external,
                screens: screens, followsTarget: false) == Self.external)
    }
}
