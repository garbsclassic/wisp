# Review: editing-polish

Findings from the review pass over `main..editing-polish`, and what was done about each.

## Fixed

1. **Auto-surround fired on programmatic edits and undo.** The branch guarded on
   `replacementString` being one of the six characters, which cannot tell a keystroke from a
   hand-rolled `replaceText` — and every hand-rolled edit in the app re-enters the delegate with
   whatever it is putting back. ⌥L unsetting the line `- *` puts back `*` and got `**- ***`;
   ⌘E unwrapping a selected `` `*` `` puts back `*` and wrapped instead of unwrapping; ⌘Z
   restoring any one of the six characters wrapped it and abandoned the undo group. Now gated on
   `NSApp.currentEvent` being a `.keyDown` whose `characters` equal the replacement. This also
   closes the dead-key case the review raised as speculative, since a dead key contributes no
   characters of its own.

2. **↵ over a selection did not delete the selection.** `handleEnter` inserted at
   `NSRange(location: cursor, length: 0)`, so `↵` with `hello` selected on `    hello world` left
   `hello` in place. Pre-existing on the list paths; the indent branch extended it to every
   indented line, which is most of a note. All three paths now replace the selection.
   Separately, `leadingIndent` read the whole line, so splitting inside the leading run handed the
   tail a full copy of the indent on top of its own whitespace — it now reads only up to the
   cursor.

3. **Raw mode kept `==marked==` backgrounds.** `resetBaseAttributes` does not remove
   `.backgroundColor` — deliberately, since the find match rides on that attribute and a restyle
   must not wipe the match — and in normal mode `styleHighlights` repaints it every keystroke.
   Raw mode returns before that pass, so the amber wash survived into a mode whose whole point is
   that nothing is styled. Both raw-mode early returns now clear it, and `applyFindHighlight` no
   longer repaints `==marked==` while raw mode is on; the match itself still paints, since finding
   text in the raw view is the point.

4. **The help row for auto-surround was wrong.** It omitted `'`, and showed `*` singly while
   showing `=` doubled — both double. Now `` ` · _ · ' · " · ** · == ``.

5. **`isLive` was private in an untested target.** Hoisted to `Escapes.Marks.isLive`, so the thing
   the escape feature actually promises — that a delimiter behind a backslash is not markup — is
   testable in `WispCore` rather than only by hand.

## Not a defect

- **Auto-surround stays live in raw mode.** Deliberate; see [intent.md](intent.md).
- **The plan's checklist.** Read mid-flight as unchecked; it was checked in the same commit as the
  work.

## Confirmed clean by the review

`Escapes.scan` bounds (including the two-character skip at the end of the text); the `where
isLive(…)` clauses being exact no-ops on backslash-free text; `outdentAtCursor`'s off-by-ones and
its behaviour on an empty `unit`; both raw-mode early returns skipping nothing but `restyleContent`;
`NotesLayoutManager.isRawMode` and the styling pass being unable to disagree for a frame, since
both are written inside the same synchronous `applyPalette`; and `lastRawMode` being unreachable
in a stale state from any keystroke.

## Known gaps

`MarkdownWrap.surroundMarkers` and the `shouldChangeTextIn` branch that consumes it have no tests —
both live in the `Wisp` target, which has none. `surroundMarkers` is a four-line switch and moving
it to `WispCore` purely to reach it would split one concept across two files; the branch itself
needs a live `NSEvent` and a text view, so it is a manual check either way. What to exercise by
hand after any change there: ⌥L on a line reading `- *`, ⌘E on a selected `` `*` ``, and ⌘Z after
typing over a selected `*` — the three that finding 1 was breaking.
