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
    /// The chord Carbon has registered, which differs from the config's if registering failed.
    private var summon: KeyChord?
    /// Every chord but `summon`, which Carbon owns so it fires while another app is in front.
    private var keyBindings: KeyBindingMonitor?
    /// Live reload of the config and the note; the note's is rebuilt when the scratchpad moves.
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

        // If this fails too, Wisp has no hotkey until the user rebinds it from the menu.
        adoptSummon(from: settings.config)

        // For the capture overlay.
        model.tryUpdateHotKey = { [weak self] chord in
            guard let self else { return "Internal error" }
            guard self.registerSummon(chord) else {
                return
                    "\(chord.displayString) is already used by another app or macOS. Try another combo."
            }
            self.settings.setSummon(chord)
            return nil
        }

        // Nothing shows at launch: a login-item launch can't be told from a user's, so only the
        // hotkey, the menu, and a re-launch open the panel.
    }

    /// A re-launch while running, from Spotlight or Finder, opens the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        presentForUserAction()
        return true
    }

    /// Activates Wisp; the hotkey summon doesn't, so it takes no focus from the app in front.
    private func presentForUserAction() {
        NSApp.activate(ignoringOtherApps: true)
        panelController?.openIfNeeded()
    }

    /// Only when the chord changed, since a re-registration can fail and lose the binding.
    private func adoptSummon(from config: WispConfig) {
        if config.summonChord != summon { registerSummon(config.summonChord) }
    }

    /// When Carbon rejects `chord`, usually because something else owns it, the previous chord is
    /// restored once.
    @discardableResult
    private func registerSummon(_ chord: KeyChord) -> Bool {
        if register(chord) {
            summon = chord
            return true
        }
        if let previous = summon, !register(previous) { summon = nil }
        return false
    }

    private func register(_ chord: KeyChord) -> Bool {
        hotKey.register(
            keyCode: chord.keyCode, modifiers: chord.carbonModifiers,
            onPress: { [weak self] in
                self?.panelController?.handleChordDown(modifiers: chord.modifierFlags)
            },
            onRelease: { [weak self] in self?.panelController?.handleChordUp() })
    }

    /// Where a keymap action becomes work, from `KeyBindingMonitor` or the status menu.
    private func perform(_ action: KeymapAction) {
        let notes = panelController?.focusedNotesView
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
        case .bold: notes?.toggleWrap(.bold)
        case .italic: notes?.toggleWrap(.italic)
        case .highlight: notes?.toggleWrap(.highlight)
        case .underline: notes?.toggleWrap(.underline)
        case .strikethrough: notes?.toggleWrap(.strikethrough)
        case .code: notes?.toggleWrap(.code)
        case .duplicateLine: notes?.duplicateSelection()
        case .openLineBelow: notes?.openLine(below: true)
        case .openLineAbove: notes?.openLine(below: false)
        case .bulletedList: notes?.toggleBulletedList()
        case .checklist: notes?.toggleChecklist()
        case .moveLineUp: notes?.moveLines(by: -1)
        case .moveLineDown: notes?.moveLines(by: 1)
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
        model.flushSave()
        // Otherwise written on hide, which quitting skips.
        panelController?.savePanelFrameIfVisible()
    }

    /// Confirms before adopting a folder's existing scratchpad; the local text is backed up.
    private func pickStorageLocation() {
        // Activate first, or the open panel can sit behind the desktop.
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
            // Even when unchanged: it re-baselines the mtime, so our own write isn't a change.
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

    /// Hides the panel first, since the config opens in another app.
    private func openSettings() {
        panelController?.dismiss()
        settings.openConfigFile()
    }

    /// Re-reads the config and checks the note's mtime, showing the panel so the result is visible.
    private func refresh() {
        panelController?.openIfNeeded()
        reloadConfig()
        model.reloadFromDiskIfChanged()
    }

    /// Shared by ⌘R and the config watcher. A no-op when nothing changed, since Wisp's own writes
    /// come back as watcher events.
    private func reloadConfig() {
        let previous = settings.config
        settings.reload()
        guard settings.config != previous else { return }

        model.adoptSettings()
        adoptSummon(from: settings.config)
        // Both are pure functions of the keymap.
        if settings.config.keymap != previous.keymap {
            keyBindings?.apply(settings.config.keymap)
            menuBarController?.apply(settings.config.keymap)
        }
        // The note moved: the watcher and the mtime baseline point at the old file.
        if settings.config.scratchpadFolder != previous.scratchpadFolder {
            startNoteWatcher()
            model.adoptScratchpadAtCurrentPath()
        }
    }

    /// The folder, not the file: writers replace it by rename, so a watch on the old inode sees
    /// nothing.
    private func startNoteWatcher() {
        noteWatcher = DirectoryWatcher(directoryURL: settings.config.scratchpadFolderPath) {
            [weak self] in
            self?.model.reloadFromDiskIfChanged()
        }
    }
}
