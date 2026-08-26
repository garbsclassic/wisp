# Progress

- 2026-08-25 — [personalize](plan-personalize.md): retheme — Flexoki Dark / Modernist Light tokens
  in a widened `Palette`, all view colors routed through it, Chrome light mode now a flat
  Modernist panel fill (67707db)
- 2026-08-25 — [personalize](plan-personalize.md): fonts — `FontFace` deleted, Inter Nerd Font /
  Propo resolved through a new `Typography` helper with system-sans fallback, all SwiftUI
  `.system(size:)` sites routed through it (c02c5cc)
- 2026-08-25 — [personalize](plan-personalize.md): click-outside — global mouse-up monitor on
  `PanelController` dismisses outright, torn down on every hide path via the new
  `FloatingPanel.onWillHide` (a0583a4)
- 2026-08-25 — [personalize](plan-personalize.md): menu bar — permanent status-item menu opens on
  plain left click with Clef's wording/icons at `.small`; dynamic state via `menuWillOpen`
  (b168611)
- 2026-08-25 — [personalize](plan-personalize.md): self-tests — FontFace block replaced by palette
  token, accent-wash, Chrome, and font-resolution checks; 157/157 pass (dc348fa)
- 2026-08-25 — [personalize](plan-personalize.md): README wording — six-fonts bullet removed,
  right-click → menu bar menu, intro mentions click-away dismissal (6312835)
- 2026-08-25 — [personalize](plan-personalize.md): fix launch crash found while driving the app —
  MenuBarController assigned weak item refs before `menu.addItem` retained them; force-unwraps
  hit nil in `applicationDidFinishLaunching` (d330218)
- 2026-08-25 — [personalize](plan-personalize.md): screenshot refreshed — light Modernist panel on
  a Flexoki-bg canvas, captured from the dev build with argument-domain overrides (demo scratchpad,
  forced theme) so no real notes leak into the repo (ec60520)
- 2026-08-25 — [personalize](plan-personalize.md): vibrancy restored for light — tint is now a 75%
  paper wash over `.windowBackground` instead of an opaque fill with the effect view hidden;
  radius and vermilion accent confirmed as-is (99d5eb8, screenshot ed1241f)
