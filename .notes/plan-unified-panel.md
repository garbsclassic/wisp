# Unified panel behaviour with Clef

Branch: `unified-panel` · Started: 2026-09-26 · Twin: `~/Source/clef/.notes/plan-unified-panel.md`

## Contents

- [Goal](#goal)
- [Decisions](#decisions)
- [Steps](#steps)

## Goal

Wisp and Clef summon, place, remember, and reset their panels the same way, from the same config keys. Tap the summon chord to pin, hold it to peek. Drag the panel anywhere and it opens there next time. Reset Position (⌃⌥0, or the menu) puts it back. Both default to the system fonts, and both status menus follow the menu-bar-extra order.

## Decisions

| Decision | Chosen | Rejected | Why |
| --- | --- | --- | --- |
| Sharing code | Identical `PanelPlacement.swift` (Core) and `PanelPositioner.swift` (app) copied into both repos | A shared local Swift package | Both repos build standalone; a path dependency breaks a fresh clone |
| Saved anchor | Top-left corner, AppKit global points, top-level `position` | Wisp's bottom-left origin inside `panel` | Clef's height changes per tab and hangs from its top; `panel` means screen shares in Clef and points in Wisp |
| Default spot | Centred, top edge 5% down, in both | Clef's `offsetY`, Wisp's `position: auto` | One mechanism; dragging plus the saved position replaces the knob. The user's Clef config already resolved to 5% |
| Where it's saved | The jsonc config, via `JSONTextEdit` | UserDefaults | Wisp's established store; chezmoi ignores the per-machine key |
| Reset writes | `null` | Deleting the key | `JSONTextEdit` replaces values in place; it can't delete one without reflowing commas |
| When it's saved | On hide, if moved more than 1pt | On every move | One write per showing, and a drag can't rewrite the file mid-edit |
| Reset chord | `ctrl+opt+0` | `hyper+0`, `cmd+opt+0` | ⌃⌥ is the window family, 0 means "back to default" like ⌘0; ⌥⌘0 is Fold Selected Ranges |
| Peek focus | A summon or a peek never takes key; only a pin does | Always `makeKeyAndOrderFront` | A glance shouldn't take the keyboard from the app underneath |
| Frame constraint | Both panels override `constrainFrameRect` | Removing Clef's override | A saved position is already vetted as reachable, and AppKit's nudge would move a panel from where it was left |
| Fonts | `nil` = system (SF Pro, SF Mono for code) | A `"system"` sentinel | Absent reads as default everywhere else in the config |

## Steps

- [x] `PanelPlacement` + `PanelPositioner`; `position` replaces `position: auto|manual`; `panel` is size only
- [x] Peek: Carbon key release, `SummonState`, `peekHold` (250)
- [x] `resetPosition` action, status menu and Window menu items
- [x] `fonts.*` optional, system by default
- [x] Status menu and hidden main menu reordered
- [x] Tests for the new Core code
- [x] Review: four findings fixed — edge-flush carry, per-screen sizing, `null` seed, Clef save on quit
- [x] Verify chords and visuals on an unlocked screen (drag needs a hand: synthetic drags never move a window)
