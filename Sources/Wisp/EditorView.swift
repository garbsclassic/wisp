import SwiftUI
import WispCore

@MainActor
final class EditorModel: ObservableObject {
    @Published var text: String = "" {
        didSet {
            headings = text.extractHeadings()
            guard didLoad, !isReloading else { return }
            scheduleSave()
        }
    }
    @Published var headings: [Heading] = []
    @Published var focusToken: Int = 0
    @Published var scrollToken: Int = 0
    @Published var wrapToken: Int = 0
    @Published var duplicateToken: Int = 0
    @Published var listItemToken: Int = 0
    @Published var moveLineToken: Int = 0
    private(set) var moveLineDelta: Int = 0
    /// Flashed for a moment each time a save lands on disk. Nil-cost when
    /// `saveIndicator` is off — nothing schedules the flash at all.
    @Published private(set) var isShowingSaveFlash = false
    private var saveFlashTask: Task<Void, Never>?
    private(set) var scrollTarget: Int = 0
    private(set) var wrapMarkers = MarkdownWrap.Markers("**")
    @Published private(set) var placeholder: String = ""
    @Published var showHotKeyCapture: Bool = false

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
    @Published var hotKey: HotKey = .default {
        didSet {
            guard didLoad else { return }
            settings.setSummon(keyCode: hotKey.keyCode, carbonModifiers: hotKey.modifiers)
        }
    }

    /// AppDelegate replaces this with the real Carbon-registration
    /// attempt. Returns nil on success or a user-facing error message
    /// if registration was rejected (typically because the combo is
    /// already in use system-wide). Default is a no-op so this is
    /// always callable.
    var tryUpdateHotKey: @MainActor (HotKey) -> String? = { _ in nil }

    private static let placeholders = [
        "What's on your mind?",
        "Type your first thought…",
        "Write it down before it's gone.",
        "Capture it before you forget.",
        "Anything to remember?",
    ]
    /// The one text-size control, replacing the old small/medium/large
    /// cycle. Mirrors the config rather than owning it — `Settings` is
    /// what persists it and what reconfigures `Typography`; this exists
    /// to be a `@Published` SwiftUI can observe.
    ///
    /// Every writer clamps before assigning (`Metrics.steppedFontScale`,
    /// `clampedFontScale`, `clampedDefaultFontScale`), so this setter does
    /// not read the clamped value back — `didSet` fires on an equal write
    /// too, and a write-back would recurse without end.
    @Published var fontScale: Double = 1.0 {
        didSet {
            guard didLoad else { return }
            settings.setFontScale(fontScale)
        }
    }
    /// User-facing choice: light, dark, or follow-system. Persisted.
    @Published var themePreference: ThemePreference = .system {
        didSet {
            guard didLoad else { return }
            settings.setTheme(themePreference)
            theme = themePreference.resolve()
        }
    }

    /// Resolved theme actually used for rendering. Driven by
    /// themePreference, or — when preference is .system — by the OS
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

    /// KVO observer that re-resolves the theme when the OS switches
    /// between Light and Dark while the user is on .system. Held strong
    /// so the observation stays alive for the model's lifetime.
    private var appearanceObservation: NSKeyValueObservation?

    private var didLoad = false
    private var saveTask: Task<Void, Never>?
    /// Set true while we're rewriting `text` from a disk reload — the
    /// `text.didSet` save trigger checks this so we don't immediately
    /// re-save the content we just loaded.
    private var isReloading = false
    /// mtime of the file the last time we successfully loaded from
    /// disk — or wrote it ourselves, which counts the same way. Drives
    /// reloadFromDiskIfChanged so we only re-read when the file has
    /// actually moved on (e.g., another Mac wrote to it via iCloud sync).
    private var lastLoadedMTime: Date?
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
        StorageLocation.scratchpadURL(in: settings.config.scratchpadFolder)
    }

    init(settings: Settings) {
        self.settings = settings
        helpDocument = HelpDocument.make(keymap: settings.config.keymap)
        themePreference = settings.config.theme
        theme = themePreference.resolve()
        appearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in self?.systemAppearanceMaybeChanged() }
        }
        fontScale = settings.config.clampedFontScale
        let chord = settings.config.summonChord
        hotKey = HotKey(keyCode: chord.keyCode, modifiers: chord.carbonModifiers)
        let url = scratchpadURL
        if let loaded = try? String(contentsOf: url, encoding: .utf8) {
            text = loaded
            lastLoadedMTime = Self.fileMTime(at: url)
        }
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
        didLoad = true
    }

    /// Re-read scratchpad.md from disk if its modification time has
    /// advanced since we last loaded it. Called on every panel-open so
    /// changes from another Mac (via iCloud Drive / Dropbox / etc.)
    /// show up the next time the user summons Wisp. Mid-session writes
    /// to the file from outside Wisp aren't observed (no file watcher
    /// — kept intentionally simple).
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
    /// `scratchpadPath` that changed in the config: the mtime baseline
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
    /// and while the help page is up that is the page, not the note —
    /// ⌘= / ⌘0 / ⌘T all call this, and each of them used to quietly hand
    /// first responder back to the note behind the page, taking ⌘A, ⌘F and
    /// the scroll keys with it.
    func requestFocus() {
        if showHelp { helpFocusToken &+= 1 } else { focusToken &+= 1 }
    }

    /// ⌘= / ⌘- and the footer's two glyph buttons. One step each way,
    /// clamped at both ends by `Metrics`.
    func stepFontScale(by steps: Int) {
        fontScale = Metrics.steppedFontScale(fontScale, by: steps)
        requestFocus()
    }

    /// ⌘0. Returns to `defaultFontScale` rather than to a constant 1.0,
    /// so "reset" means the size this user considers normal.
    func resetFontScale() {
        fontScale = settings.config.clampedDefaultFontScale
        requestFocus()
    }

    func cycleTheme() {
        themePreference = themePreference.next
        requestFocus()
    }

    private func systemAppearanceMaybeChanged() {
        guard themePreference == .system else { return }
        let resolved = themePreference.resolve()
        if resolved != theme { theme = resolved }
    }

    /// ⌘B / ⌘I from either menu. Routed through a token, like focus/scroll,
    /// rather than AppDelegate reaching into the responder chain for the
    /// notes NSTextView itself — MinimalTextEditor's Coordinator is the one
    /// that actually owns it. Bold and italic share one token/marker pair
    /// rather than each getting its own, since they're the same operation
    /// parameterized by the marker string.
    func toggleBold() { wrap(.init("**")) }
    /// `_word_` rather than `*word*`. Both still *render* as italic — this
    /// is only what the key inserts.
    func toggleItalic() { wrap(.init("_")) }
    func toggleHighlight() { wrap(.init("==")) }
    /// The one non-markdown marker Wisp writes. Markdown has no underline,
    /// `__` is already spoken for by bold, and `<u>` is what Obsidian's own
    /// underline command inserts — which matters, because these notes are
    /// read there too.
    func toggleUnderline() { wrap(.init("<u>", "</u>")) }
    func toggleCode() { wrap(.init("`")) }

    private func wrap(_ markers: MarkdownWrap.Markers) {
        wrapMarkers = markers
        wrapToken &+= 1
    }

    /// ⌘D. Same token arrangement as ⌘B / ⌘I, for the same reason: the
    /// edit needs the text view's live selection, which only
    /// `MinimalTextEditor` has a handle on.
    func duplicateSelection() { duplicateToken &+= 1 }
    func toggleListItem() { listItemToken &+= 1 }

    /// ⌥↑ / ⌥↓. The delta rides alongside the token, the same pairing
    /// `scrollTarget` has with `scrollToken`.
    func moveLine(by delta: Int) {
        moveLineDelta = delta
        moveLineToken &+= 1
    }

    func jumpTo(_ heading: Heading) {
        scrollTarget = heading.lineStart
        scrollToken &+= 1
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

    /// Re-applies the settings this model caches from a config that has
    /// just been re-read — theme, text size, and the summon chord. Without
    /// it Refresh reloads the file but the window keeps rendering the
    /// values it read at launch.
    ///
    /// Adoption, not a user change: `didLoad` is dropped for the duration
    /// so the property setters don't write the file's own values back at
    /// it, and the chord is re-registered only when it actually differs,
    /// since that can fail and cost the user their binding.
    func adoptSettings() {
        let wasLoaded = didLoad
        didLoad = false
        defer { didLoad = wasLoaded }

        themePreference = settings.config.theme
        theme = themePreference.resolve()
        fontScale = settings.config.clampedFontScale
        helpDocument = HelpDocument.make(keymap: settings.config.keymap)

        let chord = settings.config.summonChord
        let reloaded = HotKey(keyCode: chord.keyCode, modifiers: chord.carbonModifiers)
        if reloaded != hotKey { _ = tryUpdateHotKey(reloaded) }

        // Fonts and fontScale live in Typography rather than in a
        // published property, so nothing above forces the re-render that
        // picks up a changed face.
        objectWillChange.send()
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
                HeaderBar(headings: model.headings) { heading in
                    model.jumpTo(heading)
                }
                ZStack(alignment: .topLeading) {
                    MinimalTextEditor(
                        text: $model.text,
                        headings: $model.headings,
                        focusToken: model.focusToken,
                        scrollToken: model.scrollToken,
                        scrollTarget: model.scrollTarget,
                        wrapToken: model.wrapToken,
                        wrapMarkers: model.wrapMarkers,
                        duplicateToken: model.duplicateToken,
                        listItemToken: model.listItemToken,
                        moveLineToken: model.moveLineToken,
                        moveLineDelta: model.moveLineDelta,
                        findHighlightToken: model.findHighlightToken,
                        // Cleared while the help page is up: the query is
                        // searching the page, and a match left painted on
                        // the note would be a stale one.
                        findHighlightRange: model.showHelp
                            ? NSRange(location: 0, length: 0) : model.findHighlightRange,
                        fontScale: model.fontScale,
                        indent: model.settings.config.indent,
                        theme: model.theme
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, model.headings.isEmpty ? 26 : 2)
                    .padding(.bottom, 4)
                    if model.text.isEmpty {
                        Text(model.placeholder)
                            .font(Typography.notes(Metrics.bodySize))
                            .foregroundStyle(Color(palette.muted))
                            .allowsHitTesting(false)
                            .padding(.horizontal, 24)
                            .padding(.top, model.headings.isEmpty ? 26 : 2)
                    }
                }
                BottomBar(
                    wordCount: wordCount,
                    onDecreaseFontScale: { model.stepFontScale(by: -1) },
                    onIncreaseFontScale: { model.stepFontScale(by: 1) },
                    themePreference: model.themePreference,
                    keymap: model.settings.config.keymap,
                    onCycleTheme: { model.cycleTheme() },
                    onHelpClick: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.showHelp.toggle()
                        }
                    },
                    warning: model.settings.warning
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
                    focusToken: model.helpFocusToken
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
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color(palette.border), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .environment(\.palette, palette)
    }

    private var palette: Palette { Palette.for(model.theme) }

    private var wordCount: Int {
        var count = 0
        let text = model.text
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { _, _, _, _ in
            count += 1
        }
        return count
    }
}
