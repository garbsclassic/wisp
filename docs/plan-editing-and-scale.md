# One text scale, and real editing keys

## Contents

- [Context](#context)
- [Decisions](#decisions)
- [Work](#work)
- [Config surface after this](#config-surface-after-this)
- [Verification](#verification)

## Context

Two size controls fight each other today. `fontSize` (`small`/`medium`/`large` → 17/20/24pt) is cycled by ⌘1/⌘2/⌘3 and the footer's "Aa" button, and it moves the notes body only. `fontScale` is a continuous multiplier applied inside `Typography.scaled` that moves _everything_, body and chrome alike, and is reachable only by hand-editing `wisp.jsonc`. Two knobs, overlapping ranges, one of them invisible.

`fontScale` also has a bug: changing it in the config updates the chrome immediately but leaves the notes body at its old size until the next keystroke. `MinimalTextEditor.updateNSView` re-applies the body font only when `fontSize` changed ([MinimalTextEditor.swift:88](Sources/Wisp/MinimalTextEditor.swift:88)), and a scale change doesn't touch `fontSize`. SwiftUI re-evaluates chrome bodies on `objectWillChange`, so `Typography.ui` re-resolves for free; the `NSTextStorage` holds resolved `NSFont` attributes and nothing invalidates them. It self-heals on typing because `textDidChange` restyles the whole storage. Merging the two features fixes the bug by construction — the value the editor compares becomes the value that actually changed.

The editing asks are separate but land in the same two files. ⌘C/⌘X on an empty selection has to intercept `copy:`/`cut:`, which means the notes view has to be an `NSTextView` subclass rather than whatever `NSTextView.scrollableTextView()` hands back — which also lets the `replaceLayoutManager` hack go away, since the layout manager can be built into the stack directly.

## Decisions

| Decision                | Chosen                                                          | Why                                                                                              |
| ----------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Merge shape             | Delete `FontSize`; `fontScale` is the only size control          | A three-step enum inside a continuous multiplier is two spellings of one setting                  |
| Body base size          | `Metrics.bodySize = 20`, the old `.medium`                      | Scale 1.0 keeps today's default rendering byte-identical                                          |
| Reset target            | New `defaultFontScale` key, default `1.0`                       | ⌘0 needs somewhere to reset _to_; hardcoding 1.0 would make the new setting decorative            |
| Live value              | `fontScale` stays persisted, as `fontSize` was                   | A size you set should survive a relaunch                                                          |
| Step                    | ±0.1, clamped to the existing 0.6–2.5                            | Asked for; the clamp already exists and is the readability floor/ceiling                          |
| Footer control          | Two glyph buttons replacing "Aa"                                 | Asked for. A cycle button can't express a continuous range                                        |
| Panel on launch         | Never auto-open; delete `LaunchSource`                           | `NSApplicationLaunchIsDefaultLaunchKey` is not reliably false for an `SMAppService` login item     |
| Metrics home            | `Theme.swift`, beside `Palette` and `Chrome`                     | Follows Clef; type sizes are theme tokens, not view-local numbers                                 |
| Metrics token names     | By role (`chromeSize`, `titleSize`), not by value                | `size11` renames itself the first time 11 becomes 12                                              |
| ⌘D, empty selection     | The whole line, cursor riding onto the copy                      | Xcode and VS Code both do this                                                                    |
| ⌘D, with a selection    | The selection verbatim, inserted after it, copy selected         | "duplicates line (or selection)" reads as the selection when there is one                         |
| ⌘C/⌘X, empty selection  | The whole line _including_ its newline                           | Without the newline, paste lands mid-line and the round trip isn't idempotent                     |
| Bullet rendering        | `.clear` foreground on the marker, glyph drawn by layout manager | Exactly the trick `---` already uses; the file on disk stays plain markdown                       |
| Bullet glyph per depth  | `•` / `◦` / `▪`, capped at depth 3                               | Matches Claude's chat input and every word processor; deeper nesting reuses the last glyph        |
| Ordered lists           | Hanging indent, no glyph substitution                            | `1.` already _is_ its own marker — replacing it would lose the number                             |
| Indent unit             | `indent.style` + `indent.size`, spaces/2 default                 | Asked for                                                                                         |
| Tab on a list line      | Indents/outdents the item, cursor keeps its column               | Asked for; this is the whole point of the smarter handling                                        |
| Tab elsewhere           | Inserts one indent unit; ⇧Tab outdents the line                  | The obvious fallback, and ⇧Tab has nothing else to mean                                            |
| Range math home         | Pure `LineEdits` in `WispCore`                                   | Duplicate/cut/indent are all "given text and a selection, produce an edit" — testable without AppKit |
| Help chord              | ⌘/ toggling the overlay                                          | Asked for. `⌘?` is reserved by macOS for Help menu search; `⌘/` is free                            |
| Scoping the new chords  | `validateMenuItem`, gated on the panel being visible _and_ key   | A main-menu equivalent otherwise fires whenever Wisp is merely active — including with no panel up  |

Assumption worth naming: ⌘D on a selection that spans lines duplicates the selected characters exactly, not the lines they sit in. A partial first or last line therefore duplicates partially. That is the literal reading of the ask and what VS Code does; say the word and it becomes whole-lines-always, like Xcode.

## Work

### 1. Don't open the panel at launch

- [x] Drop the `LaunchSource.isUserInitiated` block from `applicationDidFinishLaunching`
- [x] Delete `Sources/WispCore/LaunchSource.swift` and `Tests/WispCoreTests/LaunchTests.swift`
- [x] Leave `applicationShouldHandleReopen` alone — re-launching a running app is an explicit request, not start-up

### 2. `Metrics` in Theme.swift

- [x] Add `public enum Metrics` to `Theme.swift` holding every literal type size, the heading ratios, the body line-height multiple, and the font-scale step and range
- [x] Point all 17 `Typography.ui(...)` / `Typography.notes(...)` call sites at it
- [x] `ThemeTests` covers the range/step invariants (step divides evenly into the range, default sits inside it)

### 3. One scale, replacing `fontSize`

- [x] Delete `Sources/WispCore/FontSize.swift`, `config.fontSize`, and the `"FontSize"` branch of `migrateLegacyDefaults`
- [x] Add `defaultFontScale` to `WispConfig` (lenient decode, like every other key)
- [x] `Settings.setFontScale(_:)`, which re-runs `Typography.configure` so chrome and body agree on the new scale in the same pass
- [x] `EditorModel.fontScale` as a `@Published` mirroring the old `fontSize` property, plus `increaseFontScale` / `decreaseFontScale` / `resetFontScale`
- [x] `MinimalTextEditor` takes `fontScale` where it took `fontSize`, and compares it in `updateNSView` — this is the bug fix
- [x] Footer: two glyph buttons (`textformat.size.smaller` / `.larger`) replacing the "Aa" cycle
- [x] View menu: Increase ⌘=, Decrease ⌘-, Actual Size ⌘0, replacing the three fixed sizes
- [x] `HelpOverlay` and the README config table follow

### 4. Indent config

- [x] `IndentStyle` (`spaces` / `tabs`) and `Indent { style, size }` in `Config.swift`, beside `FontSet` and `Keymap`
- [x] `Indent.unit` resolves to a tab or _n_ spaces, with `size` clamped so a typo can't produce a 400-space indent

### 5. `LineEdits` in WispCore

- [x] `Edit { range, replacement, selection }` as the shared return shape
- [x] `duplicate(in:selection:)` — whole line when empty, verbatim copy when not; handles the last line having no trailing newline
- [x] `lineForClipboard(in:selection:)` — the range ⌘C/⌘X act on when there's no selection
- [x] `indent(in:selection:unit:)` / `outdent(in:selection:unit:)` — every touched line, cursor and selection tracked across the width change
- [x] `SmartEditing.listItem(...)` — parses a line into leading indent, marker range, marker kind, and depth; feeds both the tab handling and the bullet drawing
- [x] Tests for each, including the edges: last line without a newline, outdent of an already-flush line, a selection ending exactly on a line boundary

### 6. `NotesTextView` and the layout manager

- [x] Build the scroll view / storage / layout manager / container stack by hand in `makeNSView` so the text view can be a subclass; drops `replaceLayoutManager`
- [x] `NotesTextView` overrides `copy(_:)` and `cut(_:)` to fall back to the current line
- [x] Rename `HorizontalRuleLayoutManager` → `NotesLayoutManager`; it now draws bullets as well as rules, and carries `bulletColor` / `bulletFont` updated alongside `ruleColor` in `applyPalette`
- [x] Styling pass hides unordered markers with a `.clear` foreground and applies a hanging-indent paragraph style to every list line

### 7. Key bindings

- [x] Edit menu: Duplicate ⌘D, routed through a token like ⌘B/⌘I already are
- [x] Help menu: Keyboard Shortcuts ⌘/, toggling the overlay
- [x] `doCommandBy` handles `insertTab:` and `insertBacktab:`
- [x] `AppDelegate.validateMenuItem` gates every panel-scoped chord — ⌘D, ⌘=, ⌘-, ⌘0, ⌘/, and the existing ⌘B/⌘I — on `panel.isVisible && panel.isKeyWindow`. ⌘F, ⌘R, and ⌘, stay ungated: each deliberately opens the panel when it is closed
- [x] `HelpOverlay` gains the new chords

## Config surface after this

```jsonc
{
  "fontScale": 1.0,        // live, moved by the footer buttons and ⌘= / ⌘-
  "defaultFontScale": 1.0, // what ⌘0 returns to
  "indent": { "style": "spaces", "size": 2 }
}
```

`fontSize` is gone. Nothing is distributed, so there is no migration — an old file's `fontSize` key is simply an unknown key, which the lenient decoder already ignores without complaint.

## Verification

Driven against a second instance pointed at a scratch `XDG_CONFIG_HOME`, so nothing touched the live config or note.

- [x] Launch: `CGWindowListCopyWindowInfo` reports no on-screen window for the fresh process; `open -a` on the same bundle then puts one up at 455,137 800×640
- [x] The scale bug: with the panel open, `fontScale` edited from `1.0` to `1.4` on disk resized the body with no keystroke. Measured, not eyeballed — the header band went 8pt → 11pt, the footer 11pt → 15pt, and the body reflowed from one 372pt block to separate 22pt and 27pt lines
- [x] Bullets in both themes: glyphs step `•` → `◦` → `▪` by depth, ordered markers stay visible, and a wrapped item hangs to its content
- [x] Marker alignment: the bullet's ink run measures 30–37px on the `-`, `*`, and `+` lines alike, with text starting at 45–46px — the 1px spread is antialiasing on the first letter, not misalignment

Two defects the screenshots caught, both fixed above:

- [x] A note arriving from disk was assigned straight to `textView.string`, which drops every attribute, so the `-` stayed visible under its own drawn bullet (and `---` under its own rule). `updateNSView` now restyles after that assignment. Pre-existing for rules; the bullets made it obvious
- [x] `.kern` was set on list markers and never cleared, so an edit that shifted a line left the kern on whatever character moved into that offset. The base-attribute reset now removes it

**Not verified:** every new key chord — ⌘D, ⌘=, ⌘-, ⌘0, ⌘/, ⇥, ⇧⇥, and ⌘C/⌘X on an empty selection. Posting synthetic key events needs an Accessibility grant this session doesn't have (`AXIsProcessTrusted()` is false), and the panel can only be opened here through `open -a`. The range arithmetic behind all of them is covered by 34 unit tests in `LineEditsTests` and `SmartEditingTests`; what is untested is the AppKit wiring — the menu items' selectors, the `doCommandBy` interception, and the `validateMenuItem` gate. Worth a manual pass after install.
