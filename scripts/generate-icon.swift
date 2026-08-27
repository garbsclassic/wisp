// Generates Resources/AppIcon.png for Wisp.
// Run with: swift scripts/generate-icon.swift
// Output: Resources/AppIcon.png (1024x1024, pre-shaped with transparent
// corners — build.sh resizes it into an .iconset via sips, no Xcode needed).

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let outputURL = scriptDir.deletingLastPathComponent().appendingPathComponent("Resources/AppIcon.png")

// "Aperture": concentric rings — pale green, mint, cyan, white core — on a
// dark squircle with a cyan glow. Design settled in the Wisp/Clef icon
// canvas (option 3c); rings and background stops are lifted verbatim from
// there, scaled off a 64pt reference box.
func makeIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Squircle mask (border-radius: 14.4px on a 64px box in the reference).
    let cornerRadius = size * (14.4 / 64)
    let squircle = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
        cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
    )
    context.addPath(squircle)
    context.clip()

    // Base gradient, top to bottom: #25292A -> #171A1B (46%) -> #0C0E0E.
    let baseColors = [
        CGColor(red: 0x25 / 255, green: 0x29 / 255, blue: 0x2A / 255, alpha: 1),
        CGColor(red: 0x17 / 255, green: 0x1A / 255, blue: 0x1B / 255, alpha: 1),
        CGColor(red: 0x0C / 255, green: 0x0E / 255, blue: 0x0E / 255, alpha: 1),
    ]
    let baseGradient = CGGradient(
        colorsSpace: colorSpace, colors: baseColors as CFArray, locations: [0, 0.46, 1]
    )!
    // CSS is top-down; CG's y axis runs bottom-up, so start/end are flipped.
    context.drawLinearGradient(
        baseGradient,
        start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0),
        options: []
    )

    // Cyan glow, centered slightly above middle (50% / 48% from top).
    let glowColors = [
        CGColor(red: 78 / 255, green: 203 / 255, blue: 223 / 255, alpha: 0.20),
        CGColor(red: 78 / 255, green: 203 / 255, blue: 223 / 255, alpha: 0),
    ]
    let glowGradient = CGGradient(
        colorsSpace: colorSpace, colors: glowColors as CFArray, locations: [0, 1]
    )!
    let glowCenter = CGPoint(x: size * 0.5, y: size * (1 - 0.48))
    context.drawRadialGradient(
        glowGradient,
        startCenter: glowCenter, startRadius: 0,
        endCenter: glowCenter, endRadius: size * 0.64,
        options: []
    )

    // Rings, defined in the reference's 50pt glyph box (centered in the
    // 64pt icon box, so scale = size / 64 and center stays size/2).
    let k = size / 64
    let center = CGPoint(x: size / 2, y: size / 2)

    func ring(radius: CGFloat, width: CGFloat, color: CGColor) {
        context.setStrokeColor(color)
        context.setLineWidth(width * k)
        context.addArc(
            center: center, radius: radius * k,
            startAngle: 0, endAngle: .pi * 2, clockwise: false
        )
        context.strokePath()
    }

    ring(
        radius: 21, width: 7,
        color: CGColor(red: 143 / 255, green: 227 / 255, blue: 136 / 255, alpha: 0.28)
    )
    ring(radius: 16.5, width: 5.5, color: CGColor(red: 0x5B / 255, green: 0xD6 / 255, blue: 0xC0 / 255, alpha: 1))
    ring(radius: 11, width: 5, color: CGColor(red: 0x4E / 255, green: 0xC5 / 255, blue: 0xDF / 255, alpha: 1))

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.addArc(center: center, radius: 7 * k, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.fillPath()

    guard let cgImage = context.makeImage() else { return nil }

    let mutableData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        mutableData,
        UTType.png.identifier as CFString,
        1,
        nil
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
