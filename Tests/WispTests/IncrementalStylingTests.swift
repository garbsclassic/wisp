import AppKit
import SwiftUI
import Testing
import WispCore

@testable import Wisp

@Suite("Incremental styling", .serialized)
@MainActor
struct IncrementalStylingTests {
    @Test("Inline styling stays equal to a full render through sequential edits")
    func inlineMarkupDifferentialAcrossSequentialEdits() throws {
        let style = bodyStyle()
        let harness = try makeHarness(
            text: "Lead placeholder tail\n\n- nearby list\n\n---\n\n# Nearby heading\n\n",
            style: style)
        defer { harness.window.close() }

        try edit(harness.textView, finding: "placeholder", replaceWith: inlineSample, style: style)
        try edit(
            harness.textView, finding: "double strike", replaceWith: "double ✨ strike",
            style: style)
        try edit(harness.textView, finding: "\\*escaped*", replaceWith: "*escaped*", style: style)
        try edit(harness.textView, finding: "tail", replaceWith: "", style: style)
    }

    @Test("Paste, deletion, undo, and redo all match a fresh full render")
    func editHistoryAndPasteDifferential() throws {
        let style = bodyStyle()
        let harness = try makeHarness(text: "plain word\nsecond paragraph\n", style: style)
        defer { harness.window.close() }
        let textView = harness.textView
        let storage = try #require(textView.textStorage)
        let undo = try #require(textView.undoManager)

        let word = (textView.string as NSString).range(of: "word")
        #expect(textView.replaceText(in: word, with: "**bold**"))
        expectFullRender(textView, style: style)

        undo.undo()
        expectFullRender(textView, style: style)
        undo.redo()
        expectFullRender(textView, style: style)

        NSPasteboard.general.clearContents()
        #expect(NSPasteboard.general.setString(" ~~pasted~~", forType: .string))
        textView.setSelectedRange(NSRange(location: storage.length, length: 0))
        textView.paste(nil)
        expectFullRender(textView, style: style)

        let deletion = (textView.string as NSString).range(of: "second ")
        #expect(textView.replaceText(in: deletion, with: ""))
        expectFullRender(textView, style: style)
    }

    @Test("Structural edits and line separator variants match a full render")
    func structuralAndSeparatorDifferential() throws {
        let style = bodyStyle()
        let scenarios: [(name: String, text: String, needle: String, replacement: String)] = [
            ("paragraph to list", "before\nordinary item\nrest\n", "ordinary item", "- item"),
            ("rule to paragraph", "before\n\n---\n\nafter\n", "---", "plain"),
            ("text to ATX heading", "before\nordinary heading\nrest\n", "ordinary heading",
             "# heading"),
            ("setext level change", "paragraph\n===\nnext\n", "===", "---"),
            ("fence removal", "before\n```\n# hidden\n```\nafter\n", "\n```\n# hidden",
             "\ntext\n# hidden"),
            ("frontmatter close removal", "---\ntitle: before\n---\nbody\n", "\n---\nbody",
             "\n...\nbody"),
            ("list continuation", "- item\n  # Heading\n  prose\n", "prose", "prose!"),
            ("CRLF prose", "first\r\nsecond word\r\nlast\r\n", "second", "**second**"),
            ("CR-only prose", "first\rsecond word\rthird", "second", "**second**"),
            ("Unicode line separators", "first\u{2028}second word\u{2029}last", "second",
             "**second**"),
        ]

        for scenario in scenarios {
            let harness = try makeHarness(text: scenario.text, style: style)
            let storage = try #require(harness.textView.textStorage)
            let range = (harness.textView.string as NSString).range(of: scenario.needle)
            #expect(range.location != NSNotFound, "Missing fixture text: \(scenario.name)")
            guard range.location != NSNotFound else {
                harness.window.close()
                continue
            }

            storage.replaceCharacters(in: range, with: scenario.replacement)
            let analysis = harness.textView.documentAnalysis()
            Editor.restyleAfterEdit(harness.textView, style: style, analysis: analysis)

            expectFullRender(harness.textView, style: style, label: scenario.name)
            #expect(harness.textView.styledAnalysis === analysis)
            #expect(harness.textView.pendingCharacterEdit == nil)
            harness.window.close()
        }
    }

    @Test("Multiple character notifications fall back to the full renderer")
    func multipleCharacterEditsDifferential() throws {
        let style = bodyStyle()
        let harness = try makeHarness(
            text: "first placeholder\nsecond placeholder\n", style: style)
        defer { harness.window.close() }
        let textView = harness.textView
        let storage = try #require(textView.textStorage)

        let first = (textView.string as NSString).range(of: "placeholder")
        storage.replaceCharacters(in: first, with: "**first**")
        let second = (textView.string as NSString).range(of: "placeholder")
        storage.replaceCharacters(in: second, with: "~~second~~")
        #expect(textView.hasMultipleCharacterEdits)

        let analysis = textView.documentAnalysis()
        Editor.restyleAfterEdit(textView, style: style, analysis: analysis)

        expectFullRender(textView, style: style)
        #expect(textView.styledAnalysis === analysis)
        #expect(!textView.hasMultipleCharacterEdits)
    }

    @Test("An ordinary prose edit leaves attributes on unrelated paragraphs untouched")
    func ordinaryEditDoesNotRewriteOtherParagraphs() throws {
        let style = bodyStyle()
        let harness = try makeHarness(
            text: "sentinel paragraph\neditable target\nlast paragraph\n", style: style)
        defer { harness.window.close() }
        let textView = harness.textView
        let storage = try #require(textView.textStorage)
        let sentinelRange = (textView.string as NSString).lineRange(
            for: NSRange(location: 0, length: 0))
        storage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: sentinelRange)
        let target = (textView.string as NSString).range(of: "target")
        storage.replaceCharacters(in: target, with: "**target**")
        let analysis = textView.documentAnalysis()

        Editor.restyleAfterEdit(textView, style: style, analysis: analysis)

        #expect(
            (storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?
                .isEqual(NSColor.systemPink) == true)
        let full = fullRender(of: textView.string, style: style)
        let targetLine = try #require(analysis.blocks.line(at: target.location))
        let actualTarget = storage.attributedSubstring(from: targetLine.range)
        let expectedTarget = full.attributedSubstring(from: targetLine.range)
        #expect(firstAttributeDifference(actualTarget, expectedTarget) == nil)
        #expect(textView.styledAnalysis === analysis)
    }

    @Test("Theme and source mode switches restore the full renderer's attributes")
    func styleSwitchesDifferential() throws {
        let initialStyle = bodyStyle()
        let harness = try makeHarness(
            text: "## Heading\nbody **bold** and ~~strike~~\n- list item\n---\n",
            style: initialStyle)
        defer { harness.window.close() }
        let textView = harness.textView

        let lightStyle = bodyStyle(theme: .light)
        Editor.restyle(textView, style: lightStyle)
        expectFullRender(textView, style: lightStyle, label: "light theme")

        let sourceStyle = bodyStyle(theme: .light, isSourceView: true)
        Editor.restyle(textView, style: sourceStyle)
        expectFullRender(textView, style: sourceStyle, label: "source mode")

        let restoredBodyStyle = bodyStyle(theme: .light)
        let range = (textView.string as NSString).range(of: "body")
        #expect(textView.replaceText(in: range, with: "body!"))
        let analysis = textView.documentAnalysis()
        Editor.restyleAfterEdit(textView, style: sourceStyle, analysis: analysis)
        expectFullRender(textView, style: sourceStyle, label: "edit in source mode")

        Editor.restyle(textView, style: restoredBodyStyle)
        expectFullRender(textView, style: restoredBodyStyle, label: "back to styled body")
    }

    @Test("Editor handoff preserves canonically equivalent Unicode with different UTF-16")
    func normalizedUnicodeRevisionIsAdopted() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let precomposed = "\u{00E9}"
        let decomposed = "e\u{0301}"
        #expect(precomposed == decomposed)
        #expect(!precomposed.utf16.elementsEqual(decomposed.utf16))
        let original = "prefix \(precomposed) suffix\n"
        let expected = "prefix \(decomposed) suffix\n"
        let model = try makeModel(in: root, initialText: original)
        let style = bodyStyle()
        let harness = try makeHarness(text: model.text, style: style, onEdit: model.acceptEdit)
        defer { harness.window.close() }
        let range = (harness.textView.string as NSString).range(of: precomposed)

        #expect(harness.textView.replaceText(in: range, with: decomposed))

        #expect(model.document === harness.textView.documentAnalysis())
        #expect(model.document.text.utf16.elementsEqual(expected.utf16))
        try model.flushSave()
    }
}

@MainActor
private struct StylingHarness {
    let textView: NotesTextView
    let window: NSWindow
    let coordinator: Editor.Coordinator
}

@MainActor
private func makeHarness(
    text: String, style: Editor.BodyStyle,
    onEdit: @escaping (DocumentAnalysis) -> Void = { _ in }
) throws -> StylingHarness {
    _ = NSApplication.shared
    let (scrollView, textView) = NotesTextView.makeScrollView()
    textView.string = text
    textView.allowsUndo = true
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
        styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = scrollView
    Editor.restyle(textView, style: style)
    let coordinator = Editor.Coordinator(
        onEdit: onEdit, caretOffset: Binding.constant(0), style: style)
    textView.delegate = coordinator
    return StylingHarness(textView: textView, window: window, coordinator: coordinator)
}

@MainActor
private func edit(
    _ textView: NotesTextView, finding needle: String, replaceWith replacement: String,
    style: Editor.BodyStyle
) throws {
    let range = (textView.string as NSString).range(of: needle)
    #expect(range.location != NSNotFound, "Missing fixture text: \(needle)")
    guard range.location != NSNotFound else { return }
    let storage = try #require(textView.textStorage)
    storage.replaceCharacters(in: range, with: replacement)
    let analysis = textView.documentAnalysis()
    Editor.restyleAfterEdit(textView, style: style, analysis: analysis)
    expectFullRender(textView, style: style, label: needle)
    #expect(textView.styledAnalysis === analysis)
}

@MainActor
private func bodyStyle(theme: Theme = .dark, isSourceView: Bool = false) -> Editor.BodyStyle {
    Editor.BodyStyle(
        theme: theme, fontScale: 1, fonts: FontSet(), indent: Indent(),
        isSourceView: isSourceView, rule: .line)
}

@MainActor
private func makeModel(in root: URL, initialText: String) throws -> EditorModel {
    _ = NSApplication.shared
    let folder = root.appendingPathComponent("notes", isDirectory: true)
    let configURL = root.appendingPathComponent("config/wisp.jsonc")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try initialText.write(
        to: StorageLocation.scratchpadURL(in: folder), atomically: true, encoding: .utf8)
    try ConfigStore.write(WispConfig(scratchpadFolder: folder.path), at: configURL)
    return EditorModel(settings: Wisp.Settings(configFileURL: configURL))
}

@MainActor
private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WispIncrementalStyling-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@MainActor
private func fullRender(of text: String, style: Editor.BodyStyle) -> NSTextStorage {
    let storage = NSTextStorage(string: text)
    Editor.restyleStorage(storage, style: style, analysis: DocumentAnalysis(text))
    return storage
}

@MainActor
private func expectFullRender(
    _ textView: NotesTextView, style: Editor.BodyStyle, label: String = "edit"
) {
    let actual = textView.textStorage!
    let expected = fullRender(of: textView.string, style: style)
    let mismatch = firstAttributeDifference(actual, expected)
    #expect(mismatch == nil, "\(label) differs from full render at UTF-16 offset \(mismatch ?? -1)")
}

private func firstAttributeDifference(
    _ actual: NSAttributedString, _ expected: NSAttributedString
) -> Int? {
    guard actual.string == expected.string else { return -1 }
    guard actual.length == expected.length else { return min(actual.length, expected.length) }
    for offset in 0..<actual.length {
        let left = NSDictionary(dictionary: actual.attributes(at: offset, effectiveRange: nil))
        let right = NSDictionary(dictionary: expected.attributes(at: offset, effectiveRange: nil))
        if !left.isEqual(right) { return offset }
    }
    return nil
}

private let inlineSample =
    "plain **bold** __strong__ *italic* _emphasis_ `code` <u>under</u> "
    + "~~double strike~~ ~single strike~ ==mark== \\*escaped* "
    + "*️⃣ keycap 🇨🇦 👩🏽‍💻"
