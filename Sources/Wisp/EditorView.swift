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
    /// Flashed for a moment each time a save lands on disk. Nil-cost when
    /// `saveIndicator` is off — nothing schedules the flash at all.
    @Published private(set) var isShowingSaveFlash = false
    private var saveFlashTask: Task<Void, Never>?
    private(set) var scrollTarget: Int = 0
    @Published private(set) var placeholder: String = ""
    @Published var showHotKeyCapture: Bool = false
    /// ⌘↩. Drops every styling pass and sets the body in the code face, so
    /// what is on screen is what is on disk.
    ///
    /// Deliberately not persisted: it is a way to glance at the file, not a
    /// preference. The panel only orders out, so it survives a dismiss and
    /// resets on quit — which is the lifetime it wants.
    @Published var isSourceView: Bool = false

    // MARK: Help

    /// The help page, rebuilt only when the keymap behind it can have moved.
    /// Held rather than computed: it is the find source while the page is
    /// up, and re-deriving it per SwiftUI body pass would re-parse every
    /// chord in the config.
    @Published private(set) var helpDocument: HelpDocument
    /// Bumped to hand first responder to the help page — which is what stops
    /// ⌘A and ⌘C landing on the note underneath it.
    @Published private(set) var helpFocusToken: Int = 0
    @Published var showHelp: Bool = false {
        didSet {
            guard didLoad, showHelp != oldValue else { return }
            requestFocus()
            // Find follows whatever is in front of the user, so opening or
            // dismissing the page re-searches against the other document.
            if showFind { recomputeMatches(resetIndex: true) }
        }
    }

    // MARK: Find
    @Published var showFind: Bool = false
    @Published var findQuery: String = "" {
        didSet {
            // Only react while find is open. When the bar is torn down,
            // the text field resigns focus and writes its value back
            // through the binding; Swift's didSet fires even on an equal
            // write, which would otherwise re-highlight the just-cleared
            // match after dismissFind().
            guard didLoad, showFind else { return }
            recomputeMatches(resetIndex: true)
        }
    }
    /// Number of matches for the current query (0 when none / empty).
    @Published private(set) var findMatchCount: Int = 0
    /// 1-based index of the current match for display ("3 / 12").
    /// 0 when there are no matches.
    @Published private(set) var findCurrentDisplayIndex: Int = 0
    /// Token + range driving the highlight in MinimalTextEditor — same
    /// pattern as scrollToken/scrollTarget. A zero-length range clears.
    @Published var findHighlightToken: Int = 0
    private(set) var findHighlightRange = NSRange(location: 0, length: 0)
    private var findMatches: [NSRange] = []
    private var findIndex = 0
    /// AppDelegate replaces this with the real Carbon-registration
    /// attempt. Returns nil on success or a user-facing error message
    /// if registration was rejected (typically because the combo is
    /// already in use system-wide). Default is a no-op so this is
    /// always callable.
    var tryUpdateHotKey: @MainActor (KeyChord) -> String? = { _ in nil }

    private static let placeholders = [
        "What's on your mind?",
        "Type your first thought…",
        "Write it down before it's gone.",
        "Capture it before you forget.",
        "Anything to remember?",
    ]
    // Read straight from the config, which `Settings` owns and persists;
    // its changes are forwarded as this model's, so views observing the
    // model re-render on them too.
    var fontScale: Double { settings.config.clampedFontScale }
    var spellcheck: Bool { settings.config.spellcheck }
    var footerStatus: FooterStatus { settings.config.footerStatus }
    var themeSetting: ThemeSetting { settings.config.theme }

    /// Resolved theme actually used for rendering. Driven by
    /// themeSetting, or — when preference is .system — by the OS
    /// appearance via the KVO observer below.
    @Published private(set) var theme: Theme = .dark {
        didSet {
            onThemeChange?(theme)
        }
    }

    /// PanelController subscribes to this so it can apply chrome changes
    /// (visualEffect material, tint color, panel appearance) when the
    /// theme flips. SwiftUI handles its own re-render via @Published.
    var onThemeChange: (@MainActor (Theme) -> Void)?

    /// The footer's close button. The panel owns its own visibility, so the
    /// model asks rather than hides — same shape as `onThemeChange`.
    var onDismissRequest: (@MainActor () -> Void)?

    /// KVO observer that re-resolves the theme when the OS switches
    /// between Light and Dark while the user is on .system. Held strong
    /// so the observation stays alive for the model's lifetime.
    private var appearanceObservation: NSKeyValueObservation?
    private var settingsObservation: AnyCancellable?

    private var didLoad = false
    private var saveTask: Task<Void, Never>?
    /// Set true while we're rewriting `text` from a disk reload — the
    /// `text.didSet` save trigger checks this so we don't immediately
    /// re-save the content we just loaded.
    private var isReloading = false
    /// mtime of the file the last time we successfully loaded from
    /// disk — or wrote it ourselves, which counts the same way. Drives
    /// reloadFromDiskIfChanged so we only re-read when the file has
    /// actually moved on (e.g., another Mac wrote to it via iCloud sync),
    /// and the footer's last-modified readout. Nil until there is a file.
    @Published private(set) var lastLoadedMTime: Date?
    /// True between a keystroke and the debounced save that follows it.
    /// The directory watcher can otherwise fire on a save of ours while
    /// the buffer has already moved past what landed on disk, and the
    /// reload would read our own stale write back over the newer text.
    private var hasPendingSave = false

    /// `wisp.jsonc`, which is where every value below is read from and
    /// written back to.
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

    /// Re-read scratchpad.md from disk if its modification time has
    /// advanced since we last loaded it. Called on every panel-open, on
    /// Refresh, and by the note folder's watcher, so changes from another
    /// Mac (via iCloud Drive / Dropbox / etc.) show up.
    func reloadFromDiskIfChanged() {
        // Our own write is still in flight and the buffer is ahead of the
        // file; whatever is on disk right now is by definition older.
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

    /// Adopts whatever file is at the current scratchpad path, for a
    /// `scratchpadFolder` that changed in the config: the mtime baseline
    /// describes a file in the old folder, so `reloadFromDiskIfChanged`
    /// can't be trusted to notice the new one. A folder with no scratchpad
    /// in it yet keeps the current text, which the next save writes there.
    func adoptScratchpadAtCurrentPath() {
        guard let loaded = try? String(contentsOf: scratchpadURL, encoding: .utf8) else {
            lastLoadedMTime = nil
            return
        }
        adoptLoadedText(loaded)
    }

    /// Replace the in-memory text with a freshly chosen content (e.g.,
    /// after switching to a folder that already contained a synced
    /// scratchpad). Suppresses the auto-save that would otherwise fire
    /// from `text.didSet`, so we don't bounce-write what we just read.
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

    /// Puts the keyboard back where the user was. Every caller means that,
    /// and while the help page is up that is the page, not the note — or
    /// ⌘= / ⌘0 / ⌘T would hand first responder to the note behind the page,
    /// taking ⌘A, ⌘F and the scroll keys with it.
    func requestFocus() {
        if showHelp { helpFocusToken &+= 1 } else { focusToken &+= 1 }
    }

    /// ⌘= / ⌘- and the footer's two glyph buttons. One step each way,
    /// clamped at both ends by `Metrics`.
    func stepFontScale(by steps: Int) {
        settings.setFontScale(Metrics.steppedFontScale(fontScale, by: steps))
        requestFocus()
    }

    /// ⌘0. Returns to `defaultFontScale` rather than to a constant 1.0,
    /// so "reset" means the size this user considers normal.
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

    /// ⌃⇧↑ / ⌃⇧↓. Every level counts, not just the two the header strip
    /// shows — the strip is an index, this is a walk. Off either end it
    /// does nothing.
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

    /// What find searches. The help page is a modal over the note, so the
    /// page in front is the one the query means — anything else searches a
    /// document the user cannot see.
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

    /// Dismisses the topmost open modal overlay, in priority order, and
    /// reports whether it dismissed anything — so a caller like Esc can fall
    /// through to further handling only once nothing is left open.
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

    /// Tear every modal overlay down. Called on every panel hide: the
    /// panel only orders out, so SwiftUI never unmounts the overlays and
    /// their local key monitors would otherwise stay installed app-wide
    /// with the panel gone.
    func dismissAllOverlays() {
        while dismissTopOverlay() {}
    }

    /// Re-derives what the model computes from a config that has just been
    /// re-read: the resolved theme and the help page.
    func adoptSettings() {
        // Assigned even when unchanged: `didSet` hands it to the chrome,
        // which reads `background` straight from the config and only
        // re-applies it when told.
        theme = settings.config.theme.resolve()
        helpDocument = HelpDocument.make(keymap: settings.config.keymap)
    }

    /// Counted on first read after an edit rather than on every body pass —
    /// a caret move re-renders the footer too, and the text hasn't changed.
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

    /// Force a synchronous flush — call from applicationWillTerminate so an
    /// in-flight debounced save isn't lost when the user quits.
    func flushSave() {
        saveTask?.cancel()
        hasPendingSave = false
        try? Self.write(text, to: scratchpadURL)
        lastLoadedMTime = Self.fileMTime(at: scratchpadURL)
    }

    /// The destination is resolved on the main actor and carried into the
    /// background write, so a folder switch mid-debounce can't land the old
    /// text in the new folder.
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

    /// Baselines the file we just wrote so the directory watcher doesn't
    /// treat our own save as someone else's change. Skipped when the
    /// scratchpad has moved out from under the write — that file is no
    /// longer the one being watched, and stamping it would suppress a real
    /// reload of the new one.
    private func didWrite(url: URL, mtime: Date?) {
        hasPendingSave = false
        guard url == scratchpadURL else { return }
        lastLoadedMTime = mtime
        flashSaveIndicator()
    }

    /// Shows the dot, then hides it again a moment later.
    ///
    /// A fresh task per save, cancelling the last: saving twice in quick
    /// succession should leave the dot up until the *second* one has had
    /// its moment, not blink out on the first one's timer.
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
                // One read, so a click jumps to the heading it was drawn from
                // even if the note changed since.
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
                        // Cleared while the help page is up: the query is
                        // searching the page, and a match left painted on
                        // the note would be a stale one.
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
                            // Same face as the body it sits on top of, which
                            // in source view is the code one.
                            .font(Font(MinimalTextEditor.baseFont(isSourceView: model.isSourceView)))
                            .foregroundStyle(Color(palette.muted))
                            .allowsHitTesting(false)
                            .padding(.horizontal, Metrics.chromeInsetX)
                            .padding(.top, barHeadings.isEmpty ? 26 : 2)
                    }
                }
                FooterBar(
                    // Only the readout on show is computed: both halves of
                    // the other one scan the whole note.
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
            // Above the editor but under every overlay: a status light has
            // no business showing through a modal page.
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

    /// What the header strip indexes: `#` and `##` only. Six levels in a
    /// one-line strip is a run of ellipses, and `###` down are subsections
    /// a reader scrolls to rather than jumps to. Styling and the ⌃⇧↑/↓
    /// walk still see every level.
    private var barHeadings: [Heading] { model.headings.filter { $0.level <= 2 } }
}
