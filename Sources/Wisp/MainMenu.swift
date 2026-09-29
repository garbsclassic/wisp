import AppKit

/// Builds the main menu, which carries only the standard editing commands.
///
/// The app is `.accessory`, so this menu bar is never drawn — it exists
/// purely for key equivalents that reach the notes view through the
/// responder chain. Every configurable chord is dispatched by
/// `KeyBindingMonitor` instead: `keyEquivalent` cannot express an
/// Option-modified letter, since macOS composes `⌥L` into `¬` before AppKit
/// compares characters.
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
                // Cut and Copy fall back to the whole line when nothing is
                // selected — see NotesTextView, which overrides them.
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
    /// Adds a submenu in the one shape this menu bar uses: a titled menu
    /// under an otherwise-empty parent item.
    fileprivate func addItem(submenu title: String, items: [NSMenuItem]) {
        let parent = NSMenuItem()
        let menu = NSMenu(title: title)
        for item in items { menu.addItem(item) }
        parent.submenu = menu
        addItem(parent)
    }
}
