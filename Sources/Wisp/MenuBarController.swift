import AppKit
import WispCore

/// The status item: left click pins or dismisses, right click opens the menu, whose dynamic items
/// refresh in `menuNeedsUpdate`.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    /// Runs keymap items through the same dispatch as their chords.
    private let perform: (KeymapAction) -> Void
    private let onSetHotKey: () -> Void
    private let currentLaunchAtLogin: () -> Bool
    private let onToggleLaunchAtLogin: () -> Void
    private let isStorageCustom: () -> Bool
    private let onPickStorageLocation: () -> Void
    private let onResetStorageLocation: () -> Void
    private let menu = NSMenu()

    // Strong is safe: NSMenuItem.target is weak.
    private var launchItem: NSMenuItem?
    private var resetItem: NSMenuItem?
    /// Configurable items, re-stamped by `apply(_:)`.
    private var boundItems: [(action: KeymapAction, item: NSMenuItem)] = []

    init(
        perform: @escaping (KeymapAction) -> Void,
        onSetHotKey: @escaping () -> Void,
        currentLaunchAtLogin: @escaping () -> Bool,
        onToggleLaunchAtLogin: @escaping () -> Void,
        isStorageCustom: @escaping () -> Bool,
        onPickStorageLocation: @escaping () -> Void,
        onResetStorageLocation: @escaping () -> Void
    ) {
        self.perform = perform
        self.onSetHotKey = onSetHotKey
        self.currentLaunchAtLogin = currentLaunchAtLogin
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
        self.isStorageCustom = isStorageCustom
        self.onPickStorageLocation = onPickStorageLocation
        self.onResetStorageLocation = onResetStorageLocation
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = Self.makeStatusIcon()
            image.accessibilityDescription = "Wisp"
            button.image = image
            button.target = self
            button.action = #selector(handleClick)
            // Left on the up, as a toggle; right on the down, as a context menu opens. As in Clef.
            button.sendAction(on: [.leftMouseUp, .rightMouseDown])
        }

        menu.delegate = self

        // Actions, then settings, then Quit; wording follows Clef's where they overlap.
        menu.addItem(
            boundItem(.resetPosition, symbol: "arrow.up.and.down.and.arrow.left.and.right"))
        menu.addItem(boundItem(.refresh, symbol: "arrow.clockwise"))
        menu.addItem(boundItem(.reveal, symbol: "doc.text.magnifyingglass"))

        menu.addItem(.separator())

        menu.addItem(makeItem(
            "Scratchpad Folder…", symbol: "folder", action: #selector(handlePickStorageLocation)
        ))
        let reset = makeItem(
            "Reset Scratchpad Folder",
            symbol: "arrow.uturn.backward",
            action: #selector(handleResetStorageLocation)
        )
        resetItem = reset
        menu.addItem(reset)

        menu.addItem(makeItem(
            "Set Shortcut…", symbol: "keyboard", action: #selector(handleSetHotKey)
        ))

        let launch = makeItem(
            "Launch at Login", symbol: "power", action: #selector(handleToggleLaunchAtLogin)
        )
        launchItem = launch
        menu.addItem(launch)

        // Opens wisp.jsonc, the only way most settings are changed.
        menu.addItem(boundItem(.settings, symbol: "gearshape"))

        menu.addItem(.separator())

        // ⌘Q fires only while this menu is open, so it collides with nothing.
        let quit = makeItem(
            "Quit Wisp", symbol: "xmark.circle", action: #selector(NSApplication.terminate(_:))
        )
        // A nil target sends terminate: up the responder chain.
        quit.target = nil
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    /// Control-click counts as right. The menu is assigned only while opening, or AppKit opens it
    /// on every click.
    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isSecondary =
            event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true
        guard isSecondary else {
            perform(.summon)
            return
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    /// Stamps each item with its live chord. These equivalents fire only while the menu is open,
    /// so they can't collide with `KeyBindingMonitor`.
    func apply(_ keymap: Keymap) {
        for (action, item) in boundItems {
            guard let equivalent = keymap.parsed(action)?.menuEquivalent else {
                // Unparseable or unspellable: better a bare item than a wrong one.
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
                continue
            }
            item.keyEquivalent = equivalent.character
            item.keyEquivalentModifierMask = equivalent.modifiers
        }
    }

    // "Veil", direction 9a from the icon canvas: at 18px only the ring and core survive, with the
    // trail as one tapered plume rising from the ring and a clipped gradient for its alpha. Drawn
    // rather than bundled, since there is no asset catalog.
    private static func makeStatusIcon() -> NSImage {
        let size = CGSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            // The canvas's 30-unit grid, y down; the artwork's span, not the grid, fills the 18pt.
            let artworkTop: CGFloat = 0.2
            let k = rect.width / 29.5
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.midX + (x - 15) * k, y: rect.maxY - (y - artworkTop) * k)
            }
            func ink(_ alpha: CGFloat) -> CGColor {
                NSColor.black.withAlphaComponent(alpha).cgColor
            }

            let center = point(15, 20.7)
            let ringOuter = 9 * k
            let tip = point(15, 0.6)

            // 58° off vertical: a plume, never wider than its ring.
            let shoulder = 58 * CGFloat.pi / 180
            let flank = CGPoint(
                x: center.x + ringOuter * sin(shoulder), y: center.y + ringOuter * cos(shoulder)
            )
            let rise = tip.y - flank.y
            let waist = center.x + (flank.x - center.x) * 0.14

            let plume = CGMutablePath()
            plume.addArc(
                center: center, radius: ringOuter,
                startAngle: .pi / 2 + shoulder, endAngle: .pi / 2 - shoulder, clockwise: true
            )
            plume.addCurve(
                to: tip,
                control1: CGPoint(x: flank.x, y: flank.y + rise * 0.45),
                control2: CGPoint(x: waist, y: tip.y - rise * 0.22)
            )
            plume.addCurve(
                to: CGPoint(x: 2 * center.x - flank.x, y: flank.y),
                control1: CGPoint(x: 2 * center.x - waist, y: tip.y - rise * 0.22),
                control2: CGPoint(x: 2 * center.x - flank.x, y: flank.y + rise * 0.45)
            )
            plume.closeSubpath()

            context.saveGState()
            context.addPath(plume)
            context.clip()
            let ramp = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [ink(0.95), ink(0.65), ink(0.35), ink(0)] as CFArray,
                locations: [0, 0.35, 0.7, 1]
            )!
            context.drawLinearGradient(
                ramp,
                start: CGPoint(x: center.x, y: flank.y), end: CGPoint(x: center.x, y: tip.y),
                options: []
            )
            context.restoreGState()

            context.setStrokeColor(ink(1))
            context.setLineWidth(3 * k)
            context.addArc(
                center: center, radius: 7.5 * k,
                startAngle: 0, endAngle: .pi * 2, clockwise: false
            )
            context.strokePath()

            context.setFillColor(ink(1))
            context.addArc(
                center: center, radius: 3.2 * k,
                startAngle: 0, endAngle: .pi * 2, clockwise: false
            )
            context.fillPath()

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Titled from the action, stamped by `apply(_:)`, and run through `perform`.
    private func boundItem(_ action: KeymapAction, symbol: String) -> NSMenuItem {
        let item = makeItem(action.title, symbol: symbol, action: #selector(handleBoundItem))
        item.representedObject = action
        boundItems.append((action, item))
        return item
    }

    private func makeItem(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(textStyle: .body, scale: .small)
            item.image = base.withSymbolConfiguration(config)
        }
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchItem?.state = currentLaunchAtLogin() ? .on : .off
        resetItem?.isHidden = !isStorageCustom()
    }

    @objc private func handleSetHotKey() {
        onSetHotKey()
    }

    @objc private func handleToggleLaunchAtLogin() {
        onToggleLaunchAtLogin()
    }

    @objc private func handlePickStorageLocation() {
        onPickStorageLocation()
    }

    @objc private func handleResetStorageLocation() {
        onResetStorageLocation()
    }

    @objc private func handleBoundItem(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? KeymapAction else { return }
        perform(action)
    }
}
