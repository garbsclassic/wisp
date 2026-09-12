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
| Task marker | `- [ ]` / `- [x]` parsed as one marker, drawn as one box | Bullet glyph followed by a visible `[ ]` | A checkbox that reads as `• [ ]` is not a checkbox; the marker is chrome exactly as a bullet is, and ⌘←, ⌫, and ↵ already treat `markerRange` as chrome |
| Ordered item under ⌘⇧L | Trades its number for `- [ ] ` | `1. [ ] foo` (GFM allows it) | A glyph drawn over `1. [ ]` hides the number, which is the one thing an ordered marker is for; Apple Notes converts the same way |
| Checked items | Content painted `muted` | Strikethrough | Apple Notes and Bear dim; strikethrough on a whole line of prose is noise, and `~~` would be the markdown for that anyway |
| Task toggle | ⌘⇧L: make every line in the block a task; if they all already are, check or uncheck them together | Obsidian's four-state cycle | Two intents, two actions: ⌘L is "is this a list", ⌘⇧L is "is this done". A cycle makes "check this" a different number of presses depending on where it starts |
| Clicking the box | Toggles it | — | Every app; a checkbox you cannot click is a bullet with a border |
| ⌥L → ⌘L | `cmd+l` | — | Asked for. ⌘L is unclaimed in Wisp; ⌥-letters are for the rarer commands |

## Steps

- [x] ↵ before the item's text moves it down — `SmartEditing.newlineBeforeItem`
- [x] ⌘L replaces ⌥L as the list toggle default — `Keymap`, README, help
- [x] ⌫ at content start strips the marker — `SmartEditing.backspaceAtItemStart`, `NotesTextView.deleteBackward`
- [x] ↵ on an empty nested item outdents — `SmartEditing.outdentedEmptyItem`, `handleEnter`
- [x] ⇧↵ continuation line and its rendering — `SmartEditing.continuationLine`, `handleEnter`, `styleLists`
- [x] Task items: parse, continue, draw, ⌘⇧L, click — `ListItem.Marker.task`, `nextListMarker`, `styleLists`, `NotesLayoutManager`, `LineEdits.toggleTaskItems`, `KeymapAction.toggleTaskItem`

## Follow-up, same branch

Asked for after the first pass landed.

| Decision | Chosen | Rejected | Why |
| --- | --- | --- | --- |
| When to renumber | After every edit, first item's value kept | Only on ↵/⇥/⌥↑↓ (Obsidian's smart lists) | Notes and Bear never show a wrong number; keeping the first value still lets a list start at 3 |
| Where the renumber runs | Hand-rolled edits renumber after setting their selection (`performEdit`); AppKit's own edits from `textDidChange` | Everything from `textDidChange` | Mid-edit the delegate sees the pre-edit selection; shifting that and then having the caller overwrite it leaves the caret off by a digit at the `9.`→`10.` boundary |
| Renumber during undo | Skipped | — | Undo restores the old marker through `didChangeText`; renumbering there registers onto the redo stack and makes the step a visible no-op |
| Long markers | Nine digits or fewer count; longer ends the run untouched | Parse whatever `Int` accepts | `Int.max` parses and `+ 1` traps on the first keystroke, every launch, once it is in the file |

- [x] Ordered runs renumber after every edit — `SmartEditing.renumber`, `NotesTextView.renumberLists`
- [x] ↵ on a continuation line starts the next item — `SmartEditing.continuedItem`, `handleEnter`

### Second follow-up

| Decision | Chosen | Rejected | Why |
| --- | --- | --- | --- |
| ↵ on an empty flush-left item | Strip the marker in place, caret stays on the now-blank line | Strip and add a newline (the first pass) | The blank line is what the user wanted; every other note app leaves the caret there |
| Task box | Drawn: a rounded square one ascender tall, stroked, tick inside | Typeset `☐` / `☑` | The two fall back to different fonts (Apple Symbols, system) at different sizes, the empty one barely x-height tall; drawn, both are the same size and as large as the line allows |
| Cursor over a box | The arrow, over the same rectangle the click tests | Pointing hand; I-beam everywhere | A box is a control, and macOS controls get the arrow; the hand is for links. An I-beam says "place a caret here" |
| Indent guides | One-point line per ancestor level, centred on the actual ancestor's marker, in `faint`, spanning wraps, continuation lines, and blank lines inside the list | Computed column per level; break at a blank line | Obsidian's guides are what makes a deep list readable; a guide off a box's centre or broken by a loose list's gap looks like a glitch. `faint` is the tier for structure that is not content |
| Guide start | One cap height below the parent's marker centre | The child's fragment top | The fragment top butts against the parent's descenders and reads as hanging off its marker; one cap down matches Obsidian's start (measured 37% vs 38% of the row pitch) |

- [x] ↵ on an empty flush-left item exits in place — `handleEnter`
- [x] Task box drawn at the text's ascender — `NotesLayoutManager.taskBoxSide`, `drawTaskBox`, `styleLists`
- [x] Arrow cursor over a box — `NotesTextView.mouseMoved`, `cursorUpdate`, `taskBoxIndex`
- [x] Indent guides — `SmartEditing.guideDepth`, `ancestors`, `NotesLayoutManager.drawGuides`

## Verification

Unit: `scripts/test.sh`. On screen, both themes: a task list with a checked item; a continuation
line under a bullet at two depths; ⌫ and ↵ at the content start of nested items.
