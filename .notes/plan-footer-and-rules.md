# Footer, rules, dashes, and help-header polish

Six refinements batched on 2026-09-28. Full design in the session plan; this is the checklist.

## Decisions

| Decision | Chosen | Why |
| --- | --- | --- |
| Rule from ↵ | third consecutive ↵ on prose; a fourth reverts | Two ↵ is an ordinary paragraph break and must stay one |
| Rule from ↵, shape | `text / blank / --- / blank / caret` | The blank above keeps `---` from being a setext underline |
| Em dash | `--` → `—` unless the dashes start the line; a third `-` gives `---` | Line-start `---` keeps reaching the rule trigger directly |
| Seam rule | `*  *  *`, config `rule: "seam"` | Manuscript section break; config only, the footer stays at six items |
| Space around rules | adjacent blank lines are exactly 1em (body point size) | Asked for; a blank line is ~1.7em otherwise |
| Spellcheck | `NSTextView` continuous checking, code ranges filtered, `f6` / `cmd+;` | No macOS default chord for the toggle; F6 is Sublime's, ⌘; is the system spelling chord |
| Zoom label | resets to `defaultFontScale`, the same as ⌘0 | One reset, not two meanings of "100%" |
| Status label | `L:C · N words` ⇄ `modified <relative>`, persisted | Hiding the counts also skips their whole-note scans |
| Relative time | just now · N min ago · N hr ago · yesterday · N days ago · date | Coarse, GitHub/Slack-style |

## Checklist

- [x] Help header: section links, click scrolls to the section
- [ ] Em dash on `--`, third `-` reverts to `---`
- [ ] Third ↵ inserts a rule, fourth reverts
- [ ] `rule: "line" | "seam"`, 1em blank lines around rules
- [ ] Spellcheck: config, toggle chord, menu, help row, footer button, code filtered
- [ ] Footer: `− 100% +`, status/modified toggle, new order
- [ ] Tests via `tester`
- [ ] Visual verification both themes; install; chezmoi template
- [ ] Reviewer pass over the branch
