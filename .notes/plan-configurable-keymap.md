# A configurable keymap, and three more editing verbs

## Contents

- [Context](#context)
- [Decisions](#decisions)
- [Work](#work)
- [Keymap surface](#keymap-surface)
- [What the verification changed](#what-the-verification-changed)
- [Verification](#verification)

## Verification note

Accessibility is granted this session, so synthetic key events work and every chord below gets driven for real — unlike [plan-editing-and-scale](plan-editing-and-scale.md), which had to leave its bindings unverified.

## Context

Six asks, and one of them reshapes how the other five are reached. "Add all keybinds to config file" means the menu can no longer be built from string literals: every item's `keyEquivalent` and modifier mask has to come from `keymap`, the menu has to be rebuilt when the config changes, and the panel-scope gate has to be derived from the same table rather than a hand-maintained `Set<Selector>`.

Two of the new verbs also need chords that aren't ⌘-based. `⌥↑` / `⌥↓` and `⌥H` / `⌥L` looked like legal menu key equivalents — AppKit takes any modifier mask — and claiming `⌥H` means it stops inserting `˙`, which is the intent. That assumption turned out to be wrong for letters; see [What the verification changed](#what-the-verification-changed).

The `fontScale` precision bug is mine from the last pass: `steppedFontScale` snaps onto the step grid and then multiplies, and `12 * 0.1` is `1.2000000000000002`. The grid arithmetic was right; the way back to a scale was not.

## Decisions

| Decision              | Chosen                                                          | Why                                                                                        |
| --------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Scale precision       | Divide by 10 rather than multiply by 0.1                         | `12/10.0` is the nearest double to 1.2 and prints "1.2"; `12*0.1` is a different double       |
| Bullets past depth 3  | Cycle `•` → `◦` → `▪` → `•`                                      | What Word and Docs do; the indent already carries absolute depth, so the glyph is rhythm      |
| Keymap shape          | One action → chord table, not 15 properties                      | 15 lenient-decode blocks to hand-maintain, against one loop over `KeymapAction.allCases`      |
| Panel scoping         | A flag on `KeymapAction`, replacing the `Set<Selector>`          | The gate and the binding then can't drift apart                                              |
| Unparseable chord     | Action left unbound, footer names it                             | Matches how `keymap.summon` already fails — visible, not silent                              |
| Dispatch              | A local key monitor on key codes, not menu equivalents           | Revised during verification — `keyEquivalent` cannot express `⌥L`; see below                  |
| Menu rebuild          | Whole `NSApp.mainMenu` on any keymap change                      | Rebuilding is microseconds and the menu is pure function of the config; patching is not       |
| Italic marker         | `_word_` for ⌘I; `*word*` still renders                          | Asked for. Reading both costs one regex and keeps old notes rendering                         |
| `_` word boundaries   | Require a non-alphanumeric on the outside of each `_`            | Without it `foo_bar_baz` renders `_bar_` italic — a real hazard in a notes app for code       |
| `__bold__`            | Rendered too                                                     | Otherwise `__x__` is the one emphasis form that renders as nothing                            |
| Highlight token       | New `Palette.highlight`, separate from `findHighlight`           | One is content the user wrote, one is transient UI state; they should be free to diverge      |
| Highlight vs find     | Find repaints on top, after the `==` pass                        | Both are `.backgroundColor` — there is no second background attribute to keep them apart      |
| Move line at an edge  | No-op `Edit`, not a wrap-around                                  | Wrapping a line from the top of the note to the bottom is never what the keypress meant       |
| Toggle list on a mix  | Any non-item in the block → make them all items                  | "Make this a list" is the common intent; unset only when it is already uniformly a list       |
| UI type sizes         | +2pt across the four chrome tokens, body untouched               | Asked for. `bodySize` is the one the scale multiplies against, so moving it would resize notes |

## Work

### 1. Fixes

- [x] `Metrics.steppedFontScale` divides by 10; test asserts the exact double, not an epsilon compare
- [x] `SmartEditing.bulletGlyph` cycles with `%` instead of clamping
- [x] Chrome sizes +2: `chromeSize` 11→13, `labelSize` 12→14, `rowSize` 13→15, `titleSize` 18→20

### 2. Inline markup

- [x] ⌘I wraps `_`; `styleInlineMarkup` reads `_x_` and `__x__` as well as the `*` forms, with the word-boundary guard
- [x] `Palette.highlight` in both themes; `==x==` painted with it
- [x] `applyFindHighlight` re-runs the `==` pass after clearing backgrounds, then paints the match over it

### 3. New verbs in `LineEdits`

- [x] `moveLines(in:selection:by:)` — ±1 line, no-op at either edge, selection rides the block
- [x] `toggleListItem(in:selection:marker:)` — via the existing `rewriteLines` head-change engine
- [x] Tests for both, including the last line with no trailing newline

### 4. Configurable keymap

- [x] `KeymapAction` — every bound action, its default chord, and whether it is panel-scoped
- [x] `Keymap` becomes an action → chord table; decode overlays the file onto the defaults so a partial `keymap` object still works
- [x] `KeyChord.menuEquivalent` — the `(character, NSEvent.ModifierFlags)` pair AppKit wants. Kept and tested, though dispatch no longer uses it
- [x] `KeyBindingMonitor` dispatches every action by key code, gated on `KeymapAction.isPanelScoped`
- [x] `MainMenuBuilder.make(target:keymap:)` builds the items; `AppDelegate.reloadConfig` rebuilds both menu and bindings when the keymap changed
- [x] `validateMenuItem` gates on `KeymapAction.isPanelScoped`
- [x] Help overlay and README read from the live keymap rather than hardcoded glyphs

## Keymap surface

```jsonc
"keymap": {
  "summon": "ctrl+opt+shift+cmd+.",
  "find": "cmd+f",
  "settings": "cmd+,",
  "refresh": "cmd+r",
  "help": "cmd+/",
  "bold": "cmd+b",
  "italic": "cmd+i",
  "highlight": "opt+h",
  "duplicateLine": "cmd+d",
  "toggleListItem": "opt+l",
  "moveLineUp": "opt+up",
  "moveLineDown": "opt+down",
  "increaseFontScale": "cmd+=",
  "decreaseFontScale": "cmd+-",
  "resetFontScale": "cmd+0"
}
```

## What the verification changed

Two things only came out under a real key event, and both changed the design.

**`keyEquivalent` cannot carry an Option-modified letter.** ⌥L typed `¬` into the note instead of firing the menu item: macOS composes the character before AppKit matches an equivalent, so an item asking for `"l"` plus `.option` never matches. Arrows and ⌘-chords were fine, which is the trap — a keymap where some chords bind and others silently type garbage is not a keymap. Dispatch moved to `KeyBindingMonitor`, a local key monitor matching on **key code**, which no modifier changes. Menu items for keymap actions now carry no equivalent at all, so nothing fires twice.

**`NSTextView` disables Cut and Copy when the selection is empty**, and a disabled item's key equivalent never fires — so the whole-line overrides added last pass were never being called. ⌘C did nothing at all. Fixed with a `validateUserInterfaceItem` override that keeps both enabled.

Neither was reachable by reading the code, and neither was covered by a unit test — the logic under both was already green.

## Verification

- [x] Every chord driven with a real `CGEvent`, asserting on the note or the config afterwards: ⌘D `'one\ntwo\ntwo\nthree'`, ⌥↑/⌥↓ round-trip, ⌥L set/unset/whole-selection, ⇥/⇧⇥ on a block, ⌘I `_three_`, ⌥H `==three==`, ⌘B `**three**`, ⌘C/⌘X whole line with the clipboard read back
- [x] `fontScale` read out of the file after three ups and one down: `1.3` then `1.2` — clean tenths, no drift
- [x] A rebound `duplicateLine` took effect on the next config reload; the old ⌘D stopped working and `opt+shift+d` started
- [x] Help page scrolls: ⌘↓ to the bottom, ⌘↑ back to a pixel-identical top, arrows step
- [x] Save dot measured appearing ~800ms after a keystroke, 6pt wide as specced, gone when idle, and absent across 12 frames with `saveIndicator: false`
- [x] `_italic_`, `__bold__`, `*star*`, `**double**`, `==highlight==` and the `foo_bar_baz` guard screenshotted in both themes
- [x] Bullet cycling screenshotted at five depths — `•` `◦` `▪` `•` `◦`

## Follow-up pass

Six smaller asks landed on the same files, plus two that needed a decision.

- **`bg-2` for chrome** was ambiguous — Flexoki's `bg-2` is already `Palette.panel`, and `Chrome.tintColor` is a different thing again. Asked; the answer was the header and footer bars, which now have a `Palette.chrome` surface of their own. Measured after: chrome composites to `#252322` against a `#21211F` body in dark — a real separation, and subtle by design.
- **Corner radius** has no API. `NSThemeFrame` carries no layer radius (macOS draws window corners in the window server), and a `.borderless` panel gets no system corners at all — every rounded edge is ours. Measuring a real window off the screen kept catching its shadow rather than its edge. Asked rather than guessed; settled on 10pt, the standard-window value since Big Sur.
- **Tooltip colour is not reachable.** AppKit renders `.help()` tooltips itself, so the chord in one cannot be muted while the label stays full-strength. The parentheses are gone and the chord is separated by spaces instead, which is as far as a system tooltip goes. A custom tooltip view would get the rest, and is not worth it for four buttons.
- **F1 is a trap on a default Mac.** It dims the display, and the app never sees the key — verified here with `defaults read -g com.apple.keyboard.fnState`. The synthetic events used for testing bypass that translation, so it passed under test and would have failed in the hand. This is the case the alias list exists for, and `cmd+/` stays bound.

## Second follow-up: two SwiftUI layout traps

Both cost a build-and-look cycle, and neither is visible in the code.

**`.fixedSize` escapes a clip and resizes the window.** The heading strip was laid out at its natural width and clipped by hand, to truncate rather than scroll. The natural width propagated up through `NSHostingView` and the panel grew to fit it — measured 3952pt wide, from a note with fourteen headings. The scroll view that was there originally is what had been absorbing that, and it went back. It clips, it does not propagate, and long lists stay reachable; the ellipsis is an overlay on top of it.

**One `PreferenceKey` used at two nesting levels reads itself.** Content width and slot width were both reported under the same key. Preferences propagate up, so the outer reader also saw the inner value, and with a `max` reduction the slot silently reported the content's width — `isTruncated` was false forever and no ellipsis ever appeared. Two key types now.

And one measurement worth keeping: aligning the save dot to the header's own `padding(.top, 14)` aligns the top of the *line box*, not the text. Glyphs start below it, so the dot landed 7pt above the text's optical centre. Offsetting by half the leftover line height brings it to within 1.5pt.
