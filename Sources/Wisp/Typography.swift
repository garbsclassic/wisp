import AppKit
import SwiftUI

/// Font resolution for the Inter Nerd Font pairing. The notes body uses
/// the fixed-width family so Nerd Font icon glyphs column-align; chrome
/// text uses the Propo (proportional) variant, which reads naturally in
/// UI. Neither is bundled — they are referenced by family name, and
/// every resolver falls back to the system sans, which is the default
/// experience on machines without them installed.
enum Typography {
    /// Fixed-width Nerd Font for the notes body (`InterNF-*` faces).
    static let notesFamily = "Inter Nerd Font"
    /// Proportional Nerd Font for UI text (`InterNFP-*` faces).
    static let uiFamily = "Inter Nerd Font Propo"

    static var notesInstalled: Bool { NSFont(name: notesFamily, size: 12) != nil }
    static var uiInstalled: Bool { NSFont(name: uiFamily, size: 12) != nil }

    // MARK: AppKit

    /// Body face for the NSTextView. Falls back to system sans when the
    /// Nerd Font is missing — never returns nil. Bold and italic derive
    /// from this base via symbolic traits, same as before the swap.
    static func notesFont(_ size: CGFloat) -> NSFont {
        NSFont(name: notesFamily, size: size) ?? .systemFont(ofSize: size)
    }

    // MARK: SwiftUI

    static func notes(_ size: CGFloat) -> Font {
        notesInstalled ? .custom(notesFamily, size: size) : .system(size: size)
    }

    /// UI face at a SwiftUI size/weight. Monospaced-design requests map
    /// to the fixed-width notes family so keycap-style labels keep the
    /// Nerd Font glyphs; everything else takes the Propo variant.
    static func ui(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        monospaced: Bool = false
    ) -> Font {
        if monospaced {
            return notesInstalled
                ? Font.custom(notesFamily, size: size).weight(weight)
                : .system(size: size, weight: weight, design: .monospaced)
        }
        return uiInstalled
            ? Font.custom(uiFamily, size: size).weight(weight)
            : .system(size: size, weight: weight)
    }
}
