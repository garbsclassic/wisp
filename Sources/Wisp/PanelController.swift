import AppKit
import Carbon.HIToolbox
import SwiftUI
import WispCore

private let panelSize = CGSize(width: 800, height: 640)
/// A remembered size smaller than this on either side is a corrupted value,
/// not a choice, and the default size is used instead.
private let minimumSide: CGFloat = 200
/// The radius a standard macOS window has had since Big Sur.
///
/// A constant rather than a lookup: AppKit exposes no API for the system
/// value, and a `.borderless` panel gets no system-drawn corners at all —
/// every rounded edge here is ours to draw. 18pt read as noticeably rounder
/// than the windows either side of it.
private let cornerRadius: CGFloat = 10

@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let model: EditorModel
    private let settings: Settings
    private let visualEffect: NSVisualEffectView
    private let tint: NSView
    private let inner: NSView
    private let outer: NSView
    private let positioner: PanelPositioner

    /// Tap to pin, hold to peek — see `SummonState`. Assigned only through
    /// `send`, which does what the change calls for, and by `handleHide`,
    /// which is told after the fact.
    private(set) var state: SummonState = .hidden
    /// Fires once the chord has been held for `peekHold`, turning the summon
    /// into a peek. A release before then cancels it and leaves a pin.
    private var holdTimer: Timer?
    /// The summon chord's modifiers as `CGEventFlags`, so a peek can outlast
    /// the release of its key for as long as they're still down.
    private var summonModifierFlags: CGEventFlags = []
    /// Polls for a peek's modifiers lifting, once its key has come up.
    private var modifierWatchTimer: Timer?
    /// Bare Esc, claimed system-wide only while the panel is up and none of
    /// our windows has focus — see `updateEscapeCapture`.
    private let escapeKey = HotKeyMonitor()
    private var keyWindowObservers: [any NSObjectProtocol] = []

    init(model: EditorModel, settings: Settings) {
        self.model = model
        self.settings = settings
        positioner = PanelPositioner(
            monitor: { settings.config.monitor },
            saved: { settings.config.position },
            save: { settings.setPosition($0) })
        let contentRect = NSRect(origin: .zero, size: panelSize)
        panel = FloatingPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
        // System shadow follows the rendered alpha mask, so it shapes itself
        // around our rounded inner view automatically. Earlier we drew a
        // custom shadow on outer.layer with shadowPath — that one leaked
        // into the corner gap (between rectangular window bounds and
        // rounded content) and was the source of all the corner-bleed
        // through v0.1.23. Removing it entirely and using the system
        // shadow gave us back a clean rounded shadow with no corner leak.
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        // Outer container: just hosts inner. No own shadow, no own bg.
        outer = NSView(frame: NSRect(origin: .zero, size: panelSize))
        outer.wantsLayer = true

        // Inner container: rounded clip via cornerRadius + masksToBounds.
        // No CAShapeLayer mask here — its fixed path didn't grow with
        // window resize, which hid the footer bar when the user dragged
        // the panel larger. cornerRadius adapts automatically.
        inner = NSView()
        inner.wantsLayer = true
        inner.layer?.cornerRadius = cornerRadius
        inner.layer?.masksToBounds = true
        inner.translatesAutoresizingMaskIntoConstraints = false

        visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = cornerRadius
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        tint = NSView()
        tint.wantsLayer = true
        tint.layer?.cornerRadius = cornerRadius
        tint.layer?.masksToBounds = true
        tint.translatesAutoresizingMaskIntoConstraints = false

        let host = NSHostingView(rootView: EditorView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false

        inner.addSubview(visualEffect)
        inner.addSubview(tint)
        inner.addSubview(host)
        outer.addSubview(inner)

        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: outer.topAnchor),
            inner.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            inner.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: outer.trailingAnchor),

            visualEffect.topAnchor.constraint(equalTo: inner.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: inner.trailingAnchor),

            tint.topAnchor.constraint(equalTo: inner.topAnchor),
            tint.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: inner.trailingAnchor),

            host.topAnchor.constraint(equalTo: inner.topAnchor),
            host.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: inner.trailingAnchor),
        ])

        panel.contentView = outer

        positioner.place(panel, size: { [rememberedSize] _ in rememberedSize })

        applyTheme(model.theme)
        model.onThemeChange = { [weak self] theme in
            self?.applyTheme(theme)
        }
        model.onDismissRequest = { [weak self] in
            self?.dismiss()
        }

        // Esc dismisses any modal overlay first; falls through to the
        // panel's normal dismiss behavior only when nothing is open.
        panel.onCancel = { [weak self] in
            self?.model.dismissTopOverlay() ?? false
        }

        // One teardown for every hide, wherever it was ordered from.
        panel.onHide = { [weak self] in
            self?.handleHide()
        }

        // Any of our windows, not just the panel: an open picker holding focus
        // must keep its own Esc.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyWindowObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    // Deferred a turn: mid-handoff, `NSApp.keyWindow` can still
                    // name the window that is resigning.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.updateEscapeCapture() }
                    }
                })
        }
    }

    /// On screen *and* holding keyboard focus. The gate for every chord
    /// that only means something with the panel in front of the user —
    /// visibility alone isn't enough, since an app-modal picker leaves the
    /// panel showing but not accepting input.
    var isPanelFocused: Bool { panel.isVisible && panel.isKeyWindow }

    /// Pins the panel unless it already is — for the menu items that need
    /// it on screen and focused before they can do anything.
    func openIfNeeded() {
        if state != .pinned { send(.togglePin) }
    }

    func togglePin() {
        send(.togglePin)
    }

    func dismiss() {
        if panel.isVisible {
            send(.dismiss)
        } else {
            // Already off screen — still tear down, in case something
            // hid the panel without going through orderOut.
            handleHide()
        }
    }

    /// The one place hide-time teardown lives. Idempotent: `dismiss()`
    /// and the panel's own orderOut can both reach it for a single hide.
    private func handleHide() {
        // Esc and the like order the panel out directly; the summon state
        // hears about it here rather than at each of those call sites.
        cancelHoldTimer()
        cancelModifierWatch()
        state = .hidden
        saveFrame()
        updateEscapeCapture()
        // orderOut leaves the SwiftUI hierarchy mounted, so overlays and
        // their app-wide key monitors survive the hide unless we say so.
        model.dismissAllOverlays()
    }

    /// Esc dismisses the panel even while another app has focus — a peek, or
    /// a pin the user has clicked away from. Carbon, like the summon chord, so
    /// no permission grant; the cost is that the app underneath doesn't get
    /// Esc while the panel is showing. With focus on one of our windows the
    /// claim is dropped, and Esc goes through `cancelOperation` and the
    /// overlays' own monitors as usual.
    private func updateEscapeCapture() {
        let wanted = panel.isVisible && NSApp.keyWindow == nil
        guard wanted != escapeKey.isRegistered else { return }
        if wanted {
            escapeKey.register(
                keyCode: UInt32(kVK_Escape), modifiers: 0,
                onPress: { [weak self] in self?.dismiss() })
        } else {
            escapeKey.unregister()
        }
    }

    /// Moves the panel back to its default spot and forgets the saved one.
    func resetPosition() {
        positioner.reset(panel, size: { [rememberedSize] _ in rememberedSize })
    }

    // MARK: Summon

    /// The summon chord went down. The panel comes up at once; which mode it
    /// settles into is decided by what happens next. Pressing it while
    /// pinned dismisses.
    func handleChordDown(modifiers: UInt32) {
        summonModifierFlags = Self.cgEventFlags(forCarbonModifiers: modifiers)
        send(.chordDown)
    }

    /// Before the hold elapses the release makes a pin. For a peek, letting
    /// go of the key alone doesn't end it while the chord's modifiers are
    /// still down; it ends when they lift.
    func handleChordUp() {
        let held = !summonModifierFlags.isEmpty && modifiersStillHeld()
        send(.chordUp(modifiersHeld: held))
        if state == .peeking { watchForModifierRelease() }
    }

    /// The one place `state` changes on purpose, and the showing, hiding,
    /// and timing that follow from it.
    ///
    /// A summon shows the panel without making it key, so a peek never
    /// takes the keyboard from the app underneath. Only a pin takes focus —
    /// it's the mode for typing into.
    private func send(_ event: SummonState.Event) {
        let previous = state
        state = state.next(on: event, peeksImmediately: settings.config.peekHoldSeconds == 0)

        if event == .chordDown || state != .summoning { cancelHoldTimer() }
        if state != .peeking { cancelModifierWatch() }
        guard state != previous || event == .chordDown else { return }

        switch state {
        case .hidden:
            panel.orderOut(nil)
        case .summoning:
            show()
            startHoldTimer()
        case .peeking:
            show()
        case .pinned:
            show()
            panel.makeKeyAndOrderFront(nil)
            model.requestFocus()
        }
    }

    /// Brings the panel up without taking focus. A no-op when it's already
    /// up, so re-summoning a peek doesn't jump it back into place.
    private func show() {
        guard !panel.isVisible else { return }
        // Every summon, not just the first: `monitor: pointer` places against
        // the screen the user is looking at *now*.
        positioner.place(panel, size: { [rememberedSize] _ in rememberedSize })
        applyTheme(model.theme)
        // Pick up changes another Mac wrote to scratchpad.md while
        // we were dismissed — covers the iCloud/Dropbox sync case.
        // Cheap (one stat + maybe one read), so safe to do every
        // open.
        model.reloadFromDiskIfChanged()
        model.refreshPlaceholder()
        panel.orderFrontRegardless()
        updateEscapeCapture()
        // Recompute shadow against current content alpha and force a
        // visual-effect re-render so the blur picks up the right
        // appearance on first show.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.visualEffect.state = .inactive
            self.visualEffect.state = .active
            self.panel.invalidateShadow()
        }
    }

    private func startHoldTimer() {
        let hold = settings.config.peekHoldSeconds
        holdTimer = Timer.scheduledTimer(withTimeInterval: hold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.holdElapsed) }
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    /// `true` while every modifier in the summon chord is still physically
    /// down. A state *query*, so unlike a `.flagsChanged` monitor it needs no
    /// Accessibility or Input Monitoring grant — the same reason the chord
    /// itself is a Carbon hotkey.
    private func modifiersStillHeld() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).intersection(summonModifierFlags)
            == summonModifierFlags
    }

    /// Polls fast enough that letting go reads as immediate, without
    /// installing anything that needs a permission grant.
    private func watchForModifierRelease() {
        modifierWatchTimer?.invalidate()
        modifierWatchTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.modifiersStillHeld() else { return }
                self.send(.modifiersReleased)
            }
        }
    }

    private func cancelModifierWatch() {
        modifierWatchTimer?.invalidate()
        modifierWatchTimer = nil
    }

    /// Carbon's modifier masks and `CGEventFlags` are different bit layouts
    /// for the same four keys.
    private static func cgEventFlags(forCarbonModifiers modifiers: UInt32) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        return flags
    }

    private func applyTheme(_ theme: Theme) {
        let chrome = Chrome.for(theme)
        panel.appearance = NSAppearance(named: chrome.appearance)
        visualEffect.material = chrome.material
        visualEffect.appearance = NSAppearance(named: chrome.appearance)
        // With blur off the tint is composited over nothing, so it starts
        // from the palette's `panel` — what the translucent version
        // composites to — rather than the chrome tint. A configured
        // opacity replaces either base's own alpha.
        let background = settings.config.background
        visualEffect.isHidden = !background.blur
        let base = background.blur ? chrome.tintColor : Palette.for(theme).panel
        let color = background.clampedOpacity.map { base.withAlphaComponent($0) } ?? base
        tint.layer?.backgroundColor = color.cgColor
        // Border is rendered by SwiftUI in EditorView via .overlay.
    }

    // MARK: Placement

    /// The size the panel was last left at, or the default one.
    private var rememberedSize: CGSize {
        guard let saved = settings.config.panel,
            saved.width >= minimumSide, saved.height >= minimumSide
        else { return panelSize }
        return CGSize(width: saved.width, height: saved.height)
    }

    /// Called from `applicationWillTerminate` — see `saveFrame`.
    func savePanelFrameIfVisible() {
        guard panel.isVisible else { return }
        saveFrame()
    }

    /// Written when the panel hides, never while it moves or resizes: the
    /// only reader is the next summon, so one write per showing is enough.
    private func saveFrame() {
        positioner.saveIfMoved(panel)
        let size = panel.frame.size
        guard size.width >= minimumSide, size.height >= minimumSide else { return }
        settings.setPanel(PanelFrame(width: Double(size.width), height: Double(size.height)))
    }
}
