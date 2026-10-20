import AppKit
import SwiftUI
import Testing
import WispCore

@testable import Wisp

@Suite("Resource usage regressions", .serialized)
@MainActor
struct ResourceUsageTests {
    @Test("Panel visibility follows repeated summon and hide for the footer clock")
    func footerClockVisibility() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (settings, model, _) = try makeModel(in: root, initialText: "saved note")
        let frame = UserDefaults.standard.object(forKey: "PanelFrame")
        defer {
            if let frame { UserDefaults.standard.set(frame, forKey: "PanelFrame") }
            else { UserDefaults.standard.removeObject(forKey: "PanelFrame") }
        }
        let panel = PanelController(model: model, settings: settings)
        #expect(!model.isPanelVisible)
        for _ in 0..<3 {
            panel.openIfNeeded()
            #expect(model.isPanelVisible)
            panel.dismiss()
            #expect(!model.isPanelVisible)
        }
    }

    @Test("Unchanged assignment preserves the analysis; edit handoff adopts its revision")
    func modelReusesAnalysisForUnchangedTextAndAcceptsEditRevision() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model, _) = try makeModel(in: root, initialText: "# Before")
        let loaded = model.document

        model.text = model.text
        #expect(model.document === loaded)

        let edited = DocumentAnalysis("# After\nbody")
        model.acceptEdit(edited)
        #expect(model.document === edited)
        #expect(model.text == edited.text)
        #expect(model.headings == edited.headings)
        try model.flushSave()
    }

    @Test("External replacement installs a new document analysis")
    func externalReplacementRebuildsAnalysis() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model, folder) = try makeModel(in: root, initialText: "# Before")
        let old = model.document
        try "# External 🐈\nnew body".write(
            to: StorageLocation.scratchpadURL(in: folder), atomically: true, encoding: .utf8)

        model.reloadFromDiskIfChanged(force: true)

        #expect(model.document !== old)
        #expect(model.document.text == "# External 🐈\nnew body")
        #expect(model.headings.map(\.name) == ["External 🐈"])
    }

    @Test("Find dismissal clears derived matches and keeps the query")
    func dismissFindReleasesMatchState() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model, _) = try makeModel(in: root, initialText: "needle then needle")
        model.openFind()
        model.findQuery = "needle"
        model.findNext()
        #expect(model.findMatchCount == 2)
        #expect(model.findCurrentDisplayIndex == 2)

        model.dismissFind()

        #expect(!model.showFind)
        #expect(model.findMatchCount == 0)
        #expect(model.findCurrentDisplayIndex == 0)
        #expect(model.findHighlightRange == NSRange(location: 0, length: 0))
        #expect(model.findQuery == "needle")
    }

    @Test("Text view reuses an analysis until paste, undo, and replacement mutate characters")
    func textViewAnalysisCacheTracksCharacterMutations() throws {
        _ = NSApplication.shared
        let (scrollView, textView) = NotesTextView.makeScrollView()
        let window = makeWindow(content: scrollView)
        defer { window.close() }
        textView.allowsUndo = true
        textView.smartPaste = false
        textView.string = "base"

        let original = textView.documentAnalysis()
        #expect(textView.documentAnalysis() === original)
        #expect(textView.replaceText(in: NSRange(location: 4, length: 0), with: " edit"))
        let edited = textView.documentAnalysis()
        #expect(edited !== original)
        #expect(edited.text == "base edit")

        let undoManager = try #require(textView.undoManager)
        undoManager.undo()
        let undone = textView.documentAnalysis()
        #expect(undone !== edited)
        #expect(undone.text == "base")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        #expect(pasteboard.setString(" paste", forType: .string))
        textView.setSelectedRange(
            NSRange(location: (textView.string as NSString).length, length: 0))
        textView.paste(nil)
        let pasted = textView.documentAnalysis()
        #expect(pasted !== undone)
        #expect(pasted.text == "base paste")

        textView.string = "replacement"
        let replaced = textView.documentAnalysis()
        #expect(replaced !== pasted)
        #expect(replaced.text == "replacement")
    }

    @Test("Renumbering publishes the final document analysis to the text view")
    func coordinatorPublishesPostRenumberAnalysis() throws {
        _ = NSApplication.shared
        let (scrollView, textView) = NotesTextView.makeScrollView()
        let window = makeWindow(content: scrollView)
        defer { window.close() }
        let style = Editor.BodyStyle(
            theme: .dark, fontScale: 1, fonts: FontSet(), indent: Indent(),
            isSourceView: false, rule: .line)
        var published: DocumentAnalysis?
        var caret = 0
        let coordinator = Editor.Coordinator(
            onEdit: { published = $0 },
            caretOffset: Binding(get: { caret }, set: { caret = $0 }), style: style)
        textView.delegate = coordinator
        textView.string = "1. first\n2. second\n3. third\n"
        let middleStart = ("1. first\n" as NSString).length
        let middleLength = ("2. second\n" as NSString).length

        #expect(
            textView.replaceText(
                in: NSRange(location: middleStart, length: middleLength), with: ""))

        #expect(textView.string == "1. first\n2. third\n")
        let final = try #require(published)
        #expect(final.text == textView.string)
        #expect(textView.documentAnalysis() === final)
    }

    @Test("Find highlighting stays temporary and is cleared after an edit")
    func findHighlightDoesNotReplaceMarkdownBackground() throws {
        _ = NSApplication.shared
        let (_, textView) = NotesTextView.makeScrollView()
        textView.string = "before ==marked== after"
        let style = Editor.BodyStyle(
            theme: .dark, fontScale: 1, fonts: FontSet(), indent: Indent(),
            isSourceView: false, rule: .line)
        Editor.restyle(textView, style: style)
        let storage = try #require(textView.textStorage)
        let layoutManager = try #require(textView.layoutManager)
        let text = textView.string as NSString
        let marked = text.range(of: "marked")
        let match = text.range(of: "before")
        let palette = Palette.for(.dark)
        let storedBackground = storage.attribute(
            .backgroundColor, at: marked.location, effectiveRange: nil)

        Editor.applyFindHighlight(to: textView, range: match, theme: .dark, scroll: false)

        #expect((storedBackground as? NSColor)?.isEqual(palette.highlight) == true)
        #expect(
            (storage.attribute(.backgroundColor, at: marked.location, effectiveRange: nil)
                as? NSColor)?.isEqual(palette.highlight) == true)
        #expect(
            (layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: match.location,
                effectiveRange: nil) as? NSColor)?.isEqual(palette.findHighlight) == true)

        let end = (textView.string as NSString).length
        #expect(textView.replaceText(in: NSRange(location: end, length: 0), with: "!"))
        #expect(
            layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: match.location,
                effectiveRange: nil) == nil)
        #expect(
            (storage.attribute(.backgroundColor, at: marked.location, effectiveRange: nil)
                as? NSColor)?.isEqual(palette.highlight) == true)
    }
}

@MainActor
private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WispResourceUsageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@MainActor
private func makeModel(
    in root: URL, initialText: String
) throws -> (Wisp.Settings, EditorModel, URL) {
    let folder = root.appendingPathComponent("notes", isDirectory: true)
    let configURL = root.appendingPathComponent("config/wisp.jsonc")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try initialText.write(
        to: StorageLocation.scratchpadURL(in: folder), atomically: true, encoding: .utf8)
    try ConfigStore.write(WispConfig(scratchpadFolder: folder.path), at: configURL)
    _ = NSApplication.shared
    let settings = Settings(configFileURL: configURL)
    return (settings, EditorModel(settings: settings), folder)
}

@MainActor
private func makeWindow(content: NSView) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
        styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = content
    return window
}
