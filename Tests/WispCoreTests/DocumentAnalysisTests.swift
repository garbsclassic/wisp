import Foundation
import Testing

@testable import WispCore

@Suite("DocumentAnalysis")
struct DocumentAnalysisTests {
    @Test("Caret positions preserve legacy Unicode, CRLF, and clamping behavior")
    func caretPositionsMatchLegacySemantics() {
        let documents = [
            "",
            "first\r\nsecond\r\n",
            "# Café 👩🏽‍💻\r\n\r\n👨‍👩‍👧‍👦e\u{301}🇨🇦x",
            "---\r\ntitle: 🐈\r\n---\r\n\r\n## End",
        ]

        for text in documents {
            let analysis = DocumentAnalysis(text)
            let length = (text as NSString).length
            for offset in (-2)...(length + 2) {
                #expect(
                    analysis.caretPosition(at: offset) == CaretPosition(in: text, at: offset),
                    "Caret position mismatch at UTF-16 offset \(offset)")
            }
        }
    }

    @Test("One analysis exposes the document text, block classification, and headings")
    func analysisContainsSharedDocumentDerivations() {
        let text = """
            ---
            title: Sample
            ---

            # First 🐈
            prose

            Setext title
            ===
            ```md
            # Not a heading
            ```
            """
        let analysis = DocumentAnalysis(text)

        #expect(analysis.text == text)
        #expect(analysis.blocks.lines.count == 12)
        #expect(analysis.headings.map(\.name) == ["First 🐈", "Setext title"])
        #expect(analysis.headings.map(\.level) == [1, 1])
        #expect(analysis.headings == text.extractHeadings())
    }

    @Test("Code ranges are the analysis revision's ranges")
    func codeRangesCoverMarkdownCodeAndFrontmatter() {
        let text = """
            ---
            title: A note
            ---
            prose `inline` text
            ```swift
            let answer = 42
            ```
            """
        let analysis = DocumentAnalysis(text)
        let actual = analysis.codeRanges.map { (text as NSString).substring(with: $0) }

        #expect(
            actual == [
                "---\n", "title: A note\n", "---\n", "`inline`", "```swift\n",
                "let answer = 42\n", "```",
            ])
    }
}
