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
        #expect(StorageLocation.defaultFolder.lastPathComponent == "Wisp")
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

@Suite("PanelFrameStore.isUsable")
struct PanelFrameStoreTests {
    static let main = NSRect(x: 0, y: 0, width: 1440, height: 900)
    static let external = NSRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test("A frame within a connected screen is restored")
    func onScreen() {
        #expect(
            PanelFrameStore.isUsable(
                NSRect(x: 100, y: 100, width: 800, height: 640), onScreens: [Self.main]
            )
        )
        #expect(
            PanelFrameStore.isUsable(
                NSRect(x: 1600, y: 100, width: 800, height: 640),
                onScreens: [Self.main, Self.external]
            )
        )
    }

    /// The case this exists for: a frame saved on a display that has since
    /// been unplugged would otherwise restore off into nowhere.
    @Test("A frame stranded by an unplugged display is discarded")
    func stranded() {
        #expect(
            !PanelFrameStore.isUsable(
                NSRect(x: 1600, y: 100, width: 800, height: 640), onScreens: [Self.main]
            )
        )
        #expect(
            !PanelFrameStore.isUsable(
                NSRect(x: 100, y: 100, width: 800, height: 640), onScreens: []
            )
        )
    }

    @Test("Enough of the panel has to remain grabbable")
    func partiallyOffScreen() {
        #expect(
            PanelFrameStore.isUsable(
                NSRect(x: 1300, y: 100, width: 800, height: 640), onScreens: [Self.main]
            )
        )
        #expect(
            !PanelFrameStore.isUsable(
                NSRect(x: 1380, y: 100, width: 800, height: 640), onScreens: [Self.main]
            )
        )
    }

    @Test("A degenerate size from a corrupted value is rejected")
    func degenerate() {
        #expect(
            !PanelFrameStore.isUsable(
                NSRect(x: 100, y: 100, width: 50, height: 50), onScreens: [Self.main]
            )
        )
    }
}
