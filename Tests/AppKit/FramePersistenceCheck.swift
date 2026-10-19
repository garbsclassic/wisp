import AppKit
import CoreGraphics
import Darwin
import Foundation
import WispCore

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Runs both phases as separate processes inside one disposable app preferences domain.
@MainActor
@main
private struct FramePersistenceCheck {
    private static let frameKey = "PanelFrame"

    static func main() {
        do {
            try run()
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 1, ["save", "restore"].contains(arguments[0]) else {
            throw CheckFailure(description: "Pass exactly one phase: save or restore")
        }
        let phase = arguments[0]
        let (bundleID, root, xdg) = try validateIsolation()
        let defaults = UserDefaults.standard
        if phase == "save" {
            let domain = defaults.persistentDomain(forName: bundleID)
            try check(domain == nil || domain?.isEmpty == true, "Defaults domain is not fresh")
        } else {
            try check(
                defaults.string(forKey: frameKey) != nil,
                "Save phase did not persist PanelFrame")
        }

        var displayCount: UInt32 = 0
        let displayResult = CGGetActiveDisplayList(0, nil, &displayCount)
        try check(
            displayResult == .success,
            "CoreGraphics could not inspect displays (error \(displayResult.rawValue))")
        try check(
            displayCount >= 2,
            "This AppKit check needs a logged-in GUI session with two active displays; "
                + "found \(displayCount)")

        var preserveDomain = phase == "save"
        defer {
            if !preserveDomain {
                defaults.removePersistentDomain(forName: bundleID)
                defaults.synchronize()
            }
        }

        NSApplication.shared.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(
            at: ConfigStore.directory, withIntermediateDirectories: true)
        try check(
            ConfigStore.directory.standardizedFileURL.path
                == xdg.appendingPathComponent("wisp").standardizedFileURL.path,
            "ConfigStore escaped scratch XDG_CONFIG_HOME")

        let (primary, upper) = try screens()
        if phase == "save" {
            try saveFrame(root: root, primary: primary, upper: upper, defaults: defaults)
        } else {
            try restoreFrame(root: root, primary: primary, upper: upper, defaults: defaults)
            preserveDomain = false
        }
    }

    private static func validateIsolation() throws -> (String, URL, URL) {
        let environment = ProcessInfo.processInfo.environment
        guard let bundleID = environment["WISP_FRAME_TEST_BUNDLE_ID"],
            bundleID.hasPrefix("dev.garbs.wisp.frame-check."),
            Bundle.main.bundleIdentifier == bundleID,
            let rootPath = environment["WISP_FRAME_TEST_ROOT"],
            let xdgPath = environment["XDG_CONFIG_HOME"]
        else {
            throw CheckFailure(description: "Test app bundle or scratch environment is invalid")
        }

        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let xdg = URL(fileURLWithPath: xdgPath, isDirectory: true).standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().path
        try check(root.path.hasPrefix("/tmp/") || root.path.hasPrefix("/private/tmp/"),
                  "Scratch root must be under /tmp")
        try check(
            Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot + "/"),
            "Test app bundle is outside the scratch root")
        try check(
            xdg.path == root.appendingPathComponent("xdg").standardizedFileURL.path,
            "XDG_CONFIG_HOME must be <scratch root>/xdg")
        return (bundleID, root, xdg)
    }

    private static func screens() throws -> (NSScreen, NSScreen) {
        let connected = NSScreen.screens
        guard let primary = connected.first,
            let upper = connected.dropFirst().first(where: {
                $0.frame.minY >= primary.frame.maxY - 1
            })
        else {
            throw CheckFailure(
                description: "This AppKit check needs a logged-in session with a display "
                    + "above primary")
        }
        guard primary.visibleFrame.width >= PanelPlacement.defaultSize.width,
            primary.visibleFrame.height >= 240
        else {
            throw CheckFailure(
                description: "Primary display must be at least 800×240 points for this check")
        }
        let visible = upper.visibleFrame
        guard visible.width >= 860, visible.height >= PanelPlacement.minimumSize.height else {
            throw CheckFailure(description: "Upper display must fit an 860×640 point window")
        }
        return (primary, upper)
    }

    private static func saveFrame(
        root: URL, primary: NSScreen, upper: NSScreen, defaults: UserDefaults
    ) throws {
        let legacyTopLeft = CGPoint(
            x: primary.visibleFrame.minX + 155, y: primary.visibleFrame.maxY - 120)
        try writeLegacy(size: CGSize(width: 720, height: 640), topLeft: legacyTopLeft)
        let configBefore = try Data(contentsOf: ConfigStore.fileURL)

        let panel = makePanel(
            CGRect(
                x: primary.visibleFrame.minX, y: primary.visibleFrame.minY,
                width: PanelPlacement.defaultSize.width,
                height: PanelPlacement.defaultSize.height))
        var controller: PanelFrameController? = PanelFrameController()
        controller?.restoreFrame(of: panel)
        let importedHeight = min(PanelPlacement.minimumSize.height, primary.visibleFrame.height)
        let imported = CGRect(
            x: legacyTopLeft.x.rounded(), y: (legacyTopLeft.y - importedHeight).rounded(),
            width: 720, height: importedHeight)
        try expectFrame(panel.frame, imported, "legacy size points and top-left migration")
        try expectSavedFrame(imported, defaults: defaults, label: "legacy frame migration")
        try expectConfigUnchanged(configBefore)

        let moved = CGRect(
            x: upper.visibleFrame.minX + (upper.visibleFrame.width - 860) / 2,
            y: upper.visibleFrame.minY + (upper.visibleFrame.height - 640) / 2,
            width: panel.frame.width, height: panel.frame.height)
        panel.setFrame(moved, display: false)
        try waitForSavedFrame(moved, defaults: defaults, label: "move-only change")
        try expectFrame(panel.frame, moved, "move-only change")
        try expectConfigUnchanged(configBefore)

        let resized = CGRect(origin: moved.origin, size: CGSize(width: 860, height: 640))
        panel.setFrame(resized, display: false)
        try waitForSavedFrame(resized, defaults: defaults, label: "resize-only change")
        try expectFrame(panel.frame, resized, "resize-only change")
        try expectConfigUnchanged(configBefore)

        guard let saved = defaults.string(forKey: frameKey) else {
            throw CheckFailure(description: "Frame observer did not store PanelFrame")
        }
        try saved.write(
            to: root.appendingPathComponent("saved-frame.txt"), atomically: true, encoding: .utf8)
        close(panel, controller: &controller)
        defaults.synchronize()
        print("PASS save phase: migrated points and saved move/resize on upper display")
    }

    private static func restoreFrame(
        root: URL, primary: NSScreen, upper: NSScreen, defaults: UserDefaults
    ) throws {
        let expected = try NSRectFromString(
            String(contentsOf: root.appendingPathComponent("saved-frame.txt"), encoding: .utf8))
        let configBefore = try Data(contentsOf: ConfigStore.fileURL)
        let panel = makePanel(
            CGRect(
                x: primary.visibleFrame.minX, y: primary.visibleFrame.minY,
                width: PanelPlacement.defaultSize.width,
                height: PanelPlacement.defaultSize.height))
        var controller: PanelFrameController? = PanelFrameController()
        controller?.restoreFrame(of: panel)
        try expectFrame(panel.frame, expected, "saved frame restored by a new process")
        try check(
            PanelPlacement.screen(under: panel.frame, in: NSScreen.screens.map(\.visibleFrame))
                == upper.visibleFrame,
            "Saved frame was remapped away from the upper display")
        try expectConfigUnchanged(configBefore)

        let reset = PanelPlacement.resetFrame(on: primary.visibleFrame)
        try check(!panel.isVisible, "Test panel unexpectedly became visible")
        controller?.resetView(of: panel)
        try check(!panel.isVisible, "Reset showed the hidden panel")
        try expectFrame(panel.frame, reset, "reset while hidden")
        if primary.visibleFrame.height < PanelPlacement.minimumSize.height {
            try check(
                panel.frame.minX >= primary.visibleFrame.minX
                    && panel.frame.maxX <= primary.visibleFrame.maxX
                    && panel.frame.minY >= primary.visibleFrame.minY
                    && panel.frame.maxY <= primary.visibleFrame.maxY,
                "Reset frame does not fit a primary visible frame shorter than minimum height")
        }
        try expectSavedFrame(reset, defaults: defaults, label: "hidden reset")
        try expectConfigUnchanged(configBefore)

        let offscreen = CGRect(
            origin: CGPoint(x: -10000, y: -10000), size: PanelPlacement.defaultSize)
        let recovered = PanelPlacement.recoveredFrame(
            offscreen, target: primary.visibleFrame, screens: NSScreen.screens.map(\.visibleFrame))
        panel.setFrame(offscreen, display: false)
        controller?.recoverFrame(of: panel)
        try check(!panel.isVisible, "Recovery showed the hidden panel")
        try expectFrame(panel.frame, recovered, "hidden recovery")
        try check(
            panel.frame.size
                == PanelPlacement.fitted(PanelPlacement.defaultSize, to: primary.visibleFrame)
                && PanelPlacement.isReachable(
                    panel.frame, on: NSScreen.screens.map(\.visibleFrame)),
            "Disconnected-frame recovery did not keep size and return to a connected display")
        try expectSavedFrame(panel.frame, defaults: defaults, label: "hidden recovery")
        try expectConfigUnchanged(configBefore)
        close(panel, controller: &controller)

        try retryMalformedLegacy(primary: primary, defaults: defaults)
        print("PASS restore phase: upper-display restore, hidden reset/recovery, and legacy retry")
    }

    private static func retryMalformedLegacy(primary: NSScreen, defaults: UserDefaults) throws {
        defaults.removeObject(forKey: frameKey)
        try writeRawConfig("{panel:")
        let panel = makePanel(
            CGRect(
                x: primary.visibleFrame.minX, y: primary.visibleFrame.minY,
                width: PanelPlacement.defaultSize.width,
                height: PanelPlacement.defaultSize.height))
        var controller: PanelFrameController? = PanelFrameController()
        controller?.restoreFrame(of: panel)
        try check(defaults.string(forKey: frameKey) == nil,
                  "Malformed legacy config was permanently migrated")

        let topLeft = CGPoint(
            x: primary.visibleFrame.minX + 190, y: primary.visibleFrame.maxY - 125)
        let config = legacyConfig(size: CGSize(width: 700, height: 640), topLeft: topLeft)
        try writeRawConfig(config)
        controller?.restoreFrame(of: panel)
        let repairedHeight = min(PanelPlacement.minimumSize.height, primary.visibleFrame.height)
        let repaired = CGRect(
            x: topLeft.x.rounded(), y: (topLeft.y - repairedHeight).rounded(),
            width: 700, height: repairedHeight)
        try expectFrame(panel.frame, repaired, "repaired legacy retry")
        try expectSavedFrame(repaired, defaults: defaults, label: "repaired legacy retry")
        try expectConfigUnchanged(Data(config.utf8))
        close(panel, controller: &controller)

        defaults.removeObject(forKey: frameKey)
        try writeRawConfig("{panel:")
        let malformedConfig = try Data(contentsOf: ConfigStore.fileURL)
        let resetPanel = makePanel(
            CGRect(
                x: primary.visibleFrame.minX, y: primary.visibleFrame.minY,
                width: PanelPlacement.defaultSize.width,
                height: PanelPlacement.defaultSize.height))
        var resetController: PanelFrameController? = PanelFrameController()
        resetController?.restoreFrame(of: resetPanel)
        try check(defaults.string(forKey: frameKey) == nil,
                  "Malformed legacy config unexpectedly created a saved frame before reset")

        let reset = PanelPlacement.resetFrame(on: primary.visibleFrame)
        resetController?.resetView(of: resetPanel)
        try check(!resetPanel.isVisible, "Reset during migration delay showed the panel")
        try expectFrame(resetPanel.frame, reset, "reset overrides malformed legacy config")
        try expectSavedFrame(reset, defaults: defaults, label: "reset during migration delay")
        try expectConfigUnchanged(malformedConfig)

        let moved = reset.offsetBy(dx: 30, dy: 15)
        resetPanel.setFrame(moved, display: false)
        try waitForSavedFrame(moved, defaults: defaults, label: "move after reset during delay")
        try expectConfigUnchanged(malformedConfig)
        close(resetPanel, controller: &resetController)
    }

    private static func makePanel(_ frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.minSize = PanelPlacement.minimumSize
        return panel
    }

    private static func writeLegacy(size: CGSize, topLeft: CGPoint) throws {
        try writeRawConfig(legacyConfig(size: size, topLeft: topLeft))
    }

    private static func legacyConfig(size: CGSize, topLeft: CGPoint) -> String {
        """
        {
          // Old window geometry is imported once and remains hand-managed in this file.
          "theme": "dark",
          "fontScale": 1.15,
          "panel": { "width": \(size.width), "height": \(size.height) },
          "position": { "x": \(topLeft.x), "y": \(topLeft.y) },
        }
        """
    }

    private static func writeRawConfig(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: ConfigStore.directory, withIntermediateDirectories: true)
        try text.write(to: ConfigStore.fileURL, atomically: true, encoding: .utf8)
    }

    private static func expectSavedFrame(
        _ expected: CGRect, defaults: UserDefaults, label: String
    ) throws {
        guard let saved = defaults.string(forKey: frameKey) else {
            throw CheckFailure(description: "\(label): PanelFrame is missing")
        }
        try expectFrame(NSRectFromString(saved), expected, label)
    }

    private static func waitForSavedFrame(
        _ expected: CGRect, defaults: UserDefaults, label: String
    ) throws {
        let deadline = Date(timeIntervalSinceNow: 1)
        while Date() < deadline {
            if let saved = defaults.string(forKey: frameKey), framesEqual(
                NSRectFromString(saved), expected) {
                return
            }
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        try expectSavedFrame(expected, defaults: defaults, label: label)
    }

    private static func expectConfigUnchanged(_ expected: Data) throws {
        let actual = try Data(contentsOf: ConfigStore.fileURL)
        try check(actual == expected, "Window frame changes rewrote wisp.jsonc")
    }

    private static func close(_ panel: NSPanel, controller: inout PanelFrameController?) {
        panel.orderOut(nil)
        panel.close()
        controller = nil
        _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }

    private static func framesEqual(_ actual: CGRect, _ expected: CGRect) -> Bool {
        let values = [
            (actual.minX, expected.minX), (actual.minY, expected.minY),
            (actual.width, expected.width), (actual.height, expected.height),
        ]
        return values.allSatisfy { abs($0.0 - $0.1) < 0.01 }
    }

    private static func expectFrame(_ actual: CGRect, _ expected: CGRect, _ label: String) throws {
        guard framesEqual(actual, expected) else {
            throw CheckFailure(description: "\(label): got \(actual), expected \(expected)")
        }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(description: message) }
    }
}
