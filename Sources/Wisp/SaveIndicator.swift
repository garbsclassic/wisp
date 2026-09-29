import SwiftUI
import WispCore

/// A small accent dot in the panel's top corner, shown for a moment each
/// time the note lands on disk. Saving is debounced and silent, so without
/// this there is nothing at all that says the note is safe.
///
/// No pulse: a ring that breathes forever is asking to be clicked; this is
/// a status light, and it should be over almost before it is noticed.
struct SaveIndicator: View {
    let isVisible: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Circle()
            .fill(Color(palette.indicator))
            .frame(width: Metrics.saveIndicatorSize, height: Metrics.saveIndicatorSize)
            .opacity(isVisible ? 1 : 0)
            // Out more slowly than in: the appearance is the event, and a
            // slow fade out reads as settling rather than as a blink.
            .animation(
                .easeOut(duration: isVisible ? 0.12 : 0.45), value: isVisible)
            .allowsHitTesting(false)
            // The header's own insets, so the dot sits on the chrome's
            // grid rather than the panel's — vertically nudged to the
            // text's optical centre, see the token.
            .padding(.top, Metrics.saveIndicatorTopInset)
            .padding(.trailing, Metrics.chromeInsetX)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
