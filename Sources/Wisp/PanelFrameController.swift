import AppKit
import WispCore

/// Persists the frame in screen points; AppKit's autosave remaps upper-display frames to primary.
@MainActor
final class PanelFrameController {
    private static let frameKey = "PanelFrame"
    private enum Restoration { case pending, awaitingMigration, complete }
    private var restoration = Restoration.pending
    private var frameObservers: [any NSObjectProtocol] = []

    isolated deinit {
        for observer in frameObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private var targetScreen: CGRect? { NSScreen.screens.first?.visibleFrame }

    func restoreFrame(of panel: NSWindow) {
        guard restoration != .complete, let target = targetScreen else { return }
        if let saved = UserDefaults.standard.string(forKey: Self.frameKey) {
            let frame = PanelPlacement.recoveredFrame(
                NSRectFromString(saved), target: target,
                screens: NSScreen.screens.map(\.visibleFrame))
            panel.setFrame(frame, display: false)
        } else {
            let legacy: LegacyPanelGeometry?
            do {
                legacy = try legacyGeometry()
            } catch {
                // Don't replace unreadable legacy geometry with a permanent default.
                let screens = NSScreen.screens.map(\.visibleFrame)
                let fallback =
                    restoration == .pending
                    ? PanelPlacement.initialFrame(legacy: nil, target: target, screens: screens)
                    : PanelPlacement.recoveredFrame(panel.frame, target: target, screens: screens)
                if fallback != panel.frame { panel.setFrame(fallback, display: panel.isVisible) }
                restoration = .awaitingMigration
                return
            }
            panel.setFrame(
                PanelPlacement.initialFrame(
                    legacy: legacy, target: target, screens: NSScreen.screens.map(\.visibleFrame)),
                display: false)
        }
        completeRestoration(of: panel)
        recoverFrame(of: panel)
    }

    private func observeFrame(of panel: NSWindow) {
        frameObservers = [NSWindow.didMoveNotification, NSWindow.didResizeNotification].map {
            name in
            NotificationCenter.default.addObserver(
                forName: name, object: panel, queue: .main
            ) { [weak self, weak panel] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel else { return }
                    self.saveFrame(of: panel)
                }
            }
        }
    }

    private func saveFrame(of panel: NSWindow) {
        guard restoration == .complete else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    private func legacyGeometry() throws -> LegacyPanelGeometry? {
        let data: Data
        do {
            data = try Data(contentsOf: ConfigStore.fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(LegacyPanelGeometry.self, from: data)
    }

    func recoverFrame(of panel: NSWindow) {
        guard restoration == .complete else {
            restoreFrame(of: panel)
            return
        }
        guard let target = targetScreen else { return }
        let recovered = PanelPlacement.recoveredFrame(
            panel.frame, target: target, screens: NSScreen.screens.map(\.visibleFrame))
        if recovered != panel.frame { panel.setFrame(recovered, display: panel.isVisible) }
        saveFrame(of: panel)
    }

    func resetPosition(of panel: NSWindow) {
        guard let target = targetScreen else { return }
        // An explicit reset supersedes even a temporarily unreadable legacy config.
        completeRestoration(of: panel)
        panel.setFrame(
            PanelPlacement.resetPosition(of: panel.frame, on: target), display: panel.isVisible)
        saveFrame(of: panel)
    }

    func resetSize(of panel: NSWindow) {
        guard let target = panel.screen?.visibleFrame ?? targetScreen else { return }
        completeRestoration(of: panel)
        panel.setFrame(
            PanelPlacement.resetSize(of: panel.frame, on: target), display: panel.isVisible)
        saveFrame(of: panel)
    }

    private func completeRestoration(of panel: NSWindow) {
        guard restoration != .complete else { return }
        restoration = .complete
        observeFrame(of: panel)
    }
}
