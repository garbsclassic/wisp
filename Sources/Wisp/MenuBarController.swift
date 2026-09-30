import AppKit
import WispCore

/// Owns the single status-bar item. A left click pins the panel, or
/// dismisses the pin that's up; a right click opens the menu. The menu
/// refreshes its dynamic state — Launch at Login checkmark, Reset
/// Scratchpad Folder visibility — in menuNeedsUpdate rather than being
/// rebuilt each time.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    /// The items that stand for a keymap action run it here, the same
    /// dispatch its chord goes through.
    private let perform: (KeymapAction) -> Void
    private let onSetHotKey: () -> Void
    private let currentLaunchAtLogin: () -> Bool
    private let onToggleLaunchAtLogin: () -> Void
    private let isStorageCustom: () -> Bool
    private let onPickStorageLocation: () -> Void
    private let onResetStorageLocation: () -> Void
    private let menu = NSMenu()

    // Strong: NSMenuItem.target is weak, so holding items here can't
    // cycle, and it drops the assign-after-addItem ordering rule that
    // weak refs made load-bearing.
    private var launchItem: NSMenuItem?
    private var resetItem: NSMenuItem?
    /// The items whose chord is configurable, so `apply(_:)` can re-stamp
    /// them from the live keymap.
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
            // Left on the up, as a toggle; right on the down, as a native
            // context menu opens. The same split as Clef's.
            button.sendAction(on: [.leftMouseUp, .rightMouseDown])
        }

        menu.delegate = self

        // Menu-bar-extra order: the app's own actions first, then its
        // settings, Quit last. Wording and icons follow Clef's menu where an
        // item exists in both.
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

        // ⌘Q here fires only while this menu is open — a status item's
        // menu isn't the app's main menu, so it can't collide with
        // anything else.
        let quit = makeItem(
            "Quit Wisp", symbol: "xmark.circle", action: #selector(NSApplication.terminate(_:))
        )
        // nil target sends terminate: up the responder chain to NSApp;
        // makeItem's default of `self` would just make it a dead item.
        quit.target = nil
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    /// Splits the click by button, control-click counting as a right click
    /// for a trackpad. The menu is assigned only for as long as it takes to
    /// open: a permanently assigned one is what makes AppKit open it on
    /// *every* click, and takes the left button away.
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

    /// Stamps each configurable item with the chord actually bound to it.
    ///
    /// The chords are not hardcoded here because they are not this menu's to
    /// decide: the same actions are dispatched by `KeyBindingMonitor` while
    /// the menu is *closed*, and an item printing `⌘R` next to an action the
    /// config has moved to `⌘G` is telling the user something untrue.
    ///
    /// A key equivalent on a status-item menu only fires while that menu is
    /// open — it is not the app's main menu — so this can't collide with the
    /// monitor, which never sees events during a menu tracking loop.
    func apply(_ keymap: Keymap) {
        for (action, item) in boundItems {
            guard let equivalent = keymap.parsed(action)?.menuEquivalent else {
                // A chord that doesn't parse, or one AppKit has no menu
                // spelling for. Better a bare item than a wrong one.
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
                continue
            }
            item.keyEquivalent = equivalent.character
            item.keyEquivalentModifierMask = equivalent.modifiers
        }
    }

    // "Veil": the aperture reduced to a ring and a core, with the vapor trail
    // above it — direction 9a from the icon canvas, matched to the app tile.
    // At 18px the bands can't survive, so only the outer ring and core remain.
    //
    // The trail departs from the canvas geometry, whose stacked ellipses read
    // at this size as a widening pile with ears flaring past the ring. It is
    // one tapered plume instead: its base *is* the ring's outer arc, so the
    // two are continuous, and it narrows to a point. A clipped linear
    // gradient carries the alpha ramp — no blur, so the template image stays
    // crisp. Drawn rather than bundled since the app ships no asset catalog;
    // isTemplate lets AppKit tint it for the bar.
    private static func makeStatusIcon() -> NSImage {
        let size = CGSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            // Authored on the canvas's 30-unit grid, y running downwards. The
            // artwork only spans y 0.2...29.7 of that grid, so the span — not
            // the grid — is what's fitted to the image, filling the full 18pt.
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

            // Shoulders 58° off vertical: wide enough to look like a plume,
            // never wider than the ring it rises from.
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

    /// An item for a keymap action: titled from the action, stamped with
    /// its chord by `apply(_:)`, and run through `perform`.
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
