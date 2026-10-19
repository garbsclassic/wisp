import SwiftUI

extension View {
    /// SwiftUI owns cursor transitions, clipping, and restoration when the control disappears.
    func pointerCursor() -> some View {
        modifier(PointerCursor())
    }
}

private struct PointerCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.pointerStyle(isEnabled ? .link : nil)
    }
}
