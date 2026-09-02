import AppKit
import Testing

@testable import WispCore

/// Relative luminance, for the "is this lighter than that" checks.
private func luminance(_ c: NSColor) -> CGFloat {
    guard let rgb = c.usingColorSpace(.sRGB) else { return 0 }
    return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
}

/// Same hue, ignoring alpha — for "is this a wash of that".
private func sameHue(_ a: NSColor, _ b: NSColor) -> Bool {
    a.withAlphaComponent(1) == b.withAlphaComponent(1)
}

@Suite("Theme enums")
struct ThemeEnumTests {
    /// Raw values are the storage format, so they have to stay compatible
    /// with what earlier versions wrote.
    @Test("Raw values are the stored strings")
    func rawValues() {
        #expect(Theme.dark.rawValue == "dark")
        #expect(Theme.light.rawValue == "light")
        #expect(ThemePreference.light.rawValue == "light")
        #expect(ThemePreference.dark.rawValue == "dark")
        #expect(ThemePreference.system.rawValue == "system")
    }

    @Test("The footer button cycles light → dark → system")
    func cycle() {
        #expect(ThemePreference.light.next == .dark)
        #expect(ThemePreference.dark.next == .system)
        #expect(ThemePreference.system.next == .light)
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
        // The point of rounding onto the grid: 1.0 + 0.1 + 0.1 + 0.1 in
        // binary floating point is 1.3000000000000003, and this value gets
        // written into a config a person reads.
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

    @Test("Headings step up off the body, largest first")
    func headingRatios() {
        #expect(Metrics.headingLevel1Ratio > Metrics.headingLevel2Ratio)
        #expect(Metrics.headingLevel2Ratio > 1)
    }
}

/// These assert the *relationships* the design depends on, not the hex
/// literals — restating a literal two files from where it's declared
/// catches nothing and turns every retune into a two-file edit.
///
/// `NSColor`'s own `==` is used deliberately: it compares across color
/// spaces, where component-wise comparison would call a device-RGB and an
/// sRGB color equal, and it returns false on a semantic color instead of
/// trapping.
@Suite("Palette tokens")
struct PaletteTests {
    let dark = Palette.for(.dark)
    let light = Palette.for(.light)

    /// Device components are consumed unconverted, so the same literal
    /// paints differently on a P3 panel than on an sRGB monitor.
    @Test("Tokens are pinned to sRGB, not device RGB")
    func colorSpace() {
        #expect(dark.accent == rgb(0x4E_CB_DF))
        #expect(light.accent == rgb(0xEC_30_13))
        #expect(
            dark.accent
                != NSColor(
                    deviceRed: 0x4E / 255.0, green: 0xCB / 255.0, blue: 0xDF / 255.0, alpha: 1
                )
        )
    }

    /// Chips are raised, so they read lighter than the paper behind them.
    /// Inverting this makes a find bar look like a recess.
    @Test("Surfaces read lighter than the panel behind them")
    func surfaceIsRaised() {
        #expect(luminance(dark.surface) > luminance(dark.panel))
        #expect(luminance(light.surface) > luminance(light.panel))
    }

    /// The light panel is a translucent tint over vibrancy; `panel` has to
    /// record what that composites to, or modal backdrops step over the
    /// live panel instead of matching it.
    @Test("The light panel token matches the chrome tint it composites from")
    func lightPanelMatchesChrome() {
        #expect(luminance(light.panel) >= luminance(Chrome.for(.light).tintColor))
    }

    /// Selection is an accent wash; the find match is deliberately a
    /// different hue, so the current match stays tellable from a selection
    /// sitting next to it.
    @Test("Selection washes the accent, the find match does not", arguments: [Theme.dark, .light])
    func selectionAndFind(theme: Theme) {
        let p = Palette.for(theme)
        #expect(sameHue(p.selection, p.accent))
        #expect(p.selection.alphaComponent < 1)
        #expect(!sameHue(p.findHighlight, p.accent))
        #expect(p.findHighlight.alphaComponent < 1)
    }

    /// Rules and borders sit on vibrancy whose luminance tracks the
    /// desktop, so they have to be alpha rather than opaque.
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
    /// An opaque tint would paint over the vibrancy view and kill the blur
    /// entirely — the bug this pins down.
    @Test("Both tints stay translucent so vibrancy shows through")
    func translucentTint() {
        #expect(Chrome.for(.light).tintColor.alphaComponent < 1)
        #expect(Chrome.for(.dark).tintColor.alphaComponent < 1)
    }

    @Test("Each theme carries its matching system appearance")
    func appearance() {
        #expect(Chrome.for(.light).appearance == .aqua)
        #expect(Chrome.for(.dark).appearance == .darkAqua)
    }
}
