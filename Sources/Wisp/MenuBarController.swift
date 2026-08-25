import AppKit

@MainActor
final class MenuBarController: NSObject {
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
            button.target = self
            button.action = #selector(handleClick)
            // Receive right-click too so we can show a context menu with Quit.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            onClick()
        }
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

    private func showContextMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "Open Wisp",
            action: #selector(openFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let hotKeyItem = NSMenuItem(
            title: "Set Shortcut…  (\(currentHotKey().displayString))",
            action: #selector(handleSetHotKey),
            keyEquivalent: ""
        )
        hotKeyItem.target = self
        menu.addItem(hotKeyItem)

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(handleToggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = currentLaunchAtLogin() ? .on : .off
        menu.addItem(launchItem)

        let storageItem = NSMenuItem(
            title: "Storage Location…",
            action: #selector(handlePickStorageLocation),
            keyEquivalent: ""
        )
        storageItem.target = self
        menu.addItem(storageItem)

        if isStorageCustom() {
            let resetItem = NSMenuItem(
                title: "Reset Storage Location",
                action: #selector(handleResetStorageLocation),
                keyEquivalent: ""
            )
            resetItem.target = self
            menu.addItem(resetItem)
        }

        let aboutItem = NSMenuItem(
            title: "About Wisp",
            action: #selector(handleShowAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Wisp",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
