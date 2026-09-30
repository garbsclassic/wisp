import AppKit

// Kept identical in Wisp and Clef; a change here belongs in both.

/// A borderless panel dragged from anywhere that isn't text, or only inside `dragArea`. Run from
/// `sendEvent`, since a SwiftUI hosting view never allows `isMovableByWindowBackground`: a press
/// becomes a drag past `dragThreshold`, and the content gets a far-off mouse-up to end tracking.
class MovablePanel: NSPanel {
    /// So a slightly unsteady click still clicks.
    private static let dragThreshold: CGFloat = 3
    /// Near a resizable panel's edge a press belongs to AppKit's resize.
    private static let resizeMargin: CGFloat = 6

    /// Where a drag may start, in window coordinates. Nil allows anywhere that isn't text.
    var dragArea: ((NSPoint) -> Bool)?

    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var isDragging = false

    /// Takes the frame it's given: `PanelPlacement` already refuses an unreachable position, and
    /// AppKit would nudge a panel left partly off screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragStart = canStartDrag(at: event) ? (NSEvent.mouseLocation, frame.origin) : nil
            isDragging = false

        case .leftMouseDragged:
            guard let start = dragStart else { break }
            // Screen coordinates, since the window moves under the pointer.
            let mouse = NSEvent.mouseLocation
            let offset = NSPoint(x: mouse.x - start.mouse.x, y: mouse.y - start.mouse.y)
            if !isDragging {
                guard hypot(offset.x, offset.y) >= Self.dragThreshold else { break }
                isDragging = true
                cancelContentTracking(from: event)
            }
            setFrameOrigin(NSPoint(x: start.origin.x + offset.x, y: start.origin.y + offset.y))
            return

        case .leftMouseUp:
            let wasDragging = isDragging
            dragStart = nil
            isDragging = false
            if wasDragging { return }

        default:
            break
        }
        super.sendEvent(event)
    }

    /// Not on text, which selects, nor on scroll bars or a resizable panel's edges.
    private func canStartDrag(at event: NSEvent) -> Bool {
        let point = event.locationInWindow
        if let dragArea, !dragArea(point) { return false }
        if styleMask.contains(.resizable) {
            let inner = NSRect(origin: .zero, size: frame.size)
                .insetBy(dx: Self.resizeMargin, dy: Self.resizeMargin)
            guard inner.contains(point) else { return false }
        }
        guard let content = contentView else { return false }
        var view = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
        while let current = view {
            if current is NSText || current is NSTextField || current is NSScroller { return false }
            view = current.superview
        }
        return true
    }

    private func cancelContentTracking(from event: NSEvent) {
        guard
            let release = NSEvent.mouseEvent(
                with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000),
                modifierFlags: event.modifierFlags, timestamp: event.timestamp,
                windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: 0)
        else { return }
        super.sendEvent(release)
    }
}
