import SwiftUI
import WispCore

/// A dot shown briefly on each save, which is otherwise silent. No pulse: it's a status light.
struct SaveIndicator: View {
    let isVisible: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Circle()
            .fill(Color(palette.indicator))
            .frame(width: Metrics.saveIndicatorSize, height: Metrics.saveIndicatorSize)
            .opacity(isVisible ? 1 : 0)
            // Out more slowly than in, so it settles rather than blinks.
            .animation(
                .easeOut(duration: isVisible ? 0.12 : 0.45), value: isVisible)
            .allowsHitTesting(false)
            // The header's insets, nudged to the text's optical centre.
            .padding(.top, Metrics.saveIndicatorTopInset)
            .padding(.trailing, Metrics.chromeInsetX)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
