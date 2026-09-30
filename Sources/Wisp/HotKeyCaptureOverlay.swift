import SwiftUI
import AppKit
import Carbon.HIToolbox
import WispCore

/// Captures the next chord with a modifier and tries to register it. A failure, such as a chord
/// already in use, shows inline and capture keeps listening.
struct HotKeyCaptureOverlay: View {
    @Environment(\.palette) private var palette
    /// Returns nil on success or a user-facing error message otherwise.
    let onTryRegister: (KeyChord) -> String?
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // No click-to-cancel, so a stray click doesn't end capture; Esc cancels.
            Rectangle()
                .fill(Color(palette.panel).opacity(0.98))

            VStack(spacing: 14) {
                Text("Press your shortcut")
                    .font(Typography.ui(Metrics.titleSize, weight: .medium))
                    .foregroundStyle(Color(palette.text))
                Text("must include ⌘, ⌥, ⌃, or ⇧ — Esc to cancel")
                    .font(Typography.ui(Metrics.chromeSize))
                    .foregroundStyle(Color(palette.muted))
                if let errorMessage {
                    Text(errorMessage)
                        .font(Typography.ui(Metrics.labelSize))
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

            let chord = KeyChord(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: KeyChord.carbonModifiers(from: mods))

            if let err = onTryRegister(chord) {
                errorMessage = err
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
