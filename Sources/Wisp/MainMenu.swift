import AppKit

/// The never-drawn main menu, there for the standard edit commands' key equivalents.
/// Configurable chords go through `KeyBindingMonitor`, since `keyEquivalent` can't express an
/// ⌥-letter, which macOS composes first.
@MainActor
enum MainMenuBuilder {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()

        mainMenu.addItem(
            submenu: "Wisp",
            items: [
                NSMenuItem(
                    title: "Quit Wisp", action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q")
            ])

        let redo = NSMenuItem(
            title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        mainMenu.addItem(
            submenu: "Edit",
            items: [
                NSMenuItem(
                    title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z"),
                redo,
                .separator(),
                // NotesTextView's Cut and Copy take the whole line when nothing is selected.
                NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
                NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
                NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
                .separator(),
                NSMenuItem(
                    title: "Select All", action: #selector(NSText.selectAll(_:)),
                    keyEquivalent: "a"),
            ])

        return mainMenu
    }
}

extension NSMenu {
    fileprivate func addItem(submenu title: String, items: [NSMenuItem]) {
        let parent = NSMenuItem()
        let menu = NSMenu(title: title)
        for item in items { menu.addItem(item) }
        parent.submenu = menu
        addItem(parent)
    }
}
