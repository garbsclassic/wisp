// Generates Resources/AppIcon.png for Wisp.
// Run with: swift scripts/generate-icon.swift
// Output: Resources/AppIcon.png (1024x1024, pre-shaped with transparent
// corners — build.sh resizes it into an .iconset via sips, no Xcode needed).

import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Foundation

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let outputURL = scriptDir.deletingLastPathComponent().appendingPathComponent("Resources/AppIcon.png")

// "Veil" (direction 9a from the icon canvas): the aperture — four concentric
// bands around a white core — sitting low on the tile with a vapor trail
// rising off it. Geometry is authored on the canvas's 50-unit grid; the vapor
// is rendered on its own layer and blurred there (the bands stay crisp).

let grid: CGFloat = 50
// The canvas prototype drew the artwork at 81% of the tile; filling more of
// it reads better in the Dock. 0.95 is the ceiling — the fringe band sits 2
// grid units off the bottom, so anything more crowds the squircle's curve.
let artworkFraction: CGFloat = 0.95
// The trail departs from the canvas's stacked ellipses, which float clear of
// the aperture and read as an arrowhead. It is one tapered plume instead,
// rising out of the fringe band and narrowing to a point, its alpha ramped by
// a clipped gradient. Blur is still what makes it vapor, just gentler — the
// gradient now carries the falloff the ellipse stack used it for.
let vaporBlurSigma: CGFloat = 2.0     // grid units
let vaporBaseRadius: CGFloat = 12.5   // the fringe band, so the plume starts buried
let vaporShoulder: CGFloat = 48       // degrees off vertical
let vaporTipY: CGFloat = 1.5
let vaporWaist: CGFloat = 0.14        // how far in the sides pinch below the tip

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// A drawing surface that speaks the canvas's coordinates: units on the
/// 50-unit grid, y running downwards from the top of the artwork box.
struct Canvas {
    let context: CGContext
    let scale: CGFloat
    let origin: CGPoint

    init(context: CGContext, pixelSize: CGFloat) {
        self.context = context
        scale = pixelSize * artworkFraction / grid
        let inset = (pixelSize - grid * scale) / 2
        origin = CGPoint(x: inset, y: inset)
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + (grid - y) * scale)
    }

    func length(_ units: CGFloat) -> CGFloat { units * scale }

    func ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, fill: CGColor) {
        let center = point(cx, cy)
        context.setFillColor(fill)
        context.fillEllipse(in: CGRect(
            x: center.x - length(rx), y: center.y - length(ry),
            width: length(rx) * 2, height: length(ry) * 2
        ))
    }

    func circle(cx: CGFloat, cy: CGFloat, r: CGFloat, stroke: CGColor, width: CGFloat) {
        context.setStrokeColor(stroke)
        context.setLineWidth(length(width))
        context.addArc(
            center: point(cx, cy), radius: length(r),
            startAngle: 0, endAngle: .pi * 2, clockwise: false
        )
        context.strokePath()
    }

    func disc(cx: CGFloat, cy: CGFloat, r: CGFloat, fill: CGColor) {
        context.setFillColor(fill)
        context.addArc(
            center: point(cx, cy), radius: length(r),
            startAngle: 0, endAngle: .pi * 2, clockwise: false
        )
        context.fillPath()
    }
}

func makeContext(pixelSize: Int) -> CGContext? {
    CGContext(
        data: nil,
        width: pixelSize, height: pixelSize,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

/// The vapor trail, drawn on a transparent layer of its own so it can be
/// blurred without touching the aperture bands it rises from.
func makeVaporLayer(pixelSize: Int) -> CGImage? {
    guard let context = makeContext(pixelSize: pixelSize) else { return nil }
    let canvas = Canvas(context: context, pixelSize: CGFloat(pixelSize))

    // The plume's base is an arc of the fringe band itself, so the trail and
    // the aperture are one continuous body rather than two stacked shapes.
    let center = canvas.point(25, 33)
    let base = canvas.length(vaporBaseRadius)
    let tip = canvas.point(25, vaporTipY)
    let shoulder = vaporShoulder * .pi / 180
    let flank = CGPoint(x: center.x + base * sin(shoulder), y: center.y + base * cos(shoulder))
    let rise = tip.y - flank.y
    let waist = center.x + (flank.x - center.x) * vaporWaist

    let plume = CGMutablePath()
    plume.addArc(
        center: center, radius: base,
        startAngle: .pi / 2 + shoulder, endAngle: .pi / 2 - shoulder, clockwise: true
    )
    plume.addCurve(
        to: tip,
        control1: CGPoint(x: flank.x, y: flank.y + rise * 0.45),
        control2: CGPoint(x: waist, y: tip.y - rise * 0.22)
    )
    plume.addCurve(
        to: CGPoint(x: 2 * center.x - flank.x, y: flank.y),
        control1: CGPoint(x: 2 * center.x - waist, y: tip.y - rise * 0.22),
        control2: CGPoint(x: 2 * center.x - flank.x, y: flank.y + rise * 0.45)
    )
    plume.closeSubpath()

    context.addPath(plume)
    context.clip()
    let vapor: (CGFloat) -> CGColor = { rgba(127, 227, 242, $0) }
    let ramp = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [vapor(1), vapor(0.70), vapor(0.35), vapor(0)] as CFArray,
        locations: [0, 0.35, 0.7, 1]
    )!
    context.drawLinearGradient(
        ramp,
        start: CGPoint(x: center.x, y: flank.y), end: CGPoint(x: center.x, y: tip.y),
        options: []
    )

    guard let layer = context.makeImage(), let blur = CIFilter(name: "CIGaussianBlur") else {
        return context.makeImage()
    }
    blur.setValue(CIImage(cgImage: layer), forKey: kCIInputImageKey)
    blur.setValue(canvas.length(vaporBlurSigma), forKey: kCIInputRadiusKey)
    guard let blurred = blur.outputImage else { return layer }

    // CIGaussianBlur grows the extent; crop back to the tile before compositing.
    let bounds = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    return CIContext().createCGImage(blurred, from: bounds)
}

func makeIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = makeContext(pixelSize: pixelSize) else { return nil }

    // Squircle mask (22.5% of the tile side).
    let cornerRadius = size * 0.225
    context.addPath(CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
        cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
    ))
    context.clip()

    // Base gradient, top to bottom: #25292A -> #171A1B (46%) -> #0C0E0E.
    let baseGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgba(0x25, 0x29, 0x2A), rgba(0x17, 0x1A, 0x1B), rgba(0x0C, 0x0E, 0x0E)] as CFArray,
        locations: [0, 0.46, 1]
    )!
    // CSS is top-down; CG's y axis runs bottom-up, so start/end are flipped.
    context.drawLinearGradient(
        baseGradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: []
    )

    // Cyan bloom behind the aperture, centred at 50% / 62% from the top.
    let bloomGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgba(78, 203, 223, 0.22), rgba(78, 203, 223, 0)] as CFArray,
        locations: [0, 1]
    )!
    let bloomCenter = CGPoint(x: size * 0.5, y: size * (1 - 0.62))
    context.drawRadialGradient(
        bloomGradient,
        startCenter: bloomCenter, startRadius: 0,
        endCenter: bloomCenter, endRadius: size * 0.66,
        options: []
    )

    if let vapor = makeVaporLayer(pixelSize: pixelSize) {
        context.draw(vapor, in: CGRect(x: 0, y: 0, width: size, height: size))
    }

    // Aperture: four concentric bands, centred low at cy 33.
    let canvas = Canvas(context: context, pixelSize: size)
    canvas.circle(cx: 25, cy: 33, r: 12.5, stroke: rgba(143, 227, 136, 0.28), width: 5)
    canvas.circle(cx: 25, cy: 33, r: 9.5, stroke: rgba(0x5B, 0xD6, 0xC0), width: 4.4)
    canvas.circle(cx: 25, cy: 33, r: 6.2, stroke: rgba(0x4E, 0xC5, 0xDF), width: 4)
    canvas.disc(cx: 25, cy: 33, r: 3.8, fill: rgba(255, 255, 255))

    guard let cgImage = context.makeImage() else { return nil }

    let mutableData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        mutableData, UTType.png.identifier as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return mutableData as Data
}

guard let data = makeIcon(pixelSize: 1024) else {
    print("Failed to render icon")
    exit(1)
}
try data.write(to: outputURL)
print("Wrote \(outputURL.path)")
