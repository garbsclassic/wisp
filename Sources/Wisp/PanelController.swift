import AppKit
import SwiftUI
import WispCore

private let panelSize = CGSize(width: 800, height: 640)
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
    /// The frame `placePanel` last put the panel at. `position: manual`
    /// compares against it on hide to tell a drag from an untouched
    /// panel that simply opened where it was told to.
    private var placedFrame: NSRect?

    init(model: EditorModel, settings: Settings) {
        self.model = model
        self.settings = settings
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
        // Actual value comes from `applyPosition()`, below — `auto`
        // places the panel itself, so there is nowhere for a drag to go.
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        // Outer container: just hosts inner. No own shadow, no own bg.
        outer = NSView(frame: NSRect(origin: .zero, size: panelSize))
        outer.wantsLayer = true

        // Inner container: rounded clip via cornerRadius + masksToBounds.
        // No CAShapeLayer mask here — its fixed path didn't grow with
        // window resize, which hid the bottom bar when the user dragged
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

        placePanel()

        applyTheme(model.theme)
        model.onThemeChange = { [weak self] theme in
            self?.applyTheme(theme)
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
    }

    /// On screen *and* holding keyboard focus. The gate for every chord
    /// that only means something with the panel in front of the user —
    /// visibility alone isn't enough, since an app-modal picker leaves the
    /// panel showing but not accepting input.
    var isPanelFocused: Bool { panel.isVisible && panel.isKeyWindow }

    func openIfNeeded() {
        if !panel.isVisible {
            toggle()
        }
    }

    func dismiss() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            // Already off screen — still tear down, in case something
            // hid the panel without going through orderOut.
            handleHide()
        }
    }

    /// The one place hide-time teardown lives. Idempotent: `dismiss()`
    /// and the panel's own orderOut can both reach it for a single hide.
    private func handleHide() {
        saveFrame()
        // orderOut leaves the SwiftUI hierarchy mounted, so overlays and
        // their app-wide key monitors survive the hide unless we say so.
        model.dismissAllOverlays()
    }

    func toggle() {
        if panel.isVisible {
            dismiss()
        } else {
            // Every summon, not just the first: `position: auto` and
            // `monitor: pointer` both place against the screen the user is
            // looking at *now*. For a settled `manual` panel it re-applies
            // the frame it already has, which is a no-op.
            placePanel()
            panel.makeKeyAndOrderFront(nil)
            applyTheme(model.theme)
            // Pick up changes another Mac wrote to scratchpad.md while
            // we were dismissed — covers the iCloud/Dropbox sync case.
            // Cheap (one stat + maybe one read), so safe to do every
            // open.
            model.reloadFromDiskIfChanged()
            model.requestFocus()
            model.refreshPlaceholder()
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

    /// Puts the panel where the config says it goes, and decides whether
    /// the user is allowed to move it from there.
    ///
    /// `position: auto` places it on every summon — centred, top edge a
    /// tenth down — and ignores any remembered origin. `manual` restores
    /// the remembered frame, falling back to the auto placement when there
    /// isn't a usable one: never dragged, or dragged onto a display that
    /// has since been unplugged.
    ///
    /// `monitor: pointer` chooses the screen for both modes, and in
    /// `manual` carries the remembered frame's position *relative to* its
    /// old screen, so the panel lands in the same spot on whichever display
    /// you are looking at.
    private func placePanel() {
        applyPositionMode()

        let manual = settings.config.position == .manual
        let screens = NSScreen.screens.map { $0.visibleFrame }
        let saved = settings.config.panel
        let size = saved.map { NSSize(width: $0.width, height: $0.height) } ?? panelSize
        let target = targetScreen()
        let auto = PanelFrameStore.autoFrame(size: size, on: target)

        guard manual, let saved, let origin = saved.origin else {
            setPlacedFrame(auto)
            return
        }

        let remembered = NSRect(
            x: origin.x, y: origin.y, width: saved.width, height: saved.height)
        guard PanelFrameStore.isUsable(remembered, onScreens: screens) else {
            setPlacedFrame(auto)
            return
        }

        if settings.config.monitor == .pointer {
            let anchor = screens.first { $0.intersects(remembered) } ?? target
            setPlacedFrame(PanelFrameStore.moved(remembered, from: anchor, to: target))
        } else {
            setPlacedFrame(remembered)
        }
    }

    /// Whether the user can drag the panel. Split out of `placePanel` so
    /// a config reload can pick up a changed `position` without also
    /// moving the panel that is currently on screen.
    func applyPositionMode() {
        let manual = settings.config.position == .manual
        panel.isMovable = manual
        panel.isMovableByWindowBackground = manual
    }

    /// The screen to place against: the pointer's under `monitor: pointer`,
    /// otherwise the one holding the menu bar — which is `screens.first`,
    /// not `NSScreen.main`. `main` is the screen holding the *focused*
    /// window, so on a two-display desk it follows whatever app the user
    /// was in when they summoned Wisp.
    private func targetScreen() -> NSRect {
        if settings.config.monitor == .pointer,
            let pointer = NSScreen.screens.first(where: {
                $0.frame.contains(NSEvent.mouseLocation)
            })
        {
            return pointer.visibleFrame
        }
        return NSScreen.screens.first?.visibleFrame ?? NSRect(origin: .zero, size: panelSize)
    }

    /// Recording where we put the panel is what lets `saveFrame` tell a
    /// drag from a panel that just opened where it was told to.
    private func setPlacedFrame(_ frame: NSRect) {
        panel.setFrame(frame, display: false)
        placedFrame = frame
    }

    /// Called from `applicationWillTerminate` — see `saveFrame`.
    func savePanelFrameIfVisible() {
        guard panel.isVisible else { return }
        saveFrame()
    }

    /// The frame is written when the panel hides, not while it moves: the
    /// only reader is the next summon, so one write per panel session is
    /// exactly sufficient — and a slow drag can't emit a burst of rewrites
    /// over someone's hand edits.
    ///
    /// The size is always remembered. The origin is only written once the
    /// panel has actually been moved off where it was placed, so under
    /// `auto` — which never moves it — the config's `x` / `y` are left
    /// exactly as the user wrote them, and under `manual` an untouched
    /// panel keeps falling back to the auto placement rather than freezing
    /// itself at one absolute point on one display.
    private func saveFrame() {
        let frame = panel.frame
        guard frame.width >= PanelFrameStore.minSize else { return }

        // A point of slack: AppKit pixel-aligns the frame it was handed,
        // and no one drags a window one point on purpose.
        let moved =
            settings.config.position == .manual
            && (placedFrame.map {
                abs($0.origin.x - frame.origin.x) > 1 || abs($0.origin.y - frame.origin.y) > 1
            } ?? true)
        let origin = moved ? frame.origin : nil

        settings.setPanel(
            PanelFrame(
                width: Double(frame.width), height: Double(frame.height),
                x: origin.map { Double($0.x) } ?? settings.config.panel?.x,
                y: origin.map { Double($0.y) } ?? settings.config.panel?.y))
    }
}
