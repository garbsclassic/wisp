import SwiftUI
import AppKit

extension View {
    /// The pointing hand while hovered, set on every move since NSTextView reasserts its I-beam.
    func pointerCursor() -> some View {
        self
            .onContinuousHover { phase in
                if case .active = phase {
                    NSCursor.pointingHand.set()
                }
            }
            .onHover { hovering in
                if !hovering {
                    NSCursor.arrow.set()
                }
            }
    }

}
