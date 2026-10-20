import AppKit
import CryptoKit
import Darwin
import Foundation
import WispCore

private struct ProfileFailure: Error, CustomStringConvertible {
    let description: String
}

/// External input must not change a disposable fixture or its undo history.
@objc(WispAllocationApplication)
private final class ProfileApplication: NSApplication {
    var ignoredInputEvents = 0

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
            .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel:
            ignoredInputEvents += 1
        default:
            super.sendEvent(event)
        }
    }
}

/// A release-built driver around production controllers, with checkpoints for external tools.
@main
@MainActor
private struct AllocationProfile {
    static func main() {
        let app = ProfileApplication.shared
        precondition(app is ProfileApplication)
        app.setActivationPolicy(.accessory)
        let driver = ProfileDriver()
        Task { @MainActor in
            do {
                try await driver.run()
                app.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("PROFILE FAILED: \(error)\n".utf8))
                exit(1)
            }
        }
        app.run()
    }
}

@MainActor
private final class ProfileDriver {
    private var settings: Settings?
    private var model: EditorModel?
    private var panel: PanelController?
    private weak var trackedModel: EditorModel?
    private weak var trackedView: NotesTextView?
    private var root: URL!
    private var originalLength = 0
    private var undoOperations = 0
    private var expectedExtraCharacters = 0
    private var originalDigest: SHA256.Digest?
    private var editCount = 100
    private var overlayCount = 50
    private var completedOverlays = 0

    func run() async throws {
        try prepare()
        try await checkpoint("00-hidden")
        showWithoutFocus()
        try await settle()
        trackedView = NSApp.windows.lazy.compactMap { self.findNotes(in: $0.contentView) }.first
        guard trackedView != nil else {
            throw ProfileFailure(description: "The production editor did not mount")
        }
        try await checkpoint("01-visible")
        let earlyEdits = max(1, editCount / 5)
        try editBatch(count: earlyEdits)
        try await checkpoint("02-edits-early")
        try editBatch(count: editCount - earlyEdits)
        try await checkpoint("03-edits-final")
        try undoEdits()
        try await checkpoint("04-undone")
        let earlyOverlays = max(1, overlayCount / 5)
        try await overlayBatch(count: earlyOverlays)
        try await checkpoint("05-overlays-early")
        try await overlayBatch(count: overlayCount - earlyOverlays)
        try await checkpoint("06-overlays-final")
        panel?.dismiss()
        try model?.flushSave()
        try await checkpoint("07-hidden-settled")
        autoreleasepool {
            for window in NSApp.windows {
                window.contentView = nil
                window.close()
            }
            panel = nil
            model = nil
            settings = nil
        }
        try await checkpoint("08-released")
        if let identifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: identifier)
        }
    }

    private func prepare() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["WISP_ALLOCATION_ROOT"],
            let identifier = Bundle.main.bundleIdentifier,
            identifier.hasPrefix("dev.garbs.wisp.allocation-profile."),
            let count = Int(environment["WISP_ALLOCATION_LINES"] ?? ""), count > 0,
            ["lf", "crlf"].contains(environment["WISP_ALLOCATION_NEWLINE"] ?? "")
        else { throw ProfileFailure(description: "Missing isolated profiling configuration") }
        guard let edits = Int(environment["WISP_ALLOCATION_EDITS"] ?? "100"), edits > 0,
            let overlays = Int(environment["WISP_ALLOCATION_OVERLAYS"] ?? "50"), overlays > 0
        else { throw ProfileFailure(description: "Invalid profiling workload counts") }
        editCount = edits
        overlayCount = overlays
        root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard
            ConfigStore.directory.resolvingSymlinksInPath().path
                == root.appendingPathComponent("xdg/wisp").resolvingSymlinksInPath().path
        else {
            throw ProfileFailure(
                description:
                    "XDG config is not isolated: got \(ConfigStore.directory.path), expected "
                    + root.appendingPathComponent("xdg/wisp").path)
        }
        let notes = root.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let rows = [
            "# Heading", "plain prose café 👋 é", "**bold** _italic_ ==marked== `code`",
            "- item", "  continuation", "", "```swift", "let x = 1", "```", "",
        ]
        let newline = environment["WISP_ALLOCATION_NEWLINE"] == "crlf" ? "\r\n" : "\n"
        let text = (0..<count).map { rows[$0 % rows.count] }.joined(separator: newline) + "tail"
        originalLength = (text as NSString).length
        originalDigest = SHA256.hash(data: Data(text.utf8))
        try text.write(
            to: StorageLocation.scratchpadURL(in: notes), atomically: true, encoding: .utf8)
        try ConfigStore.write(
            WispConfig(scratchpadFolder: notes.path, footerStatus: .modified),
            at: ConfigStore.fileURL)
        settings = Settings(configFileURL: ConfigStore.fileURL)
        model = EditorModel(settings: settings!)
        trackedModel = model
        panel = PanelController(model: model!, settings: settings!)
        // No AppDelegate: file watchers, login items, and global hotkeys are not registered.
        // The production panel still supplies its actual editor, overlay, and save behavior.
    }

    private func editBatch(count: Int) throws {
        guard let view = trackedView, let undo = view.undoManager else {
            throw ProfileFailure(description: "The editor has no undo manager")
        }
        for _ in 0..<count {
            try autoreleasepool {
                view.breakUndoCoalescing()
                undo.beginUndoGrouping()
                defer { undo.endUndoGrouping() }
                let range = NSRange(location: (view.string as NSString).length, length: 0)
                guard view.replaceText(in: range, with: "x") else {
                    throw ProfileFailure(description: "The editor refused a profiling edit")
                }
            }
        }
        expectedExtraCharacters += count
    }

    private func undoEdits() throws {
        guard let undo = trackedView?.undoManager else {
            throw ProfileFailure(description: "The editor lost its undo manager")
        }
        // AppKit's outer event groups can contain several of the edits in a batch.
        while undo.canUndo {
            guard undoOperations < editCount else {
                throw ProfileFailure(description: "Undo did not exhaust the edit history")
            }
            autoreleasepool { undo.undo() }
            undoOperations += 1
        }
        guard let model,
            (model.text as NSString).length == originalLength, model.text.hasSuffix("tail")
        else { throw ProfileFailure(description: "Undo did not restore the fixture") }
        expectedExtraCharacters = 0
    }

    private func overlayBatch(count: Int) async throws {
        for _ in 0..<count {
            model?.openFind()
            model?.findQuery = "marked"
            try await Task.sleep(for: .milliseconds(100))
            guard let view = trackedView, let range = model?.findHighlightRange,
                let currentModel = model, range.length > 0
            else { throw ProfileFailure(description: "The note find highlight did not render") }
            let color = Palette.for(currentModel.theme).findHighlight
            let temporary =
                view.layoutManager?.temporaryAttribute(
                    .backgroundColor, atCharacterIndex: range.location, effectiveRange: nil)
                as? NSColor
            let stored =
                view.textStorage?.attribute(
                    .backgroundColor, at: range.location, effectiveRange: nil) as? NSColor
            guard temporary?.isEqual(color) == true || stored?.isEqual(color) == true else {
                throw ProfileFailure(description: "The note find highlight has not been painted")
            }
            for _ in 0..<3 {
                model?.findNext()
                try await Task.sleep(for: .milliseconds(20))
                model?.findPrevious()
                try await Task.sleep(for: .milliseconds(20))
            }
            model?.dismissFind()
            model?.showHelp = true
            try await Task.sleep(for: .milliseconds(200))
            completedOverlays += 1
            model?.openFind()
            currentModel.findQuery = "line"
            try await Task.sleep(for: .milliseconds(100))
            guard currentModel.findMatchCount > 1 else {
                throw ProfileFailure(description: "The help find query has no navigation targets")
            }
            for _ in 0..<3 {
                model?.findNext()
                try await Task.sleep(for: .milliseconds(20))
                model?.findPrevious()
                try await Task.sleep(for: .milliseconds(20))
            }
            autoreleasepool {
                model?.dismissFind()
                model?.showHelp = false
                panel?.dismiss()
                showWithoutFocus()
            }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    private func settle() async throws {
        try await Task.sleep(for: .seconds(2))
    }

    private func showWithoutFocus() {
        // Use the production peek path, which orders front without making the panel key.
        panel?.handleChordDown(modifiers: [])
    }

    private func verifyFixture() throws {
        guard let model else { return }
        try autoreleasepool {
            let bytes = model.text.utf8
            guard (model.text as NSString).length == originalLength + expectedExtraCharacters,
                bytes.suffix(expectedExtraCharacters).allSatisfy({ $0 == 0x78 }),
                SHA256.hash(data: Data(bytes.dropLast(expectedExtraCharacters))) == originalDigest,
                trackedView.map({ $0.string.utf16.elementsEqual(model.text.utf16) }) ?? true
            else { throw ProfileFailure(description: "The profiling fixture was contaminated") }
        }
    }

    private func checkpoint(_ stage: String) async throws {
        try await settle()
        try verifyFixture()
        var vm = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw ProfileFailure(description: "Cannot read process footprint: \(result)")
        }
        var malloc = malloc_statistics_t()
        malloc_zone_statistics(nil, &malloc)
        let values: [String: Any] = [
            "stage": stage, "pid": ProcessInfo.processInfo.processIdentifier,
            "phys_footprint": vm.phys_footprint, "malloc_bytes": malloc.size_in_use,
            "view_alive": trackedView != nil, "model_alive": trackedModel != nil,
            "text_utf16": model.map { ($0.text as NSString).length } ?? 0,
            "can_undo": trackedView?.undoManager?.canUndo ?? false,
            "can_redo": trackedView?.undoManager?.canRedo ?? false,
            "undo_operations": undoOperations,
            "planned_edits": editCount, "planned_overlays": overlayCount,
            "edits": expectedExtraCharacters, "overlay_cycles": completedOverlays,
            "fixture_verified": true,
            "ignored_inputs": (NSApp as? ProfileApplication)?.ignoredInputEvents ?? 0,
        ]
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        try data.write(to: root.appendingPathComponent("\(stage).ready"), options: .atomic)
        let resume = root.appendingPathComponent("\(stage).resume")
        let clock = SuspendingClock()
        let deadline = clock.now.advanced(by: .seconds(1800))
        while !FileManager.default.fileExists(atPath: resume.path) {
            guard clock.now < deadline else {
                throw ProfileFailure(description: "Timed out waiting for profiler at \(stage)")
            }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    private func findNotes(in view: NSView?) -> NotesTextView? {
        guard let view else { return nil }
        if let notes = view as? NotesTextView { return notes }
        return view.subviews.lazy.compactMap { self.findNotes(in: $0) }.first
    }
}
