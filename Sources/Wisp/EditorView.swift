import Combine
import SwiftUI
import WispCore

@MainActor
final class EditorModel: ObservableObject {
    @Published var text: String = "" {
        didSet {
            headings = text.extractHeadings()
            cachedWordCount = nil
            guard didLoad, !isReloading else { return }
            scheduleSave()
        }
    }
    @Published var headings: [Heading] = []
    private var cachedWordCount: Int?
    /// The caret's UTF-16 offset, as the text view last reported it.
    @Published var caretOffset = 0
    @Published var focusToken: Int = 0
    @Published var scrollToken: Int = 0
    /// Flashed briefly on each save; nothing schedules it when `saveIndicator` is off.
    @Published private(set) var isShowingSaveFlash = false
    private var saveFlashTask: Task<Void, Never>?
    private(set) var scrollTarget: Int = 0
    @Published private(set) var placeholder: String = ""
    @Published var showHotKeyCapture: Bool = false
    /// The raw text in the code face. Not persisted: it's a glance at the file, not a preference.
    @Published var isSourceView: Bool = false

    // MARK: Help

    /// Held rather than computed, since it's find's source while the page is up.
    @Published private(set) var helpDocument: HelpDocument
    /// Bumped to give the help page first responder, so ⌘A and ⌘C don't reach the note.
    @Published private(set) var helpFocusToken: Int = 0
    @Published var showHelp: Bool = false {
        didSet {
            guard didLoad, showHelp != oldValue else { return }
            requestFocus()
            // Find follows the page in front, so re-search the other document.
            if showFind { recomputeMatches(resetIndex: true) }
        }
    }

    // MARK: Find
    @Published var showFind: Bool = false
    @Published var findQuery: String = "" {
        didSet {
            // Tearing the bar down writes the field's value back, which would re-highlight a
            // cleared match.
            guard didLoad, showFind else { return }
            recomputeMatches(resetIndex: true)
        }
    }
    @Published private(set) var findMatchCount: Int = 0
    /// 1-based, or 0 with no matches.
    @Published private(set) var findCurrentDisplayIndex: Int = 0
    /// A zero-length range clears the highlight.
    @Published var findHighlightToken: Int = 0
    private(set) var findHighlightRange = NSRange(location: 0, length: 0)
    private var findMatches: [NSRange] = []
    private var findIndex = 0
    /// Set by the app delegate: nil on success, or a message when the chord is taken.
    var tryUpdateHotKey: @MainActor (KeyChord) -> String? = { _ in nil }

    private static let placeholders = [
        "What's on your mind?",
        "Type your first thought…",
        "Write it down before it's gone.",
        "Capture it before you forget.",
        "Anything to remember?",
    ]
    // Read from the config; `Settings`' changes are forwarded as this model's.
    var fontScale: Double { settings.config.clampedFontScale }
    var spellcheck: Bool { settings.config.spellcheck }
    var footerStatus: FooterStatus { settings.config.footerStatus }
    var themeSetting: ThemeSetting { settings.config.theme }

    /// The resolved theme: `themeSetting`, or the system appearance under `.system`.
    @Published private(set) var theme: Theme = .dark {
        didSet {
            onThemeChange?(theme)
        }
    }

    /// Lets the panel controller apply chrome changes; SwiftUI re-renders on its own.
    var onThemeChange: (@MainActor (Theme) -> Void)?

    /// The footer's close button; the panel owns its visibility.
    var onDismissRequest: (@MainActor () -> Void)?

    /// Re-resolves the theme when the system appearance changes under `.system`.
    private var appearanceObservation: NSKeyValueObservation?
    private var settingsObservation: AnyCancellable?

    private var didLoad = false
    private var saveTask: Task<Void, Never>?
    /// Set while a disk reload rewrites `text`, so it isn't saved straight back.
    private var isReloading = false
    /// The mtime at our last load or write, so only someone else's write reloads. Also the
    /// footer's last-modified readout; nil until there is a file.
    @Published private(set) var lastLoadedMTime: Date?
    /// Between a keystroke and its save, when a watcher event for our earlier write would read
    /// stale text back over newer.
    private var hasPendingSave = false

    let settings: Settings

    /// Where `scratchpad.md` lives right now, per the config.
    var scratchpadURL: URL {
        StorageLocation.scratchpadURL(in: settings.config.scratchpadFolderPath)
    }

    init(settings: Settings) {
        self.settings = settings
        helpDocument = HelpDocument.make(keymap: settings.config.keymap)
        theme = settings.config.theme.resolve()
        appearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in self?.systemAppearanceMaybeChanged() }
        }
        settingsObservation = settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        let url = scratchpadURL
        if let loaded = try? String(contentsOf: url, encoding: .utf8) {
            text = loaded
            lastLoadedMTime = Self.fileMTime(at: url)
        }
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
        didLoad = true
    }

    /// Re-reads the note if its mtime moved: on every show, on Refresh, and from the watcher.
    func reloadFromDiskIfChanged() {
        // Our own write is pending, so the file on disk is older than the buffer.
        guard !hasPendingSave else { return }
        let url = scratchpadURL
        guard let mtime = Self.fileMTime(at: url) else { return }
        if let last = lastLoadedMTime, mtime <= last { return }
        guard let loaded = try? String(contentsOf: url, encoding: .utf8) else { return }
        if loaded != text {
            isReloading = true
            text = loaded
            isReloading = false
        }
        lastLoadedMTime = mtime
    }

    /// For a changed `scratchpadFolder`, whose mtime baseline is the old file's. A folder with no
    /// scratchpad yet keeps the current text for the next save.
    func adoptScratchpadAtCurrentPath() {
        guard let loaded = try? String(contentsOf: scratchpadURL, encoding: .utf8) else {
            lastLoadedMTime = nil
            return
        }
        adoptLoadedText(loaded)
    }

    /// Replaces the text without saving it straight back.
    func adoptLoadedText(_ newText: String) {
        isReloading = true
        text = newText
        isReloading = false
        lastLoadedMTime = Self.fileMTime(at: scratchpadURL)
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
        if showHotKeyCapture {
            showHotKeyCapture = false
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
    }

    /// Counted on first read after an edit, not on every render.
    var wordCount: Int {
        if let cachedWordCount { return cachedWordCount }
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex..., options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in count += 1 }
        cachedWordCount = count
        return count
    }

    func refreshPlaceholder() {
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
    }

    /// For quitting, so a pending debounced save isn't lost.
    func flushSave() {
        saveTask?.cancel()
        hasPendingSave = false
        try? Self.write(text, to: scratchpadURL)
        lastLoadedMTime = Self.fileMTime(at: scratchpadURL)
    }

    /// The URL is fixed up front, so a folder switch mid-debounce can't land the old text there.
    private func scheduleSave() {
        saveTask?.cancel()
        hasPendingSave = true
        let snapshot = text
        let url = scratchpadURL
        saveTask = Task.detached(priority: .background) { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            try? Self.write(snapshot, to: url)
            let mtime = Self.fileMTime(at: url)
            await MainActor.run { self?.didWrite(url: url, mtime: mtime) }
        }
    }

    /// Baselines our own write so the watcher doesn't read it as a change; skipped if the
    /// scratchpad has since moved.
    private func didWrite(url: URL, mtime: Date?) {
        hasPendingSave = false
        guard url == scratchpadURL else { return }
        lastLoadedMTime = mtime
        flashSaveIndicator()
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
    @ObservedObject var model: EditorModel

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // One read, so a click jumps to the heading it was drawn from.
                let headings = barHeadings
                HeaderBar(labels: headings.map(\.name)) { index in
                    model.jumpTo(headings[index])
                }
                ZStack(alignment: .topLeading) {
                    MinimalTextEditor(
                        text: $model.text,
                        caretOffset: $model.caretOffset,
                        focusToken: model.focusToken,
                        scrollToken: model.scrollToken,
                        scrollTarget: model.scrollTarget,
                        findHighlightToken: model.findHighlightToken,
                        // Cleared under the help page, which the query is searching.
                        findHighlightRange: model.showHelp
                            ? NSRange(location: 0, length: 0) : model.findHighlightRange,
                        style: .init(
                            theme: model.theme, fontScale: model.fontScale,
                            indent: model.settings.config.indent,
                            isSourceView: model.isSourceView, rule: model.settings.config.rule),
                        smartPaste: model.settings.config.smartPaste,
                        caret: model.settings.config.caret,
                        spellcheck: model.spellcheck,
                        onToggleSpellcheck: { model.toggleSpellcheck() }
                    )
                    .padding(.horizontal, Metrics.chromeInsetX)
                    .padding(.top, barHeadings.isEmpty ? 24 : 4)
                    .padding(.bottom, 4)
                    if model.text.isEmpty {
                        Text(model.placeholder)
                            // The body's face, which in source view is the code one.
                            .font(Font(MinimalTextEditor.baseFont(isSourceView: model.isSourceView)))
                            .foregroundStyle(Color(palette.muted))
                            .allowsHitTesting(false)
                            .padding(.horizontal, Metrics.chromeInsetX)
                            .padding(.top, barHeadings.isEmpty ? 26 : 2)
                    }
                }
                FooterBar(
                    // Only the shown readout is computed; both scan the whole note.
                    readout: model.footerStatus == .position
                        ? .position(
                            CaretPosition(in: model.text, at: model.caretOffset),
                            words: model.wordCount)
                        : .modified(model.lastLoadedMTime),
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
                    warning: model.settings.warning,
                    onDismiss: { model.onDismissRequest?() }
                )
            }
            // Above the editor, under every overlay.
            if model.settings.config.saveIndicator, !model.showFind {
                SaveIndicator(isVisible: model.isShowingSaveFlash)
            }
            if model.showHelp {
                HelpOverlay(
                    document: model.helpDocument,
                    findHighlightToken: model.findHighlightToken,
                    findHighlightRange: model.findHighlightRange,
                    focusToken: model.helpFocusToken,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.showHelp = false
                        }
                    }
                )
                .transition(.opacity)
            }
            if model.showHotKeyCapture {
                HotKeyCaptureOverlay(
                    onTryRegister: { hk in model.tryUpdateHotKey(hk) },
                    onSuccess: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.showHotKeyCapture = false
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.showHotKeyCapture = false
                        }
                    }
                )
                .transition(.opacity)
            }
            if model.showFind {
                FindBar(
                    query: $model.findQuery,
                    matchCount: model.findMatchCount,
                    currentIndex: model.findCurrentDisplayIndex,
                    onNext: { model.findNext() },
                    onPrev: { model.findPrevious() },
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            model.dismissFind()
                        }
                    }
                )
                .padding(.top, 12)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .strokeBorder(Color(palette.border), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .environment(\.palette, palette)
    }

    private var palette: Palette { Palette.for(model.theme) }

    /// `#` and `##` only; `###` down are scrolled to rather than jumped to.
    private var barHeadings: [Heading] { model.headings.filter { $0.level <= 2 } }
}
