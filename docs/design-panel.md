# Panel ownership and persistence

Wisp and Clef use a nonactivating AppKit panel with SwiftUI content. A peek is ordered forward without taking keyboard focus; a pin becomes key immediately. Window geometry belongs to `PanelFrameController`, while `PanelController` owns summon state, focus, and editor teardown.

Geometry is local runtime state rather than hand-edited configuration. Persist one rectangle in screen points through `NSStringFromRect` and `NSRectFromString`. AppKit's named-frame restoration remapped upper-display frames in Clef, so restore with `setFrame` and validate the actual resulting frame. Keep ordinary AppKit movement and resize constraints.

The panel stays where it was left. Use the primary display for initial placement and reset, and recover unreachable frames when showing the panel or when displays change. Reset restores Wisp's default size as well as its position. Keep pure geometry rules in `WispCore/PanelPlacement.swift`; the two apps retain their own default dimensions and legacy size formats.

Import Wisp's former JSON `panel` and `position` only when no current saved frame exists. Wisp's old size was already in points, unlike Clef's old screen shares. Retain the old file without rewriting it. Delay migration and persistence while the file is unreadable so a transient error cannot permanently replace a user's placement. An explicit reset supersedes migration.

The implementations remain local to each repository so both build from a fresh clone. `MovablePanel` shares the drag algorithm; placement and migration can differ where the applications' needs differ.
