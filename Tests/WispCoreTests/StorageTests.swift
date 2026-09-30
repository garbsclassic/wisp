import AppKit
import Foundation
import Testing

@testable import WispCore

@Suite("StorageLocation")
struct StorageLocationTests {
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
}
