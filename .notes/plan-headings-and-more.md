# Heading ramp, heading jumps, strikethrough, caret footer, ⌫ outdent, `hyper`

Seven refinements batched on 2026-09-14. Full design in the session plan; this is the checklist.

## Decisions

| Decision | Chosen | Why |
| --- | --- | --- |
| Heading colours | Flexoki 400s dark, 600s light | Modernist has only green/blue; light `danger` already borrows red-600 |
| Heading sizes | 1.06 → 1.01, one point per level | Felt, not seen — colour carries the tier |
| Strikethrough syntax | render `~~x~~` and `~x~`, write `~~` | Obsidian writes `~~`; Notion accepts `~` when typing |
| Strikethrough chord | `cmd+shift+s` | Notion's, and the user's Obsidian keymap |
| Heading jumps | `ctrl+shift+up/down`, every level | The strip is an index; the walk sees `###`+ too |
| Header strip | `#` and `##` only | Six levels in one line is a run of ellipses |
| Footer | `12:34 · 120 words` | 1-based, column in characters |
| ⌫ in indent | one level off | Obsidian; makes ⇥ ⌫ a round trip |
| `hyper` | Clef's `parse` branch; `string()` emits `hyper+` | Config spelling for a remapped Caps Lock |

## Checklist

- [x] Theme: `Metrics.headingRatios`, `Palette.headings`, coloured `styleHeadings`
- [x] KeyChord: `hyper` / `❖` parse, `string()` round-trip
- [x] Strikethrough: render, `KeymapAction.strikethrough`, `~` auto-surround, help, README
- [x] `CaretPosition`, `caretOffset` binding, footer label
- [x] `previousHeading` / `nextHeading` actions, `[Heading].heading(before:/after:)`
- [x] Header strip filtered to level ≤ 2
- [x] `LineEdits.backspaceInIndent`, `deleteBackward` order
- [ ] Tests via `tester`: CaretPosition, backspaceInIndent, heading(before/after), keymap defaults
- [ ] Visual verification both themes; install
- [ ] chezmoi: `summon` → `hyper+.`, new keymap keys
