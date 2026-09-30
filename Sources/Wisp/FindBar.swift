import SwiftUI
import AppKit
import Carbon.HIToolbox
import WispCore

/// The find bar: ↵ and ⇧↵ step through matches, Esc dismisses.
struct FindBar: View {
    @Environment(\.palette) private var palette
    @Binding var query: String
    let matchCount: Int
    let currentIndex: Int   // 1-based; 0 when no matches
    let onNext: () -> Void
    let onPrev: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focused: Bool
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Typography.ui(Metrics.labelSize))
                .foregroundStyle(Color(palette.muted))

            TextField("Find", text: $query)
                .textFieldStyle(.plain)
                .font(Typography.ui(Metrics.rowSize))
                .focused($focused)
                .frame(width: 160)

            Text(countLabel)
                .font(Typography.ui(Metrics.chromeSize, tabularDigits: true))
                .foregroundStyle(Color(palette.muted))
                .frame(minWidth: 58, alignment: .trailing)

            Divider().frame(height: 16)

            iconButton("chevron.up", help: "Previous (⇧↵)", action: onPrev)
                .disabled(matchCount == 0)
            iconButton("chevron.down", help: "Next (↵)", action: onNext)
                .disabled(matchCount == 0)
            iconButton("xmark", help: "Dismiss (Esc)", action: onDismiss)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(barFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 14, y: 4)
        )
        .onAppear {
            startListening()
            // Next tick: the field isn't in the responder chain yet, so focusing now does nothing.
            DispatchQueue.main.async { focused = true }
        }
        .onDisappear { stopListening() }
    }

    private var countLabel: String {
        if query.isEmpty { return "" }
        if matchCount == 0 { return "none" }
        return "\(currentIndex)/\(matchCount)"
    }

    private var barFill: Color {
        Color(palette.surface)
    }

    private var borderColor: Color {
        Color(palette.border)
    }

    @ViewBuilder
    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(Typography.ui(Metrics.chromeSize, weight: .medium))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(palette.muted))
        .pointerCursor()
        .help(help)
    }

    /// Esc and ↵ while the field has focus, which would otherwise swallow them.
    private func startListening() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                onDismiss()
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if event.modifierFlags.contains(.shift) { onPrev() } else { onNext() }
                return nil
            default:
                return event
            }
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
