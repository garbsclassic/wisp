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
    private(set) var scrollTarget: Int = 0
    @Published private(set) var placeholder: String = ""
    @Published var showHelp: Bool = false
    @Published var showHotKeyCapture: Bool = false

    // MARK: Find
    @Published var showFind: Bool = false
    @Published var findQuery: String = "" {
        didSet {
            // Only react while find is open. When the bar is torn down,
            // the text field resigns focus and writes its value back
            // through the binding; Swift's didSet fires even on an equal
            // write, which would otherwise re-highlight the just-cleared
            // match after closeFind().
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
    @Published var fontSize: FontSize = .medium {
        didSet {
            guard didLoad else { return }
            settings.setFontSize(fontSize)
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
    /// disk. Drives reloadFromDiskIfChanged so we only re-read when
    /// the file has actually moved on (e.g., another Mac wrote to it
    /// via iCloud sync).
    private var lastLoadedMTime: Date?

    /// `wisp.jsonc`, which is where every value below is read from and
    /// written back to.
    let settings: Settings

    /// Where `scratchpad.md` lives right now, per the config.
    var scratchpadURL: URL {
        StorageLocation.scratchpadURL(in: settings.config.scratchpadFolder)
    }

    init(settings: Settings) {
        self.settings = settings
        themePreference = settings.config.theme
        theme = themePreference.resolve()
        appearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in self?.systemAppearanceMaybeChanged() }
        }
        fontSize = settings.config.fontSize
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

    func requestFocus() {
        focusToken &+= 1
    }

    func cycleFontSize() {
        fontSize = fontSize.next
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

    func jumpTo(_ heading: Heading) {
        scrollTarget = heading.lineStart
        scrollToken &+= 1
    }

    // MARK: Find

    func openFind() {
        showFind = true
        recomputeMatches(resetIndex: true)
    }

    func closeFind() {
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

    private func recomputeMatches(resetIndex: Bool) {
        findMatches = TextSearch.matches(in: text, query: findQuery)
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

    /// Tear every modal overlay down. Called on every panel hide: the
    /// panel only orders out, so SwiftUI never unmounts the overlays and
    /// their local key monitors would otherwise stay installed app-wide
    /// with the panel gone.
    func closeAllOverlays() {
        if showFind { closeFind() }
        showHotKeyCapture = false
        showHelp = false
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
        fontSize = settings.config.fontSize

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
        try? Self.write(text, to: scratchpadURL)
    }

    /// The destination is resolved on the main actor and carried into the
    /// background write, so a folder switch mid-debounce can't land the old
    /// text in the new folder.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = text
        let url = scratchpadURL
        saveTask = Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            try? Self.write(snapshot, to: url)
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
                        focusToken: model.focusToken,
                        scrollToken: model.scrollToken,
                        scrollTarget: model.scrollTarget,
                        findHighlightToken: model.findHighlightToken,
                        findHighlightRange: model.findHighlightRange,
                        fontSize: model.fontSize,
                        theme: model.theme
                    )
                    .padding(.horizontal, 28)
                    .padding(.top, model.headings.isEmpty ? 28 : 4)
                    .padding(.bottom, 4)
                    if model.text.isEmpty {
                        Text(model.placeholder)
                            .font(Typography.notes(model.fontSize.pointSize))
                            .foregroundStyle(Color(palette.muted))
                            .allowsHitTesting(false)
                            .padding(.horizontal, 28)
                            .padding(.top, model.headings.isEmpty ? 28 : 4)
                    }
                }
                BottomBar(
                    wordCount: wordCount,
                    fontSize: model.fontSize,
                    onCycleFontSize: { model.cycleFontSize() },
                    themePreference: model.themePreference,
                    onCycleTheme: { model.cycleTheme() },
                    onHelpClick: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.showHelp.toggle()
                        }
                    },
                    warning: model.settings.warning
                )
            }
            if model.showHelp {
                HelpOverlay(summonChord: model.hotKey.displayString) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.showHelp = false
                    }
                }
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
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            model.closeFind()
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
