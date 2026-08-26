import AppKit

/// Persists the panel's frame (size + position) across launches so
/// summoning Wisp restores it where and how the user last left it,
/// instead of snapping back to default-centered every time.
///
/// The validation logic (is a saved frame still reachable on the
/// current screen arrangement?) is pure so it can be unit-tested
/// without a running NSApplication.
public enum PanelFrameStore {
    /// A saved frame must keep at least this much of itself overlapping
    /// a screen, otherwise it's considered stranded (e.g., it was saved
    /// on an external monitor that's since been unplugged) and we fall
    /// back to centering. Enough that the user can always grab it.
    public static let minVisible: CGFloat = 120

    /// Reject degenerate / absurd sizes from a corrupted default.
    public static let minSize: CGFloat = 200

    /// Pure: is `frame` reachable given the current screens' visible
    /// frames? True when it's a sane size and overlaps some screen by
    /// at least `minVisible` in both dimensions.
    public static func isUsable(_ frame: NSRect, onScreens screens: [NSRect]) -> Bool {
        guard frame.width >= minSize, frame.height >= minSize else { return false }
        for screen in screens {
            let overlap = frame.intersection(screen)
            if !overlap.isNull,
               overlap.width >= minVisible,
               overlap.height >= minVisible {
                return true
            }
        }
        return false
    }

    /// Carries a frame from one screen to another, keeping its size and its
    /// position *relative to* the screen it came from.
    ///
    /// This is what `monitor: pointer` needs: a frame two thirds down the
    /// left of a 1440-wide display should land two thirds down the left of
    /// the 1920-wide one, not at the same absolute coordinates — which on a
    /// smaller second screen would be off the edge entirely.
    ///
    /// The size is clamped to the destination, so moving to a smaller
    /// display shrinks the panel rather than stranding it.
    public static func moved(_ frame: NSRect, from source: NSRect, to destination: NSRect)
        -> NSRect
    {
        let size = NSSize(
            width: min(frame.width, destination.width),
            height: min(frame.height, destination.height))

        // Guard the degenerate case: a zero-width screen would divide by
        // zero, and there's nothing sensible to be relative *to*.
        let slackX = max(source.width - frame.width, 0)
        let slackY = max(source.height - frame.height, 0)
        let ratioX = slackX > 0 ? (frame.minX - source.minX) / slackX : 0.5
        let ratioY = slackY > 0 ? (frame.minY - source.minY) / slackY : 0.5

        return NSRect(
            x: destination.minX + (destination.width - size.width) * ratioX,
            y: destination.minY + (destination.height - size.height) * ratioY,
            width: size.width,
            height: size.height)
    }
}
