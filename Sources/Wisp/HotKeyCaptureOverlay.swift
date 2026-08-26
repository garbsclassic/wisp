import SwiftUI
import AppKit
import Carbon.HIToolbox
import WispCore

/// Modal overlay shown while the user is rebinding the global hotkey.
/// Listens for the next valid key combo (must include at least one
/// modifier), then asks the parent to attempt Carbon registration.
/// On success the parent dismisses; on failure (combo in use system-
/// wide) the error is shown inline and capture mode keeps listening.
struct HotKeyCaptureOverlay: View {
    @Environment(\.palette) private var palette
    /// Returns nil on success or a user-facing error message otherwise.
    let onTryRegister: (HotKey) -> String?
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Solid background — no click-to-cancel here. Stray clicks
            // while the user is thinking about a combo shouldn't drop
            // them out of capture mode. Esc still cancels.
            Rectangle()
                .fill(Color(palette.panel).opacity(0.98))

            VStack(spacing: 14) {
                Text("Press your shortcut")
                    .font(Typography.ui(18, weight: .medium))
                    .foregroundStyle(Color(palette.text))
                Text("must include ⌘, ⌥, ⌃, or ⇧ — Esc to cancel")
                    .font(Typography.ui(11))
                    .foregroundStyle(Color(palette.muted))
                if let errorMessage {
                    Text(errorMessage)
                        .font(Typography.ui(12))
                        .foregroundStyle(Color(palette.danger))
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .padding(.horizontal, 24)
                }
            }
            .padding(40)
        }
        .onAppear { startListening() }
        .onDisappear { stopListening() }
    }

    private func startListening() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                onCancel()
                return nil
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let needed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            guard !mods.intersection(needed).isEmpty else { return nil }

            let hotKey = HotKey(
                keyCode: UInt32(event.keyCode),
                modifiers: HotKey.carbonModifiers(from: mods)
            )

            if let err = onTryRegister(hotKey) {
                errorMessage = err
                // Stay listening so the user can immediately try another.
            } else {
                onSuccess()
            }
            return nil
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
