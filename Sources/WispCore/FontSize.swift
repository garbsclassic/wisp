import CoreGraphics

/// The editor's three text sizes, cycled with ⌘1 / ⌘2 / ⌘3 or the footer
/// "Aa" button.
public enum FontSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    public var pointSize: CGFloat {
        switch self {
        case .small: return 17
        case .medium: return 20
        case .large: return 24
        }
    }

    public var next: FontSize {
        let all = FontSize.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}
