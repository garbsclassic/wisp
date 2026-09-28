# Review: footer-and-rules

Reviewer pass over `main..995cd0f` on 2026-09-28, driven through a harness on a copy of the tree.

- [x] Medium — spellcheck rebuilds `MarkdownBlocks` per `setSpellingState` call, once per misspelling: 5.9 s at 125K chars ([NotesTextView.swift:546](../Sources/Wisp/NotesTextView.swift:546)). The whole-note `checkSpelling` on enable is also redundant ([MinimalTextEditor.swift:214](../Sources/Wisp/MinimalTextEditor.swift:214)).
- [x] Low–Medium — the right-click Spelling submenu's Check Spelling While Typing bypasses the model; its grammar and autocorrect items turn on features nothing turns off.
- [x] Low — `emDashEdit`'s returned edit is not the one the app applies, so its tests check a discarded value.
- [x] Low — marks made in source view survive leaving it, since the code filter is skipped there.
- [x] Low — `codeSpans` ignores `\``; `isInsideCodeSpan` honors it. One scanner.
- [x] Low — "which line kinds are code" listed in three places with `default:` arms; want `Kind.isCode`.
- [x] Low — `RelativeTime` comment claims 23:59 → 00:01 reads `yesterday`; it reads `2 min ago`.
- [x] Low — cleanups: `lastModified` mirror, full restyle on a `ruleStyle` change, `HoverTextButton` duplicating `GlyphButton`, `+1`/`+5` tracker arithmetic, `isShifted` read twice.
- [x] Nit — stale `chrome` comment in HelpOverlay; help page lacks the `--` and ↵↵↵ rows; header jump re-reads `barHeadings` at click time.
- [x] Caveat — `spellcheck` and `footerStatus` absent from the chezmoi template, so the first toggle on a synced machine hits the full-rewrite path.

## Outcome

- Spellcheck: code ranges are cached per character edit (invalidated from `didProcessEditing`). The reviewer's claim that enabling checks visible text on its own didn't hold on screen — no marks 6.5 s after F6 — so the whole-note check stays, now cheap.
- Menu: `willOpenMenu` never fired for the text view's context menu and stripping in `menu(for:)` left Substitutions in place, so instead the rewriting properties are overridden to stay off; the items remain but do nothing.
