import AppKit
import SwiftUI
import WispCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()
    lazy var model = EditorModel(settings: settings)
    private var menuBarController: MenuBarController?
    private var panelController: PanelController?
    private let hotKey = HotKeyMonitor()
    /// Every configurable chord except `summon`, which Carbon owns because
    /// it has to fire while another app is frontmost.
    private var keyBindings: KeyBindingMonitor?
    /// Live reload: wisp.jsonc changed by hand or by a chezmoi apply, and
    /// scratchpad.md changed by another Mac through iCloud Drive, Dropbox,
    /// or Syncthing. The note watcher is rebuilt whenever the scratchpad
    /// moves, since it is bound to one directory for its lifetime.
    private var configWatcher: DirectoryWatcher?
    private var noteWatcher: DirectoryWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.make()
        let panel = PanelController(model: model, settings: settings)
        panelController = panel
        menuBarController = MenuBarController(
            perform: { [weak self] action in self?.perform(action) },
            onSetHotKey: { [weak self, weak panel] in
                panel?.openIfNeeded()
                self?.model.showHotKeyCapture = true
            },
            currentLaunchAtLogin: { LaunchAtLogin.isEnabled },
            onToggleLaunchAtLogin: {
                LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
            },
            isStorageCustom: { [weak self] in
                StorageLocation.isCustom(self?.settings.config.scratchpadFolder ?? "")
            },
            onPickStorageLocation: { [weak self] in
                self?.pickStorageLocation()
            },
            onResetStorageLocation: { [weak self] in
                self?.resetStorageLocation()
            }
        )
        menuBarController?.apply(settings.config.keymap)

        let bindings = KeyBindingMonitor(
            isPanelFocused: { [weak panel] in panel?.isPanelFocused ?? false },
            perform: { [weak self] action in self?.perform(action) })
        bindings.apply(settings.config.keymap)
        keyBindings = bindings

        configWatcher = DirectoryWatcher(directoryURL: ConfigStore.directory) { [weak self] in
            self?.reloadConfig()
        }
        startNoteWatcher()
        let failures = [configWatcher, noteWatcher].compactMap { $0?.failureDescription }
        if !failures.isEmpty {
            settings.reportWatcherFailure(failures.joined(separator: " "))
        }

        // Initial registration uses the chord from wisp.jsonc (or the
        // default when the file doesn't name one). If
        // even this fails — e.g. user's saved binding is now claimed by
        // some other app — we leave the app without a hotkey; the user
        // can rebind from the menu bar menu.
        _ = registerHotKey(model.hotKey)

        // Mediator the capture overlay calls when the user picks a
        // combo. Tries Carbon registration; on failure we restore the
        // previous binding and surface a user-readable error.
        model.tryUpdateHotKey = { [weak self] hk in
            guard let self else { return "Internal error" }
            if self.registerHotKey(hk) {
                self.model.hotKey = hk
                return nil
            }
            // New binding rejected by Carbon — usually means another
            // app or macOS itself owns it. Re-register the previous
            // one so the user isn't left without any hotkey.
            _ = self.registerHotKey(self.model.hotKey)
            return "\(hk.displayString) is already used by another app or macOS. Try another combo."
        }

        // Nothing is shown at launch: NSApplicationLaunchIsDefaultLaunchKey
        // isn't reliably false for an SMAppService login item, so there is
        // no telling a login launch from a user one. The hotkey, the menu bar
        // item, and a re-launch all open the panel — see
        // applicationShouldHandleReopen.
    }

    /// Re-launching the app while it's already running (Spotlight,
    /// Finder double-click) hits this. Treat it as "open the panel."
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        presentForUserAction()
        return true
    }

    /// Bring Wisp to the front and show the panel — the re-launch path,
    /// the only launch-adjacent one that opens anything. The hotkey summon
    /// stays separate so it doesn't steal focus from
    /// whatever app the user was in when they pressed the chord.
    private func presentForUserAction() {
        NSApp.activate(ignoringOtherApps: true)
        panelController?.openIfNeeded()
    }

    @discardableResult
    private func registerHotKey(_ hk: HotKey) -> Bool {
        hotKey.register(
            keyCode: hk.keyCode, modifiers: hk.modifiers,
            onPress: { [weak self] in
                self?.panelController?.handleChordDown(modifiers: hk.modifiers)
            },
            onRelease: { [weak self] in self?.panelController?.handleChordUp() })
    }

    /// The one place a keymap action turns into work. `KeyBindingMonitor`
    /// and the status menu both land here.
    private func perform(_ action: KeymapAction) {
        switch action {
        case .summon: panelController?.togglePin()
        case .find:
            panelController?.openIfNeeded()
            model.openFind()
        case .settings: openSettings()
        case .refresh: refresh()
        case .help: model.toggleHelp()
        case .cycleTheme: model.cycleTheme()
        case .sourceView: model.toggleSourceView()
        case .spellcheck: model.toggleSpellcheck()
        case .bold: model.toggleBold()
        case .italic: model.toggleItalic()
        case .highlight: model.toggleHighlight()
        case .underline: model.toggleUnderline()
        case .strikethrough: model.toggleStrikethrough()
        case .code: model.toggleCode()
        case .duplicateLine: model.duplicateSelection()
        case .openLineBelow: model.openLine(below: true)
        case .openLineAbove: model.openLine(below: false)
        case .bulletedList: model.toggleBulletedList()
        case .checklist: model.toggleChecklist()
        case .moveLineUp: model.moveLine(by: -1)
        case .moveLineDown: model.moveLine(by: 1)
        case .previousHeading: model.jumpToHeading(.previous)
        case .nextHeading: model.jumpToHeading(.next)
        case .increaseFontScale: model.stepFontScale(by: 1)
        case .decreaseFontScale: model.stepFontScale(by: -1)
        case .resetFontScale: model.resetFontScale()
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting([model.scratchpadURL])
        case .resetPosition: panelController?.resetPosition()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush any pending debounced save so quitting never loses the
        // last few keystrokes.
        model.flushSave()
        // The frame is otherwise written on hide; quitting with the panel
        // still open never hides it.
        panelController?.savePanelFrameIfVisible()
    }

    /// Open an NSOpenPanel for the user to pick a folder. If the
    /// chosen folder already contains a scratchpad.md, confirm before
    /// adopting it (the local text gets backed up either way). The
    /// panel's sidebar shows iCloud Drive as a one-click destination,
    /// so users wanting iCloud sync just navigate there.
    private func pickStorageLocation() {
        // Make sure the panel is open and active so NSOpenPanel attaches
        // somewhere visible; otherwise it can sit behind the desktop.
        panelController?.openIfNeeded()
        NSApp.activate(ignoringOtherApps: true)

        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Wisp's Scratchpad Folder"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = settings.config.scratchpadFolderPath

        guard openPanel.runModal() == .OK, let folder = openPanel.url else { return }

        let candidate = StorageLocation.scratchpadURL(in: folder)
        let destinationHasFile = FileManager.default.fileExists(atPath: candidate.path)
        if destinationHasFile {
            let alert = NSAlert()
            alert.messageText = "A scratchpad already exists in this folder"
            alert.informativeText = "Use the existing one? Your current text will be saved as a backup file in the previous location."
            alert.addButton(withTitle: "Use Existing")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .informational
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            let result = try StorageLocation.setFolder(
                folder, currentText: model.text,
                currentFolder: settings.config.scratchpadFolderPath)
            settings.setScratchpadFolder(folder.path)
            startNoteWatcher()
            // Also when the text is unchanged: it re-baselines the mtime, so
            // the next reloadFromDiskIfChanged doesn't trip on our own write.
            model.adoptLoadedText(result.text)
            if let backupURL = result.backupURL {
                let alert = NSAlert()
                alert.messageText = "Local text saved as backup"
                alert.informativeText = "Your previous scratchpad was saved to:\n\(backupURL.path)"
                alert.addButton(withTitle: "OK")
                alert.alertStyle = .informational
                _ = alert.runModal()
            }
        } catch {
            let alert = NSAlert(error: error)
            _ = alert.runModal()
        }
    }

    private func resetStorageLocation() {
        guard StorageLocation.isCustom(settings.config.scratchpadFolder) else { return }
        do {
            try StorageLocation.resetToDefault(currentText: model.text)
            settings.setScratchpadFolder("")
            startNoteWatcher()
            model.adoptLoadedText(model.text)
        } catch {
            let alert = NSAlert(error: error)
            _ = alert.runModal()
        }
    }

    /// ⌘, and the status menu's Settings….
    ///
    /// The panel goes away first: settings open in whatever app owns
    /// .jsonc, and leaving Wisp floating over the editor you are about to
    /// type in is the wrong half of the screen.
    private func openSettings() {
        panelController?.dismiss()
        settings.openConfigFile()
    }

    /// ⌘R and the status menu's Refresh — re-reads wisp.jsonc and re-checks
    /// scratchpad.md's mtime, for either changing on disk without Wisp's
    /// own writes (iCloud Drive, Dropbox, or a chezmoi apply on another
    /// Mac).
    ///
    /// Shows the panel, since a refresh you can't see the result of isn't
    /// worth a keystroke; one already open stays open and keeps its
    /// selection.
    private func refresh() {
        panelController?.openIfNeeded()
        reloadConfig()
        model.reloadFromDiskIfChanged()
    }

    /// Re-reads wisp.jsonc and applies whatever changed in it. Shared by
    /// ⌘R and the config watcher, so a hand-edit and a menu Refresh land in
    /// exactly the same place.
    ///
    /// Does nothing when the file's contents haven't actually changed —
    /// Wisp writes this file itself on every theme flip, text-size change,
    /// and panel hide, and each of those comes back as a watcher event.
    private func reloadConfig() {
        let previous = settings.config
        settings.reload()
        guard settings.config != previous else { return }

        model.adoptSettings()
        // The binding table and the status menu's equivalents are pure
        // functions of the keymap, so a changed one means rebuilding both.
        if settings.config.keymap != previous.keymap {
            keyBindings?.apply(settings.config.keymap)
            menuBarController?.apply(settings.config.keymap)
        }
        // The note itself moved, so the watcher is pointed at the wrong
        // directory and the mtime baseline describes the wrong file.
        if settings.config.scratchpadFolder != previous.scratchpadFolder {
            startNoteWatcher()
            model.adoptScratchpadAtCurrentPath()
        }
    }

    /// (Re)starts the watcher on the folder holding scratchpad.md. The
    /// folder, not the file: every writer here replaces it by rename, and
    /// a watch on the old inode would see nothing.
    private func startNoteWatcher() {
        noteWatcher = DirectoryWatcher(directoryURL: settings.config.scratchpadFolderPath) {
            [weak self] in
            self?.model.reloadFromDiskIfChanged()
        }
    }
}
