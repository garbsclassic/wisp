import AppKit
import SwiftUI
import WispCore

private let panelSize = CGSize(width: 800, height: 640)
private let cornerRadius: CGFloat = 18

@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let model: EditorModel
    private let settings: Settings
    private let visualEffect: NSVisualEffectView
    private let tint: NSView
    private let inner: NSView
    private let outer: NSView
    /// Only the app hide/unhide pair now — the frame observers are gone,
    /// deliberately: nothing writes the config during a drag.
    private var observers: [NSObjectProtocol] = []
    /// Global mouse-up monitor backing click-outside-to-dismiss. Non-nil
    /// only while the panel is visible.
    private var outsideClickMonitor: Any?
    /// The frame `placePanel` last put the panel at. `position: manual`
    /// compares against it on hide to tell a drag from an untouched
    /// panel that simply opened where it was told to.
    private var placedFrame: NSRect?
    /// When the panel last moved or resized, used to spot the mouse-up
    /// that *ended* a drag — see `startOutsideClickMonitor`.
    private var frameChangedAt: Date?

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

        // Esc closes any modal overlay first; falls through to the
        // panel's normal dismiss behavior only when nothing is open.
        panel.onCancel = { [weak self] in
            guard let self else { return false }
            if self.model.showFind {
                self.model.closeFind()
                return true
            }
            if self.model.showHotKeyCapture {
                self.model.showHotKeyCapture = false
                return true
            }
            if self.model.showHelp {
                self.model.showHelp = false
                return true
            }
            return false
        }

        // One teardown for every hide, wherever it was ordered from.
        panel.onHide = { [weak self] in
            self?.handleHide()
        }

        // A drag or a live resize is the one thing that can put a mouse-up
        // over the panel in front of the *global* monitor, so note when one
        // happened — `startOutsideClickMonitor` uses it.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.frameChangedAt = Date() }
            }
            observers.append(token)
        }

        // NSApp.hide (⌥⌘H from another app, Dock → Hide) takes the panel
        // off screen without routing through orderOut, so the monitor has
        // to be stopped and restarted around it explicitly.
        for (name, visible) in [
            (NSApplication.didHideNotification, false),
            (NSApplication.didUnhideNotification, true),
        ] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: NSApp, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if visible {
                        if self.panel.isVisible,
                            self.settings.config.dismissOnOutsideClick
                        {
                            self.startOutsideClickMonitor()
                        }
                    } else {
                        self.stopOutsideClickMonitor()
                    }
                }
            }
            observers.append(token)
        }
    }

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
        stopOutsideClickMonitor()
        // orderOut leaves the SwiftUI hierarchy mounted, so overlays and
        // their app-wide key monitors survive the hide unless we say so.
        model.closeAllOverlays()
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
            if settings.config.dismissOnOutsideClick { startOutsideClickMonitor() }
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

    // MARK: Outside-click dismissal

    /// Set while Wisp is presenting its own modal (storage picker,
    /// alerts). Those run app-modal, so the rest of the desktop stays
    /// clickable and every such click would otherwise dismiss the panel
    /// the modal is sitting on.
    private var isPresentingModal = false

    /// Run `body` with outside-click dismissal suspended.
    func presentingModal<T>(_ body: () -> T) -> T {
        isPresentingModal = true
        defer { isPresentingModal = false }
        return body()
    }

    /// Any click outside the panel dismisses it outright — "go away",
    /// not "back out one level" (Esc keeps the layered-cancel chain).
    /// A global monitor only sees *other* apps' events, so clicks inside
    /// the panel and on Wisp's own status item can't false-trigger.
    /// Teardown hangs off FloatingPanel.onHide, so it can't be skipped by
    /// a hide added later; one left running while hidden would fire on
    /// every click the user makes anywhere.
    ///
    /// Dragging the panel is the exception the two guards below exist for.
    /// AppKit runs the drag inside its own tracking loop, so the mouse-up
    /// that ends it never arrives as a local event and this monitor sees
    /// it — closing the panel the user was only repositioning. The cursor
    /// is over the panel for the whole drag, which covers it; except when
    /// the window clamps against a screen edge and the cursor keeps going,
    /// which the just-moved window is what covers.
    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPresentingModal else { return }
                if self.panel.frame.contains(NSEvent.mouseLocation) { return }
                if let changed = self.frameChangedAt,
                    Date().timeIntervalSince(changed) < Self.dragSettleWindow
                {
                    self.frameChangedAt = nil
                    return
                }
                self.dismiss()
            }
        }
    }

    /// How recently the panel has to have moved for a mouse-up to read as
    /// the end of that drag. Long enough to cover the gap between the last
    /// `didMove` and the mouse-up, short enough that a deliberate click
    /// away right after a drag still dismisses.
    private static let dragSettleWindow: TimeInterval = 0.3

    private func stopOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func applyTheme(_ theme: Theme) {
        let chrome = Chrome.for(theme)
        panel.appearance = NSAppearance(named: chrome.appearance)
        visualEffect.material = chrome.material
        visualEffect.appearance = NSAppearance(named: chrome.appearance)
        // With vibrancy off the tint is composited over nothing, so it has
        // to carry the panel on its own; the palette records what the
        // translucent version composites to.
        let vibrancy = settings.config.vibrancy
        visualEffect.isHidden = !vibrancy
        tint.layer?.backgroundColor =
            (vibrancy ? chrome.tintColor : Palette.for(theme).panel).cgColor
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
        let manual = settings.config.position == .manual
        panel.isMovable = manual
        panel.isMovableByWindowBackground = manual

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

    /// Moving the panel ourselves fires `didMove`, which would otherwise
    /// leave `frameChangedAt` set and swallow the user's next outside
    /// click. Recording where we put it is what lets `saveFrame` tell a
    /// drag from a panel that just opened where it was told to.
    private func setPlacedFrame(_ frame: NSRect) {
        panel.setFrame(frame, display: false)
        placedFrame = frame
        frameChangedAt = nil
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
