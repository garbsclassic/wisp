import AppKit

// Kept identical in Wisp and Clef: both panels are dragged by this one type.

/// A borderless panel moved by dragging anywhere that isn't text, or only
/// inside `dragArea` when one is set.
///
/// `isMovableByWindowBackground` can't do it: AppKit only starts that drag
/// when the view under the pointer answers `mouseDownCanMoveWindow`, and a
/// SwiftUI hosting view never does. So the drag is run here, in `sendEvent`,
/// ahead of the content: the mouse-down still reaches the content, and only
/// once the pointer has travelled `dragThreshold` does it become a move.
///
/// At that point the content is sent a mouse-up far outside itself, which
/// ends whatever it was tracking — a button or a tap gesture — without
/// firing it, and the rest of the drag is kept from it.
class MovablePanel: NSPanel {
    /// How far the pointer travels before a press becomes a drag, so a
    /// slightly unsteady click still clicks.
    private static let dragThreshold: CGFloat = 3
    /// Near a resizable panel's edge a press belongs to AppKit's resize.
    private static let resizeMargin: CGFloat = 6

    /// Where a drag may start, in window coordinates. Nil allows anywhere that
    /// isn't text; a panel whose body is all clickable rows narrows it to its
    /// chrome.
    var dragArea: ((NSPoint) -> Bool)?

    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var isDragging = false

    /// AppKit constrains a window's frame to keep it on the screen it opens
    /// on, which would nudge a panel saved partly off screen back to somewhere
    /// it wasn't left. `PanelPlacement` already refuses a position that isn't
    /// reachable, so the panel takes the frame it's given.
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
            // Screen coordinates, not the event's window ones: the window moves
            // under the pointer, so a window-relative location would chase it.
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

    /// Text keeps its own drags — they select — as do scroll bars and, on a
    /// resizable panel, the edges.
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
