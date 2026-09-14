# Smooth caret: animated movement and a fading blink

Branch: `smooth-caret` · Started: 2026-09-14

## Contents

- [Goal](#goal)
- [Decisions](#decisions)
- [Steps](#steps)
- [Verification](#verification)

## Goal

The caret JetBrains shipped in 2026.1: it slides to where it is going instead of teleporting, and
fades in and out instead of switching. Two motion styles — *snappy* lands almost at once and
settles; *gliding* is the slower, easier-to-follow slide — plus off. Typing must stay instantaneous:
a caret that animates on every keystroke reads as input lag.

## Decisions

| Decision | Chosen | Why |
| --- | --- | --- |
| Where it draws | A `CALayer` sublayer of the text view; AppKit's caret suppressed | Core Animation runs the move and the blink on the render server: no timer, no main-thread wakeups, no dirty rect per tick. Cheaper than the stock caret |
| Suppressing the stock caret | `shouldDrawInsertionPoint` → `false`, `drawInsertionPoint` a no-op | The first stops the blink timer; the second is belt and braces for the TextKit 1 draw path |
| When to reposition | `updateInsertionPointStateAndRestartTimer(_:)` | AppKit calls it on every selection, focus, key-window, and text change — the exact set of moments the stock caret repaints |
| Whether to show | Own bookkeeping: first-responder flag, `isKeyWindow`, empty selection | `super.shouldDrawInsertionPoint` answered true through a focus loss (review probe, and two carets on screen with the find bar open), so it isn't the verdict it looks like |
| Where the caret is | `firstRect(forCharacterRange:)` | The `NSTextInputClient` contract: a zero-length range yields the insertion point. Same rect the IME candidate window keys off, so it agrees with where AppKit would have drawn |
| Typing vs navigation | A move that coincides with a change in text length is instant | Catches typing, delete, paste, undo, and every hand-rolled edit without threading a flag through them. A same-length replacement animating is the accepted miss |
| Snappy curve | 90 ms, control points (0.05, 0.7, 0.1, 1) | Nearly all of the distance in the first third, then a soft stop |
| Gliding curve | 160 ms, control points (0.4, 0, 0.2, 1) | Material's standard ease: visible travel, no bounce |
| Blink | One looping `CAKeyframeAnimation` on `opacity`, restarted on every move | Solid 450 ms after a move, 100 ms fade out, 350 ms off, 100 ms fade in. The restart is what keeps the caret solid while typing |
| Config | `caret.motion: snappy \| gliding \| off`, `caret.blink: true` | Mirrors `indent.*`. Reduce Motion in System Settings forces `off` without touching the file |
| Width | 2 pt, 1 pt radius | Matches the modern AppKit indicator measured on this machine before the change |

## Steps

- [x] `Caret` config struct: `motion`, `blink`; lenient decode; README row
- [x] `NotesTextView`: suppress the stock caret, `CaretLayer` overlay, hook the update method
- [x] Plumb `caret` through `MinimalTextEditor` like `indent`
- [x] Tests via `tester`: config decode, defaults, malformed key naming
- [x] Visual verification: width and position against the stock caret, both themes, typing stays instant
- [x] Progress line

## Verification

Screenshot the stock caret first and measure its pixel width and x/y with `caret.swift`; the overlay
must land on the same pixels. Then: arrow through a heading (height change), ⌘↓ to the end of the
document (extra line fragment), click into a nested list item, type a word and confirm the caret
never lags the glyph, drag the panel wider so lines reflow. Both themes.
