import AppKit

/// Persists the panel's frame (size + position) across launches so
/// summoning Wisp restores it where and how the user last left it,
/// instead of snapping back to default-centered every time.
///
/// The validation logic (is a saved frame still reachable on the
/// current screen arrangement?) is pure so it can be unit-tested
/// without a running NSApplication.
public enum PanelFrameStore {
    public static let key = "PanelFrame"

    /// A saved frame must keep at least this much of itself overlapping
    /// a screen, otherwise it's considered stranded (e.g., it was saved
    /// on an external monitor that's since been unplugged) and we fall
    /// back to centering. Enough that the user can always grab it.
    public static let minVisible: CGFloat = 120

    /// Reject degenerate / absurd sizes from a corrupted default.
    public static let minSize: CGFloat = 200

    public static func save(_ frame: NSRect, defaults: UserDefaults = .standard) {
        defaults.set(NSStringFromRect(frame), forKey: key)
    }

    public static func load(defaults: UserDefaults = .standard) -> NSRect? {
        guard let s = defaults.string(forKey: key) else { return nil }
        let rect = NSRectFromString(s)
        if rect.isEmpty { return nil }
        return rect
    }

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
}
