import AppKit
import SwiftUI

public enum Theme: String, CaseIterable, Sendable {
    case dark
    case light
}

/// The config's `theme`; `.system` follows the app's effective appearance.
public enum ThemeSetting: String, Codable, CaseIterable, Sendable {
    case light
    case dark
    case system

    /// The footer button's cycle.
    public var next: ThemeSetting {
        switch self {
        case .light: return .dark
        case .dark: return .system
        case .system: return .light
        }
    }

    @MainActor public func resolve() -> Theme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? .dark : .light
        }
    }
}

public func rgb(_ hex: UInt32, _ alpha: CGFloat = 1.0) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
        green: CGFloat((hex >> 8) & 0xFF) / 255.0,
        blue: CGFloat(hex & 0xFF) / 255.0,
        alpha: alpha
    )
}

/// Colour tokens: Flexoki Dark and Modernist Light.
public struct Palette {
    /// Body text. Flexoki `tx` / Modernist `ink`.
    public let text: NSColor
    /// Secondary text on modal surfaces. Flexoki `tx-2` / Modernist `muted`.
    public let muted: NSColor
    /// Syntax to look past, such as an escape's backslash. Flexoki `tx-3` / Modernist `ui-2`.
    public let faint: NSColor
    /// Error text, distinct from `accent` so an error never reads as a hint.
    public let danger: NSColor
    /// What the live panel composites to, so modal backdrops match it.
    public let panel: NSColor
    /// Raised chips such as the find bar; lighter than `panel`, or a chip reads as a recess.
    public let surface: NSColor
    /// The header and footer bars. Flexoki `bg-2`.
    public let chrome: NSColor
    /// Caret, selection, save dot, help labels, heading links. Flexoki cyan / Modernist vermilion.
    public let accent: NSColor
    public let indicator: NSColor
    /// Hairline rules. Translucent, since an opaque one washes out over a light wallpaper.
    public let rule: NSColor
    /// Panel frame and chip borders.
    public let border: NSColor
    public let selection: NSColor
    /// The current find match: amber, so it stays distinct from the accent-tinted selection.
    public let findHighlight: NSColor
    /// `==marked==` text. Its own token apart from `findHighlight`, since content and UI state
    /// may diverge.
    public let highlight: NSColor
    /// One colour per level, `#` first: Flexoki's hue ramp, 400s on dark and 600s on light, since
    /// Modernist has too few hues.
    public let headings: [NSColor]

    public static func `for`(_ theme: Theme) -> Palette {
        switch theme {
        case .dark:
            // Flexoki Dark — warm greys, cyan accent.
            return Palette(
                text: rgb(0xCECDC3),
                muted: rgb(0x7D7C78),
                faint: rgb(0x575653),
                danger: rgb(0xD14D41),
                panel: rgb(0x1C1B1A),
                surface: rgb(0x282726),
                chrome: rgb(0x1C1B1A),
                accent: rgb(0x3AA99F),
                indicator: rgb(0xD7AE7F),
                rule: rgb(0xCECDC3, 0.32),
                border: rgb(0xCECDC3, 0.10),
                selection: rgb(0x3AA99F, 0.20),
                findHighlight: rgb(0xD0A215, 0.38),
                highlight: rgb(0xD0A215, 0.24),
                headings: [
                    rgb(0xD14D41), rgb(0xDA702C), rgb(0xD0A215),
                    rgb(0x879A39), rgb(0x4385BE), rgb(0x8B7EC8),
                ]
            )
        case .light:
            // Modernist Light.
            return Palette(
                text: rgb(0x161413),
                muted: rgb(0x4B4949),
                faint: rgb(0x6A685E),
                danger: rgb(0xAF3029),
                panel: rgb(0xF0EFEF),
                surface: rgb(0xF7F6F6),
                chrome: rgb(0xE6E4E1),
                accent: rgb(0xEC3013),
                indicator: rgb(0x558A86),
                rule: rgb(0x201E1D, 0.18),
                border: rgb(0x201E1D, 0.12),
                selection: rgb(0xEC3013, 0.14),
                findHighlight: rgb(0xD0A215, 0.50),
                highlight: rgb(0xD0A215, 0.34),
                headings: [
                    rgb(0xAF3029), rgb(0xBC5215), rgb(0xAD8301),
                    rgb(0x66800B), rgb(0x205EA6), rgb(0x5E409D),
                ]
            )
        }
    }
}

/// Window tokens for AppKit: blur material, tint, and the appearance system controls follow.
public struct Chrome {
    public let material: NSVisualEffectView.Material
    public let tintColor: NSColor
    public let appearance: NSAppearance.Name

    public static func `for`(_ theme: Theme) -> Chrome {
        switch theme {
        case .dark:
            // Warm black rather than pure, so the blur sits with the palette.
            return Chrome(
                material: .fullScreenUI,
                tintColor: rgb(0x100F0F, 0.55),
                appearance: .darkAqua
            )
        case .light:
            // Composites over .windowBackground to #F0EFEF (measured), which
            // `Palette.light.panel` records; keep the two in step.
            return Chrome(
                material: .windowBackground,
                tintColor: rgb(0xE8E6E6, 0.75),
                appearance: .aqua
            )
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    // Computed, so this is a resolver rather than shared global state.
    public static var defaultValue: Palette { Palette.for(.dark) }
}

extension EnvironmentValues {
    /// Set once on the panel's root view, for every view below.
    public var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Type sizes and the geometry derived from them, at design size: `Typography` applies the scale.
public enum Metrics {
    // MARK: Notes body

    public static let bodySize: CGFloat = 15
    /// Heading size off the body, indexed by `level - 1`. The ramp is shallow because
    /// `Palette.headings` carries the tier.
    public static let headingRatios: [CGFloat] = [1.08, 1.06, 1.04, 1.02, 1, 0.98]
    /// Generous leading — this is a writing surface, not a dense list.
    public static let bodyLineHeightMultiple: CGFloat = 1.40

    // MARK: Chrome

    /// Header, footer, and the incidental hint lines in the overlays.
    public static let chromeSize: CGFloat = 13
    /// Secondary overlay labels, such as chord names.
    public static let labelSize: CGFloat = 14
    /// Overlay rows and the find field: chrome meant to be read.
    public static let rowSize: CGFloat = 15
    /// The single large string in the hotkey-capture overlay.
    public static let titleSize: CGFloat = 21

    /// The save dot, small enough to read as a status light.
    public static let saveIndicatorSize: CGFloat = 6

    /// The header and footer insets, which the save dot shares.
    public static let chromeInsetX: CGFloat = 24
    public static let chromeInsetY: CGFloat = 10

    /// Centres the dot on the header text rather than on its line box's top.
    public static var saveIndicatorTopInset: CGFloat {
        chromeInsetY + (chromeLineHeight - saveIndicatorSize) / 2
    }

    /// Approximate: 1.2 is the usual ratio at UI sizes, close enough to centre the dot.
    public static var chromeLineHeight: CGFloat { chromeSize * 1.2 }

    /// Keeps a long heading list clear of the save dot: its inset, the dot, and about an em.
    public static var headerTrailingInset: CGFloat {
        chromeInsetX + saveIndicatorSize + chromeSize + 2
    }

    /// A fixed box, so the footer's spacing doesn't rag as icons change.
    public static let footerButtonWidth: CGFloat = 24
    public static let footerButtonHeight: CGFloat = 20

    // MARK: Help page

    // The page reuses `chromeInsetX` and `chromeInsetY`, so its column lands on the note's when
    // they crossfade. The first label's gap is the container inset, since AppKit doesn't reliably
    // honour `paragraphSpacingBefore` on a first paragraph; the inset also pads the last row.

    /// The design's 172px gutter and 22px gap, as multiples of the row size so they scale.
    public static let helpKeyColumnRatio: CGFloat = 172.0 / 14.5
    public static let helpColumnGapRatio: CGFloat = 22.0 / 14.5
    /// Section labels against the row size, same reasoning.
    public static let helpSectionLabelRatio: CGFloat = 10.5 / 14.5
    /// Letter-spacing on those labels, as a fraction of their own size.
    public static let helpSectionTracking: CGFloat = 0.16

    /// Half the design's 10pt row gap, paid once below a row and once above the next.
    public static let helpRowSpacing: CGFloat = 5

    // MARK: Font scale

    /// One press of ⌘= / ⌘- or one click of a footer button.
    public static let fontScaleStep: Double = 0.1
    /// Bounded so a typo or a held key can't leave the app unreadable.
    public static let fontScaleRange: ClosedRange<Double> = 0.6...2.5

    /// Only stepping snaps to `fontScaleStep`; a hand-edited value is kept as written.
    public static func clampFontScale(_ scale: Double) -> Double {
        min(max(scale, fontScaleRange.lowerBound), fontScaleRange.upperBound)
    }

    private static let stepsPerUnit: Double = 1 / fontScaleStep

    /// Counts whole steps and divides at the end: `12 * 0.1` is 1.2000000000000002, but `12 / 10`
    /// prints as 1.2 in the config.
    public static func steppedFontScale(_ scale: Double, by steps: Int) -> Double {
        let grid = (scale * stepsPerUnit).rounded() + Double(steps)
        return clampFontScale(grid / stepsPerUnit)
    }
}
