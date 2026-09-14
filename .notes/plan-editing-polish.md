# Editing polish: accent header, indent fixes, escapes, auto-surround, raw mode

## Contents

- [Context](#context)
- [Decisions](#decisions)
- [Work](#work)
- [Verification](#verification)

## Context

Six unrelated papercuts and additions, batched because they land in the same three files
(`MinimalTextEditor`, `NotesTextView`, `SmartEditing`).

- Header headings render in `palette.muted`, the same tone as the `·` between them, so nothing in
  the strip reads as clickable.
- `⇥` with a bare cursor in prose inserts an indent unit *at the cursor*, but `⇧⇥` only ever strips
  *leading* whitespace. The round trip is broken anywhere but column 0.
- `nextListMarker` anchors at `^([-*+])\s` with no allowance for leading whitespace, so `↵` on a
  nested item drops both the indent and the marker. A plain indented line loses its indent too,
  since `handleEnter` returns false and AppKit inserts a bare newline.
- No way to write a literal `` ` `` or `*` — every inline pass matches unconditionally.
- Wrapping a selection needs a chord; typing the delimiter replaces the selection instead.
- No way to see the file as it actually is on disk.

## Decisions

| Decision | Chosen | Why |
| --- | --- | --- |
| `⇧⇥` mid-line | Delete whitespace before the caret first, fall back to line outdent | Makes `⇥`/`⇧⇥` a true inverse pair anywhere on the line; the fallback keeps the block behaviour intact |
| Escape backslash | Stays visible, painted in a new faint token | The app's stated bargain is that markers stay visible; a fourth hidden-character case would put the caret through an invisible cell |
| Escapable set | Obsidian's list, extended with what Wisp renders | These notes are read in Obsidian too, so `\|` should read as an escape even though Wisp has no tables |
| `faint` on light | Modernist `ui-2` `#6A685E`, not `tx-3` | Modernist's `tx-3` is already Wisp's `light.muted`; reusing it would collapse two tiers |
| Auto-surround | Wrap-only, never unwrap | ⌘B is a command and may toggle; typing a character is an insertion, and `"` swallowing the quotes off `"foo"` is not what the keypress meant |
| Raw mode state | Session-only, not in `wisp.jsonc` | It is a way to glance at the file, not a preference; the panel only orders out, so it survives a dismiss and resets on quit |
| Raw mode + smart editing | List continuation stays, the rest goes | Continuation is typing assistance, not rendering; `---`→rule and `:rocket:`→🚀 both *rewrite the file*, which is the one thing raw mode is for looking at |

## Work

- [x] 1. Accent for header text, not separators — `HeaderBar.swift`
- [x] 2. `⇧⇥` mirrors `⇥` at the cursor — `LineEdits.outdentAtCursor`, `NotesTextView.handleBacktab`
- [x] 3. `↵` preserves indentation and continues nested lists — `SmartEditing`, `handleEnter`
- [x] 4. Backslash escapes — new `Escapes.swift`, `Palette.faint`, the styling and layout passes
- [x] 5. Auto-surround a selection by typing a delimiter — `MarkdownWrap`, `shouldChangeTextIn`
- [x] 6. Raw text mode on ⌘↩ — `KeymapAction.sourceView`, `MinimalTextEditor`, `FooterBar`, help page

## Verification

Unit: `scripts/test.sh`. Manual, in both themes: header colors; `⇥`/`⇧⇥` round trip; `↵` on nested
lists and indented prose; `\`x\``, `\#`, `\-`, `\\`; the six auto-surround characters plus a paste
over a selection; raw mode's font, glyph, list continuation, and suppressed emoji.
