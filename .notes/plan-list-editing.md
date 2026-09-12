# List editing: the behaviours other note apps have and Wisp didn't

Branch: `list-editing` · Started: 2026-09-12

## Contents

- [Goal](#goal)
- [Decisions](#decisions)
- [Steps](#steps)
- [Verification](#verification)

## Goal

Lists in Wisp continue on ↵ and nest on ⇥, and stop there. Apple Notes, Bear, Notion, and Obsidian
all agree on a further handful of behaviours that fingers expect: ⌫ at the start of an item's text
takes the marker off rather than the space after it; ↵ on an empty nested item steps out a level
before it leaves the list; ⇧↵ starts a continuation line under the item; and `- [ ]` is a thing.
Plus the bug that started it — ↵ at column 0 doubled the marker — and ⌘L for the list toggle.

## Decisions

| Decision | Chosen | Rejected | Why |
| --- | --- | --- | --- |
| ↵ before the item's text | Item moves down intact, caret rides with it | New empty item above (Apple Notes) | The caret is before the marker only after Home×2 or a click into the gutter; "push this line down" is what that position means in every text editor |
| ⌫ at content start | Strip the marker, keep the indent | Outdent first (Notion, Docs) | Apple Notes, Bear, and Obsidian all strip; ⇧⇥ already exists for outdenting, and ⌫ meaning two different things depending on depth is the kind of rule nobody remembers |
| ↵ on an empty nested item | Outdent one level per press | Straight to a flush-left blank line (previous) | Universal across the four apps; also the only way ↵ alone can get a caret from a sub-item back to its parent's level |
| ⇧↵ | Continuation line: newline plus whitespace to the item's content column | Bare newline; ⌥↵ | ⇧↵ reaches AppKit as plain `insertNewline:`, so it is free to claim by modifier; the whitespace is CommonMark's own spelling of "still this item" and reads correctly in Obsidian |
| Continuation rendering | Paragraph indents pull the text to the item's content column | Leave the spaces to render themselves | Inter is proportional: `- ` and two spaces are not the same width, so unstyled the line sits a hair off. Hidden-nothing: the spaces remain in the file and in raw mode |
| Task marker | `- [ ]` / `- [x]` parsed as one marker, drawn as one glyph (☐ · ☑) | Bullet glyph followed by a visible `[ ]` | A checkbox that reads as `• [ ]` is not a checkbox; the marker is chrome exactly as a bullet is, and ⌘←, ⌫, and ↵ already treat `markerRange` as chrome |
| Checked items | Content painted `muted` | Strikethrough | Apple Notes and Bear dim; strikethrough on a whole line of prose is noise, and `~~` would be the markdown for that anyway |
| Task toggle | ⌘⇧L: make every line in the block a task; if they all already are, check or uncheck them together | Obsidian's four-state cycle | Two intents, two actions: ⌘L is "is this a list", ⌘⇧L is "is this done". A cycle makes "check this" a different number of presses depending on where it starts |
| Clicking the box | Toggles it | — | Every app; a checkbox you cannot click is a bullet with a border |
| ⌥L → ⌘L | `cmd+l` | — | Asked for. ⌘L is unclaimed in Wisp; ⌥-letters are for the rarer commands |

## Steps

- [x] ↵ before the item's text moves it down — `SmartEditing.newlineBeforeItem`
- [ ] ⌘L replaces ⌥L as the list toggle default — `Keymap`, README, help
- [ ] ⌫ at content start strips the marker — `SmartEditing.backspaceAtItemStart`, `NotesTextView.deleteBackward`
- [ ] ↵ on an empty nested item outdents — `SmartEditing.outdentedEmptyItem`, `handleEnter`
- [ ] ⇧↵ continuation line and its rendering — `SmartEditing.continuationLine`, `handleEnter`, `styleLists`
- [ ] Task items: parse, continue, draw, ⌘⇧L, click — `ListItem.Marker.task`, `nextListMarker`, `styleLists`, `NotesLayoutManager`, `LineEdits.toggleTaskItems`, `KeymapAction.toggleTaskItem`

## Verification

Unit: `scripts/test.sh`. On screen, both themes: a task list with a checked item; a continuation
line under a bullet at two depths; ⌫ and ↵ at the content start of nested items.
