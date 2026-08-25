import AppKit

enum Theme: String, CaseIterable {
    case dark
    case light
}

/// User-facing appearance preference. Persisted in UserDefaults under
/// the "Theme" key. Raw values "light"/"dark" are deliberately the same
/// as Theme's so a stored value from the pre-system-mode era still
/// loads correctly. `.system` resolves at runtime against
/// NSApp.effectiveAppearance.
enum ThemePreference: String, CaseIterable {
    case light
    case dark
    case system

    /// One-click cycle wired into the BottomBar button.
    var next: ThemePreference {
        switch self {
        case .light: return .dark
        case .dark: return .system
        case .system: return .light
        }
    }

    @MainActor func resolve() -> Theme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? .dark : .light
        }
    }
}

private func rgb(_ hex: UInt32, _ alpha: CGFloat = 1.0) -> NSColor {
    NSColor(
        deviceRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
        green: CGFloat((hex >> 8) & 0xFF) / 255.0,
        blue: CGFloat(hex & 0xFF) / 255.0,
        alpha: alpha
    )
}

/// Text-surface tokens. Dark is Flexoki Dark, light is Modernist Light
/// (colors only — Wisp keeps its own rounded, blurred posture). Every
/// color a view draws comes from here; nothing hardcodes a hex.
struct Palette {
    /// Body text. Flexoki `tx` / Modernist `ink`.
    let text: NSColor
    /// Secondary text on modal surfaces. Flexoki `tx-2` / Modernist `muted`.
    let muted: NSColor
    /// Panel background behind modal backdrops. Flexoki `bg-2` /
    /// Modernist `panel`. The live panel itself is Chrome's job.
    let panel: NSColor
    /// Raised chips: find bar, update card. Flexoki `ui` / Modernist `surface`.
    let surface: NSColor
    /// The single accent, used sparingly — caret, selection, find match.
    /// Flexoki cyan / Modernist vermilion.
    let accent: NSColor
    /// 1px incidental rules, including the horizontal-rule glyph.
    /// Flexoki `ui-3` / Modernist `row-rule`.
    let rule: NSColor
    /// Panel frame and chip borders. Flexoki `ui-2` / Modernist `rule`.
    let border: NSColor
    /// Selection background. Accent-tinted per theme.
    let selection: NSColor
    /// Background drawn behind the current Find match (temporary layout
    /// attribute). Accent at a wash so words stay readable through it.
    let findHighlight: NSColor

    static func `for`(_ theme: Theme) -> Palette {
        switch theme {
        case .dark:
            // Flexoki Dark — warm greys, cyan accent.
            return Palette(
                text: rgb(0xCECDC3),
                muted: rgb(0x7D7C78),
                panel: rgb(0x1C1B1A),
                surface: rgb(0x282726),
                accent: rgb(0x4ECBDF),
                rule: rgb(0x403E3C),
                border: rgb(0x343331),
                selection: rgb(0x4ECBDF, 0.20),
                findHighlight: rgb(0x4ECBDF, 0.28)
            )
        case .light:
            // Modernist Light — near-black ink on warm paper, vermilion
            // accent kept for caret and matches only.
            return Palette(
                text: rgb(0x161413),
                muted: rgb(0x4B4949),
                panel: rgb(0xE8E6E6),
                surface: rgb(0xEAE9E9),
                accent: rgb(0xEC3013),
                rule: rgb(0x201E1D, 0.18),
                border: rgb(0x201E1D),
                selection: rgb(0xEC3013, 0.14),
                findHighlight: rgb(0xEC3013, 0.18)
            )
        }
    }
}

/// Window-chrome tokens feeding AppKit: blur material, tint layer, and
/// the NSAppearance that makes system controls and semantic colors agree
/// with the palette. Kept separate from Palette because they have
/// different types and different consumers.
struct Chrome {
    let material: NSVisualEffectView.Material
    let tintColor: NSColor
    let appearance: NSAppearance.Name

    static func `for`(_ theme: Theme) -> Chrome {
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
            // wash so the blur stays alive in both themes, while the
            // #E8E6E6 fill keeps the panel reading as the palette.
            return Chrome(
                material: .windowBackground,
                tintColor: rgb(0xE8E6E6, 0.75),
                appearance: .aqua
            )
        }
    }
}
