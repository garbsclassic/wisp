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
            // With `monitor: pointer` the panel follows the cursor's
            // screen on every summon; on `primary` this is a no-op once a
            // usable frame has been restored.
            if settings.config.monitor == .pointer { placePanel() }
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
    /// the panel and on Wisp's own status item can't false-trigger, and
    /// panel drags (local events) are unaffected. Teardown hangs off
    /// FloatingPanel.onHide, so it can't be skipped by a hide added
    /// later; one left running while hidden would fire on every click
    /// the user makes anywhere.
    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPresentingModal else { return }
                self.dismiss()
            }
        }
    }

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

    /// Restores the remembered frame, or centres when there isn't a usable
    /// one — a frame saved on a display that has since been unplugged, say.
    ///
    /// `monitor: pointer` always places on the pointer's screen, carrying
    /// the remembered frame's size and its position *relative to* its old
    /// screen, so the panel lands in the same spot on whichever display you
    /// are looking at.
    private func placePanel() {
        let screens = NSScreen.screens.map { $0.visibleFrame }
        let saved = settings.config.panel.map {
            NSRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h)
        }

        if settings.config.monitor == .pointer,
            let target = NSScreen.screens.first(where: {
                $0.frame.contains(NSEvent.mouseLocation)
            })?.visibleFrame
        {
            let frame = saved ?? NSRect(origin: .zero, size: panelSize)
            let anchor = screens.first { $0.intersects(frame) } ?? screens.first ?? target
            panel.setFrame(
                PanelFrameStore.moved(frame, from: anchor, to: target), display: false)
            return
        }

        if let saved, PanelFrameStore.isUsable(saved, onScreens: screens) {
            panel.setFrame(saved, display: false)
        } else {
            panel.center()
        }
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
    private func saveFrame() {
        guard panel.frame.width >= PanelFrameStore.minSize else { return }
        settings.setPanelFrame(panel.frame)
    }
}
