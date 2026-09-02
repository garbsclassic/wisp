import AppKit
import WispCore

/// Builds the main menu from the config's keymap.
///
/// The app is `.accessory`, so this menu bar is never drawn — it exists
/// purely to carry key equivalents. That is also why every item is wired to
/// the delegate rather than to the responder chain: an item with a target is
/// offered to `validateMenuItem`, which is what scopes a chord to the
/// focused panel.
@MainActor
enum MainMenuBuilder {
    /// Actions that dispatch to the delegate. `NSText`'s own editing items
    /// (cut/copy/paste/undo) stay on the responder chain, since the notes
    /// view overrides them directly.
    private static let selectors: [KeymapAction: Selector] = [
        .find: #selector(AppDelegate.showFind(_:)),
        .settings: #selector(AppDelegate.openSettings(_:)),
        .refresh: #selector(AppDelegate.refresh(_:)),
        .help: #selector(AppDelegate.toggleHelp(_:)),
        .bold: #selector(AppDelegate.toggleBold(_:)),
        .italic: #selector(AppDelegate.toggleItalic(_:)),
        .highlight: #selector(AppDelegate.toggleHighlight(_:)),
        .duplicateLine: #selector(AppDelegate.duplicateSelection(_:)),
        .toggleListItem: #selector(AppDelegate.toggleListItem(_:)),
        .moveLineUp: #selector(AppDelegate.moveLineUp(_:)),
        .moveLineDown: #selector(AppDelegate.moveLineDown(_:)),
        .increaseFontScale: #selector(AppDelegate.increaseFontScale(_:)),
        .decreaseFontScale: #selector(AppDelegate.decreaseFontScale(_:)),
        .resetFontScale: #selector(AppDelegate.resetFontScale(_:)),
    ]

    /// The action a menu item stands for, recovered from its selector.
    /// `validateMenuItem` uses this to reach `isPanelScoped`, so the gate
    /// and the binding are read off the same table.
    static func action(for selector: Selector) -> KeymapAction? {
        selectors.first { $0.value == selector }?.key
    }

    static func make(target: AnyObject, keymap: Keymap) -> NSMenu {
        let mainMenu = NSMenu()

        mainMenu.addItem(
            submenu: "Wisp",
            items: [
                item(.settings, target: target, keymap: keymap),
                item(.refresh, target: target, keymap: keymap),
                .separator(),
                NSMenuItem(
                    title: "Quit Wisp", action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q"),
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
                item(.duplicateLine, target: target, keymap: keymap),
                item(.moveLineUp, target: target, keymap: keymap),
                item(.moveLineDown, target: target, keymap: keymap),
                .separator(),
                NSMenuItem(
                    title: "Select All", action: #selector(NSText.selectAll(_:)),
                    keyEquivalent: "a"),
                .separator(),
                item(.find, target: target, keymap: keymap),
            ])

        mainMenu.addItem(
            submenu: "Format",
            items: [
                item(.bold, target: target, keymap: keymap),
                item(.italic, target: target, keymap: keymap),
                item(.highlight, target: target, keymap: keymap),
                .separator(),
                item(.toggleListItem, target: target, keymap: keymap),
            ])

        mainMenu.addItem(
            submenu: "View",
            items: [
                item(.increaseFontScale, target: target, keymap: keymap),
                item(.decreaseFontScale, target: target, keymap: keymap),
                item(.resetFontScale, target: target, keymap: keymap),
            ])

        // Titled "Shortcuts" rather than "Help" so AppKit doesn't claim it
        // as *the* help menu and graft its search field on.
        mainMenu.addItem(
            submenu: "Shortcuts", items: [item(.help, target: target, keymap: keymap)])

        return mainMenu
    }

    /// One item for a keymap action — deliberately with *no* key
    /// equivalent.
    ///
    /// `KeyBindingMonitor` dispatches every configurable chord, because
    /// `keyEquivalent` cannot express an Option-modified letter (macOS
    /// composes `⌥L` into `¬` before AppKit compares characters). Leaving
    /// the equivalent off is what stops a ⌘-chord firing twice — once from
    /// the menu and once from the monitor.
    ///
    /// The items themselves stay: the app is `.accessory`, so this is not
    /// about a menu anyone reads, but `validateMenuItem` and the selector
    /// table both key off them.
    private static func item(
        _ action: KeymapAction, target: AnyObject, keymap: Keymap
    ) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: selectors[action], keyEquivalent: "")
        item.target = target
        return item
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
