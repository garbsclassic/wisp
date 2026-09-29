import AppKit
import SwiftUI

/// Font resolution for the three configured faces. Each is either a family
/// name or nil for the system's own — SF Pro for notes and chrome, SF Mono
/// for code — and a named family that isn't installed falls back to the same
/// system face, with the footer saying which one didn't resolve.
///
/// Configured once at launch from `fonts` and `fontScale`, then read from
/// everywhere. `@MainActor` rather than immutable because the families come
/// from the config file, which isn't known until the app has started.
@MainActor
public enum Typography {
    /// The families actually in use: nil wherever the system face draws,
    /// whether by choice or because the configured one isn't installed.
    ///
    /// Resolved at configure time rather than per call: `NSFont(name:)`
    /// costs ~2µs on a hit and ~12µs on a miss with no negative caching,
    /// and `ui(_:)` is called ~40 times per overlay body evaluation. A
    /// font activated mid-session needs a relaunch to be picked up.
    public private(set) static var notesFamily: String?
    public private(set) static var uiFamily: String?
    public private(set) static var codeFamily: String?

    /// The configured families that didn't resolve, for the footer warning.
    /// Fonts are referenced by name and never bundled, so this is a real
    /// case rather than a defensive one.
    public private(set) static var missingFamilies: [String] = []

    /// Multiplies every type size and nothing else — rules, padding, and
    /// the panel's own proportions are untouched, so a dense display can be
    /// made readable without redrawing the layout.
    public private(set) static var scale: CGFloat = 1

    /// Point sizes at the current scale. The single place the scale is
    /// applied — call sites keep passing their design sizes.
    static func scaled(_ size: CGFloat) -> CGFloat { size * scale }

    public static func configure(fonts: FontSet, scale: Double) {
        var missing: [String] = []
        func resolve(_ family: String?) -> String? {
            guard let family else { return nil }
            guard NSFont(name: family, size: 12) != nil else {
                missing.append(family)
                return nil
            }
            return family
        }
        notesFamily = resolve(fonts.notes)
        uiFamily = resolve(fonts.ui)
        codeFamily = resolve(fonts.code)
        missingFamilies = missing
        self.scale = CGFloat(scale)
    }

    // MARK: AppKit

    /// Body face for the NSTextView. Bold and italic derive from this base
    /// via symbolic traits.
    public static func notesFont(_ size: CGFloat) -> NSFont {
        let size = scaled(size)
        return notesFamily.flatMap { NSFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
    }

    /// Chrome face for the places that typeset with AppKit rather than
    /// SwiftUI — the help page, whose rows live in an `NSTextView`. Weight
    /// is not a parameter: a custom family carries it in the family name,
    /// and everything drawn through this is regular.
    public static func uiFont(_ size: CGFloat) -> NSFont {
        let size = scaled(size)
        return uiFamily.flatMap { NSFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
    }

    /// The face for a `` `code` `` run, at whatever size the surrounding
    /// text is already using — a span inside a heading keeps the heading's
    /// size. The system face here is the system *monospace*, not the body
    /// face: code set as plain prose is the one thing the markers are there
    /// to deny.
    ///
    /// The size arrives already scaled, since it comes off a resolved font
    /// rather than from a `Metrics` constant.
    public static func codeFont(atResolvedSize size: CGFloat) -> NSFont {
        codeFamily.flatMap { NSFont(name: $0, size: size) }
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// The code face at a *design* size, scaled the way `notesFont` is — for
    /// raw mode, where the whole body is set in it rather than one span
    /// inside prose. The `atResolvedSize` overload above takes an
    /// already-scaled size, since it reads one off a resolved font.
    public static func codeFont(_ size: CGFloat) -> NSFont {
        codeFont(atResolvedSize: scaled(size))
    }

    // MARK: SwiftUI

    /// UI face at a SwiftUI size/weight. `tabularDigits` keeps numeric
    /// labels from reflowing as their digits change — the system face has
    /// its own tabular figures, and a custom family is asked for `tnum`.
    ///
    /// With `tnum` on, a custom family also turns contextual alternates off.
    /// Inter's `calt` swaps the colon between two digits for a raised one,
    /// and the Nerd Font build's table for that points at an icon glyph —
    /// `12:34` drew a globe where the colon should be.
    /// Only the tabular path is affected, and only there is the feature
    /// worth losing.
    public static func ui(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        tabularDigits: Bool = false
    ) -> Font {
        let size = scaled(size)
        guard let uiFamily else {
            let base = Font.system(size: size, weight: weight)
            return tabularDigits ? base.monospacedDigit() : base
        }
        guard tabularDigits else { return Font.custom(uiFamily, size: size).weight(weight) }

        let features: [[NSFontDescriptor.FeatureKey: Int]] = [
            [.typeIdentifier: kNumberSpacingType, .selectorIdentifier: kMonospacedNumbersSelector],
            [.typeIdentifier: kContextualAlternatesType,
             .selectorIdentifier: kContextualAlternatesOffSelector],
        ]
        let descriptor = NSFontDescriptor(fontAttributes: [.family: uiFamily])
            .addingAttributes([.featureSettings: features])
        guard let resolved = NSFont(descriptor: descriptor, size: size) else {
            return Font.custom(uiFamily, size: size).weight(weight).monospacedDigit()
        }
        return Font(resolved).weight(weight)
    }
}
