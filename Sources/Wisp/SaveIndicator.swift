import SwiftUI
import WispCore

/// A small accent dot in the panel's top corner, shown for a moment each
/// time the note lands on disk.
///
/// The fork this app started from had a dot in the same place — a pulsing
/// one, which opened a first-run tour that no longer exists. The tour went;
/// the affordance is worth keeping, repurposed for the one piece of state
/// the panel otherwise never reports. Saving is debounced and silent, so
/// without this there is nothing at all that says the note is safe.
///
/// No pulse this time. A ring that breathes forever is asking to be
/// clicked; this is a status light, and it should be over almost before it
/// is noticed.
struct SaveIndicator: View {
    let isVisible: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Circle()
            .fill(Color(palette.accent))
            .frame(width: Metrics.saveIndicatorSize, height: Metrics.saveIndicatorSize)
            .opacity(isVisible ? 1 : 0)
            // Out more slowly than in: the appearance is the event, and a
            // slow fade out reads as settling rather than as a blink.
            .animation(
                .easeOut(duration: isVisible ? 0.12 : 0.45), value: isVisible)
            .allowsHitTesting(false)
            .padding(.top, 14)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
