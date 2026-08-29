import AppKit

@MainActor
enum MainMenuBuilder {
    static func make(target: AnyObject) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(AppDelegate.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = target
        appMenu.addItem(settingsItem)
        // Re-reads wisp.jsonc and the note. Here as well as in the
        // menu-bar menu so ⌘R works while the panel has focus, which is
        // where the reloaded note actually shows up.
        let refreshItem = NSMenuItem(
            title: "Refresh",
            action: #selector(AppDelegate.refresh(_:)),
            keyEquivalent: "r"
        )
        refreshItem.target = target
        appMenu.addItem(refreshItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit Wisp",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Undo",
            action: NSSelectorFromString("undo:"),
            keyEquivalent: "z"
        )
        let redoItem = NSMenuItem(
            title: "Redo",
            action: NSSelectorFromString("redo:"),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenu.addItem(NSMenuItem.separator())
        let findItem = NSMenuItem(
            title: "Find",
            action: #selector(AppDelegate.showFind(_:)),
            keyEquivalent: "f"
        )
        findItem.target = target
        editMenu.addItem(findItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let formatMenuItem = NSMenuItem()
        let formatMenu = NSMenu(title: "Format")
        let boldItem = NSMenuItem(
            title: "Bold",
            action: #selector(AppDelegate.toggleBold(_:)),
            keyEquivalent: "b"
        )
        boldItem.target = target
        formatMenu.addItem(boldItem)
        let italicItem = NSMenuItem(
            title: "Italic",
            action: #selector(AppDelegate.toggleItalic(_:)),
            keyEquivalent: "i"
        )
        italicItem.target = target
        formatMenu.addItem(italicItem)
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let smallItem = NSMenuItem(
            title: "Smaller Text",
            action: #selector(AppDelegate.setSmallFont(_:)),
            keyEquivalent: "1"
        )
        smallItem.target = target
        viewMenu.addItem(smallItem)
        let mediumItem = NSMenuItem(
            title: "Default Text Size",
            action: #selector(AppDelegate.setMediumFont(_:)),
            keyEquivalent: "2"
        )
        mediumItem.target = target
        viewMenu.addItem(mediumItem)
        let largeItem = NSMenuItem(
            title: "Larger Text",
            action: #selector(AppDelegate.setLargeFont(_:)),
            keyEquivalent: "3"
        )
        largeItem.target = target
        viewMenu.addItem(largeItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        return mainMenu
    }
}
