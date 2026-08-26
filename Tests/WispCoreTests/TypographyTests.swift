import AppKit
import Testing

@testable import WispCore

@Suite("Typography", .serialized)
@MainActor
struct TypographyTests {
    @Test("The families default to the Nerd Font pair")
    func families() {
        #expect(Typography.notesFamily == "Inter Nerd Font")
        #expect(Typography.uiFamily == "Inter Nerd Font Propo")
    }

    /// Every size goes through one multiplier, so a display that needs
    /// everything a notch bigger doesn't need the layout redrawn.
    @Test("Configuring applies the families and scales every size")
    func configuring() {
        defer { Typography.configure(fonts: FontSet(), scale: 1) }
        Typography.configure(fonts: FontSet(notes: "Helvetica", ui: "Menlo"), scale: 1.5)
        #expect(Typography.notesFamily == "Helvetica")
        #expect(Typography.notesFont(20).pointSize == 30)
        #expect(Typography.uiFont(20).pointSize == 30)
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

    @Test("A resolved face keeps the requested size")
    func sizes() {
        #expect(Typography.notesFont(20).pointSize == 20)
        #expect(Typography.uiFont(20).pointSize == 20)
    }

    /// Fonts are referenced by name, never bundled, so both branches are
    /// real: on a machine without the Nerd Font installed the fallback has
    /// to be the one that resolves.
    @Test("Resolution either finds the Nerd Font or falls back off it")
    func resolution() {
        let body = Typography.notesFont(20)
        if Typography.notesInstalled {
            #expect(body.familyName == "Inter Nerd Font")
        } else {
            #expect(body.familyName != "Inter Nerd Font")
        }
    }

    /// Heading styling and ⌘B derive scaled bold from the base descriptor.
    /// A face that came back non-bold would silently unbold every heading.
    @Test("Bold derives off the base descriptor at the requested size")
    func boldDerivation() throws {
        let body = Typography.notesFont(20)
        let derived = try #require(
            NSFont(descriptor: body.fontDescriptor.withSymbolicTraits(.bold), size: 24)
        )
        #expect(derived.pointSize == 24)
        #expect(derived.fontDescriptor.symbolicTraits.contains(.bold))
    }
}
