import AppKit
import Observation
import Synchronization
import SwiftUI
import Testing
import WispCore

@testable import Wisp

@Suite("Model observation boundaries", .serialized)
@MainActor
struct ObservationTests {
    @Test("Navigation reads ignore caret, save flash, and body-only edits")
    func navigationReadIsNarrow() throws {
        let root = try observationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model) = try observationModel(in: root, text: "# Heading\nOld body")
        let original = model.navigationHeadings
        let invalidated = ObservationFlag()
        withObservationTracking {
            _ = model.navigationHeadings
        } onChange: {
            invalidated.set()
        }

        model.caretOffset = 5
        #expect(!invalidated.isSet)
        model.acceptEdit(DocumentAnalysis("# Heading\nEdited body"))
        try model.flushSave()

        #expect(model.isShowingSaveFlash)
        #expect(!invalidated.isSet)
        #expect(model.navigationHeadings.map(\.id) == original.map(\.id))
        #expect(model.navigationHeadings.map(\.title) == ["Heading"])
    }

    @Test("Heading insertion and rename invalidate navigation reads with current payloads")
    func headingChangesInvalidateNavigation() throws {
        let root = try observationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model) = try observationModel(in: root, text: "# First\n## Second")
        let prefix = "# Added\n"
        let insertionInvalidated = ObservationFlag()
        withObservationTracking {
            _ = model.navigationHeadings
        } onChange: {
            insertionInvalidated.set()
        }

        model.acceptEdit(DocumentAnalysis(prefix + model.text))

        #expect(insertionInvalidated.isSet)
        #expect(model.navigationHeadings.map(\.title) == ["Added", "First", "Second"])
        #expect(model.navigationHeadings.map(\.heading.lineStart)
            == [0, prefix.utf16.count, (prefix + "# First\n").utf16.count])

        let renameInvalidated = ObservationFlag()
        withObservationTracking {
            _ = model.navigationHeadings
        } onChange: {
            renameInvalidated.set()
        }
        model.acceptEdit(DocumentAnalysis("# Added\n# First\n## Renamed"))
        try model.flushSave()

        #expect(renameInvalidated.isSet)
        #expect(model.navigationHeadings.map(\.title) == ["Added", "First", "Renamed"])
        #expect(model.navigationHeadings.last?.heading.lineStart
            == ("# Added\n# First\n").utf16.count)
    }

    @Test("Font scale reads observe Settings changes directly")
    func settingsChangeInvalidatesFontScaleRead() throws {
        let root = try observationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (settings, model) = try observationModel(in: root, text: "note")
        let nextScale = model.fontScale + Metrics.fontScaleStep
        let invalidated = ObservationFlag()
        withObservationTracking {
            _ = model.fontScale
        } onChange: {
            invalidated.set()
        }

        #expect(settings.setFontScale(nextScale))

        #expect(invalidated.isSet)
        #expect(model.fontScale == nextScale)
    }

    @Test("Resolved SwiftUI fonts observe config changes but ignore no-op writes")
    func uiFontObservesTypographyScale() throws {
        let root = try observationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (settings, _) = try observationModel(in: root, text: "note")
        let currentScale = settings.config.clampedFontScale
        let invalidated = ObservationFlag()
        withObservationTracking {
            _ = Typography.ui(Metrics.chromeSize, tabularDigits: true)
        } onChange: {
            invalidated.set()
        }

        #expect(settings.setFontScale(currentScale))
        #expect(!invalidated.isSet)
        #expect(settings.setFontScale(currentScale + Metrics.fontScaleStep))

        #expect(invalidated.isSet)
        _ = Typography.ui(Metrics.chromeSize, tabularDigits: true)
    }

    @Test("Settings adoption refreshes panel chrome when the resolved theme is unchanged")
    func unchangedThemeStillRefreshesPanelChrome() throws {
        let root = try observationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (settings, model) = try observationModel(in: root, text: "note")
        #expect(settings.setTheme(.light))
        model.adoptSettings()
        let background = Background(blur: false, opacity: 0.42)
        var updatedConfig = settings.config
        updatedConfig.background = background
        try ConfigStore.write(updatedConfig, at: settings.configFileURL)
        #expect(settings.reload())

        var callbackThemes: [Theme] = []
        var callbackBackgrounds: [Background] = []
        model.onThemeChange = { theme in
            callbackThemes.append(theme)
            callbackBackgrounds.append(settings.config.background)
        }
        model.adoptSettings()

        #expect(model.theme == .light)
        #expect(callbackThemes == [.light])
        #expect(callbackBackgrounds == [background])
    }

    @Test("Cached word count follows documents, while caret movement leaves it alone")
    func wordCountCacheTracksDocumentOnly() throws {
        let root = try observationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model) = try observationModel(in: root, text: "One two")
        #expect(model.wordCount == 2)
        let invalidated = ObservationFlag()
        withObservationTracking {
            _ = model.wordCount
        } onChange: {
            invalidated.set()
        }

        model.caretOffset = 2

        #expect(!invalidated.isSet)
        model.acceptEdit(DocumentAnalysis("One two three"))

        #expect(invalidated.isSet)
        #expect(model.wordCount == 3)
        try model.flushSave()
    }

    @Test("Cached caret position follows both caret and document changes")
    func caretPositionCacheTracksInputs() throws {
        let root = try observationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, model) = try observationModel(in: root, text: "One\nTwo\n")
        model.caretOffset = 5
        #expect(model.caretPosition == CaretPosition(line: 2, column: 2))
        let caretInvalidated = ObservationFlag()
        withObservationTracking {
            _ = model.caretPosition
        } onChange: {
            caretInvalidated.set()
        }

        model.caretOffset = 6

        #expect(caretInvalidated.isSet)
        #expect(model.caretPosition == CaretPosition(line: 2, column: 3))

        let documentInvalidated = ObservationFlag()
        withObservationTracking {
            _ = model.caretPosition
        } onChange: {
            documentInvalidated.set()
        }
        model.acceptEdit(DocumentAnalysis("Prefix\nOne\nTwo\n"))
        try model.flushSave()

        #expect(documentInvalidated.isSet)
        #expect(model.caretPosition == CaretPosition(line: 1, column: 7))
    }
}

@MainActor
private func observationTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WispObservationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@MainActor
private func observationModel(in root: URL, text: String) throws -> (Wisp.Settings, EditorModel) {
    let folder = root.appendingPathComponent("notes", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try text.write(
        to: StorageLocation.scratchpadURL(in: folder), atomically: true, encoding: .utf8)
    let configURL = root.appendingPathComponent("config/wisp.jsonc")
    try ConfigStore.write(WispConfig(scratchpadFolder: folder.path), at: configURL)
    _ = NSApplication.shared
    let settings = Wisp.Settings(configFileURL: configURL)
    return (settings, EditorModel(settings: settings))
}

private final class ObservationFlag: Sendable {
    private let value = Mutex(false)

    var isSet: Bool { value.withLock { $0 } }

    func set() { value.withLock { $0 = true } }
}
