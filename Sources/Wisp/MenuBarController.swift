import AppKit

/// Owns the single status-bar item. The permanently-assigned menu is
/// what makes any click open it, and it refreshes its dynamic state —
/// Launch at Login checkmark, Reset Scratchpad Folder visibility — in
/// menuWillOpen rather than being rebuilt each time. Wording and icons
/// follow Clef's menu where an item exists in both.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onSetHotKey: () -> Void
    private let onOpenConfig: () -> Void
    private let onRefresh: () -> Void
    private let currentLaunchAtLogin: () -> Bool
    private let onToggleLaunchAtLogin: () -> Void
    private let isStorageCustom: () -> Bool
    private let onPickStorageLocation: () -> Void
    private let onResetStorageLocation: () -> Void
    private let onRevealNote: () -> Void

    // Strong: NSMenuItem.target is weak, so holding items here can't
    // cycle, and it drops the assign-after-addItem ordering rule that
    // weak refs made load-bearing.
    private var launchItem: NSMenuItem?
    private var resetItem: NSMenuItem?

    init(
        onSetHotKey: @escaping () -> Void,
        onOpenConfig: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        currentLaunchAtLogin: @escaping () -> Bool,
        onToggleLaunchAtLogin: @escaping () -> Void,
        isStorageCustom: @escaping () -> Bool,
        onPickStorageLocation: @escaping () -> Void,
        onResetStorageLocation: @escaping () -> Void,
        onRevealNote: @escaping () -> Void
    ) {
        self.onSetHotKey = onSetHotKey
        self.onOpenConfig = onOpenConfig
        self.onRefresh = onRefresh
        self.currentLaunchAtLogin = currentLaunchAtLogin
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
        self.isStorageCustom = isStorageCustom
        self.onPickStorageLocation = onPickStorageLocation
        self.onResetStorageLocation = onResetStorageLocation
        self.onRevealNote = onRevealNote
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = Self.makeStatusIcon()
            image.accessibilityDescription = "Wisp"
            button.image = image
        }

        let menu = NSMenu()
        menu.delegate = self

        // Opens wisp.jsonc in whatever app owns .jsonc — the same move as
        // Clef's Settings…, and the only way most settings are changed.
        // ⌘, mirrors Clef's shortcut for it; fires while this menu is open.
        let settings = makeItem(
            "Settings…", symbol: "gearshape", action: #selector(handleOpenConfig)
        )
        settings.keyEquivalent = ","
        menu.addItem(settings)

        // Re-reads wisp.jsonc and re-checks scratchpad.md's mtime — for
        // either changing underfoot via iCloud/Dropbox/chezmoi sync.
        // ⌘R matches the main menu's item and fires while this menu is
        // open, the same arrangement Settings… above has with ⌘,.
        let refresh = makeItem(
            "Refresh", symbol: "arrow.clockwise", action: #selector(handleRefresh)
        )
        refresh.keyEquivalent = "r"
        menu.addItem(refresh)

        menu.addItem(makeItem(
            "Set Shortcut…", symbol: "keyboard", action: #selector(handleSetHotKey)
        ))

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

        menu.addItem(.separator())

        menu.addItem(makeItem(
            "Reveal Note in Finder", symbol: "doc.text.magnifyingglass",
            action: #selector(handleRevealNote)
        ))

        menu.addItem(.separator())

        let launch = makeItem(
            "Launch at Login", symbol: "power", action: #selector(handleToggleLaunchAtLogin)
        )
        launchItem = launch
        menu.addItem(launch)

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

        // Assigned permanently so any click — left or right — opens it.
        statusItem.menu = menu
    }

    // "Veil": the aperture reduced to a ring and a core, with the vapor
    // trail above it — direction 9a from the icon canvas, matched to the app
    // tile. At 18px the bands can't survive, so only the outer ring and core
    // remain, and the trail is alpha-ramped rather than blurred to keep the
    // template image crisp. Drawn rather than bundled since the app ships no
    // asset catalog; isTemplate lets AppKit tint it for the bar.
    private static func makeStatusIcon() -> NSImage {
        let size = CGSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            // Authored on the canvas's 30-unit grid, y running downwards.
            let k = rect.width / 30
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * k, y: rect.maxY - y * k)
            }
            func ink(_ alpha: CGFloat) -> CGColor {
                NSColor.black.withAlphaComponent(alpha).cgColor
            }

            // Vapor: a wide low-alpha skirt under a brighter body and a tip.
            // The skirt is what makes it read as vapor and not a stack of dots.
            let vapor: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (15, 10.4, 9.8, 4.3, 0.30),
                (15, 6.2, 6.2, 3.2, 0.20),
                (15, 10, 6.6, 3.3, 0.80),
                (14.7, 5.6, 4.1, 2.5, 0.50),
                (15.4, 2, 2.3, 1.8, 0.26),
            ]
            for (cx, cy, rx, ry, alpha) in vapor {
                let center = point(cx, cy)
                context.setFillColor(ink(alpha))
                context.fillEllipse(in: CGRect(
                    x: center.x - rx * k, y: center.y - ry * k,
                    width: rx * 2 * k, height: ry * 2 * k
                ))
            }

            let aperture = point(15, 20.7)
            context.setStrokeColor(ink(1))
            context.setLineWidth(3 * k)
            context.addArc(
                center: aperture, radius: 7.5 * k,
                startAngle: 0, endAngle: .pi * 2, clockwise: false
            )
            context.strokePath()

            context.setFillColor(ink(1))
            context.addArc(
                center: aperture, radius: 3.2 * k,
                startAngle: 0, endAngle: .pi * 2, clockwise: false
            )
            context.fillPath()

            return true
        }
        image.isTemplate = true
        return image
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

    @objc private func handleOpenConfig() {
        onOpenConfig()
    }

    @objc private func handleRefresh() {
        onRefresh()
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

    @objc private func handleRevealNote() {
        onRevealNote()
    }
}
