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
// rising off it. Geometry is authored on the canvas's 50-unit grid, which
// fills 81% of the tile; the vapor is rendered on its own layer and blurred
// as one body (the bands stay crisp).

let grid: CGFloat = 50
let artworkFraction: CGFloat = 0.8125  // 52pt of artwork in a 64pt tile
let vaporBlurSigma: CGFloat = 2.4      // feGaussianBlur stdDeviation, grid units

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

/// The vapor trail, drawn on a transparent layer of its own so the whole
/// group can be blurred together — that shared blur is what fuses the five
/// ellipses into one body instead of a stack of rings.
func makeVaporLayer(pixelSize: Int) -> CGImage? {
    guard let context = makeContext(pixelSize: pixelSize) else { return nil }
    let canvas = Canvas(context: context, pixelSize: CGFloat(pixelSize))
    let vapor: (CGFloat) -> CGColor = { rgba(127, 227, 242, $0) }

    canvas.ellipse(cx: 25,   cy: 18.6, rx: 11.2, ry: 6.4, fill: vapor(0.34))
    canvas.ellipse(cx: 24.8, cy: 13.4, rx: 8,    ry: 5.2, fill: vapor(0.28))
    canvas.ellipse(cx: 25.4, cy: 8.8,  rx: 5.4,  ry: 4.2, fill: vapor(0.21))
    canvas.ellipse(cx: 25,   cy: 4.8,  rx: 3.4,  ry: 3.2, fill: vapor(0.15))
    canvas.ellipse(cx: 25.2, cy: 1.8,  rx: 2,    ry: 2,   fill: vapor(0.09))

    // Faint directional core: M25 18 C22.6 14.4, 26.6 12, 25 8.6
    let path = CGMutablePath()
    path.move(to: canvas.point(25, 18))
    path.addCurve(
        to: canvas.point(25, 8.6),
        control1: canvas.point(22.6, 14.4), control2: canvas.point(26.6, 12)
    )
    context.addPath(path)
    context.setStrokeColor(rgba(0xDD, 0xF7, 0xFC, 0.5))
    context.setLineWidth(canvas.length(2.6))
    context.setLineCap(.round)
    context.strokePath()

    guard let layer = context.makeImage() else { return nil }

    let sigma = canvas.length(vaporBlurSigma)
    guard let blur = CIFilter(name: "CIGaussianBlur") else { return layer }
    blur.setValue(CIImage(cgImage: layer), forKey: kCIInputImageKey)
    blur.setValue(sigma, forKey: kCIInputRadiusKey)
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
