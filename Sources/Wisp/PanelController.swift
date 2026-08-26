import AppKit
import SwiftUI

private let panelSize = CGSize(width: 800, height: 640)
private let cornerRadius: CGFloat = 18

@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let model: EditorModel
    private let visualEffect: NSVisualEffectView
    private let tint: NSView
    private let inner: NSView
    private let outer: NSView
    private var frameObservers: [NSObjectProtocol] = []
    /// Global mouse-up monitor backing click-outside-to-dismiss. Non-nil
    /// only while the panel is visible.
    private var outsideClickMonitor: Any?

    init(model: EditorModel) {
        self.model = model
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

        // Restore the user's last frame if it's still reachable on the
        // current screen layout; otherwise center at the default size.
        let screens = NSScreen.screens.map { $0.visibleFrame }
        if let saved = PanelFrameStore.load(), PanelFrameStore.isUsable(saved, onScreens: screens) {
            panel.setFrame(saved, display: false)
        } else {
            panel.center()
        }

        applyTheme(model.theme)
        model.onThemeChange = { [weak self] theme in
            self?.applyTheme(theme)
        }

        // Persist size + position whenever the user moves or finishes
        // resizing the panel, so the next summon restores it. UserDefaults
        // writes are cheap; didMove/didEndLiveResize don't fire per-pixel.
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: panel, queue: .main
            ) { [weak panel] _ in
                // queue: .main guarantees this runs on the main actor;
                // assumeIsolated lets us touch panel.frame without a hop.
                MainActor.assumeIsolated {
                    guard let panel else { return }
                    PanelFrameStore.save(panel.frame)
                }
            }
            frameObservers.append(token)
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
                        if self.panel.isVisible { self.startOutsideClickMonitor() }
                    } else {
                        self.stopOutsideClickMonitor()
                    }
                }
            }
            frameObservers.append(token)
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
        stopOutsideClickMonitor()
        // orderOut leaves the SwiftUI hierarchy mounted, so overlays and
        // their app-wide key monitors survive the hide unless we say so.
        model.closeAllOverlays()
    }

    func toggle() {
        if panel.isVisible {
            dismiss()
        } else {
            // No re-centering — the panel keeps the size and position the
            // user last left it (restored from PanelFrameStore on launch,
            // kept fresh by the move/resize observers).
            panel.makeKeyAndOrderFront(nil)
            startOutsideClickMonitor()
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
        tint.layer?.backgroundColor = chrome.tintColor.cgColor
        // Border is rendered by SwiftUI in EditorView via .overlay.
    }
}
