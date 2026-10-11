import AppKit
import Foundation
import Testing

@testable import WispCore

@Suite("StorageLocation")
struct StorageLocationTests {
    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wisp-storage-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("The scratchpad lands directly inside the chosen folder")
    func composedURL() {
        let folder = URL(fileURLWithPath: "/tmp/wisp-probe")
        let composed = StorageLocation.scratchpadURL(in: folder)
        #expect(composed.lastPathComponent == "scratchpad.md")
        #expect(
            composed.deletingLastPathComponent().standardizedFileURL.path
                == folder.standardizedFileURL.path
        )
    }

    /// Finder shows a colon in a file name as `/`.
    @Test("A backup name is prefixed, suffixed, and colon-free")
    func backupFilename() {
        let name = StorageLocation.backupFilename(at: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(name.hasPrefix(StorageLocation.backupPrefix))
        #expect(name.hasSuffix(".md"))
        #expect(!name.contains(":"))
    }

    @Test("A successful switch writes the destination before removing the local note")
    func migratesToEmptyFolder() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let sourceNote = StorageLocation.scratchpadURL(in: source)
        try "local edits".write(to: sourceNote, atomically: true, encoding: .utf8)

        var committed = false
        let result = try StorageLocation.setFolder(
            destination, currentText: "local edits", currentFolder: source,
            commit: {
                committed = true
                #expect((try? String(contentsOf: sourceNote, encoding: .utf8)) == "local edits")
                #expect(
                    (try? String(
                        contentsOf: StorageLocation.scratchpadURL(in: destination),
                        encoding: .utf8)) == "local edits")
            })

        #expect(committed)
        #expect(result.text == "local edits")
        #expect(result.backupURL == nil)
        #expect(!FileManager.default.fileExists(atPath: sourceNote.path))
        #expect(
            try String(
                contentsOf: StorageLocation.scratchpadURL(in: destination), encoding: .utf8)
                == "local edits")
    }

    @Test("A symlink to the active folder is treated as the same location")
    func sameFolderThroughSymlink() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        let sourceNote = StorageLocation.scratchpadURL(in: source)
        try "local edits".write(to: sourceNote, atomically: true, encoding: .utf8)

        let result = try StorageLocation.setFolder(
            alias, currentText: "local edits", currentFolder: source)

        #expect(result.text == "local edits")
        #expect(result.backupURL == nil)
        #expect(try String(contentsOf: sourceNote, encoding: .utf8) == "local edits")
    }

    @Test("An existing destination loads while the local text gets its own backup")
    func loadsExistingDestinationAndBacksUpLocalText() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceNote = StorageLocation.scratchpadURL(in: source)
        let destinationNote = StorageLocation.scratchpadURL(in: destination)
        try "local edits".write(to: sourceNote, atomically: true, encoding: .utf8)
        try "synced note".write(to: destinationNote, atomically: true, encoding: .utf8)

        let result = try StorageLocation.setFolder(
            destination, currentText: "local edits", currentFolder: source)

        let backup = try #require(result.backupURL)
        #expect(result.text == "synced note")
        #expect(try String(contentsOf: destinationNote, encoding: .utf8) == "synced note")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "local edits")
        #expect(!FileManager.default.fileExists(atPath: sourceNote.path))
    }

    @Test("Invalid UTF-8 in an existing destination leaves the local note untouched")
    func unreadableDestinationPreservesLocalNote() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceNote = StorageLocation.scratchpadURL(in: source)
        let destinationNote = StorageLocation.scratchpadURL(in: destination)
        let invalidBytes = Data([0xFF, 0xFE, 0x80])
        try "local edits".write(to: sourceNote, atomically: true, encoding: .utf8)
        try invalidBytes.write(to: destinationNote)
        var committed = false

        var failed = false
        do {
            _ = try StorageLocation.setFolder(
                destination, currentText: "local edits", currentFolder: source,
                commit: { committed = true })
        } catch {
            failed = true
        }

        #expect(failed)
        #expect(!committed)
        #expect(try String(contentsOf: sourceNote, encoding: .utf8) == "local edits")
        #expect(try Data(contentsOf: destinationNote) == invalidBytes)
    }

    @Test("A backup failure leaves both the active destination and local text intact")
    func backupFailurePreservesNotes() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("not-a-folder")
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try "source path blocker".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let destinationNote = StorageLocation.scratchpadURL(in: destination)
        try "synced note".write(to: destinationNote, atomically: true, encoding: .utf8)
        var committed = false

        var failed = false
        do {
            _ = try StorageLocation.setFolder(
                destination, currentText: "unsaved local edits", currentFolder: source,
                commit: { committed = true })
        } catch {
            failed = true
        }

        #expect(failed)
        #expect(!committed)
        #expect(try String(contentsOf: source, encoding: .utf8) == "source path blocker")
        #expect(try String(contentsOf: destinationNote, encoding: .utf8) == "synced note")
    }

    @Test("A destination path that is a file leaves the local note untouched")
    func destinationWriteFailurePreservesLocalNote() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination-is-a-file")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "local edits".write(
            to: StorageLocation.scratchpadURL(in: source), atomically: true, encoding: .utf8)
        try "destination blocker".write(to: destination, atomically: true, encoding: .utf8)
        var committed = false

        var failed = false
        do {
            _ = try StorageLocation.setFolder(
                destination, currentText: "local edits", currentFolder: source,
                commit: { committed = true })
        } catch {
            failed = true
        }

        #expect(failed)
        #expect(!committed)
        #expect(
            try String(
                contentsOf: StorageLocation.scratchpadURL(in: source), encoding: .utf8)
                == "local edits")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "destination blocker")
    }

    @Test("A failed config commit leaves the source note available")
    func failedCommitPreservesSourceNote() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let sourceNote = StorageLocation.scratchpadURL(in: source)
        try "local edits".write(to: sourceNote, atomically: true, encoding: .utf8)

        var failed = false
        do {
            _ = try StorageLocation.setFolder(
                destination, currentText: "local edits", currentFolder: source,
                commit: { throw CommitFailure.expected })
        } catch CommitFailure.expected {
            failed = true
        }

        #expect(failed)
        #expect(try String(contentsOf: sourceNote, encoding: .utf8) == "local edits")
        #expect(
            try String(
                contentsOf: StorageLocation.scratchpadURL(in: destination), encoding: .utf8)
                == "local edits")
    }

    private enum CommitFailure: Error { case expected }
}
