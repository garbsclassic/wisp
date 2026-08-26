# Personalize the Wisp fork

## Context

`wisp` is a fork of `sulemaanhamza/wisp` — a menu bar scratchpad — that still looks and behaves
like upstream's app, stores its settings in UserDefaults, and polls upstream's release feed. The
goal is to make it yours and bring it in line with Clef: your token sets, Inter Nerd Font,
dismiss-on-outside-click, a left-click menu, and a hand-editable `~/.config/wisp/wisp.jsonc` that
chezmoi manages the same way it manages `clef.jsonc`.

**This updates the fork rather than rebuilding.** Every ask lands on a seam that already exists:
`ThemePreference`/`Palette`/`Chrome` for theming, the `FontFace` enum and `makeFont` chain for
fonts, `FloatingPanel.onCancel` for dismissal, and an isolated `MenuBarController`. The theme work
is further along than it looks — `ThemePreference` already cycles light/dark/system, already
defaults to `.system`, and already re-resolves live through a KVO observer on
`NSApp.effectiveAppearance` ([EditorView.swift:149](Sources/Wisp/EditorView.swift:149)). Only the
color _values_ are wrong. Rebuilding would mean re-implementing ~1,000 lines of subtle `NSTextView`
work — the horizontal-rule layout manager, heading styling, smart list continuation, markdown
wrapping, find — that none of the asks touch.

One item surfaced during exploration and is now in scope: the fork still polls **upstream's**
release feed and can self-install over itself, which would revert everything below.

## Decisions

| Decision           | Chosen                                         | Why                                                                           |
| ------------------ | ---------------------------------------------- | ----------------------------------------------------------------------------- |
| Update vs. rebuild | Update the fork                                | All asks sit on existing seams; ~1,000 lines of NSTextView work untouched     |
| Dark palette       | Flexoki Dark                                   | The themes skill routes editors here; already backs Clef's dark theme         |
| Light palette      | Modernist Light, _colors only_                 | Its flush-corner geometry suits dense reference UI, not a writing surface     |
| Panel shape        | Keep the 18pt radius and vibrancy blur         | Light and dark keep one silhouette                                            |
| Accent             | Keep `#ec3013`, use it far less                | Cursor, find match, active states only; chrome goes to ink/muted              |
| Notes face         | `Inter Nerd Font` (`InterNF-*`)                | Fixed-width icon glyphs column-align in a notes body                          |
| UI face            | `Inter Nerd Font Propo` (`InterNFP-*`)         | Proportional glyphs read naturally in chrome, as Clef already does            |
| Font picker        | Delete `FontFace` entirely                     | A picker with one entry is a dead menu item                                   |
| Fonts on disk      | Reference by name, never bundle                | Matches Clef, which ships no font files at all                                |
| Outside click      | Dismiss the panel outright                     | Clicking away is "go away", not Esc's "back out one level"                    |
| Click hook         | `NSEvent.addGlobalMonitorForEvents`            | Only sees _other_ apps' events, so our own windows can't false-trigger        |
| Menu trigger       | Assign `statusItem.menu` permanently           | What makes left click open it; matches Clef's `StatusItemController`          |
| Updater            | Remove it entirely                             | Personal build; upstream releases would otherwise overwrite it                |
| Config location    | `~/.config/wisp/wisp.jsonc`, `XDG_CONFIG_HOME` | Alongside your other tools, not buried in Application Support; chezmoi-ready  |
| Config writes      | Targeted value rewrite, strict JSON out        | Keeps key order and formatting stable so `chezmoi diff` and re-add stay quiet |
| Panel frame        | In the config, on the preserve list            | Mirrors Clef's `sizeX`/`sizeY`/`offsetY` — visible and editable, never synced |
| Summon chord       | `ctrl+opt+.`                                   | ctrl is unused in `global.md`; sits beside Clef's `ctrl+opt+/` peek           |
| Test layout        | `WispCore` target + Swift Testing              | Replaces the hand-rolled harness with real assertions and `swift test`        |

## Work

### 1. Remove the updater and the first-run tour

First, because both are pure deletion and shrink the surface everything else touches.

Delete `Sources/Wisp/Updater.swift`, `UpdateAvailableOverlay.swift`, `ReleaseNotes.swift`, then
unpick the wiring:

- [main.swift:11](Sources/Wisp/main.swift:11) — drop the `applyPendingUpdateIfPossible()` guard
- [AppDelegate.swift:7](Sources/Wisp/AppDelegate.swift:7) — drop the `Updater()` property, the
  `PanelController` argument, and the `Task { await updater.check() }` at line 69
- [PanelController.swift:11](Sources/Wisp/PanelController.swift:11) — drop the stored `updater`, the
  init parameter, the `EditorView` argument, and the check block at lines 188–190
- [EditorView.swift:44](Sources/Wisp/EditorView.swift:44) — drop `updateDismissed`, the
  `@ObservedObject var updater`, `shouldShowUpdateOverlay` at line 467, the overlay at lines
  421–429, and the two `BottomBar` arguments at lines 367–368
- [BottomBar.swift:9](Sources/Wisp/BottomBar.swift:9) — drop `updateState` / `onUpdateClick` and the
  `updateIndicator` view
- [SelfTests.swift:252](Sources/Wisp/SelfTests.swift:252) — drop the throttle, `buttonAction`, and
  `ReleaseNotes` blocks (lines 252–290, 381–412)

Then the tour, which exists to introduce a stranger to upstream's app and whose copy is about to be
wrong on every line — it names `⌥Space` and "right-click the menu bar icon", both of which this
plan changes. Delete `Sources/Wisp/TourOverlay.swift` and `FirstRunDot.swift`, then:

- [EditorView.swift:39](Sources/Wisp/EditorView.swift:39) — drop `showFirstRunHint` and `showTour`,
  the `HasSeenFirstRunTour` read at line 166, `openTour()` and `dismissTour()` at lines 290–298, the
  dot at 376–381, and the overlay at 387–392
- [PanelController.swift:146](Sources/Wisp/PanelController.swift:146) — drop the tour branch from the
  `onCancel` chain

Check whether `pointerCursor()` in `CursorHelpers.swift` still has callers once `FirstRunDot` is
gone; delete it if not.

Delete `scripts/release.sh` and `scripts/bump-tap.sh`, which publish to upstream's repo and tap.
Keep `build-app.sh`. Correct the About string at
[AppDelegate.swift:201](Sources/Wisp/AppDelegate.swift:201), which still credits
`github.com/sulemaanhamza/wisp`, and drop the auto-update bullet from `README.md`.

### 2. Split out WispCore and adopt Swift Testing

Do this before the rewrites, so the new config and theme code lands in the right target with real
tests rather than being moved afterward.

Restructure `Package.swift` on Clef's shape: a `WispCore` target with no AppKit, a `Wisp`
executable depending on it, and a `WispCoreTests` test target. Swift Testing ships with the Swift 6
toolchain, so `swift test` works under Command Line Tools with no external dependency — Clef's
`Tests/ClefCoreTests` is the working precedent.

Move into `WispCore`: `Headings.swift`, `SmartEditing.swift`, `EmojiReplace.swift`,
`TextSearch.swift`, `HotKey.swift` (Carbon-only, like Clef's `KeyChord`), `StorageLocation.swift`,
`PanelFrameStore.swift`, `LaunchSource.swift`, plus the new config and token types. `MarkdownWrap`
and everything else that takes an `NSTextView` stays in the app target.

Replace `Sources/Wisp/SelfTests.swift` and the `--test` flag in `main.swift` with `@Test` functions
using `#expect` / `#require`, mirroring `Tests/ClefCoreTests/KeyChordTests.swift`. Add
`.swift-format` at the repo root with Clef's contents — `{"version": 1, "indentation": {"spaces": 4}}`.

### 3. Config file

Port Clef's config system into `WispCore` as `Config.swift` and `ConfigStore.swift`, keeping four
patterns that are the reason it holds up to hand-editing:

- **`ConfigStore.directory`** honors `XDG_CONFIG_HOME`, falling back to `~/.config/wisp`
- **`decoder.allowsJSON5 = true`** — JSON5 is a strict superset of JSONC, so comments and trailing
  commas parse with no hand-rolled stripper
- **`ConfigDiagnostics` + `lenientValue(forKey:default:diagnostics:pathPrefix:)`** — every key is
  optional on the way in, so adding a setting never invalidates a hand-edited file, and a key that
  is _present but the wrong shape_ gets named instead of silently defaulting
- **Clamping accessors** (`clampedFontScale` and friends) so a typo cannot render the app unusable

The schema, with everything not listed deliberately excluded as Clef-specific:

| Key                     | From Clef       | Notes                                                           |
| ----------------------- | --------------- | --------------------------------------------------------------- |
| `theme`                 | `theme`         | Wisp's is richer — light/dark/**system**, Clef has only two     |
| `fonts.notes`           | `fonts.body`    | `InterNF-Regular`                                               |
| `fonts.ui`              | `fonts.body`    | `InterNFP-Regular`                                              |
| `fontSize`              | —               | The existing small/medium/large cycle                           |
| `fontScale`             | `fontScale`     | Continuous multiplier, clamped 0.6–2.5, composes with the above |
| `vibrancy`              | `vibrancy`      | Currently hardcoded on for dark, off for light                  |
| `monitor`               | `monitor`       | `primary` \| `pointer` — see the placement rule below           |
| `dismissOnOutsideClick` | —               | Makes the new behavior switchable without a rebuild             |
| `scratchpadPath`        | `vaultPath`     | Replaces the `ScratchpadFolder` key                             |
| `keymap.summon`         | `keymap.peek`   | A chord string, not raw keycodes — defaults to `ctrl+opt+.`     |
| `panel.{x,y,w,h}`       | `sizeX`/`sizeY` | The remembered frame, replacing the `PanelFrame` key            |

Port Clef's `KeyChord` into `WispCore` too. Wisp stores the summon shortcut as raw Carbon integers
(`HotKeyCode` / `HotKeyMods`), which is meaningless in a config file; `KeyChord.parse` is what makes
`keymap.summon` hand-editable, and `KeyChord.menuKeyEquivalent(for:)` renders named keys as glyphs
in the menu.

The default changes from `opt+space` to **`ctrl+opt+.`** — `HotKey.default` in
[HotKey.swift:10](Sources/Wisp/HotKey.swift:10), the README's summon line, and the help overlay copy
all name the old chord. Verified free: the ctrl glyph does not appear anywhere in `global.md`, and
the only `.` bindings there are `shift+cmd+.` and `opt+.`.

**UserDefaults ends up empty.** With the tour and the updater gone, every remaining persisted value
moves into `wisp.jsonc` — theme, type size, font face, hotkey, storage path, panel frame — so the
config file becomes the single source of truth with no shadow store beside it. Old keys are read
once on first run to seed the file, then ignored. `PanelFrameStore`'s validation (`minSize`,
`minVisible`, `isUsable`) is already pure, so it moves to `WispCore` unchanged and keeps governing
whether a stored frame is restored or discarded.

**The frame is written when the panel hides, not while it moves.** Its only reader is the next
summon, so persisting at dismiss is exactly sufficient — no debounce timer, no burst during a drag,
one write per panel session. That deletes the two `NotificationCenter` observers and the
`frameObservers` array in [PanelController.swift:120](Sources/Wisp/PanelController.swift:120)
outright: route both hide paths (`dismiss()` and `toggle()`) through one method that saves before
`orderOut`, and add an `applicationWillTerminate` save for a quit with the panel still open. The
trade is that a crash or force-quit loses the last move, which is worth it to keep hand edits to
`panel` from being clobbered mid-drag.

**`monitor` versus the remembered frame.** These genuinely conflict, so give each a job:
`primary` keeps today's behavior — the saved frame wins when
[`PanelFrameStore.isUsable`](Sources/Wisp/PanelFrameStore.swift) says it fits the current layout,
otherwise center. `pointer` always places on the pointer's screen, carrying the saved frame's size
and its position _relative to_ its old screen. That needs an additive relative-placement helper in
`PanelFrameStore`, not a rewrite.

**The writer emits strict JSON.** UI affordances mutate settings (theme cycle, font size cycle,
hotkey capture, storage picker), so the file must round-trip. Rewrite only the changed key's value
in the file text rather than re-encoding the whole document — that keeps key order, indentation,
and any hand-added comments intact, which is what stops `chezmoi diff` filling with churn. Output
stays strict JSON for the reason in the chezmoi step below.

### 4. Warning surface

Adopt Clef's coalesced warning: several `@Published private var` warnings, one computed `warning`
that returns the most severe non-nil, rendered in the footer
([HUDViewModel.swift:98](/Users/comet/Source/clef/Sources/Clef/HUDViewModel.swift)). Wisp currently
has no way to report a bad config or a missing font, which matters now that fonts are referenced
rather than bundled. Cover: config unreadable, malformed config keys (`ConfigDiagnostics.summary`),
and fonts that failed to resolve.

### 5. Theme

Widen `Palette` in [Theme.swift](Sources/Wisp/Theme.swift) beyond its five tokens (`text`, `cursor`,
`selection`, `divider`, `findHighlight`) to cover what the views hardcode — at least `panel`,
`muted`, `accent`, `rule`, `surface`, `border` — and fill them from the themes skill: Flexoki Dark
for `.dark`, Modernist Light for `.light`. Follow Clef and express the tokens as an AppKit-free
`RGBA` value type in `WispCore`, with a thin AppKit binding in the app target, so palettes are
assertable in tests.

Keep `Chrome` separate — it feeds AppKit's material, appearance, and border, a different consumer
from `Palette`'s text attributes — and drive its blur from the new `vibrancy` setting instead of
`theme == .light`.

Then replace the hardcoded colors with palette lookups. The pattern repeats across seven view
files — `Color(white: 0.16)`, `.foregroundStyle(.secondary)`, `Color.black.opacity(0.18)` — with
[FindBar.swift:74](Sources/Wisp/FindBar.swift:74) and
[HelpOverlay.swift:15](Sources/Wisp/HelpOverlay.swift:15) as the representative cases; `BottomBar`,
`HeaderBar`, `TourOverlay`, and `HotKeyCaptureOverlay` follow the same shape.

Accent discipline: `#ec3013` lands on the cursor, the find match, and active states only.

### 6. Fonts

Delete `Sources/Wisp/FontFace.swift`. Point `makeFont` in
[MinimalTextEditor.swift:270](Sources/Wisp/MinimalTextEditor.swift:270) at the configured
`fonts.notes`, replacing the serif fallback chain with `NSFont.systemFont`.

Add a `Typography` helper resolving `fonts.ui` with a system fallback, modeled on Clef's
`ResolvedFonts` (`clef/Sources/Clef/HUDViewModel.swift:269`) — try `NSFont(name:size:)`, collect
what fails into `missing`, fall back to `.system(size:weight:)` at the matching weight, and feed
`missing` into the warning surface. Route the 25 `.system(size:)` call sites across the eight view
files through it, multiplying every size by `clampedFontScale`.

### 7. Outside click

Add a global monitor to [PanelController.swift](Sources/Wisp/PanelController.swift), started in
`toggle()` when the panel becomes visible and torn down in `dismiss()`, gated on
`dismissOnOutsideClick`:

```swift
NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
    self.dismiss()
}
```

Call `dismiss()` directly rather than `panel.onCancel` — an outside click closes the panel outright,
including with the Find bar or an overlay open. Esc keeps its layered behavior in
[FloatingPanel.swift:15](Sources/Wisp/FloatingPanel.swift:15), untouched.

### 8. Menu bar

Rewrite [MenuBarController.swift](Sources/Wisp/MenuBarController.swift) against Clef's
`StatusItemController`. Three changes carry it: assign `statusItem.menu` permanently at init instead
of the `performClick`-then-nil trick, which is what makes a plain left click open the menu; give
every item an SF Symbol at `.small` scale via Clef's `symbol(_:)` helper; and adopt
`NSMenuDelegate.menuWillOpen` to refresh the Launch at Login checkmark.

| Wisp item              | Icon                   | From Clef                          |
| ---------------------- | ---------------------- | ---------------------------------- |
| Open Wisp              | `square.and.pencil`    | no equivalent — HUD is hotkey-only |
| Settings…              | `gearshape`            | exact match, same wording          |
| Set Shortcut…          | `keyboard`             | no equivalent                      |
| Launch at Login        | `power`                | exact match, same wording          |
| Storage Location…      | `folder`               | `Reveal Notes in Finder`           |
| Reset Storage Location | `arrow.uturn.backward` | no equivalent                      |
| About Wisp             | `info.circle`          | no equivalent                      |
| Quit Wisp              | `xmark.circle`         | exact match, same wording          |

`Settings…` is new and reuses Clef's `openConfig` verbatim — seed the file if absent, then
`NSWorkspace.shared.open` it so whatever owns `.jsonc` handles it. The `Font` submenu goes with
`FontFace`. `Open Wisp` becomes item one, since left click now opens the menu; ⌥Space stays the fast
path.

### 9. chezmoi integration

Mirror the clef setup exactly, in `~/.local/share/chezmoi`:

- `.chezmoitemplates/wisp/wisp.jsonc` — managed defaults, sorted and biome-formatted
- `.chezmoitemplates/wisp/wisp-preserve.jsonc` —
  `[["fontScale"], ["fontSize"], ["monitor"], ["panel"], ["theme"]]`
- `dot_config/wisp/modify_wisp.jsonc.tmpl` — a copy of
  [modify_clef.jsonc.tmpl](/Users/comet/.local/share/chezmoi/dot_config/clef/modify_clef.jsonc.tmpl)
  with the names swapped
- `.chezmoiignore.tmpl` — add `.config/wisp/` to the non-macOS block beside `.config/clef/`
- `.chezmoi.toml.tmpl` — add a wisp block to `[hooks.re-add.post]` inside the existing
  `{{- if .is_macos }}` guard, mirroring the clef block at lines 88–107

The preserve list is what the app rewrites at runtime _and_ that legitimately varies per machine —
theme, type size, type scale, monitor choice, and the panel frame, whose absolute coordinates are
meaningless on a Mac with a different display. `keymap`, `fonts`, `scratchpadPath`, `vibrancy`, and
`dismissOnOutsideClick` stay managed, because you want those identical on every Mac; changing one
through the UI is local until `chezmoi re-add` promotes it. Preserving `["panel"]` as a whole
subtree rather than four separate paths keeps the list readable and the `jq` merge simple.

### 10. Docs

Update `README.md` — drop the "Six fonts" and "Auto-update" bullets, document the config file and
its keys, and reword the right-click menu references. Refresh `docs/screenshot.png`. Mirror this
plan into `notes/plan-personalize.md` and start `notes/progress.md`, per the project-notes
convention.

## Gotchas

- **The deployed `wisp.jsonc` must stay strict JSON.** The app reads it with `allowsJSON5`, so
  comments are fine as far as Wisp is concerned — but `jq` parses strict JSON only, and both the
  `modify_` script and the re-add hook run through `jq`. A comment in the live file makes the merge
  silently fall back to managed-only values and **drop every preserved setting**. Clef's script
  documents this; Wisp's must too.
- **Nothing writes the config during a drag.** The frame save moved to panel-hide precisely so a
  slow drag cannot emit a burst of file rewrites over someone's hand edits. Do not reintroduce a
  `didMove` observer.
- **Bold and italic derivation is verified safe.** Both families resolve by family name, and
  `withSymbolicTraits` yields `InterNF-Bold`, `-Italic`, and `-BoldItalic` correctly. Heading
  styling and ⌘B/⌘I need no change beyond the base font swap.
- **Tear the monitor down.** A global monitor left running while the panel is hidden fires on every
  click the user makes anywhere, forever.
- **`resignKey` is the wrong signal here.** The panel is `.nonactivatingPanel` with
  `hidesOnDeactivate = false`, and the app is usually not frontmost when summoned by hotkey.
- **Panel drags are unaffected.** `isMovableByWindowBackground` uses local events the global monitor
  never sees.
- **A staged update may be orphaned.** If a pending zip is already downloaded, removing the apply
  path leaves it in `~/Library/Application Support/Wisp/updates/` with two stale UserDefaults keys.
  Harmless; delete the directory by hand.
- **Do not rename the bundle ID** as part of this. `build-app.sh` still uses
  `com.sulemaanhamza.wisp`, and changing it orphans every existing setting plus the `SMAppService`
  login-item registration. Worth doing deliberately, with a migration, as separate work.

## Verification

```bash
swift test
```

`WispCoreTests` must cover chord parsing round-trips, config decoding with a missing key, a
malformed key landing in `ConfigDiagnostics`, clamping bounds, and both palettes' token values.

```bash
./scripts/build-app.sh && open build/Wisp.app
```

Then check by hand:

- **Config** — first run seeds `~/.config/wisp/wisp.jsonc`; `Settings…` opens it; a hand-edited
  `fonts.ui` takes effect; a deliberately malformed key names itself in the footer rather than
  vanishing; `XDG_CONFIG_HOME` redirects the location.
- **Migration** — with the old UserDefaults keys present, first run carries theme, font size,
  hotkey, storage path, and panel frame into the file. Afterward `defaults read com.sulemaanhamza.wisp`
  should be empty: nothing persists outside `wisp.jsonc`.
- **Summon chord** — a fresh install binds `ctrl+opt+.`; the README and help overlay name it rather
  than `⌥Space`. Confirm Clef's `ctrl+opt+/` still works with Wisp running.
- **Panel frame** — drag and resize with the file open in an editor and confirm nothing is written
  mid-drag; dismiss, and confirm `panel` updates once. Unplug an external display and confirm a
  stranded frame re-centers. Hand-edit `panel` while the panel is hidden and confirm the next summon
  honors it.
- **Tour is gone** — a first run on a clean profile opens straight into the editor, with no pulsing
  dot and no welcome overlay.
- **Theme** — cycle light → dark → system; flip macOS appearance while on system and confirm it
  re-resolves live. Confirm the accent appears only on cursor, find match, and active states, and
  that `vibrancy` toggles the blur.
- **Fonts** — notes in Inter Nerd Font, chrome in Propo. Type `**bold**`, `_italic_`, `# Heading`
  and confirm each resolves to a real face. Set `fonts.notes` to a nonexistent family and confirm
  the fallback plus a footer warning.
- **Outside click** — summon with ⌥Space, click another app: panel dismisses. Repeat with Find open
  and confirm the whole panel goes. Confirm Esc still closes Find first, and that
  `dismissOnOutsideClick: false` disables it.
- **Monitor** — with `pointer`, summon with the cursor on a second display and confirm the panel
  follows at its remembered size.
- **Menu** — plain left click opens it; every item shows its icon; the Launch at Login checkmark
  reflects reality after toggling externally.
- **chezmoi** — `chezmoi diff` is clean after a UI-driven theme change (preserved path); dirty after
  a hotkey change (managed path); `chezmoi re-add` promotes the latter and not the former.
