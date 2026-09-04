# Help screen redesign

## Context

`notes/designs/help/` carries a high-fidelity handoff replacing the current prose-heavy help page with a dense two-column keyboard reference: keys right-aligned in a fixed gutter, descriptions beside them, sticky section headers, and pinned header/footer chrome around a scrolling body.

Five instructions came with it, and they override the handoff where they disagree:

1. Body font size for row text.
2. Accent color for section headers.
3. Text must be selectable and findable — today ⌘F and ⌘A reach the scratchpad _underneath_ the help page.
4. A hyperkey glyph anywhere `⌃⌥⇧⌘` appears.
5. "dismiss" replaces "close" app-wide.

Item 3 is the one that decides the architecture. The current page is a SwiftUI `VStack` of `Text` views ([HelpOverlay.swift](Sources/Wisp/HelpOverlay.swift)) — nothing there can be selected, searched, or made first responder, so every editing chord falls through to the notes `NSTextView` behind it.

## Decisions

| Decision | Chosen | Why |
| --- | --- | --- |
| Body rendering | One read-only `NSTextView` | The only thing that gets selection, ⌘A, ⌘C, and a findable string for free — all through the responder chain, with no new key handling |
| Two-column grid | Right tab stop + left tab stop | `NSParagraphStyle` does the design's `172px 1fr` grid natively; `headIndent` makes a wrapped description align under itself |
| Sticky headers | A flipped container holding the scroll view, with the pinned label positioned by hand | An `NSTextView` cannot pin a paragraph. `addFloatingSubview(_:for:)` is the purpose-built API, but it positions in the scroll view's own unflipped space, and the push-up offset is easier to reason about measured downward from the top. Positions come from each title's first line-fragment _used_ rect — the fragment rect carries the paragraph spacing above it, which would read a section gap too high |
| Document build | `HelpDocument` in WispCore | Content and layout are pure functions of a `Keymap` plus a `Palette`, so both are testable without a window |
| Find routing | Source string picked by `showHelp` | No new find state: `EditorModel` already owns the query, matches, and highlight token. Only the _source_ and the _consumer_ of the highlight change |
| Panel geometry | Fill the Wisp panel | The handoff's `760 × 800` card _is_ the Wisp panel ("in the app the panel is user-resizable"), so the page takes the panel's own radius and chrome insets rather than drawing a second card inside it |
| Backdrop gutters | Removed | They existed only to leave somewhere to click for dismissal. A full-bleed page has no inside gutter; esc, the summon chord, the help chord, and the footer button all still dismiss |
| Colors | Palette tokens, not the handoff's hex | The handoff is dark-only; Wisp ships light and dark. Accent for headers is instruction 2, and the rest maps token for token |
| Hyperkey glyph | `❖` (U+2756) | Chosen by the user from four candidates. Collapses all four modifier bits in `HotKey.displayString`, so it reaches the help page, tooltips, and the capture overlay at once |
| `ScrollableContent` | Deleted | `HelpOverlay` was its only caller, and the scroll view now belongs to `HelpBody`. Its key monitor went with it: a read-only `NSTextView` is first responder while the page is up, so scroll keys arrive at `keyDown` and cannot leak into the find field |

### Content: live keymap, verbatim where unbound

The handoff lists its rows as verbatim content, and several of its chords disagree with the app's current defaults (`⌘L` against `opt+l`, `⌘H` against `opt+h`, `⌘+` against `cmd+=`). Rebinding is a separate task the user has already scheduled after this one.

So: rows that map to a `KeymapAction` keep rendering from the live keymap, exactly as the page does today — a help page that lies about the build it ships in is worse than one that disagrees with a mockup, and the rows correct themselves for free once the bindings task lands. Rows with no action behind them take the handoff's text verbatim, including `⌥⌘R`.

Deviations to confirm, all flagged rather than silently taken:

- ~~`⌘U · underline` is dropped — there is no underline feature to bind.~~ **Resolved.** Underline is implemented; see below. Both it and `⌥⌘R` are live keymap actions now, so no row on the page is a literal chord any more.
- The handoff's key order `⌘B · ⌘I · ⌘H · ⌘U` does not match its own description `bold · highlight · italic · underline`. Keys follow the description.
- Four real bindings appear nowhere in the handoff's content list: `help` (F1 / ⌘/), `toggleTheme` (⌘T), ⌘Q, and the menu-bar-only items (Set Shortcut…, Scratchpad Folder…, Launch at Login). The current page documents all of them. Following the handoff drops them.

## Follow-up: the two bindings the page was promising

- [x] `underline` (`cmd+u`), writing `<u>…</u>`. Markdown has no underline; `__` is already bold in this editor, and `<u>` is what Obsidian's own underline command inserts — which matters, because the note is read there. `MarkdownWrap` grew an open/close pair for it, since every other marker is its own closer. It styles through `.underlineStyle` rather than `applyTrait`: underline is an attribute, not a symbolic trait, so it also has to be removed in `resetBaseAttributes` alongside `.kern`, or the rule outlives the tags.
- [x] `revealNote` (`opt+cmd+r`), panel-scoped, so it fires with the menu closed and the panel focused.
- [x] The status-item menu stamps its own chords from the live keymap rather than hardcoding them. `KeyChord.menuEquivalent` already existed for this and had tests but no caller. A key equivalent on a status-item menu only fires while that menu is open, and `KeyBindingMonitor` never sees events during a menu tracking loop, so the two paths can't double-fire.

### Padding: the app's tokens, not the handoff's

The handoff gives the page its own spacing throughout — `11px 16px` chrome, a `34px` content column, `22px` / `7px` around a section label. The page has none of it. Every inset comes from `Metrics.chromeInsetX` / `chromeInsetY` (24 / 12), the same values the heading strip, the footer, and the note's own text column use.

The reason is that the page crossfades onto the editor rather than appearing beside it: a column that lands 10pt off the one it replaced is the first thing you see on the way in. Same for the header — "help" takes the heading strip's font, color, and leading inset, so the bar looks like the bar it covers.

The header's "⌘F to find" hint is gone with it. It labelled a shortcut the page itself already lists, in the one spot on the page reserved for saying where you are.

## Checklist

- [x] `HotKey.displayString` collapses `⌃⌥⇧⌘` to `❖`, with a test
- [x] `HelpDocument` in WispCore: sections, rows, and an `NSAttributedString` renderer returning the plain string and each section title's range
- [x] `HelpBody`: `NSScrollView` + read-only selectable `NSTextView` + pinned sticky header, with `ScrollCommand` moved onto the text view's own `keyDown`
- [x] Find routing in `EditorModel` — source string and highlight consumer both keyed on `showHelp`
- [x] `HelpOverlay` rebuilt as header bar / body / footer bar; focus the help text view on appear, restore notes focus on dismiss
- [x] Delete `ScrollableContent`
- [x] "close" → "dismiss" across user-facing strings, method names, and the README
- [x] Visual verification in both themes, measured against the handoff
  - [x] Dark and light, at rest: gutter, insets, accent labels, and the hyperkey glyph
  - [x] Sticky header pins and hides the rows passing under it
  - [x] ⌘F searches the page and highlights in it; ⌘A selects it, not the note

## Found while verifying

Three bugs the screenshots caught, none of which a test would have:

- [x] The pinned header painted over the whole page. `NSView.clipsToBounds` defaults to **false**, and AppKit hands `draw` a dirty rect larger than the view, so `dirtyRect.fill()` covered every sibling. At the band's 0.98 alpha this read as the page being washed out rather than as a fill in the wrong place, which sent the first diagnosis at vibrancy instead. Fixed by clipping and filling `dirtyRect.intersection(bounds)`.
- [x] The page never took first responder. `makeNSView` runs before the representable is mounted, so a `makeFirstResponder` scheduled there finds `window` nil. Moved to `viewDidMoveToWindow`.
- [x] `requestFocus()` always focused the note. ⌘=, ⌘0 and ⌘T all call it, so any of the three handed first responder back to the note _while the page was still up_ — taking ⌘A, ⌘F and the scroll keys with it. It now follows whatever is in front.

Also: a re-render used to throw the reader back to the top of the page. The only thing that re-renders mid-read is a text-size change, so `setDocument` now carries the scroll offset across.
