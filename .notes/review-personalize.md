# Review: personalize

Branch: `personalize` · Reviewed: 2026-08-25 · Fixed: 2026-08-26

Max-effort pass over `git diff main...HEAD` (12 commits, 20 files). Ten finder angles, one-vote
verification, one sweep. Two candidates were refuted and are recorded at the bottom so they don't
get re-raised.

All fifteen are fixed. The suite is 161/161, and four of the palette bugs below were
mutation-tested against the new assertions to confirm they would now be caught.

## Contents

- [Panel lifecycle](#panel-lifecycle)
- [Palette tokens](#palette-tokens)
- [Typography](#typography)
- [Tests and coverage](#tests-and-coverage)
- [Refuted](#refuted)
- [Cut for the report cap](#cut-for-the-report-cap)

## Panel lifecycle

- [x] **Outside-click dismiss stranded every modal overlay.**
      [PanelController.swift:174](../Sources/Wisp/PanelController.swift#L174) — `dismiss()` ordered
      the panel out without the `onCancel` chain, and `orderOut` doesn't unmount the SwiftUI
      hierarchy, so `showHotKeyCapture` stayed true with its swallow-everything keyDown monitor
      installed app-wide. Worst case: the next summon reopened in capture mode and the first
      modified keystroke silently rebound the global hotkey. Fixed with `EditorModel
      .closeAllOverlays()` called from a single `handleHide()`.
- [x] **"Open Wisp" closed the panel.**
      [AppDelegate.swift:17](../Sources/Wisp/AppDelegate.swift#L17) — `onClick` was still
      `toggle()` from when a plain left click was the trigger; with the button action deleted its
      only caller is a menu item labelled "Open Wisp", and the panel is still visible while the
      status menu tracks. Now `openIfNeeded()`.
- [x] **Modals ran with the click monitor armed.**
      [AppDelegate.swift:134](../Sources/Wisp/AppDelegate.swift#L134) — `pickStorageLocation`
      opened the panel _so the modal had something to sit over_, then any click elsewhere on the
      desktop dismissed it mid-flow. Added `PanelController.presentingModal { }`, wrapping the
      NSOpenPanel and every NSAlert in both storage paths.
- [x] **The teardown invariant was enforced in three places, and `NSApp.hide` escaped all of them.**
      [PanelController.swift:223](../Sources/Wisp/PanelController.swift#L223) — ⌥⌘H left the
      monitor armed while hidden; the next click anywhere ran `dismiss()`, which removed the
      monitor, leaving click-away silently dead after unhide. `FloatingPanel` now overrides
      `orderOut(_:)` with one `onHide` callback, and app hide/unhide notifications bracket the
      monitor. `onWillHide` is gone.

## Palette tokens

- [x] **Raised chips rendered as recesses in light theme.**
      [Theme.swift:132](../Sources/Wisp/Theme.swift#L132) — dropping `visualEffect.isHidden` left
      the panel compositing to `#F0EFEF`, above the `surface` chips at `#EAE9E9`. Measured off the
      running app rather than the nominal tint. `surface` → `#F7F6F6`, `panel` pinned to the
      measured `#F0EFEF`; both themes now sample chip-lighter-than-panel.
- [x] **The `---` rule went opaque over vibrancy.**
      [Theme.swift:84](../Sources/Wisp/Theme.swift#L84) — the dark panel is 55% tint over
      `.fullScreenUI`, so its luminance tracks the desktop; an opaque `#403E3C` rule halved in
      contrast at best and inverted over a light wallpaper. Back to an alpha-derived light line.
- [x] **`border` carried Modernist's structural rule at full alpha.**
      [Theme.swift:99](../Sources/Wisp/Theme.swift#L99) — it replaced three call sites that were
      all 10–12% washes, putting a 13.7:1 near-black outline on the find chip. This is the
      [two rule weights](plan-personalize.md#gotchas) gotcha arriving as a side effect of the token
      refactor. Now a hairline in both themes.
- [x] **The find match was indistinguishable from a selection.**
      [Theme.swift:100](../Sources/Wisp/Theme.swift#L100) — both became washes of one accent, 4–8%
      of alpha apart (1.06:1 in light). `findHighlight` is amber again, which is what the deleted
      "reads in both themes" comment was protecting.
- [x] **Tokens were pinned to device RGB.**
      [Theme.swift:40](../Sources/Wisp/Theme.swift#L40) — `NSColor(deviceRed:)` components are
      consumed unconverted, so the vermilion accent shifted between a P3 panel and an sRGB monitor.
      Now `srgbRed:`, the space the Flexoki/Modernist sets are specified in.
- [x] **Hotkey errors rendered in the accent.**
      [HotKeyCaptureOverlay.swift:40](../Sources/Wisp/HotKeyCaptureOverlay.swift#L40) — cyan in
      dark, the same hue as the caret two lines above, so the one string that must read as failure
      read as a hint. Added a `danger` token rather than overloading `accent`.
- [x] **The find highlight kept the outgoing theme's color.**
      [MinimalTextEditor.swift:72](../Sources/Wisp/MinimalTextEditor.swift#L72) — it's a storage
      attribute and `applyPalette` merges rather than replaces, so a mid-find theme flip left cyan
      on vermilion paper. Extracted `applyFindHighlight(to:scroll:)` and call it from both branches.
      The staleness predates the branch; opposed hues are what made it visible.
- [x] **The palette rollout stopped half way.**
      [BottomBar.swift:49](../Sources/Wisp/BottomBar.swift#L49) — thirteen chrome sites kept
      semantic colors while their neighbours moved to tokens, leaving two grey scales side by side
      and the footer at 1.85:1 where `muted` gives 7.19:1. Fixed at depth: a `\.palette`
      EnvironmentKey published once at the root. The five duplicate `private var palette` copies
      and the five `theme:` parameters are gone, and `FirstRunDot`'s `Color.accentColor` — the last
      non-palette accent — now reads the same environment.

## Typography

- [x] **`monospaced: true` resolved a proportional family.**
      [Typography.swift:44](../Sources/Wisp/Typography.swift#L44) — a Nerd Font's Mono/Propo suffix
      describes _icon_ advance, not Latin metrics; both families measured `isFixedPitch=false` with
      identical text metrics. The flag was a no-op where the fonts are installed and a real face
      swap where they aren't, so the fallback branch was the better-rendering one. Now
      `tabularDigits`, applying `.monospacedDigit()` over the UI family.

      Only FindBar's counter needed it. Verification found SF Mono had been _overflowing_
      HelpOverlay's 180pt and TourOverlay's 160pt key columns, so those drop the flag.
- [x] **`notesInstalled`/`uiInstalled` re-probed the font system on every access.**
      [Typography.swift:16](../Sources/Wisp/Typography.swift#L16) — ~2 µs on a hit, ~12 µs on a
      miss with no negative caching, ~40 lookups per overlay body. The miss is the shipping
      default. Now `static let`; a font activated mid-session needs a relaunch, which is noted.
- [x] **Two resolvers for one face, and no AppKit UI face.** `notes(_:)` re-resolved through a
      separate probe from `notesFont(_:)`, though they draw the same text in the same place — the
      empty-state placeholder sits directly on the text view. Now bridges via `Font(notesFont(…))`.
      Added `uiFont(_:)` so the About panel uses the face it describes, and corrected its copy,
      which claimed a fixed-width family that doesn't exist.

## Tests and coverage

- [x] **The palette self-tests were tautologies.**
      [SelfTests.swift:226](../Sources/Wisp/SelfTests.swift#L226) — 19 of 29 checks restated the
      hex literal `Theme.swift` states two files away, via a copy of its own `rgb` helper. Proved
      by mutation: swapping `deviceRed:` for `srgbRed:` passed all 21 checks unchanged.

      `sameColor` was also strictly _weaker_ than `NSColor.==` — it compared raw components, so a
      device-RGB and an sRGB color read equal, and `redComponent` aborts on a catalog color, which
      would turn a reportable failure into a suite-wide crash.

      Rewritten as relationship assertions: surface above panel, selection a wash _of_ the accent,
      find match _not_ the accent hue, rule translucent, border a hairline, danger distinct from
      accent, text tiers ordered. Mutation-tested against four bugs from this review — each now
      fails a named check.
- [x] **The bold-derivation check asserted the wrong thing.** `derived?.pointSize == 24` was the
      stated risk's proxy rather than the risk; now also asserts the `.bold` trait resolved.

## Refuted

Recorded so they don't get re-raised:

- **`menuWillOpen` clipping the appended shortcut.** The NSMenu.h prohibition is real ("Do not
  modify the structure of the menu or the menu items"), but a probe showed AppKit re-lays out
  afterwards — the rendered menu measured full width with the hidden row removed from layout, not
  left as a gap. Moved to `menuNeedsUpdate(_:)` anyway, since it costs nothing and is the
  sanctioned hook.
- **The bold-derivation test "cannot fail".** `NSFont(descriptor:size:)` returns nil, not a regular
  face, when the trait doesn't resolve — verified across all 189 installed families: 66 nil, 123
  genuinely bold, 0 non-nil-but-unbold. The check was oblique, not inert.

## Cut for the report cap

Fixed in the same pass, below the fifteen reported:

- [x] Five lines in `MenuBarController.init` over the 100-column default, wrapped to match the
      already-wrapped call five lines below.
- [x] The three menu-item back-references were `weak`, making assign-after-`addItem` load-bearing —
      the rule that caused the launch crash in d330218. `NSMenuItem.target` is itself weak, so
      strong refs can't cycle; the ordering hazard is gone.
- [x] `Quit Wisp` was the only item built without an icon, against the
      [menu mapping](plan-personalize.md#menu-mapping)'s `xmark.circle`.
- [x] `scripts/generate-icon.swift` still derived the icon from Charter, citing "the app's body
      typography (Charter)" — both anchors deleted on this branch.
- [x] Two source comments still pointed at the removed right-click menu.
- [x] Click-away dismissal was advertised in the README but nowhere in the app; added to the Help
      overlay's "Open / dismiss" section.
