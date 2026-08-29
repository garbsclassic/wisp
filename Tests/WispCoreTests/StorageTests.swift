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

/// `position: auto` places the panel itself: centred across the screen,
/// top edge a fifth of the way down.
@Suite("PanelFrameStore.autoFrame")
struct PanelFrameAutoTests {
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let size = NSSize(width: 800, height: 640)

    @Test("The panel is centred horizontally")
    func centredHorizontally() {
        #expect(PanelFrameStore.autoFrame(size: size, on: screen).midX == screen.midX)
    }

    @Test("The top edge sits a fifth of the way down")
    func topInset() {
        let frame = PanelFrameStore.autoFrame(size: size, on: screen)
        #expect(frame.maxY == screen.maxY - screen.height * PanelFrameStore.autoTopInset)
    }

    /// AppKit pixel-aligns whatever frame it is handed, so a fractional
    /// origin would come back changed and read as a drag.
    @Test("The origin lands on whole points")
    func integralOrigin() {
        let odd = NSRect(x: 0, y: 0, width: 1443, height: 907)
        let frame = PanelFrameStore.autoFrame(size: size, on: odd)
        #expect(frame.origin.x == frame.origin.x.rounded())
        #expect(frame.origin.y == frame.origin.y.rounded())
    }

    /// The origin is relative to the screen, not the global coordinate
    /// space — a second display to the right isn't a 1440-point offset.
    @Test("A screen with a non-zero origin is placed against its own bounds")
    func offsetScreen() {
        let second = NSRect(x: 1440, y: 300, width: 1920, height: 1080)
        let frame = PanelFrameStore.autoFrame(size: size, on: second)
        #expect(frame.midX == second.midX)
        #expect(frame.maxY == second.maxY - second.height * PanelFrameStore.autoTopInset)
        #expect(frame.minX > second.minX)
    }

    /// A panel remembered from a larger display still has to arrive whole
    /// and grabbable on a smaller one.
    @Test("A panel larger than the screen is clamped onto it")
    func clamped() {
        let small = NSRect(x: 0, y: 0, width: 600, height: 400)
        let frame = PanelFrameStore.autoFrame(size: size, on: small)
        #expect(frame.size == small.size)
        #expect(PanelFrameStore.isUsable(frame, onScreens: [small]))
    }

    /// Tall enough that a fifth-down top edge would hang the bottom off
    /// the screen; the placement gives up the inset before the panel.
    @Test("A tall panel is pushed up rather than off the bottom")
    func tallPanel() {
        let frame = PanelFrameStore.autoFrame(
            size: NSSize(width: 800, height: 880), on: screen)
        #expect(frame.minY >= screen.minY)
    }
}

/// `monitor: pointer` carries the remembered frame to whichever display the
/// cursor is on. Absolute coordinates would put it off the edge of a smaller
/// second screen, so the position is kept relative to the screen it left.
@Suite("PanelFrameStore.moved")
struct PanelFrameMoveTests {
    let small = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let large = NSRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test("A centred frame lands centred on the destination")
    func centred() {
        let frame = NSRect(x: 320, y: 130, width: 800, height: 640)
        let moved = PanelFrameStore.moved(frame, from: small, to: large)
        #expect(moved.midX == large.midX)
        #expect(moved.midY == large.midY)
    }

    @Test("A corner-pinned frame stays in that corner")
    func corner() {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 640)
        let moved = PanelFrameStore.moved(frame, from: small, to: large)
        #expect(moved.origin == large.origin)
    }

    @Test("The size is carried across unchanged when it fits")
    func sizePreserved() {
        let frame = NSRect(x: 100, y: 100, width: 800, height: 640)
        #expect(PanelFrameStore.moved(frame, from: small, to: large).size == frame.size)
    }

    /// Moving to a smaller display shrinks the panel rather than stranding
    /// part of it off the edge.
    @Test("A frame wider than the destination is clamped to it")
    func clampedToDestination() {
        let frame = NSRect(x: 0, y: 0, width: 1800, height: 1000)
        let moved = PanelFrameStore.moved(frame, from: large, to: small)
        #expect(moved.width == small.width)
        #expect(moved.height == small.height)
        #expect(PanelFrameStore.isUsable(moved, onScreens: [small]))
    }

    /// A frame that exactly fills its screen has no slack to be relative
    /// to — centring is the only answer that isn't a divide by zero.
    @Test("A full-screen frame centres rather than dividing by zero")
    func noSlack() {
        let moved = PanelFrameStore.moved(small, from: small, to: large)
        #expect(moved.midX == large.midX)
        #expect(moved.midY == large.midY)
    }
}
