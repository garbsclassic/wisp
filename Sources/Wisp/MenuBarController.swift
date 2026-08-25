import AppKit

/// Owns the single status-bar item. The menu is assigned permanently,
/// which is what makes a plain left click open it (the old performClick
/// trick is unnecessary); there is no separate right-click behavior.
/// Item wording and icons follow Clef's menu where an item exists in
/// both apps. Dynamic state — Launch at Login checkmark, Reset Storage
/// visibility, current shortcut — refreshes in menuWillOpen rather than
/// rebuilding the menu each time.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onClick: () -> Void
    private let currentHotKey: () -> HotKey
    private let onSetHotKey: () -> Void
    private let onShowAbout: () -> Void
    private let currentLaunchAtLogin: () -> Bool
    private let onToggleLaunchAtLogin: () -> Void
    private let isStorageCustom: () -> Bool
    private let onPickStorageLocation: () -> Void
    private let onResetStorageLocation: () -> Void

    private weak var shortcutItem: NSMenuItem?
    private weak var launchItem: NSMenuItem?
    private weak var resetItem: NSMenuItem?

    init(
        onClick: @escaping () -> Void,
        currentHotKey: @escaping () -> HotKey,
        onSetHotKey: @escaping () -> Void,
        onShowAbout: @escaping () -> Void,
        currentLaunchAtLogin: @escaping () -> Bool,
        onToggleLaunchAtLogin: @escaping () -> Void,
        isStorageCustom: @escaping () -> Bool,
        onPickStorageLocation: @escaping () -> Void,
        onResetStorageLocation: @escaping () -> Void
    ) {
        self.onClick = onClick
        self.currentHotKey = currentHotKey
        self.onSetHotKey = onSetHotKey
        self.onShowAbout = onShowAbout
        self.currentLaunchAtLogin = currentLaunchAtLogin
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
        self.isStorageCustom = isStorageCustom
        self.onPickStorageLocation = onPickStorageLocation
        self.onResetStorageLocation = onResetStorageLocation
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            // SF Symbol `wind` reads as "wisp" — a single curved stroke,
            // simpler and more on-brand than the default pencil glyph.
            let image = NSImage(systemSymbolName: "wind", accessibilityDescription: "Wisp")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeItem("Open Wisp", symbol: "square.and.pencil", action: #selector(openFromMenu)))
        shortcutItem = makeItem(
            "Set Shortcut…", symbol: "keyboard", action: #selector(handleSetHotKey)
        )
        menu.addItem(shortcutItem!)
        launchItem = makeItem(
            "Launch at Login", symbol: "power", action: #selector(handleToggleLaunchAtLogin)
        )
        menu.addItem(launchItem!)

        menu.addItem(.separator())

        menu.addItem(makeItem("Storage Location…", symbol: "folder", action: #selector(handlePickStorageLocation)))
        resetItem = makeItem(
            "Reset Storage Location",
            symbol: "arrow.uturn.backward",
            action: #selector(handleResetStorageLocation)
        )
        menu.addItem(resetItem!)

        menu.addItem(.separator())

        menu.addItem(makeItem("About Wisp", symbol: "info.circle", action: #selector(handleShowAbout)))

        menu.addItem(.separator())

        // ⌘Q here fires only while this menu is open — a status item's
        // menu isn't the app's main menu, so it can't collide with
        // anything else.
        menu.addItem(NSMenuItem(
            title: "Quit Wisp",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // Assigned permanently so any click — left or right — opens it.
        statusItem.menu = menu
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

    func menuWillOpen(_ menu: NSMenu) {
        launchItem?.state = currentLaunchAtLogin() ? .on : .off
        resetItem?.isHidden = !isStorageCustom()
        shortcutItem?.title = "Set Shortcut…  (\(currentHotKey().displayString))"
    }

    @objc private func openFromMenu() {
        onClick()
    }

    @objc private func handleSetHotKey() {
        onSetHotKey()
    }

    @objc private func handleShowAbout() {
        onShowAbout()
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
}
