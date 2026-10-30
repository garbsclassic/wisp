import Observation
import SwiftUI
import WispCore

@Observable
@MainActor
final class EditorModel {
    var isPanelVisible = false
    private(set) var document = DocumentAnalysis("")
    var text: String {
        get { document.text }
        set {
            guard !document.matches(newValue) else { return }
            acceptEdit(DocumentAnalysis(newValue))
        }
    }
    var headings: [Heading] { document.headings }
    private var headingNavigation = HeadingNavigation()
    var navigationHeadings: [HeadingNavigation.Item] { headingNavigation.items }

    /// The editor hands over its final post-renumber revision, including its derived structure.
    func acceptEdit(_ revision: DocumentAnalysis) {
        guard isEditable, !document.matches(revision.text) else { return }
        var navigation = headingNavigation
        navigation.update(from: document, to: revision)
        headingNavigation = navigation
        document = revision
        cachedWordCount = nil
        cachedPosition = nil
        if didLoad, showFind, !showHelp { recomputeMatches(resetIndex: false) }
        guard didLoad, !isReloading else { return }
        scheduleSave()
    }

    @ObservationIgnored private var cachedPosition: (offset: Int, value: CaretPosition)?
    var caretPosition: CaretPosition {
        let revision = document
        let offset = caretOffset
        if let cachedPosition, cachedPosition.offset == offset { return cachedPosition.value }
        let value = revision.caretPosition(at: offset)
        cachedPosition = (offset, value)
        return value
    }
    @ObservationIgnored private var cachedWordCount: Int?
    /// The caret's UTF-16 offset, as the text view last reported it.
    var caretOffset = 0
    var focusToken: Int = 0
    var scrollToken: Int = 0
    /// Flashed briefly on each save; nothing schedules it when `saveIndicator` is off.
    private(set) var isShowingSaveFlash = false
    @ObservationIgnored private var saveFlashTask: Task<Void, Never>?
    private(set) var scrollTarget: Int = 0
    private(set) var placeholder: String = ""
    /// The raw text in the code face. Not persisted: it's a glance at the file, not a preference.
    var isSourceView: Bool = false

    // MARK: Help

    /// Held rather than computed, since it's find's source while the page is up.
    private(set) var helpDocument: HelpDocument
    /// Bumped to give the help page first responder, so ⌘A and ⌘C don't reach the note.
    private(set) var helpFocusToken: Int = 0
    var showHelp: Bool = false {
        didSet {
            guard didLoad, showHelp != oldValue else { return }
            requestFocus()
            // Find follows the page in front, so re-search the other document.
            if showFind { recomputeMatches(resetIndex: true) }
        }
    }

    // MARK: Find
    var showFind: Bool = false
    var findQuery: String = "" {
        didSet {
            // Tearing the bar down writes the field's value back, which would re-highlight a
            // cleared match.
            guard didLoad, showFind else { return }
            recomputeMatches(resetIndex: true)
        }
    }
    private(set) var findMatchCount: Int = 0
    /// 1-based, or 0 with no matches.
    private(set) var findCurrentDisplayIndex: Int = 0
    /// A zero-length range clears the highlight.
    var findHighlightToken: Int = 0
    private(set) var findHighlightRange = NSRange(location: 0, length: 0)
    @ObservationIgnored private var findMatches: [NSRange] = []
    @ObservationIgnored private var findIndex = 0
    private static let placeholders = [
        "What's on your mind?",
        "Type your first thought…",
        "Write it down before it's gone.",
        "Capture it before you forget.",
        "Anything to remember?",
    ]
    // Observation follows these reads into Settings.
    var fontScale: Double { settings.config.clampedFontScale }
    var spellcheck: Bool { settings.config.spellcheck }
    var footerStatus: FooterStatus { settings.config.footerStatus }
    var themeSetting: ThemeSetting { settings.config.theme }

    /// The resolved theme: `themeSetting`, or the system appearance under `.system`.
    private(set) var theme: Theme = .dark {
        didSet {
            onThemeChange?(theme)
        }
    }

    /// Lets the panel controller apply chrome changes; SwiftUI re-renders on its own.
    @ObservationIgnored var onThemeChange: (@MainActor (Theme) -> Void)?

    /// The footer's close button; the panel owns its visibility.
    @ObservationIgnored var onDismissRequest: (@MainActor () -> Void)?

    /// Re-resolves the theme when the system appearance changes under `.system`.
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Set while a disk reload rewrites `text`, so it isn't saved straight back.
    @ObservationIgnored private var isReloading = false
    /// The mtime at our last load or write, so only someone else's write reloads. Also the
    /// footer's last-modified readout; nil until there is a file.
    private(set) var lastLoadedMTime: Date?
    /// Between a keystroke and its save, when a watcher event for our earlier write would read
    /// stale text back over newer.
    private(set) var hasPendingSave = false
    private(set) var persistenceWarning: String?
    private var loadError: Error?
    var isEditable: Bool { loadError == nil }
    private(set) var scratchpadURL: URL

    let settings: Settings

    init(settings: Settings) {
        self.settings = settings
        scratchpadURL = StorageLocation.scratchpadURL(in: settings.config.scratchpadFolderPath)
        helpDocument = HelpDocument.make(keymap: settings.config.keymap)
        theme = settings.config.theme.resolve()
        appearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in self?.systemAppearanceMaybeChanged() }
        }
        let url = scratchpadURL
        do {
            text = try Self.readNote(at: url)
            lastLoadedMTime = Self.fileMTime(at: url)
        } catch {
            loadError = error
            persistenceWarning = "Couldn't read scratchpad: \(error.localizedDescription)"
        }
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
        didLoad = true
    }

    /// Unsaved local edits take precedence, even for an explicit Refresh.
    func reloadFromDiskIfChanged(force: Bool = false) {
        guard !hasPendingSave else { return }
        let mtime = Self.fileMTime(at: scratchpadURL)
        guard force || loadError != nil || mtime != lastLoadedMTime else { return }
        do {
            let loaded = try Self.readNote(at: scratchpadURL)
            adoptLoadedText(loaded)
        } catch {
            loadError = error
            persistenceWarning = "Couldn't read scratchpad: \(error.localizedDescription)"
        }
    }

    /// Config-file folder changes save the old buffer before adopting the new location.
    @discardableResult
    func reloadSettings() -> Bool {
        let reloaded = settings.reload { incoming in
            let url = StorageLocation.scratchpadURL(in: incoming.scratchpadFolderPath)
            guard url.standardizedFileURL != self.scratchpadURL.standardizedFileURL else { return }
            try self.flushSave()
            let exists = FileManager.default.fileExists(atPath: url.path)
            let loaded = try Self.readNote(at: url)
            if !exists { try Self.write(self.text, to: url) }
            self.scratchpadURL = url
            self.adoptLoadedText(exists ? loaded : self.text)
        }
        if reloaded { adoptSettings() }
        return reloaded
    }

    /// Commits config only after the destination and any required backup are safe.
    @discardableResult
    func changeScratchpadFolder(to folder: URL, reset: Bool = false) throws
        -> StorageLocation.SwitchResult
    {
        try flushSave()
        let current = try Self.readNote(at: scratchpadURL)
        adoptLoadedText(current)
        let result = try StorageLocation.setFolder(
            folder, currentText: text, currentFolder: scratchpadURL.deletingLastPathComponent(),
            removeCurrent: !reset
        ) {
            guard self.settings.setScratchpadFolder(reset ? "" : folder.path) else {
                throw NSError(
                    domain: "Wisp", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: self.settings.configWarning
                            ?? "Couldn't update scratchpad folder"
                    ])
            }
        }
        scratchpadURL = StorageLocation.scratchpadURL(in: folder)
        adoptLoadedText(result.text)
        return result
    }

    /// Replaces the text without saving it straight back.
    private func adoptLoadedText(_ newText: String) {
        saveTask?.cancel()
        hasPendingSave = false
        loadError = nil
        persistenceWarning = nil
        isReloading = true
        text = newText
        isReloading = false
        lastLoadedMTime = Self.fileMTime(at: scratchpadURL)
    }

    private static func readNote(at url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch CocoaError.fileReadNoSuchFile {
            return ""
        }
    }

    nonisolated private static func fileMTime(at url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    /// Returns the keyboard to the help page while it's up, else the note, so ⌘A, ⌘F, and the
    /// scroll keys stay with what's in front.
    func requestFocus() {
        if showHelp { helpFocusToken &+= 1 } else { focusToken &+= 1 }
    }

    /// ⌘= / ⌘- and the footer buttons.
    func stepFontScale(by steps: Int) {
        settings.setFontScale(Metrics.steppedFontScale(fontScale, by: steps))
        requestFocus()
    }

    /// ⌘0 returns to `defaultFontScale`, the user's normal size.
    func resetFontScale() {
        settings.setFontScale(settings.config.clampedDefaultFontScale)
        requestFocus()
    }

    func toggleSourceView() {
        isSourceView.toggle()
        requestFocus()
    }

    func toggleFooterStatus() {
        settings.setFooterStatus(footerStatus == .position ? .modified : .position)
        requestFocus()
    }

    func toggleSpellcheck() {
        settings.setSpellcheck(!spellcheck)
        requestFocus()
    }

    func cycleTheme() {
        settings.setTheme(themeSetting.next)
        theme = themeSetting.resolve()
        requestFocus()
    }

    func toggleHelp() {
        withAnimation(.easeInOut(duration: 0.18)) { showHelp.toggle() }
    }

    private func systemAppearanceMaybeChanged() {
        guard themeSetting == .system else { return }
        let resolved = themeSetting.resolve()
        if resolved != theme { theme = resolved }
    }

    func jumpTo(_ heading: Heading) {
        scrollTarget = heading.lineStart
        scrollToken &+= 1
    }

    enum HeadingDirection { case previous, next }

    /// ⌃⇧↑ / ⌃⇧↓ walk every level, not just the two the header shows.
    func jumpToHeading(_ direction: HeadingDirection) {
        let lineStart = LineEdits.lineRange(in: text as NSString, at: caretOffset).location
        let target: Heading? =
            switch direction {
            case .previous: headings.heading(before: lineStart)
            case .next: headings.heading(after: lineStart)
            }
        if let target { jumpTo(target) }
    }

    // MARK: Find

    func openFind() {
        showFind = true
        recomputeMatches(resetIndex: true)
    }

    func dismissFind() {
        showFind = false
        findMatches = []
        findIndex = 0
        findMatchCount = 0
        findCurrentDisplayIndex = 0
        clearFindHighlight()
        requestFocus()
    }

    func findNext() {
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex + 1) % findMatches.count
        navigateToCurrentMatch()
    }

    func findPrevious() {
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex - 1 + findMatches.count) % findMatches.count
        navigateToCurrentMatch()
    }

    /// The help page while it's up, since find searches what's in front.
    private var findSourceText: String {
        showHelp ? helpDocument.plainText : text
    }

    private func recomputeMatches(resetIndex: Bool) {
        findMatches = TextSearch.matches(in: findSourceText, query: findQuery)
        findMatchCount = findMatches.count
        if resetIndex { findIndex = 0 }
        if findIndex >= findMatches.count { findIndex = max(0, findMatches.count - 1) }
        if findMatches.isEmpty {
            findCurrentDisplayIndex = 0
            clearFindHighlight()
        } else {
            navigateToCurrentMatch()
        }
    }

    private func navigateToCurrentMatch() {
        guard findIndex < findMatches.count else { return }
        findCurrentDisplayIndex = findIndex + 1
        findHighlightRange = findMatches[findIndex]
        findHighlightToken &+= 1
    }

    private func clearFindHighlight() {
        findHighlightRange = NSRange(location: 0, length: 0)
        findHighlightToken &+= 1
    }

    /// Dismisses the topmost overlay; false when none was open, so Esc can fall through.
    @discardableResult
    func dismissTopOverlay() -> Bool {
        if showFind {
            dismissFind()
            return true
        }
        if showHelp {
            showHelp = false
            return true
        }
        return false
    }

    /// On every hide, since SwiftUI never unmounts the overlays or their key monitors.
    func dismissAllOverlays() {
        while dismissTopOverlay() {}
    }

    /// Re-derives the resolved theme and the help page from a re-read config.
    func adoptSettings() {
        // Even when unchanged: `didSet` tells the chrome to re-read `background`.
        theme = settings.config.theme.resolve()
        helpDocument = HelpDocument.make(keymap: settings.config.keymap)
        if showFind, showHelp { recomputeMatches(resetIndex: false) }
    }

    /// Counted on first read after an edit, not on every render.
    var wordCount: Int {
        let source = text
        if let cachedWordCount { return cachedWordCount }
        var count = 0
        source.enumerateSubstrings(
            in: source.startIndex..., options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in count += 1 }
        cachedWordCount = count
        return count
    }

    func refreshPlaceholder() {
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
    }

    /// Clean buffers never rewrite disk; a failed save remains dirty and blocks quit.
    func flushSave() throws {
        saveTask?.cancel()
        saveTask = nil
        guard hasPendingSave else { return }
        do {
            if let loadError { throw loadError }
            try Self.write(text, to: scratchpadURL)
            hasPendingSave = false
            persistenceWarning = nil
            lastLoadedMTime = Self.fileMTime(at: scratchpadURL)
            flashSaveIndicator()
        } catch {
            persistenceWarning = "Couldn't save scratchpad: \(error.localizedDescription)"
            throw error
        }
    }

    /// Debounce and writes share the main actor, so a canceled older task cannot write later.
    private func scheduleSave() {
        saveTask?.cancel()
        hasPendingSave = true
        saveTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 800_000_000) } catch { return }
            guard !Task.isCancelled, let self else { return }
            do {
                try self.flushSave()
            } catch {
                // The footer retains the error and dirty buffer.
            }
        }
    }

    /// A fresh task per save, so a second save keeps the dot up for its own moment.
    private func flashSaveIndicator() {
        guard settings.config.saveIndicator else { return }
        saveFlashTask?.cancel()
        isShowingSaveFlash = true
        saveFlashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            self?.isShowingSaveFlash = false
        }
    }

    nonisolated private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct EditorView: View {
    let model: EditorModel

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                EditorHeader(model: model)
                EditorContent(model: model)
                EditorFooter(model: model)
            }
            .disabled(model.showHelp)
            .accessibilityHidden(model.showHelp)
            EditorSaveFeedback(model: model)
            if model.showHelp {
                EditorHelp(model: model)
                    .transition(.opacity)
            }
            if model.showFind {
                EditorFind(model: model)
                    .padding(.top, 12)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .strokeBorder(Color(nsColor: palette.border), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .environment(\.palette, palette)
    }

    private var palette: Palette { Palette.for(model.theme) }
}

private struct EditorHeader: View {
    let model: EditorModel

    var body: some View {
        HeaderBar(items: model.navigationHeadings, title: \.title) { item in
            model.jumpTo(item.heading)
        }
    }
}

private struct EditorContent: View {
    @Bindable var model: EditorModel
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .topLeading) {
            Editor(
                document: model.document,
                onEdit: model.acceptEdit,
                isEditable: model.isEditable,
                caretOffset: $model.caretOffset,
                focusToken: model.focusToken,
                scrollToken: model.scrollToken,
                scrollTarget: model.scrollTarget,
                findHighlightToken: model.findHighlightToken,
                findHighlightRange: model.showHelp
                    ? NSRange(location: 0, length: 0) : model.findHighlightRange,
                style: .init(
                    theme: model.theme, fontScale: model.fontScale,
                    fonts: model.settings.config.fonts,
                    indent: model.settings.config.indent,
                    isSourceView: model.isSourceView, rule: model.settings.config.rule),
                smartPaste: model.settings.config.smartPaste,
                caret: model.settings.config.caret,
                spellcheck: model.spellcheck,
                onToggleSpellcheck: { model.toggleSpellcheck() }
            )
            .padding(.horizontal, Metrics.chromeInsetX)
            .padding(.top, model.navigationHeadings.isEmpty ? 24 : 4)
            .padding(.bottom, 4)
            if model.text.isEmpty {
                Text(model.placeholder)
                    .font(Font(Editor.baseFont(isSourceView: model.isSourceView)))
                    .foregroundStyle(Color(nsColor: palette.muted))
                    .allowsHitTesting(false)
                    .padding(.horizontal, Metrics.chromeInsetX)
                    .padding(.top, model.navigationHeadings.isEmpty ? 26 : 2)
            }
        }
    }
}

private struct EditorFooter: View {
    let model: EditorModel

    var body: some View {
        FooterBar(
            readout: model.footerStatus == .position
                ? .position(model.caretPosition, words: model.wordCount)
                : .modified(model.lastLoadedMTime),
            isPanelVisible: model.isPanelVisible,
            onToggleReadout: { model.toggleFooterStatus() },
            fontScale: model.fontScale,
            isDefaultFontScale:
                model.fontScale == model.settings.config.clampedDefaultFontScale,
            onDecreaseFontScale: { model.stepFontScale(by: -1) },
            onIncreaseFontScale: { model.stepFontScale(by: 1) },
            onResetFontScale: { model.resetFontScale() },
            themeSetting: model.themeSetting,
            isSourceView: model.isSourceView,
            isSpellcheckOn: model.spellcheck,
            keymap: model.settings.config.keymap,
            onCycleTheme: { model.cycleTheme() },
            onToggleSourceView: { model.toggleSourceView() },
            onToggleSpellcheck: { model.toggleSpellcheck() },
            onHelpClick: { model.toggleHelp() },
            warning: model.persistenceWarning ?? model.settings.warning,
            onDismiss: { model.onDismissRequest?() }
        )
    }
}

private struct EditorSaveFeedback: View {
    let model: EditorModel

    var body: some View {
        if model.settings.config.saveIndicator, !model.showFind {
            SaveIndicator(isVisible: model.isShowingSaveFlash)
        }
    }
}

private struct EditorHelp: View {
    let model: EditorModel

    var body: some View {
        HelpOverlay(
            document: model.helpDocument,
            findHighlightToken: model.findHighlightToken,
            findHighlightRange: model.findHighlightRange,
            focusToken: model.helpFocusToken,
            onClose: {
                withAnimation(.easeInOut(duration: 0.18)) { model.showHelp = false }
            }
        )
    }
}

private struct EditorFind: View {
    @Bindable var model: EditorModel

    var body: some View {
        FindBar(
            query: $model.findQuery,
            matchCount: model.findMatchCount,
            currentIndex: model.findCurrentDisplayIndex,
            onNext: { model.findNext() },
            onPrev: { model.findPrevious() },
            onDismiss: {
                withAnimation(.easeInOut(duration: 0.15)) { model.dismissFind() }
            }
        )
    }
}
