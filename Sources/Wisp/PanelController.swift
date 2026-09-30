import AppKit
import SwiftUI
import WispCore

private let panelSize = CGSize(width: 800, height: 640)
/// Smaller than this on either side is a corrupted value, not a choice.
private let minimumSide: CGFloat = 200
/// A standard window's radius since Big Sur. AppKit exposes none, and a borderless panel draws no
/// corners of its own.
let panelCornerRadius: CGFloat = 10

@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let model: EditorModel
    private let settings: Settings
    private let visualEffect: NSVisualEffectView
    private let tint: NSView
    private let positioner: PanelPositioner

    /// Changed only through `send`, and by `handleHide` after the fact.
    private(set) var state: SummonState = .hidden
    /// Turns a summon into a peek after `peekHold`; a release before then leaves a pin.
    private var holdTimer: Timer?
    /// So a peek outlasts its key's release while the modifiers stay down.
    private var summonModifierFlags: CGEventFlags = []
    /// Polls for a peek's modifiers lifting, once its key has come up.
    private var modifierWatchTimer: Timer?

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
        // The system shadow follows the alpha mask, so it hugs the rounded content.
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let outer = NSView(frame: NSRect(origin: .zero, size: panelSize))
        outer.wantsLayer = true

        // cornerRadius and masksToBounds follow a resize, where a fixed mask layer wouldn't.
        let inner = NSView()
        inner.wantsLayer = true
        inner.layer?.cornerRadius = panelCornerRadius
        inner.layer?.masksToBounds = true
        inner.translatesAutoresizingMaskIntoConstraints = false

        visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = panelCornerRadius
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        tint = NSView()
        tint.wantsLayer = true
        tint.layer?.cornerRadius = panelCornerRadius
        tint.layer?.masksToBounds = true
        tint.translatesAutoresizingMaskIntoConstraints = false

        let host = NSHostingView(rootView: EditorView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false

        inner.addSubview(visualEffect)
        inner.addSubview(tint)
        inner.addSubview(host)
        outer.addSubview(inner)

        NSLayoutConstraint.activate(
            Self.edges(of: inner, pinnedTo: outer)
                + [visualEffect, tint, host].flatMap { Self.edges(of: $0, pinnedTo: inner) })

        panel.contentView = outer

        positioner.place(panel, size: { [rememberedSize] _ in rememberedSize })

        applyTheme(model.theme)
        model.onThemeChange = { [weak self] theme in
            self?.applyTheme(theme)
        }
        model.onDismissRequest = { [weak self] in
            self?.dismiss()
        }

        // Esc closes the top overlay first, and hides the panel only when none is open.
        panel.onCancel = { [weak self] in
            self?.model.dismissTopOverlay() ?? false
        }

        // One teardown for every hide, wherever it was ordered from.
        panel.onHide = { [weak self] in
            self?.handleHide()
        }
    }

    /// On screen and key: an app-modal picker leaves the panel showing but not taking input.
    var isPanelFocused: Bool { panel.isVisible && panel.isKeyWindow }

    /// The note's text view while it has the keyboard, not the help page or find field.
    var focusedNotesView: NotesTextView? {
        isPanelFocused ? panel.firstResponder as? NotesTextView : nil
    }

    /// Pins the panel unless it already is.
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
            // Tear down anyway, in case something hid it without orderOut.
            handleHide()
        }
    }

    /// Hide-time teardown. Idempotent, since `dismiss()` and orderOut can both reach it.
    private func handleHide() {
        // Esc and the like order out directly, so the summon state learns of it here.
        cancelHoldTimer()
        cancelModifierWatch()
        state = .hidden
        saveFrame()
        // orderOut leaves SwiftUI mounted, and overlays' key monitors with it.
        model.dismissAllOverlays()
    }

    /// Moves the panel back to its default spot and forgets the saved one.
    func resetPosition() {
        positioner.reset(panel, size: { [rememberedSize] _ in rememberedSize })
    }

    // MARK: Summon

    /// Shows the panel at once; what happens next decides the mode. Dismisses a pin.
    func handleChordDown(modifiers: NSEvent.ModifierFlags) {
        summonModifierFlags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        send(.chordDown)
    }

    /// A release before the hold makes a pin. A peek ends when the modifiers lift, not the key.
    func handleChordUp() {
        let held = !summonModifierFlags.isEmpty && modifiersStillHeld()
        send(.chordUp(modifiersHeld: held))
        if state == .peeking { watchForModifierRelease() }
    }

    /// Where `state` changes, and the showing and hiding that follow. Only a pin takes focus, so a
    /// peek never takes the keyboard from the app underneath.
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

    /// Without taking focus. A no-op when up, so re-summoning a peek doesn't move it.
    private func show() {
        guard !panel.isVisible else { return }
        // Every summon, since `monitor: pointer` follows the screen in use now.
        positioner.place(panel, size: { [rememberedSize] _ in rememberedSize })
        applyTheme(model.theme)
        // Picks up a synced change: one stat, and a read only if it changed.
        model.reloadFromDiskIfChanged()
        model.refreshPlaceholder()
        panel.orderFrontRegardless()
        // Re-render the blur and shadow, or the first show can have the wrong appearance.
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

    /// A state query, which needs no Accessibility or Input Monitoring grant.
    private func modifiersStillHeld() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).intersection(summonModifierFlags)
            == summonModifierFlags
    }

    /// Polls fast enough to feel immediate, with nothing that needs a grant.
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

    private func applyTheme(_ theme: Theme) {
        let chrome = Chrome.for(theme)
        panel.appearance = NSAppearance(named: chrome.appearance)
        visualEffect.material = chrome.material
        visualEffect.appearance = NSAppearance(named: chrome.appearance)
        // Without blur the tint composites over nothing, so it starts from `panel`. A configured
        // opacity replaces the base's alpha.
        let background = settings.config.background
        visualEffect.isHidden = !background.blur
        let base = background.blur ? chrome.tintColor : Palette.for(theme).panel
        let color = background.clampedOpacity.map { base.withAlphaComponent($0) } ?? base
        tint.layer?.backgroundColor = color.cgColor
        // EditorView draws the border.
    }

    private static func edges(of view: NSView, pinnedTo container: NSView) -> [NSLayoutConstraint] {
        [
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ]
    }

    // MARK: Placement

    /// The size the panel was last left at, or the default one.
    private var rememberedSize: CGSize {
        guard let saved = settings.config.panel,
            saved.width >= minimumSide, saved.height >= minimumSide
        else { return panelSize }
        return CGSize(width: saved.width, height: saved.height)
    }

    /// For quitting, which skips the hide.
    func savePanelFrameIfVisible() {
        guard panel.isVisible else { return }
        saveFrame()
    }

    /// On hide rather than on every move or resize: the next summon is the only reader.
    private func saveFrame() {
        positioner.saveIfMoved(panel)
        let size = panel.frame.size
        guard size.width >= minimumSide, size.height >= minimumSide else { return }
        settings.setPanel(PanelFrame(width: Double(size.width), height: Double(size.height)))
    }
}
