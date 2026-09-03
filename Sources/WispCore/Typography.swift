import AppKit
import SwiftUI

/// Font resolution for the Inter Nerd Font pairing. Notes are set in the
/// non-Propo family, whose Nerd Font icon glyphs share one advance so
/// they column-align; chrome text takes the Propo variant. Both families
/// are proportional for Latin text — the suffix only describes icon
/// width — so numeric labels ask for `tabularDigits` rather than a
/// monospaced design. Neither font is bundled; both resolve by family
/// name and fall back to the system sans, which is the default
/// experience on machines without them installed.
/// Configured once at launch from `fonts` and `fontScale`, then read from
/// everywhere. `@MainActor` rather than immutable because the families come
/// from the config file, which isn't known until the app has started.
@MainActor
public enum Typography {
    /// Notes body, icon glyphs at a fixed advance (`InterNF-*` faces).
    public private(set) static var notesFamily = FontSet().notes
    /// Proportional Nerd Font for UI text (`InterNFP-*` faces).
    public private(set) static var uiFamily = FontSet().ui

    // Resolved at configure time rather than per call: `NSFont(name:)`
    // costs ~2µs on a hit and ~12µs on a miss with no negative caching,
    // and `ui(_:)` is called ~40 times per overlay body evaluation. A
    // font activated mid-session needs a relaunch to be picked up.
    public private(set) static var notesInstalled = NSFont(name: notesFamily, size: 12) != nil
    public private(set) static var uiInstalled = NSFont(name: uiFamily, size: 12) != nil

    /// Multiplies every type size and nothing else — rules, padding, and
    /// the panel's own proportions are untouched, so a dense display can be
    /// made readable without redrawing the layout.
    public private(set) static var scale: CGFloat = 1

    /// The configured families that didn't resolve, for the footer warning.
    /// Fonts are referenced by name and never bundled, so this is a real
    /// case rather than a defensive one.
    public static var missingFamilies: [String] {
        (notesInstalled ? [] : [notesFamily]) + (uiInstalled ? [] : [uiFamily])
    }

    /// Point sizes at the current scale. The single place the scale is
    /// applied — call sites keep passing their design sizes.
    static func scaled(_ size: CGFloat) -> CGFloat { size * scale }

    public static func configure(fonts: FontSet, scale: Double) {
        notesFamily = fonts.notes
        uiFamily = fonts.ui
        notesInstalled = NSFont(name: notesFamily, size: 12) != nil
        uiInstalled = NSFont(name: uiFamily, size: 12) != nil
        self.scale = CGFloat(scale)
    }

    // MARK: AppKit

    /// Body face for the NSTextView. Falls back to system sans when the
    /// Nerd Font is missing — never returns nil. Bold and italic derive
    /// from this base via symbolic traits, same as before the swap.
    public static func notesFont(_ size: CGFloat) -> NSFont {
        let size = scaled(size)
        return NSFont(name: notesFamily, size: size) ?? .systemFont(ofSize: size)
    }

    /// Chrome face for the places that typeset with AppKit rather than
    /// SwiftUI — the help page, whose rows live in an `NSTextView`. Weight
    /// is not a parameter: the custom family carries it in the family name,
    /// and everything drawn through this is regular.
    public static func uiFont(_ size: CGFloat) -> NSFont {
        let size = scaled(size)
        return NSFont(name: uiFamily, size: size) ?? .systemFont(ofSize: size)
    }

    // MARK: SwiftUI

    /// Bridges the AppKit resolver rather than re-resolving, so the
    /// empty-state placeholder can't land in a different face than the
    /// text view it sits on top of.
    public static func notes(_ size: CGFloat) -> Font {
        Font(notesFont(size))
    }

    /// UI face at a SwiftUI size/weight. `tabularDigits` keeps numeric
    /// labels from reflowing as their digits change — Inter ships `tnum`,
    /// and the system fallback has its own tabular figures.
    public static func ui(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        tabularDigits: Bool = false
    ) -> Font {
        let size = scaled(size)
        let base = uiInstalled
            ? Font.custom(uiFamily, size: size).weight(weight)
            : .system(size: size, weight: weight)

        return tabularDigits ? base.monospacedDigit() : base
    }
}
