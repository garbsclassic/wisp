# Panel ownership and persistence

Wisp and Clef use a nonactivating AppKit panel with SwiftUI content. A peek is ordered forward without taking keyboard focus; a pin becomes key immediately. Window geometry belongs to `PanelFrameController`, while `PanelController` owns summon state, focus, and editor teardown.

Geometry is local runtime state rather than hand-edited configuration. Persist one rectangle in screen points through `NSStringFromRect` and `NSRectFromString`. AppKit's named-frame restoration remapped upper-display frames in Clef, so restore with `setFrame` and validate the actual resulting frame. Keep ordinary AppKit movement and resize constraints.

The panel stays where it was left. Use the primary display for initial placement and Reset Position, and recover unreachable frames when showing the panel or when displays change. Reset Position preserves size and centres the panel horizontally with its top edge 10% down the usable screen, reducing the inset when needed to fit. Reset Size preserves the top-left and sizes the panel to 40% of its current display's usable width and 60% of its usable height, with a 540×640-point minimum fitted to that screen. Both actions use the configurable keymap for the focused panel and the open status menu. Keep pure geometry rules in `WispCore/PanelPlacement.swift`; the two apps retain their own default dimensions and legacy size formats.

Import Wisp's former JSON `panel` and `position` only when no current saved frame exists. Wisp's old size was already in points, unlike Clef's old screen shares. Retain the old file without rewriting it. Delay migration and persistence while the file is unreadable so a transient error cannot permanently replace a user's placement. Either explicit reset supersedes migration, preserving the other current dimension even while the legacy file is unreadable.

The implementations remain local to each repository so both build from a fresh clone. `MovablePanel` shares the drag algorithm; placement and migration can differ where the applications' needs differ.

SwiftUI owns pointing-hand cursors through `pointerStyle(.link)`, including clipping and cursor restoration when controls disappear or are disabled. AppKit owns window-edge resizing and text cursors. The drawn checklist boxes retain their small text-view cursor override so a clickable box has an arrow while the surrounding text has an I-beam. Native pointer styles require macOS 15, matching Clef.
