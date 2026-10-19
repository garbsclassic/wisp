import CoreGraphics
import Foundation
import Testing

@testable import WispCore

private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)

private func legacyGeometry(_ json: String, json5: Bool = false) throws -> LegacyPanelGeometry {
    let decoder = JSONDecoder()
    decoder.allowsJSON5 = json5
    return try decoder.decode(LegacyPanelGeometry.self, from: Data(json.utf8))
}

@Suite("PanelPlacement.initialFrame")
struct InitialFrameTests {
    @Test("The minimum and default sizes are the supported window sizes")
    func sizeDefaults() {
        #expect(PanelPlacement.minimumSize == CGSize(width: 200, height: 200))
        #expect(PanelPlacement.defaultSize == CGSize(width: 800, height: 640))
    }

    @Test("No legacy geometry starts centered near the top at the default size")
    func noLegacyGeometry() {
        let frame = PanelPlacement.initialFrame(legacy: nil, target: primary, screens: [primary])

        #expect(frame == CGRect(x: 320, y: 215, width: 800, height: 640))
    }

    @Test("Legacy size is read in points and position remains a top-left corner")
    func legacyGeometryUsesPointsAndTopLeft() throws {
        let legacy = try legacyGeometry(
            #"{"panel":{"width":600,"height":400},"position":{"x":200,"y":700}}"#)

        let frame = PanelPlacement.initialFrame(legacy: legacy, target: primary, screens: [primary])

        #expect(frame == CGRect(x: 200, y: 300, width: 600, height: 400))
    }

    @Test("An invalid legacy size falls back while a valid position is retained")
    func invalidSizeFallsBackIndependently() throws {
        let legacy = try legacyGeometry(
            #"{"panel":{"width":"wide","height":500},"position":{"x":200,"y":700}}"#)

        let frame = PanelPlacement.initialFrame(legacy: legacy, target: primary, screens: [primary])

        #expect(frame == CGRect(x: 200, y: 60, width: 800, height: 640))
    }

    @Test("A malformed legacy position falls back while a valid size is retained")
    func malformedPositionFallsBackIndependently() throws {
        let legacy = try legacyGeometry(
            #"{"panel":{"width":600,"height":400},"position":{"x":"left","y":700}}"#)

        let frame = PanelPlacement.initialFrame(legacy: legacy, target: primary, screens: [primary])

        #expect(frame == CGRect(x: 420, y: 455, width: 600, height: 400))
    }

    @Test("JSON5 legacy geometry accepts comments and trailing commas")
    func json5LegacyGeometry() throws {
        let legacy = try legacyGeometry(
            """
            {
              // These are points, not fractions of the screen.
              panel: { width: 600, height: 400, },
              position: { x: 200, y: 700, },
            }
            """, json5: true)

        let frame = PanelPlacement.initialFrame(legacy: legacy, target: primary, screens: [primary])

        #expect(frame == CGRect(x: 200, y: 300, width: 600, height: 400))
    }

    @Test("A nonfinite legacy size falls back without discarding a valid position")
    func nonfiniteSizeFallsBackIndependently() throws {
        let legacy = try legacyGeometry(
            #"{panel:{width:Infinity,height:500},position:{x:200,y:700}}"#, json5: true)

        let frame = PanelPlacement.initialFrame(legacy: legacy, target: primary, screens: [primary])

        #expect(frame == CGRect(x: 200, y: 60, width: 800, height: 640))
    }

    @Test("An unreachable legacy position uses the default location and keeps its size")
    func unreachableLegacyPosition() throws {
        let legacy = try legacyGeometry(
            #"{"panel":{"width":600,"height":400},"position":{"x":4000,"y":4000}}"#)

        let frame = PanelPlacement.initialFrame(legacy: legacy, target: primary, screens: [primary])

        #expect(frame == CGRect(x: 420, y: 455, width: 600, height: 400))
    }

    @Test("A reachable legacy frame on a negative-origin display is retained")
    func negativeOriginDisplay() throws {
        let secondary = CGRect(x: -1280, y: 0, width: 1280, height: 1024)
        let legacy = try legacyGeometry(
            #"{"panel":{"width":600,"height":400},"position":{"x":-1200,"y":900}}"#)

        let frame = PanelPlacement.initialFrame(
            legacy: legacy, target: primary, screens: [primary, secondary])

        #expect(frame == CGRect(x: -1200, y: 500, width: 600, height: 400))
    }

    @Test("An oversized legacy size without a position stays on the target screen")
    func oversizedLegacySizeUsesTarget() throws {
        let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let legacy = try legacyGeometry(#"{"panel":{"width":3000,"height":1500}}"#)

        let frame = PanelPlacement.initialFrame(
            legacy: legacy, target: primary, screens: [primary, secondary])

        #expect(frame == primary)
    }
}

@Suite("PanelPlacement.recoveredFrame")
struct RecoveredFrameTests {
    let secondary = CGRect(x: -1280, y: 0, width: 1280, height: 1024)

    @Test("A reachable frame on a connected secondary display stays put")
    func connectedSecondaryIsUnchanged() {
        let frame = CGRect(x: -1100, y: 300, width: 800, height: 500)

        let recovered = PanelPlacement.recoveredFrame(
            frame, target: primary, screens: [primary, secondary])

        #expect(recovered == frame)
        #expect(PanelPlacement.screen(under: frame, in: [primary, secondary]) == secondary)
    }

    @Test("A frame from a disconnected display returns to the target at the same size")
    func detachedDisplayFallsBack() {
        let frame = CGRect(x: -1100, y: 300, width: 800, height: 400)

        let recovered = PanelPlacement.recoveredFrame(frame, target: primary, screens: [primary])

        #expect(recovered == CGRect(x: 320, y: 455, width: 800, height: 400))
    }

    @Test("An undersized saved frame grows to the minimum and remains reachable")
    func undersizedFrameGrows() {
        let frame = CGRect(x: 500, y: 300, width: 100, height: 100)

        let recovered = PanelPlacement.recoveredFrame(frame, target: primary, screens: [primary])

        #expect(recovered == CGRect(x: 620, y: 655, width: 200, height: 200))
        #expect(PanelPlacement.isReachable(recovered, on: [primary]))
    }

    @Test("An oversized frame is fitted to the target screen")
    func oversizedFrameIsFitted() {
        let frame = CGRect(x: 0, y: 0, width: 2000, height: 1000)

        let recovered = PanelPlacement.recoveredFrame(frame, target: primary, screens: [primary])

        #expect(recovered == primary)
    }

    @Test("No connected screens leaves the current frame alone")
    func noScreensIsNoOp() {
        let frame = CGRect(x: -1100, y: 300, width: 800, height: 400)

        #expect(PanelPlacement.recoveredFrame(frame, target: .zero, screens: []) == frame)
    }

    @Test("Nonfinite, zero, and negative saved rectangles recover to the default frame")
    func corruptSavedRectanglesRecover() {
        let corruptFrames = [
            CGRect(x: CGFloat.infinity, y: 100, width: 800, height: 640),
            CGRect(x: 100, y: CGFloat.nan, width: 800, height: 640),
            CGRect(x: 100, y: 100, width: 0, height: 640),
            CGRect(x: 100, y: 100, width: 800, height: -1),
        ]
        let usableDefault = CGRect(x: 320, y: 215, width: 800, height: 640)

        for frame in corruptFrames {
            #expect(
                PanelPlacement.recoveredFrame(frame, target: primary, screens: [primary])
                    == usableDefault)
        }
    }

    @Test("An undersized target fits the default reset frame to its bounds")
    func resetFitsTinyTarget() {
        let tiny = CGRect(x: -200, y: 30, width: 500, height: 300)

        #expect(PanelPlacement.resetFrame(on: tiny) == tiny)
    }

    @Test("Reachability requires the full minimum overlap in both dimensions")
    func reachabilityThreshold() {
        let exactlyAtThreshold = CGRect(
            x: primary.maxX - PanelPlacement.minVisible,
            y: primary.maxY - PanelPlacement.minVisible,
            width: 300,
            height: 300)
        let shortOnWidth = exactlyAtThreshold.offsetBy(dx: 0.01, dy: 0)
        let shortOnHeight = exactlyAtThreshold.offsetBy(dx: 0, dy: 0.01)

        #expect(PanelPlacement.isReachable(exactlyAtThreshold, on: [primary]))
        #expect(!PanelPlacement.isReachable(shortOnWidth, on: [primary]))
        #expect(!PanelPlacement.isReachable(shortOnHeight, on: [primary]))
    }

    @Test("A reachable frame remains in its partial offscreen position")
    func reachablePartialOffscreenFrameStaysPut() {
        let frame = CGRect(
            x: primary.maxX - PanelPlacement.minVisible,
            y: 250,
            width: 800,
            height: 500)

        #expect(PanelPlacement.isReachable(frame, on: [primary]))
        #expect(PanelPlacement.recoveredFrame(frame, target: primary, screens: [primary]) == frame)
    }
}

@Test("Reset returns the default frame on the requested screen")
func resetFrame() {
    #expect(
        PanelPlacement.resetFrame(on: primary)
            == CGRect(x: 320, y: 215, width: 800, height: 640))
}

@Test("The top-left corner uses minX and maxY")
func topLeftUsesAppKitCoordinates() {
    #expect(CGRect(x: 10, y: 20, width: 100, height: 50).topLeft == CGPoint(x: 10, y: 70))
}
