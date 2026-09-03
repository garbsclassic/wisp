import AppKit
import SwiftUI

public enum Theme: String, CaseIterable, Sendable {
    case dark
    case light
}

/// User-facing appearance preference. Persisted in UserDefaults under
/// the "Theme" key. Raw values "light"/"dark" are deliberately the same
/// as Theme's so a stored value from the pre-system-mode era still
/// loads correctly. `.system` resolves at runtime against
/// NSApp.effectiveAppearance.
public enum ThemePreference: String, Codable, CaseIterable, Sendable {
    case light
    case dark
    case system

    /// One-click cycle wired into the BottomBar button.
    public var next: ThemePreference {
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

/// Text-surface tokens. Dark is Flexoki Dark, light is Modernist Light
/// (colors only — Wisp keeps its own rounded, blurred posture). Views
/// draw their colors from here; the exception left on AppKit semantic
/// colors is the first-run dot.
public struct Palette {
    /// Body text. Flexoki `tx` / Modernist `ink`.
    public let text: NSColor
    /// Secondary text on modal surfaces. Flexoki `tx-2` / Modernist `muted`.
    public let muted: NSColor
    /// Failure text — hotkey registration errors. Flexoki red; distinct
    /// from `accent` so an error never reads as a hint.
    public let danger: NSColor
    /// The paper the live panel composites to, so modal backdrops paint
    /// the same tone rather than stepping over it. See Chrome.for(.light).
    public let panel: NSColor
    /// Raised chips: find bar, update card. Always lighter than `panel`
    /// in both themes, or a chip reads as a recess.
    public let surface: NSColor
    /// The header and footer bars. Flexoki `bg-2`, whose whole job in that
    /// palette is "surfaces: cards, sidebars, modals" — which is what the
    /// chrome bars are relative to the writing area they frame.
    public let chrome: NSColor
    /// The single accent, used sparingly — caret and selection only.
    /// Flexoki cyan / Modernist vermilion.
    public let accent: NSColor
    /// 1px incidental rules, including the horizontal-rule glyph. Alpha,
    /// not opaque: the panel is vibrancy whose luminance tracks the
    /// desktop, so an opaque rule washes out over a light wallpaper.
    public let rule: NSColor
    /// Panel frame and chip borders — a hairline, not a structural rule.
    public let border: NSColor
    /// Selection background. Accent-tinted per theme.
    public let selection: NSColor
    /// Background behind the current Find match. Amber in both themes so
    /// it stays distinguishable from an accent-tinted selection.
    public let findHighlight: NSColor
    /// Background behind `==marked==` text. A marker-pen yellow, and a
    /// token of its own rather than a reuse of `findHighlight`: one is
    /// content the user wrote and the other is transient UI state, so
    /// they should be free to diverge. They read alike today, which is
    /// survivable because only the *current* find match is painted and
    /// the view scrolls to it.
    public let highlight: NSColor

    public static func `for`(_ theme: Theme) -> Palette {
        switch theme {
        case .dark:
            // Flexoki Dark — warm greys, cyan accent.
            return Palette(
                text: rgb(0xCECDC3),
                muted: rgb(0x7D7C78),
                danger: rgb(0xD14D41),
                panel: rgb(0x1C1B1A),
                surface: rgb(0x282726),
                chrome: rgb(0x1C1B1A),
                accent: rgb(0x4ECBDF),
                rule: rgb(0xCECDC3, 0.32),
                border: rgb(0xCECDC3, 0.10),
                selection: rgb(0x4ECBDF, 0.20),
                findHighlight: rgb(0xD0A215, 0.38),
                highlight: rgb(0xD0A215, 0.24)
            )
        case .light:
            // Modernist Light — near-black ink on warm paper, vermilion
            // accent kept for the caret and selection only.
            return Palette(
                text: rgb(0x161413),
                muted: rgb(0x4B4949),
                danger: rgb(0xAF3029),
                panel: rgb(0xF0EFEF),
                surface: rgb(0xF7F6F6),
                chrome: rgb(0xE6E4E1),
                accent: rgb(0xEC3013),
                rule: rgb(0x201E1D, 0.18),
                border: rgb(0x201E1D, 0.12),
                selection: rgb(0xEC3013, 0.14),
                findHighlight: rgb(0xD0A215, 0.50),
                highlight: rgb(0xD0A215, 0.34)
            )
        }
    }
}

/// Window-chrome tokens feeding AppKit: blur material, tint layer, and
/// the NSAppearance that makes system controls and semantic colors agree
/// with the palette. Kept separate from Palette because they have
/// different types and different consumers.
public struct Chrome {
    public let material: NSVisualEffectView.Material
    public let tintColor: NSColor
    public let appearance: NSAppearance.Name

    public static func `for`(_ theme: Theme) -> Chrome {
        switch theme {
        case .dark:
            // Warm-black glass over the Flexoki bg tone rather than pure
            // black, so the blur reads with the palette instead of against it.
            return Chrome(
                material: .fullScreenUI,
                tintColor: rgb(0x100F0F, 0.55),
                appearance: .darkAqua
            )
        case .light:
            // Modernist paper over vibrancy: the tint is a translucent
            // wash so the blur stays alive in both themes. It composites
            // over .windowBackground to #F0EFEF (measured), which is
            // what Palette.light.panel records — keep the two in step,
            // or modal backdrops step over the live panel.
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
    /// Set once on the panel's root view. Every view below reads its
    /// colors from here rather than taking a `theme` parameter and
    /// resolving a Palette of its own.
    public var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Every type size Wisp draws with, plus the geometry that derives from
/// one. Sizes are *design* sizes: `Typography` multiplies them by the
/// live font scale on the way out, so nothing here is pre-scaled.
///
/// Named by role rather than by value — `chromeSize` survives 11 becoming
/// 12, `size11` renames itself the first time that happens.
public enum Metrics {
    // MARK: Notes body

    /// The notes body at scale 1.0. Was `FontSize.medium` before the
    /// three-step enum and the continuous scale were merged into one
    /// control, so a default config renders exactly as it used to.
    public static let bodySize: CGFloat = 16
    /// `#` and `##` step up off the body; `###` and below are bold at
    /// body size, which is enough to read as a heading without a
    /// six-level ramp that runs out of headroom.
    public static let headingLevel1Ratio: CGFloat = 1.20
    public static let headingLevel2Ratio: CGFloat = 1.10
    /// Generous leading — this is a writing surface, not a dense list.
    public static let bodyLineHeightMultiple: CGFloat = 1.45

    // MARK: Chrome

    /// Header, footer, and the incidental hint lines in the overlays.
    public static let chromeSize: CGFloat = 14
    /// Secondary labels inside an overlay — chord names, the find field's
    /// leading glyph.
    public static let labelSize: CGFloat = 15
    /// Overlay row text and the find field itself: the one chrome size
    /// meant to be read rather than glanced at.
    public static let rowSize: CGFloat = 16
    /// The single large string in the hotkey-capture overlay.
    public static let titleSize: CGFloat = 21

    /// Footer buttons are pinned to a fixed box rather than sized by
    /// their glyph, so the row's spacing doesn't rag as icons change.
    /// The save dot. Small enough to read as a status light rather than a
    /// control — the fork's original dot at this spot was clickable, and
    /// anything larger invites the same reading.
    public static let saveIndicatorSize: CGFloat = 6

    /// The header and footer bars' own insets, and the save dot's, so the
    /// dot lines up with the chrome it sits in rather than with the panel
    /// edge.
    public static let chromeInsetX: CGFloat = 24
    public static let chromeInsetY: CGFloat = 12

    /// Where the save dot's top edge goes, so the dot's centre lands on
    /// the header text's rather than on its line-box top.
    ///
    /// Matching `chromeInsetY` outright looks wrong: padding aligns the top
    /// of the *line box*, but glyphs start below it, so the dot measured
    /// 7pt high of the text it was meant to sit beside. Half the leftover
    /// line height puts it back.
    public static var saveIndicatorTopInset: CGFloat {
        chromeInsetY + (chromeLineHeight - saveIndicatorSize) / 2
    }

    /// A chrome line's rendered height. The 1.2 is the usual ratio for a
    /// text face at UI sizes — close enough to centre a 6pt dot against,
    /// and it tracks `chromeSize` where a literal would not.
    public static var chromeLineHeight: CGFloat { chromeSize * 1.2 }

    /// How far the header stops short of the panel's right edge: the dot's
    /// own inset, the dot, and a gap. Without it a long heading list runs
    /// underneath the indicator.
    public static var headerTrailingInset: CGFloat {
        chromeInsetX + saveIndicatorSize + 8
    }

    public static let footerButtonWidth: CGFloat = 24
    public static let footerButtonHeight: CGFloat = 20

    // MARK: Font scale

    /// One press of ⌘= / ⌘- or one click of a footer button.
    public static let fontScaleStep: Double = 0.1
    /// Bounded so a typo in the config — or a key held down — can't leave
    /// the app unreadable at either end.
    public static let fontScaleRange: ClosedRange<Double> = 0.6...2.5

    /// The scale clamped into range. A hand-edited value is kept as
    /// written — only stepping snaps to `fontScaleStep`.
    public static func clampFontScale(_ scale: Double) -> Double {
        min(max(scale, fontScaleRange.lowerBound), fontScaleRange.upperBound)
    }

    /// How many steps make up a scale of 1.0. The step is expressed as a
    /// whole number of these rather than as `fontScaleStep` so the
    /// arithmetic below can stay in integers until the last moment.
    private static let stepsPerUnit: Double = 1 / fontScaleStep

    /// `scale` moved by `steps` increments.
    ///
    /// Counts in whole steps and *divides* at the end. Adding 0.1 repeatedly
    /// drifts (1.0999999999999999); so does snapping to the grid and then
    /// multiplying back, which is what this did first — `12 * 0.1` is
    /// 1.2000000000000002, a different double from `12 / 10`. Only the
    /// division lands on the double that prints as "1.2", and this value is
    /// written into a config a person has to read.
    public static func steppedFontScale(_ scale: Double, by steps: Int) -> Double {
        let grid = (scale * stepsPerUnit).rounded() + Double(steps)
        return clampFontScale(grid / stepsPerUnit)
    }
}
