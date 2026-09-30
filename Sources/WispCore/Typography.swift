import AppKit
import SwiftUI

/// The three configured faces. A family that isn't installed falls back to the system face and
/// is named in the footer. Main-actor state, since the families come from the config at launch.
@MainActor
public enum Typography {
    /// Nil wherever the system face draws. Resolved once, since `NSFont(name:)` doesn't cache a
    /// miss and `ui(_:)` runs ~40 times per overlay render; a new font needs a relaunch.
    public private(set) static var notesFamily: String?
    public private(set) static var uiFamily: String?
    public private(set) static var codeFamily: String?

    /// Configured families that didn't resolve, for the footer.
    public private(set) static var missingFamilies: [String] = []

    /// Multiplies type sizes only; rules, padding, and the panel's proportions stay put.
    public private(set) static var scale: CGFloat = 1

    /// The one place the scale is applied; call sites pass design sizes.
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

    /// Bold and italic derive from this via symbolic traits.
    public static func notesFont(_ size: CGFloat) -> NSFont {
        let size = scaled(size)
        return notesFamily.flatMap { NSFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
    }

    /// Chrome face for text AppKit typesets, such as the help page. Always regular weight.
    public static func uiFont(_ size: CGFloat) -> NSFont {
        let size = scaled(size)
        return uiFamily.flatMap { NSFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
    }

    /// The face for a `` `code` `` run at an already-scaled size, so a span in a heading keeps
    /// the heading's size. Falls back to the system monospace, never the body face.
    public static func codeFont(atResolvedSize size: CGFloat) -> NSFont {
        codeFamily.flatMap { NSFont(name: $0, size: size) }
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// The code face at a design size, for raw mode's whole body.
    public static func codeFont(_ size: CGFloat) -> NSFont {
        codeFont(atResolvedSize: scaled(size))
    }

    // MARK: SwiftUI

    /// `tabularDigits` keeps numeric labels from reflowing. For a custom family it also turns off
    /// contextual alternates: the Inter Nerd Font's `calt` draws an icon for the colon in `12:34`.
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
