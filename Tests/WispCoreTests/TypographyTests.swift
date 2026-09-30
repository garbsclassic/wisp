import AppKit
import Testing

@testable import WispCore

@Suite("Typography", .serialized)
@MainActor
struct TypographyTests {
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

    @Test("An unresolved code family still lands on a monospace")
    func codeFallsBackToMonospace() {
        defer { Typography.configure(fonts: FontSet(), scale: 1) }
        Typography.configure(fonts: FontSet(code: "No Such Face"), scale: 1)

        let font = Typography.codeFont(atResolvedSize: 16)
        #expect(font.pointSize == 16)
        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(Typography.missingFamilies == ["No Such Face"])
    }

    @Test("The code face at a design size is scaled like the body's")
    func codeFontScales() {
        Typography.configure(fonts: FontSet(), scale: 2)
        defer { Typography.configure(fonts: FontSet(), scale: 1) }
        #expect(Typography.codeFont(16).pointSize == 32)
        // `atResolvedSize` takes a size that is already scaled.
        #expect(Typography.codeFont(atResolvedSize: 16).pointSize == 16)
    }

    @Test("Configuring applies the families and scales every size")
    func configuring() {
        defer { Typography.configure(fonts: FontSet(), scale: 1) }
        Typography.configure(fonts: FontSet(notes: "Helvetica", ui: "Menlo"), scale: 1.5)
        #expect(Typography.notesFamily == "Helvetica")
        #expect(Typography.notesFont(20).pointSize == 30)
    }

    @Test("A family that doesn't resolve is reported by name")
    func missingFamilies() {
        defer { Typography.configure(fonts: FontSet(), scale: 1) }
        Typography.configure(fonts: FontSet(notes: "No Such Face", ui: "Menlo"), scale: 1)
        #expect(Typography.missingFamilies == ["No Such Face"])
    }
}
