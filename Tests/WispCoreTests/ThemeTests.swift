import AppKit
import Testing

@testable import WispCore

private func luminance(_ c: NSColor) -> CGFloat {
    guard let rgb = c.usingColorSpace(.sRGB) else { return 0 }
    return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
}

/// Equal apart from alpha. `NSColor ==` compares across color spaces, and is false rather
/// than trapping on a semantic color.
private func sameHue(_ a: NSColor, _ b: NSColor) -> Bool {
    a.withAlphaComponent(1) == b.withAlphaComponent(1)
}

@Suite("Theme enums")
struct ThemeEnumTests {
    @Test("The footer button cycles light → dark → system")
    func cycle() {
        #expect(ThemeSetting.light.next == .dark)
        #expect(ThemeSetting.dark.next == .system)
        #expect(ThemeSetting.system.next == .light)
    }
}

@Suite("Metrics")
struct MetricsTests {
    @Test("The default scale sits inside the clamp range")
    func defaultInRange() {
        #expect(Metrics.fontScaleRange.contains(WispConfig().fontScale))
        #expect(Metrics.fontScaleRange.contains(WispConfig().defaultFontScale))
    }

    @Test("Clamping bounds a scale without moving one already in range")
    func clamping() {
        #expect(Metrics.clampFontScale(0.1) == Metrics.fontScaleRange.lowerBound)
        #expect(Metrics.clampFontScale(9) == Metrics.fontScaleRange.upperBound)
        #expect(Metrics.clampFontScale(1.05) == 1.05)
    }

    @Test("Stepping lands on the step grid rather than accumulating drift")
    func stepping() {
        var scale = 1.0
        for _ in 0..<3 { scale = Metrics.steppedFontScale(scale, by: 1) }
        // Unrounded, three steps give 1.3000000000000003, which lands in the config file.
        #expect(scale == 1.3)
        #expect(Metrics.steppedFontScale(scale, by: -3) == 1.0)
    }

    @Test("Stepping stops at the ends of the range")
    func steppingClamps() {
        #expect(Metrics.steppedFontScale(Metrics.fontScaleRange.upperBound, by: 1)
            == Metrics.fontScaleRange.upperBound)
        #expect(Metrics.steppedFontScale(Metrics.fontScaleRange.lowerBound, by: -1)
            == Metrics.fontScaleRange.lowerBound)
    }

    @Test("Six heading levels, `#` above body size, strictly shrinking")
    func headingRatios() {
        let ratios = Metrics.headingRatios
        #expect(ratios.count == 6)
        #expect(ratios[0] > 1)
        #expect(zip(ratios, ratios.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test("Each theme colours all six heading levels distinctly", arguments: Theme.allCases)
    func headingColors(theme: Theme) {
        let colors = Palette.for(theme).headings
        #expect(colors.count == Metrics.headingRatios.count)
        #expect(Set(colors.map(\.description)).count == colors.count)
    }
}

/// The relationships the design depends on, not the hex literals.
@Suite("Palette tokens")
struct PaletteTests {
    let dark = Palette.for(.dark)
    let light = Palette.for(.light)

    /// Device RGB paints the same literal differently on a P3 panel than on an sRGB one.
    @Test("Every token is sRGB, not device RGB", arguments: Theme.allCases)
    func colorSpace(theme: Theme) {
        let palette = Mirror(reflecting: Palette.for(theme)).children.flatMap { child in
            let colors = child.value as? [NSColor] ?? [child.value as? NSColor].compactMap { $0 }
            return colors.map { (child.label ?? "?", $0) }
        }
        #expect(!palette.isEmpty)
        for (name, color) in palette + [("tintColor", Chrome.for(theme).tintColor)] {
            #expect(color.colorSpace == .sRGB, "\(name) is \(color.colorSpace)")
        }
    }

    @Test("Surfaces read lighter than the panel behind them")
    func surfaceIsRaised() {
        #expect(luminance(dark.surface) > luminance(dark.panel))
        #expect(luminance(light.surface) > luminance(light.panel))
    }

    @Test("The light panel token matches the chrome tint it composites from")
    func lightPanelMatchesChrome() {
        #expect(luminance(light.panel) >= luminance(Chrome.for(.light).tintColor))
    }

    @Test("Selection washes the accent, the find match does not", arguments: [Theme.dark, .light])
    func selectionAndFind(theme: Theme) {
        let p = Palette.for(theme)
        #expect(sameHue(p.selection, p.accent))
        #expect(p.selection.alphaComponent < 1)
        #expect(!sameHue(p.findHighlight, p.accent))
        #expect(p.findHighlight.alphaComponent < 1)
    }

    @Test("Rules and borders are translucent", arguments: [Theme.dark, .light])
    func hairlines(theme: Theme) {
        let p = Palette.for(theme)
        #expect(p.rule.alphaComponent < 1)
        #expect(p.border.alphaComponent <= 0.15)
    }

    @Test("Danger never reads as an accent hint", arguments: [Theme.dark, .light])
    func dangerIsDistinct(theme: Theme) {
        let p = Palette.for(theme)
        #expect(!sameHue(p.danger, p.accent))
    }

    @Test("Text tiers stay ordered against their own background")
    func textTiers() {
        #expect(luminance(dark.panel) < luminance(dark.muted))
        #expect(luminance(dark.text) > luminance(dark.muted))
        #expect(luminance(light.text) < luminance(light.muted))
    }
}

@Suite("Chrome")
struct ChromeTests {
    @Test("Both tints stay translucent so vibrancy shows through")
    func translucentTint() {
        #expect(Chrome.for(.light).tintColor.alphaComponent < 1)
        #expect(Chrome.for(.dark).tintColor.alphaComponent < 1)
    }
}
