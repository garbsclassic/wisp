import AppKit

@MainActor
enum MainMenuBuilder {
    /// Builds one item wired to `target`, so `validateMenuItem` on the
    /// delegate gets a say in whether it fires. An item left targeting nil
    /// goes to the first responder and is never offered for validation.
    private static func item(
        _ title: String, _ action: Selector, _ key: String, target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

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
        // ⌘C and ⌘X above fall back to the whole line when nothing is
        // selected — see NotesTextView. ⌘D goes through the delegate
        // because it needs the panel-focus gate the others get for free
        // from the responder chain.
        editMenu.addItem(
            item("Duplicate", #selector(AppDelegate.duplicateSelection(_:)), "d", target: target))
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
        // One continuous scale replaces the old small/medium/large trio,
        // so these are the standard zoom chords rather than ⌘1 / ⌘2 / ⌘3.
        // ⌘= is bound to the unshifted key even though it reads as ⌘+,
        // which is the platform convention.
        viewMenu.addItem(
            item("Increase Text Size", #selector(AppDelegate.increaseFontScale(_:)), "=",
                 target: target))
        viewMenu.addItem(
            item("Decrease Text Size", #selector(AppDelegate.decreaseFontScale(_:)), "-",
                 target: target))
        viewMenu.addItem(
            item("Actual Size", #selector(AppDelegate.resetFontScale(_:)), "0", target: target))
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Titled "Shortcuts" rather than "Help" so AppKit doesn't claim it
        // as *the* help menu and graft its search field on. Invisible
        // either way — the app is `.accessory`, so this whole menu bar
        // exists only to carry key equivalents.
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Shortcuts")
        // ⌘/ rather than the more obvious ⌘?: macOS reserves ⇧⌘/ for the
        // help menu's own search field.
        helpMenu.addItem(
            item("Keyboard Shortcuts", #selector(AppDelegate.toggleHelp(_:)), "/", target: target))
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        return mainMenu
    }
}
