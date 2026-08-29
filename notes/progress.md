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
- 2026-08-26 — [personalize](plan-personalize.md): code review of the branch
  ([findings](review-personalize.md)) — 15 findings fixed across panel lifecycle, palette tokens,
  typography, and the self-test suite; 161/161 pass
- 2026-08-26 — [personalize](plan-personalize.md): updater and first-run tour removed — Updater,
  UpdateAvailableOverlay, ReleaseNotes, TourOverlay, FirstRunDot and the two upstream release
  scripts deleted, wiring unpicked, About string re-credited (48f7743)
- 2026-08-26 — [personalize](plan-personalize.md): WispCore split + Swift Testing — logic target
  carved out of the app, SelfTests replaced by 53 `#expect` tests in 14 suites. Command Line Tools
  ships no XCTest or Testing module, so swift-testing is a pinned source dependency and the suites
  run as `swift run WispCoreTests` rather than `swift test` (f556925)
- 2026-08-26 — [personalize](plan-personalize.md): config file — Clef's Config/ConfigStore ported
  into WispCore, every UserDefaults key migrated into `~/.config/wisp/wisp.jsonc` and then cleared.
  New `JSONTextEdit` rewrites only the changed key's span so comments and key order survive a
  UI-driven change. KeyChord ported with an inverse renderer; default chord is now `ctrl+opt+.`.
  Also wires the settings that had none — vibrancy, dismissOnOutsideClick, `monitor: pointer` via a
  new relative-placement helper, fontScale — plus the coalesced footer warning (step 4) and the
  Settings… menu item. Frame now saves on hide, not on drag. 98 tests (4abdc69)
- 2026-08-26 — [personalize](plan-personalize.md): chezmoi integration — `.chezmoitemplates/wisp/`,
  `dot_config/wisp/modify_wisp.jsonc.tmpl`, the `.chezmoiignore.tmpl` entry, and a re-add hook
  block, all mirroring clef's. Preserve list is fontScale/fontSize/monitor/panel/theme. Verified
  end to end: `chezmoi apply` merges the live per-machine keys into the managed defaults, and a
  targeted app write leaves the biome-formatted file byte-identical but for the changed value
  (chezmoi 231a708)
- 2026-08-26 — tooling unification with Clef: switched `WispCoreTests` off the pinned
  `swift-testing` source package onto Clef's native `Testing.framework` approach (a real
  `.testTarget` plus `scripts/test.sh`'s linker flags) — the prior "does not actually run here"
  note turned out to be a stale `.build` cache, not a real incompatibility, confirmed by a clean
  rebuild passing all 99 tests. Also moved the app icon to a source PNG in `Resources/` with the
  `.icns` built at build time, renamed `build-app.sh`/`build/` to `build.sh`/`dist/`, added
  `install.sh`/`uninstall.sh` ported from Clef's (the former now restarts the app after a reinstall
  only if it was running before), and renamed the bundle identifier to `dev.garbs.wisp` (c4aeecf)
- 2026-08-29 — panel placement: new `position` setting (`auto` / `manual`, default `auto`). `auto`
  places the panel on every summon — centred, top edge a fifth down the screen's visible frame, via
  a pure `PanelFrameStore.autoFrame` — and neither reads nor writes `panel.x` / `panel.y`; the panel
  is not movable in that mode. `manual` is the old remember-where-you-left-it behavior, except an
  untouched panel now falls back to the auto placement and only writes an origin once it has
  actually been dragged, so a never-dragged panel isn't frozen to one display. `panel`'s `w` / `h`
  are spelled `width` / `height` (the old keys are still read), and `x` / `y` are optional. Fixed a
  drag that closed the panel on mouse-up under `dismissOnOutsideClick`: AppKit runs a
  window drag in its own tracking loop, so the mouse-up ending it reaches the *global* monitor and
  reads as a click on another app — now guarded by the cursor being over the panel plus a
  just-moved window. `monitor: primary` also placed against `NSScreen.main`, which is the *focused*
  screen, not the menu-bar one; it uses `screens.first` now. 110 tests
- 2026-08-29 — `position: auto` now puts the panel's top edge a tenth of the way down the screen
  rather than a fifth, so it reads as an overlay near the top of the display instead of sitting at
  eye level over whatever is behind it
