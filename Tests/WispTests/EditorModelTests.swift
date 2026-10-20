import AppKit
import Testing
import WispCore

@testable import Wisp

@Suite("EditorModel", .serialized)
@MainActor
struct EditorModelTests {
    @Test("A missing note is empty, while an unreadable note reports a load failure")
    func missingAndUnreadableStartup() throws {
        let missingRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: missingRoot) }
        let (_, missingModel, missingFolder) = try makeModel(in: missingRoot)

        #expect(missingModel.text.isEmpty)
        #expect(missingModel.persistenceWarning == nil)
        #expect(!missingModel.hasPendingSave)

        let unreadableRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: unreadableRoot) }
        let unreadableFolder = unreadableRoot.appendingPathComponent("notes", isDirectory: true)
        let noteURL = StorageLocation.scratchpadURL(in: unreadableFolder)
        try FileManager.default.createDirectory(at: noteURL, withIntermediateDirectories: true)
        try "not the note file".write(
            to: noteURL.appendingPathComponent("child"), atomically: true, encoding: .utf8)
        let configURL = unreadableRoot.appendingPathComponent("config/wisp.jsonc")
        try ConfigStore.write(
            WispConfig(scratchpadFolder: unreadableFolder.path), at: configURL)
        _ = NSApplication.shared
        let settings = Settings(configFileURL: configURL)
        let model = EditorModel(settings: settings)
        #expect(model.text.isEmpty)
        #expect(model.persistenceWarning != nil)
        model.text = "keep this local text"
        #expect(throws: (any Error).self) { try model.flushSave() }
        #expect(model.text == "keep this local text")
        #expect(model.hasPendingSave)
        let childURL = noteURL.appendingPathComponent("child")
        #expect(FileManager.default.fileExists(atPath: childURL.path))

        #expect(missingModel.scratchpadURL == StorageLocation.scratchpadURL(in: missingFolder))
    }

    @Test("A clean final flush preserves an external edit")
    func cleanFlushPreservesExternalEdit() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model, folder) = try makeModel(in: root, initialText: "local version")
        let noteURL = StorageLocation.scratchpadURL(in: folder)

        try "external version".write(to: noteURL, atomically: true, encoding: .utf8)
        try model.flushSave()

        #expect(try String(contentsOf: noteURL, encoding: .utf8) == "external version")
        #expect(!model.hasPendingSave)
    }

    @Test("A folder change migrates a clean external edit instead of stale memory")
    func folderChangeReadsCleanExternalEdit() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model, oldFolder) = try makeModel(in: root, initialText: "stale memory")
        let noteURL = model.scratchpadURL
        let newFolder = root.appendingPathComponent("external-edit", isDirectory: true)
        try "newer disk text".write(to: noteURL, atomically: true, encoding: .utf8)

        try model.changeScratchpadFolder(to: newFolder)

        #expect(try String(contentsOf: model.scratchpadURL, encoding: .utf8) == "newer disk text")
        #expect(!FileManager.default.fileExists(atPath: noteURL.path))
        #expect(oldFolder != newFolder)
    }

    @Test("A failed save keeps edits dirty and does not flash; a retry saves them")
    func failedSaveCanBeRetried() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model, folder) = try makeModel(in: root, initialText: "before")
        let noteURL = StorageLocation.scratchpadURL(in: folder)

        try FileManager.default.removeItem(at: noteURL)
        try FileManager.default.createDirectory(at: noteURL, withIntermediateDirectories: true)
        model.text = "pending edit"

        #expect(throws: (any Error).self) { try model.flushSave() }
        #expect(model.text == "pending edit")
        #expect(model.hasPendingSave)
        #expect(model.persistenceWarning != nil)
        #expect(!model.isShowingSaveFlash)

        try FileManager.default.removeItem(at: noteURL)
        try model.flushSave()
        #expect(try String(contentsOf: noteURL, encoding: .utf8) == "pending edit")
        #expect(!model.hasPendingSave)
        #expect(model.persistenceWarning == nil)
        #expect(model.isShowingSaveFlash)
    }

    @Test("A successful folder change flushes pending text before adopting the new note")
    func folderChangeFlushesPendingText() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (settings, model, oldFolder) = try makeModel(in: root, initialText: "before")
        let newFolder = root.appendingPathComponent("new-notes", isDirectory: true)
        let oldURL = model.scratchpadURL
        model.text = "latest local text"

        try model.changeScratchpadFolder(to: newFolder)

        #expect(model.scratchpadURL == StorageLocation.scratchpadURL(in: newFolder))
        #expect(
            settings.config.scratchpadFolderPath.standardizedFileURL
                == newFolder.standardizedFileURL)
        #expect(try String(contentsOf: model.scratchpadURL, encoding: .utf8) == "latest local text")
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(!model.hasPendingSave)
        #expect(oldFolder != newFolder)
    }

    @Test("A config write failure leaves the active folder and old note intact")
    func folderChangeConfigFailureKeepsActiveFolder() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (settings, model, oldFolder) = try makeModel(in: root, initialText: "original")
        let oldURL = model.scratchpadURL
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        model.text = "edited before switch"
        try "{ malformed config".write(
            to: settings.configFileURL, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) { try model.changeScratchpadFolder(to: destination) }

        #expect(model.scratchpadURL == oldURL)
        #expect(
            settings.config.scratchpadFolderPath.standardizedFileURL
                == oldFolder.standardizedFileURL)
        #expect(try String(contentsOf: oldURL, encoding: .utf8) == "edited before switch")
        #expect(
            try String(
                contentsOf: StorageLocation.scratchpadURL(in: destination), encoding: .utf8)
                == "edited before switch")
        #expect(!model.hasPendingSave)
    }

    @Test("An unreadable destination leaves the current location and note unchanged")
    func destinationReadFailureKeepsActiveFolder() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (settings, model, oldFolder) = try makeModel(in: root, initialText: "current note")
        let oldURL = model.scratchpadURL
        let destination = root.appendingPathComponent("unreadable", isDirectory: true)
        let destinationURL = StorageLocation.scratchpadURL(in: destination)
        try FileManager.default.createDirectory(
            at: destinationURL, withIntermediateDirectories: true)

        #expect(throws: (any Error).self) { try model.changeScratchpadFolder(to: destination) }

        #expect(model.scratchpadURL == oldURL)
        #expect(
            settings.config.scratchpadFolderPath.standardizedFileURL
                == oldFolder.standardizedFileURL)
        #expect(try String(contentsOf: oldURL, encoding: .utf8) == "current note")
        #expect(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    @Test("An external folder config is not adopted when its note cannot be read")
    func externalFolderAdoptionFailureKeepsActiveFolder() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (settings, model, oldFolder) = try makeModel(in: root, initialText: "active note")
        let oldURL = model.scratchpadURL
        let incomingFolder = root.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(
            at: StorageLocation.scratchpadURL(in: incomingFolder),
            withIntermediateDirectories: true)
        var incoming = settings.config
        incoming.scratchpadFolder = incomingFolder.path
        try ConfigStore.write(incoming, at: settings.configFileURL)

        #expect(!model.reloadSettings())

        #expect(model.scratchpadURL == oldURL)
        #expect(
            settings.config.scratchpadFolderPath.standardizedFileURL
                == oldFolder.standardizedFileURL)
        #expect(try String(contentsOf: oldURL, encoding: .utf8) == "active note")
        #expect(settings.configWarning != nil)
    }

    @Test("Failed config seeding does not move the model to default settings")
    func failedConfigSeedingKeepsActiveFolder() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (settings, model, oldFolder) = try makeModel(in: root, initialText: "active note")
        let oldURL = model.scratchpadURL
        let configParent = settings.configFileURL.deletingLastPathComponent()
        try FileManager.default.removeItem(at: settings.configFileURL)
        try FileManager.default.removeItem(at: configParent)
        try "blocks config directory creation".write(
            to: configParent, atomically: true, encoding: .utf8)

        #expect(!model.reloadSettings())

        #expect(model.scratchpadURL == oldURL)
        #expect(
            settings.config.scratchpadFolderPath.standardizedFileURL
                == oldFolder.standardizedFileURL)
        #expect(try String(contentsOf: oldURL, encoding: .utf8) == "active note")
        #expect(settings.configWarning != nil)
    }

    @Test("Reload detects older timestamps and force reads content with the same timestamp")
    func reloadHandlesRestoredAndSameTimestamps() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model, folder) = try makeModel(in: root, initialText: "original")
        let noteURL = StorageLocation.scratchpadURL(in: folder)
        let initialTime = try #require(model.lastLoadedMTime)
        let restoredTime = initialTime.addingTimeInterval(-60)

        try "restored older version".write(to: noteURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: restoredTime], ofItemAtPath: noteURL.path)
        model.reloadFromDiskIfChanged()
        #expect(model.text == "restored older version")

        let unchangedTime = try #require(model.lastLoadedMTime)
        try "same timestamp version".write(to: noteURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: unchangedTime], ofItemAtPath: noteURL.path)
        model.reloadFromDiskIfChanged()
        #expect(model.text == "restored older version")

        model.reloadFromDiskIfChanged(force: true)
        #expect(model.text == "same timestamp version")
    }

    @Test("Forced refresh still preserves pending local edits")
    func forcedRefreshPreservesPendingEdits() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model, folder) = try makeModel(in: root, initialText: "disk version")
        let noteURL = StorageLocation.scratchpadURL(in: folder)
        model.text = "local edit"
        try "external version".write(to: noteURL, atomically: true, encoding: .utf8)

        model.reloadFromDiskIfChanged(force: true)

        #expect(model.text == "local edit")
        #expect(model.hasPendingSave)
        try model.flushSave()
        #expect(try String(contentsOf: noteURL, encoding: .utf8) == "local edit")
    }

    @Test("A canceled debounce cannot change the note after an explicit flush")
    func canceledDebounceCannotOverwriteFlush() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model, folder) = try makeModel(in: root, initialText: "before")
        let noteURL = StorageLocation.scratchpadURL(in: folder)
        model.text = "first edit"
        model.text = "newer edit"
        try model.flushSave()

        // The debounce is 800 ms; let a canceled task cross that deadline before checking disk.
        try await Task.sleep(for: .milliseconds(900))

        #expect(try String(contentsOf: noteURL, encoding: .utf8) == "newer edit")
        #expect(!model.hasPendingSave)
    }

    @Test("Find tracks local and disk changes and refreshes when help text changes")
    func findTracksActiveDocumentChanges() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (settings, model, folder) = try makeModel(in: root, initialText: "hit x hit")
        let noteURL = StorageLocation.scratchpadURL(in: folder)
        model.openFind()
        model.findQuery = "hit"
        #expect(model.findMatchCount == 2)
        model.findNext()
        #expect(model.findHighlightRange.location == 6)

        model.text = "prefix hit"
        #expect(model.findMatchCount == 1)
        #expect(model.findCurrentDisplayIndex == 1)
        #expect(model.findHighlightRange.location == 7)
        try model.flushSave()

        try "xx hit".write(to: noteURL, atomically: true, encoding: .utf8)
        model.reloadFromDiskIfChanged(force: true)
        #expect(model.findMatchCount == 1)
        #expect(model.findHighlightRange.location == 3)

        model.showHelp = true
        model.findQuery = "⌘F"
        #expect(model.findMatchCount == 1)
        var config = settings.config
        config.keymap.setChord("ctrl+f", for: .find)
        try ConfigStore.write(config, at: settings.configFileURL)
        #expect(model.reloadSettings())
        #expect(model.findMatchCount == 0)
        #expect(model.findCurrentDisplayIndex == 0)
        #expect(model.findHighlightRange == NSRange(location: 0, length: 0))
    }

    @Test("Font family changes alone make body styles unequal")
    func bodyStyleIncludesFontFamilies() {
        let style = Editor.BodyStyle(
            theme: .dark, fontScale: 1, fonts: FontSet(notes: "Helvetica", code: "Menlo"),
            indent: Indent(), isSourceView: false, rule: .line)
        var changedNotes = style
        changedNotes.fonts.notes = "Arial"
        var changedCode = style
        changedCode.fonts.code = "Monaco"

        #expect(changedNotes != style)
        #expect(changedCode != style)
    }

    @Test("A failed settings write leaves in-memory config unchanged")
    func settingsWriteFailureDoesNotPublish() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (settings, _, _) = try makeModel(in: root)
        let oldConfig = settings.config
        try "{ malformed config".write(
            to: settings.configFileURL, atomically: true, encoding: .utf8)

        #expect(!settings.setFontScale(oldConfig.fontScale + 0.25))

        #expect(settings.config == oldConfig)
        #expect(settings.configWarning != nil)
        #expect(
            try String(contentsOf: settings.configFileURL, encoding: .utf8)
                == "{ malformed config")
    }
}

@Suite("NotesTextView undo")
@MainActor
struct NotesTextViewUndoTests {
    @Test("A checklist shortcut on an empty document can be undone")
    func emptyDocumentChecklistCanBeUndone() throws {
        _ = NSApplication.shared
        let (scrollView, textView) = NotesTextView.makeScrollView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = scrollView
        textView.allowsUndo = true
        let undoManager = try #require(textView.undoManager)
        textView.toggleChecklist()

        #expect(textView.string == "- [ ] ")
        undoManager.undo()
        #expect(textView.string.isEmpty)
    }
}

@MainActor
private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WispModelTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@MainActor
private func makeModel(
    in root: URL, initialText: String? = nil, folder: URL? = nil
) throws -> (settings: Settings, model: EditorModel, folder: URL) {
    let notesFolder = folder ?? root.appendingPathComponent("notes", isDirectory: true)
    let noteURL = StorageLocation.scratchpadURL(in: notesFolder)
    let configURL = root.appendingPathComponent("config/wisp.jsonc")
    try FileManager.default.createDirectory(
        at: notesFolder, withIntermediateDirectories: true)
    if let initialText {
        try initialText.write(to: noteURL, atomically: true, encoding: .utf8)
    }
    try ConfigStore.write(WispConfig(scratchpadFolder: notesFolder.path), at: configURL)
    _ = NSApplication.shared
    let settings = Settings(configFileURL: configURL)
    return (settings, EditorModel(settings: settings), notesFolder)
}
