import AppKit
import Foundation
import Testing

@testable import WispCore

@Suite("StorageLocation")
struct StorageLocationTests {
    @Test("The on-disk names are the documented ones")
    func names() {
        #expect(StorageLocation.scratchpadFilename == "scratchpad.md")
        #expect(StorageLocation.backupPrefix == "scratchpad-local-backup-")
        #expect(StorageLocation.defaultFolder.lastPathComponent == "Documents")
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

    /// Colons are legal in HFS+ display names but not in the POSIX path
    /// the backup is actually written through, so the timestamp must not
    /// carry any.
    @Test("A backup name is prefixed, suffixed, and colon-free")
    func backupFilename() {
        let name = StorageLocation.backupFilename(at: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(name.hasPrefix(StorageLocation.backupPrefix))
        #expect(name.hasSuffix(".md"))
        #expect(!name.contains(":"))
    }
}
