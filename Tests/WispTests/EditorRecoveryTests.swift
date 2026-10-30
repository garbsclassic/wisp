import AppKit
import SwiftUI
import Testing
import WispCore

@testable import Wisp

@Suite("Editor recovery and undo", .serialized)
@MainActor
struct EditorRecoveryTests {
    @Test("An unreadable startup stays read-only until refresh succeeds")
    func unreadableStartupCanRecover() throws {
        let root = try recoveryTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("notes", isDirectory: true)
        let noteURL = StorageLocation.scratchpadURL(in: folder)
        try FileManager.default.createDirectory(at: noteURL, withIntermediateDirectories: true)
        try "blocks file read".write(
            to: noteURL.appendingPathComponent("child"), atomically: true, encoding: .utf8)
        let (model, _) = try recoveryModel(in: root, folder: folder)
        let mounted = try mountEditor(model)
        defer { mounted.window.close() }

        #expect(!model.isEditable)
        #expect(!mounted.textView.isEditable)
        model.text = "must be rejected"
        #expect(model.text.isEmpty)
        #expect(!model.hasPendingSave)

        try FileManager.default.removeItem(at: noteURL)
        try "repaired note".write(to: noteURL, atomically: true, encoding: .utf8)
        model.reloadFromDiskIfChanged(force: true)

        #expect(model.isEditable)
        #expect(model.text == "repaired note")
        #expect(hostedUpdate(mounted.host) { mounted.textView.isEditable })
        let end = (mounted.textView.string as NSString).length
        #expect(mounted.textView.replaceText(in: NSRange(location: end, length: 0), with: "!"))
        try model.flushSave()
        #expect(try String(contentsOf: noteURL, encoding: .utf8) == "repaired note!")
    }

    @Test("A failed reload blocks edits and custom actions until a later refresh")
    func failedReloadPreservesBufferAndCanRecover() throws {
        let root = try recoveryTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "1. first\n3. second\n- [ ] checklist\nbody"
        let (model, noteURL) = try recoveryModel(in: root, initialText: original)
        let mounted = try mountEditor(model)
        defer { mounted.window.close() }
        let textView = mounted.textView
        #expect(textView.isEditable)

        try makeUnreadable(noteURL)
        model.reloadFromDiskIfChanged(force: true)

        #expect(!model.isEditable)
        #expect(model.text == original)
        #expect(!model.hasPendingSave)
        model.acceptEdit(DocumentAnalysis("edit that bypasses the text view"))
        #expect(model.text == original)
        #expect(hostedUpdate(mounted.host) { !textView.isEditable })
        #expect(textView.string == original)
        #expect(!textView.replaceText(in: NSRange(location: 0, length: 0), with: "lost"))
        let originalEnd = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: originalEnd, length: 0))
        textView.toggleChecklist()
        #expect(!textView.renumberLists())
        #expect(textView.string == original)

        let pasteboard = NSPasteboard.general
        let priorItems = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            pasteboard.clearContents()
            let restored = priorItems.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            if !restored.isEmpty { pasteboard.writeObjects(restored) }
        }
        pasteboard.clearContents()
        #expect(pasteboard.setString("clipboard sentinel", forType: .string))
        let clipboardChangeCount = pasteboard.changeCount
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.cut(nil)
        #expect(pasteboard.changeCount == clipboardChangeCount)
        #expect(pasteboard.string(forType: .string) == "clipboard sentinel")
        #expect(textView.string == original)

        try repair(noteURL, with: "recovered note")
        model.reloadFromDiskIfChanged(force: true)

        #expect(model.isEditable)
        #expect(model.text == "recovered note")
        #expect(hostedUpdate(mounted.host) { textView.isEditable })
        let recoveredEnd = (textView.string as NSString).length
        #expect(
            textView.replaceText(
                in: NSRange(location: recoveredEnd, length: 0), with: "!"))
        try model.flushSave()
        #expect(try String(contentsOf: noteURL, encoding: .utf8) == "recovered note!")
    }

    @Test("Unchanged reloads and restyling keep valid local undo history")
    func localUndoSurvivesReloadAndRestyling() throws {
        let root = try recoveryTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "A paragraph with its original ending."
        let (model, _) = try recoveryModel(in: root, initialText: original)
        let mounted = try mountEditor(model)
        defer { mounted.window.close() }
        let textView = mounted.textView
        let range = (textView.string as NSString).range(of: "original")
        #expect(textView.replaceText(in: range, with: "edited!!"))
        #expect(model.document === textView.documentAnalysis())
        let undo = try #require(textView.undoManager)
        #expect(undo.canUndo)
        try model.flushSave()

        let revision = model.document
        model.reloadFromDiskIfChanged(force: true)
        #expect(model.document === revision)
        #expect(undo.canUndo)

        let nextTheme: ThemeSetting = model.theme == .dark ? .light : .dark
        #expect(model.settings.setTheme(nextTheme))
        model.adoptSettings()
        #expect(hostedUpdate(mounted.host) {
            textView.textColor?.isEqual(Palette.for(nextTheme.resolve()).text) == true
        })
        #expect(undo.canUndo)
        undo.undo()
        #expect(textView.string == original)
        #expect(model.text == original)
    }

    @Test("Opening help disables the covered editor without discarding undo")
    func helpDisablesCoveredEditor() throws {
        let root = try recoveryTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "# Help boundary\nDisposable note text"
        let (model, _) = try recoveryModel(in: root, initialText: original)
        let mounted = try mountEditor(model)
        defer { mounted.window.close() }
        let textView = mounted.textView
        let undo = try #require(textView.undoManager)
        let range = (textView.string as NSString).range(of: "Disposable")
        #expect(textView.replaceText(in: range, with: "Changed"))
        #expect(textView.string == "# Help boundary\nChanged note text")
        #expect(undo.canUndo)

        model.showHelp = true

        #expect(hostedUpdate(mounted.host) { !textView.isEditable && !textView.isSelectable })
        #expect(textView.string == "# Help boundary\nChanged note text")
        #expect(model.text == textView.string)
        #expect(!textView.replaceText(in: NSRange(location: 0, length: 0), with: "lost"))
        #expect(undo.canUndo)

        model.showHelp = false

        #expect(hostedUpdate(mounted.host) { textView.isEditable && textView.isSelectable })
        undo.undo()
        #expect(textView.string == original)
        #expect(model.text == original)
    }

    @Test("A shorter external replacement removes undo actions from the old text")
    func shorterExternalReplacementClearsUndo() throws {
        let root = try recoveryTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, noteURL) = try recoveryModel(
            in: root, initialText: "A note with a long ending that will be replaced")
        let mounted = try mountEditor(model)
        defer { mounted.window.close() }
        let textView = mounted.textView
        let range = (textView.string as NSString).range(of: "long ending")
        #expect(textView.replaceText(in: range, with: "edited ending"))
        let undo = try #require(textView.undoManager)
        #expect(undo.canUndo)
        try model.flushSave()

        try "short".write(to: noteURL, atomically: true, encoding: .utf8)
        model.reloadFromDiskIfChanged(force: true)

        #expect(model.text == "short")
        #expect(hostedUpdate(mounted.host) { textView.string == "short" })
        #expect(!undo.canUndo)
        #expect(!undo.canRedo)
        undo.undo()
        #expect(textView.string == "short")
        #expect(model.text == "short")
    }
}

@MainActor
private struct MountedEditor {
    let host: NSHostingView<EditorView>
    let window: NSWindow
    let textView: NotesTextView
}

@MainActor
private func recoveryTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WispEditorRecovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@MainActor
private func recoveryModel(
    in root: URL, initialText: String? = nil, folder: URL? = nil
) throws -> (EditorModel, URL) {
    let notes = folder ?? root.appendingPathComponent("notes", isDirectory: true)
    try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
    let noteURL = StorageLocation.scratchpadURL(in: notes)
    if let initialText {
        try initialText.write(to: noteURL, atomically: true, encoding: .utf8)
    }
    let configURL = root.appendingPathComponent("config/wisp.jsonc")
    try ConfigStore.write(WispConfig(scratchpadFolder: notes.path), at: configURL)
    _ = NSApplication.shared
    let model = EditorModel(settings: Settings(configFileURL: configURL))
    return (model, noteURL)
}

@MainActor
private func mountEditor(_ model: EditorModel) throws -> MountedEditor {
    let host = NSHostingView(rootView: EditorView(model: model))
    host.sizingOptions = []
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
        styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    guard let textView = findNotesTextView(in: host) else {
        throw NSError(
            domain: "WispEditorRecoveryTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The mounted editor has no notes text view"])
    }
    return MountedEditor(host: host, window: window, textView: textView)
}

@MainActor
private func findNotesTextView(in view: NSView) -> NotesTextView? {
    if let textView = view as? NotesTextView { return textView }
    if let textView = (view as? NSScrollView)?.documentView as? NotesTextView {
        return textView
    }
    for child in view.subviews {
        if let textView = findNotesTextView(in: child) { return textView }
    }
    return nil
}

@MainActor
private func hostedUpdate(_ host: NSHostingView<EditorView>, until condition: () -> Bool) -> Bool {
    let deadline = Date(timeIntervalSinceNow: 1)
    repeat {
        host.layoutSubtreeIfNeeded()
        if condition() { return true }
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    } while Date() < deadline
    host.layoutSubtreeIfNeeded()
    return condition()
}

private func makeUnreadable(_ noteURL: URL) throws {
    try FileManager.default.removeItem(at: noteURL)
    try FileManager.default.createDirectory(at: noteURL, withIntermediateDirectories: true)
    try "blocks file read".write(
        to: noteURL.appendingPathComponent("child"), atomically: true, encoding: .utf8)
}

private func repair(_ noteURL: URL, with text: String) throws {
    try FileManager.default.removeItem(at: noteURL)
    try text.write(to: noteURL, atomically: true, encoding: .utf8)
}
