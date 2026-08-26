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
enum Typography {
    /// Notes body, icon glyphs at a fixed advance (`InterNF-*` faces).
    static let notesFamily = "Inter Nerd Font"
    /// Proportional Nerd Font for UI text (`InterNFP-*` faces).
    static let uiFamily = "Inter Nerd Font Propo"

    // Resolved once at first use rather than per call: `NSFont(name:)`
    // costs ~2µs on a hit and ~12µs on a miss with no negative caching,
    // and `ui(_:)` is called ~40 times per overlay body evaluation. A
    // font activated mid-session needs a relaunch to be picked up.
    static let notesInstalled = NSFont(name: notesFamily, size: 12) != nil
    static let uiInstalled = NSFont(name: uiFamily, size: 12) != nil

    // MARK: AppKit

    /// Body face for the NSTextView. Falls back to system sans when the
    /// Nerd Font is missing — never returns nil. Bold and italic derive
    /// from this base via symbolic traits, same as before the swap.
    static func notesFont(_ size: CGFloat) -> NSFont {
        NSFont(name: notesFamily, size: size) ?? .systemFont(ofSize: size)
    }

    /// UI face for AppKit call sites — the About panel's credits block.
    static func uiFont(_ size: CGFloat) -> NSFont {
        NSFont(name: uiFamily, size: size) ?? .systemFont(ofSize: size)
    }

    // MARK: SwiftUI

    /// Bridges the AppKit resolver rather than re-resolving, so the
    /// empty-state placeholder can't land in a different face than the
    /// text view it sits on top of.
    static func notes(_ size: CGFloat) -> Font {
        Font(notesFont(size))
    }

    /// UI face at a SwiftUI size/weight. `tabularDigits` keeps numeric
    /// labels from reflowing as their digits change — Inter ships `tnum`,
    /// and the system fallback has its own tabular figures.
    static func ui(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        tabularDigits: Bool = false
    ) -> Font {
        let base = uiInstalled
            ? Font.custom(uiFamily, size: size).weight(weight)
            : .system(size: size, weight: weight)

        return tabularDigits ? base.monospacedDigit() : base
    }
}
