import AppKit
import Testing

@testable import WispCore

@Suite("Typography", .serialized)
@MainActor
struct TypographyTests {
    /// `FontSet()` is what every field defaults to, so nothing here should
    /// ever be reported missing or resolve to a custom family.
    @Test("The default FontSet resolves to no custom family, and falls back correctly")
    func defaultsToTheSystemFace() {
        defer { Typography.configure(fonts: FontSet(), scale: 1) }
        Typography.configure(fonts: FontSet(), scale: 1)

        #expect(Typography.notesFamily == nil)
        #expect(Typography.uiFamily == nil)
        #expect(Typography.codeFamily == nil)
        #expect(Typography.missingFamilies.isEmpty)
        #expect(Typography.notesFont(13).familyName == NSFont.systemFont(ofSize: 13).familyName)
        #expect(
            Typography.codeFont(atResolvedSize: 13).fontDescriptor.symbolicTraits
                .contains(.monoSpace))
    }

    /// The one face with a real fallback of its own: code that quietly
    /// renders as prose has lost the only thing the backticks were for.
    @Test("An unresolved code family still lands on a monospace")
    func codeFallsBackToMonospace() {
        defer { Typography.configure(fonts: FontSet(), scale: 1) }
        Typography.configure(fonts: FontSet(code: "No Such Face"), scale: 1)

        let font = Typography.codeFont(atResolvedSize: 16)
        #expect(font.pointSize == 16)
        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(Typography.missingFamilies == ["No Such Face"])
    }

    /// The size arrives already scaled — it comes off a resolved font, not
    /// off a `Metrics` constant, so scaling it again would compound.
    @Test("The code face at a design size is scaled like the body's")
    func codeFontScales() {
        Typography.configure(fonts: FontSet(), scale: 2)
        defer { Typography.configure(fonts: FontSet(), scale: 1) }
        #expect(Typography.codeFont(16).pointSize == 32)
        // The `atResolvedSize` overload is the unscaled one; raw mode passes a
        // design size and needs the scale applied, same as the body face.
        #expect(Typography.codeFont(atResolvedSize: 16).pointSize == 16)
    }

    /// Every size goes through one multiplier, so a display that needs
    /// everything a notch larger doesn't need the layout redrawn.
    @Test("Configuring applies the families and scales every size")
    func configuring() {
        defer { Typography.configure(fonts: FontSet(), scale: 1) }
        Typography.configure(fonts: FontSet(notes: "Helvetica", ui: "Menlo"), scale: 1.5)
        #expect(Typography.notesFamily == "Helvetica")
        #expect(Typography.notesFont(20).pointSize == 30)
    }

    /// Fonts are referenced by name and never bundled, so a family that
    /// isn't installed has to be nameable in the footer rather than just
    /// silently falling back.
    @Test("A family that doesn't resolve is reported by name")
    func missingFamilies() {
        defer { Typography.configure(fonts: FontSet(), scale: 1) }
        Typography.configure(fonts: FontSet(notes: "No Such Face", ui: "Menlo"), scale: 1)
        #expect(Typography.missingFamilies == ["No Such Face"])
    }
}
