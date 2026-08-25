# Personalize the Wisp fork

Branch: `personalize` · Started: 2026-08-25

## Contents

- [Verdict: update, do not rebuild](#verdict-update-do-not-rebuild)
- [Goal](#goal)
- [Decisions](#decisions)
- [Steps](#steps)
- [Menu mapping](#menu-mapping)
- [Gotchas](#gotchas)
- [Open questions](#open-questions)

## Verdict: update, do not rebuild

**Update the fork.** All four asks are surface work sitting on seams the app already has.

| Ask                | Seam that already exists                                            | Real work                       |
| ------------------ | ------------------------------------------------------------------- | ------------------------------- |
| Light/dark/system  | `ThemePreference` + `Palette` + `Chrome`, KVO on `effectiveAppearance` | Swap token values, widen struct |
| System fonts       | `FontFace` enum, `makeFont` fallback chain                          | Replace enum, add UI helper     |
| Click-outside      | `FloatingPanel.onCancel`, `PanelController.dismiss()`               | One event monitor               |
| Menu bar behavior  | `MenuBarController`, isolated, 184 lines                            | Rewrite one file               |

The theme work is further along than the ask assumes: `ThemePreference` already has a three-way
light/dark/system cycle, already defaults to `.system`, and already re-resolves live through a KVO
observer on `NSApp.effectiveAppearance` ([EditorView.swift:149](../Sources/Wisp/EditorView.swift#L149)).
Only the _color values_ are wrong, not the mechanism.

Against rebuilding: roughly 1,000 lines of the 4,019 are subtle `NSTextView` work — the
horizontal-rule layout manager, heading styling, smart list continuation, markdown wrapping,
find-in-scratchpad — plus a Carbon hotkey registrar, a background updater, an icon generator, and a
release pipeline. None of that is touched by the four asks, and none of it is quick to reproduce.

Fork divergence is a non-issue: `origin` is `garbsclassic/wisp` with no upstream remote configured,
so there is no merge to protect and no reason to keep the retheme surgical.

## Goal

Wisp stops looking like someone else's app. It picks up the Flexoki Dark / Modernist Light token
sets used across the rest of the toolchain, draws every glyph in Inter Nerd Font, dismisses on a
click anywhere outside the panel, and grows a menu bar menu that opens on a plain left click with
the same wording and icons Clef already uses for the items the two apps share.

## Decisions

| Decision            | Chosen                                        | Rejected                          | Why                                                                                                            |
| ------------------- | --------------------------------------------- | --------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Update vs. rebuild  | Update the fork                               | Rebuild from scratch              | Every ask lands on an existing seam; ~1,000 lines of NSTextView work is untouched by all four                    |
| Dark palette        | Flexoki Dark                                  | Keep the warm off-white           | The themes skill routes editors to Flexoki; it already backs Clef's dark theme                                   |
| Light palette       | Modernist Light, _colors only_                | Modernist including its geometry  | Modernist's flush corners and 2px rules suit dense reference UI; Wisp is a writing surface with an 18pt radius   |
| Accent use          | Sparingly — cursor, find match, active states  | Accent on chrome and labels       | `#ec3013` is a loud vermilion; on a page of prose it competes with the words                                     |
| Token struct        | Widen `Palette`, keep `Chrome` separate       | One flat struct                   | `Chrome` feeds AppKit material/appearance, `Palette` feeds text attributes — different consumers, different types |
| Notes face          | `Inter Nerd Font` (`InterNF-*`)               | Propo for both roles              | Fixed-width icon glyphs column-align in a notes body; this deliberately inverts Clef, which uses Propo for body   |
| UI face             | `Inter Nerd Font Propo` (`InterNFP-*`)        | Non-Propo for both roles          | Proportional glyphs read naturally in chrome, which is what Clef already does                                    |
| Font picker         | Delete `FontFace` entirely                    | Keep it, add Inter as a 7th       | "Remove current fonts" — a picker with one entry is a menu item that does nothing                                |
| Fallback            | System sans (`NSFont.systemFont`)             | Bundle the fonts in `Resources/`  | Fonts are referenced by family name, not shipped; bundling raises a license question for a public tap            |
| Click-outside hook  | `NSEvent.addGlobalMonitorForEvents`           | `windowDidResignKey`              | Global monitors only see _other_ apps' events, so the open panel and About window can't false-trigger a dismiss   |
| Click-outside verb  | Dismiss the panel outright                    | Run the layered Esc cancel chain  | Clicking away is "go away", not "back out one level" — see [Open questions](#open-questions)                      |
| Menu trigger        | Assign `statusItem.menu` permanently          | Keep the `performClick` trick     | A permanently assigned menu is what makes left click open it; matches `StatusItemController`                      |
| Panel summon        | `Open Wisp` as menu item 1                    | Left click toggles, menu on right | Explicitly asked for; ⌥Space stays the fast path, as Clef's HUD is hotkey-only                                    |

## Steps

- [x] Port Flexoki Dark and Modernist Light into `Theme.swift` as a widened `Palette`, adding the
      tokens the views currently hardcode: `panel`, `muted`, `accent`, `rule`, `surface`, `border`
- [x] Replace the hardcoded colors in `HelpOverlay`, `FindBar`, `BottomBar`, `HeaderBar`,
      `TourOverlay`, `UpdateAvailableOverlay`, `HotKeyCaptureOverlay` with palette lookups
- [x] Retune `Chrome` so the light theme reads as Modernist panel rather than plain white
- [x] Delete `FontFace.swift`; point `makeFont` at `Inter Nerd Font` with a system-sans fallback
- [x] Add a `Typography` helper resolving `InterNFP-*` with a system fallback, mirroring
      Clef's `ResolvedFonts` (`clef/Sources/Clef/HUDViewModel.swift:269`)
- [x] Route all 25 `.system(size:)` call sites across the 8 view files through it
- [x] Add the outside-click monitor to `PanelController`, started on show and torn down on dismiss
- [x] Rewrite `MenuBarController` against the [menu mapping](#menu-mapping): permanent menu, SF
      Symbols at `.small`, `NSMenuDelegate.menuWillOpen` for the Launch at Login checkmark
- [x] Drop the `FontFace` block from `SelfTests.swift`; add palette and font-resolution checks
- [x] Update `README.md` — the "Six fonts" bullet goes, the right-click wording changes
- [x] Refresh `docs/screenshot.png`

## Menu mapping

Wording and icon come from Clef where an item exists in both. `Launch at Login` and `Quit` are
exact matches; `Storage Location…` borrows the `folder` icon from `Reveal Notes in Finder` because
both answer "where do the files live", though the actions differ.

| Wisp item                | Icon                     | From Clef                        |
| ------------------------ | ------------------------ | -------------------------------- |
| Open Wisp                | `square.and.pencil`      | no equivalent — HUD is hotkey-only |
| Set Shortcut…            | `keyboard`               | no equivalent                    |
| Launch at Login          | `power`                  | exact match, same wording        |
| Storage Location…        | `folder`                 | `Reveal Notes in Finder`         |
| Reset Storage Location   | `arrow.uturn.backward`   | no equivalent                    |
| About Wisp               | `info.circle`            | no equivalent                    |
| Quit Wisp                | `xmark.circle`           | exact match, same wording        |

The `Font` submenu is removed with `FontFace`.

## Gotchas

- **Bold and italic derivation is safe.** Verified on this machine: `Inter Nerd Font` and
  `Inter Nerd Font Propo` both resolve by family name, and `withSymbolicTraits` yields
  `InterNF-Bold`, `InterNF-Italic`, and `InterNF-BoldItalic` correctly. Heading styling and ⌘B/⌘I
  in `MinimalTextEditor` need no change beyond the base font swap.
- **Everyone else gets the fallback.** The fonts are referenced, not bundled, and the Homebrew tap
  ships to people who don't have them. The system-sans fallback is the _default_ experience for
  anyone but you — it has to look deliberate, not broken.
- **A stale `FontFace` default persists.** Deleting the enum leaves a `"FontFace"` key in
  UserDefaults. Harmless if simply never read; no migration needed.
- **The panel is `.nonactivatingPanel` with `hidesOnDeactivate = false`.** The app is often not
  frontmost when summoned by hotkey, which is exactly why `resignKey` is the wrong signal and a
  global monitor is the right one.
- **The monitor must be torn down.** A global monitor left running while the panel is hidden burns
  a callback on every click the user makes anywhere, forever.
- **`isMovableByWindowBackground` is unaffected.** Panel drags are local events; the global monitor
  never sees them.
- **Two rule weights, if Modernist geometry is adopted.** Collapsing the 2px structural and 1px
  incidental rules to one weight flattens the hierarchy the palette depends on.

## Open questions

- **Does an outside click cancel one layer or dismiss everything?** The ask says "same as esc",
  which literally means running `panel.onCancel` — closing just the Find bar if it's open. The
  recommendation above is to dismiss outright instead, on the reasoning that clicking into another
  app is a "go away" gesture while Esc is a "back out" gesture. Worth confirming, since it's the one
  place the spec knowingly departs from the wording.
- **Should the light theme keep the 18pt corner radius and vibrancy blur?** Modernist calls for
  flush corners and flat fills. Keeping the radius means the light theme borrows Modernist's colors
  without its posture; going flush means light and dark panels have visibly different silhouettes.
- **Is Modernist's vermilion right for a writing surface at all?** Flexoki's cyan `#4ecbdf` has a
  light-mode-safe sibling if the accent turns out to shout.
