# Handoff: Wisp help screen redesign

## Overview
Wisp is a macOS menu-bar scratchpad. The help screen is the panel a user summons to look up a
keyboard shortcut and then dismisses. This redesign replaces a loose, prose-heavy scrolling list
with a dense two-column keyboard reference: shortcut keys right-aligned in a fixed gutter,
descriptions left-aligned beside them, and sticky section headers so the current section stays
visible while scrolling.

Audience is a returning user hunting one shortcut. It is pure reference — no onboarding copy,
no intro.

## About the design files
`Wisp Help.dc.html` in this bundle is a **design reference created in HTML** — a prototype showing
intended look and layout, not production code to copy. Recreate it in Wisp's existing environment
(AppKit/SwiftUI, or whatever the app uses) with that codebase's established patterns. `support.js`
is only the runtime that lets the HTML file open in a browser; it has nothing to port.

## Fidelity
**High fidelity.** Colors, type sizes, and spacing below are final. Match them.

## Screen: Help panel

### Layout
- Panel: fixed `760 × 800`, corner radius `12`, clipped contents.
  Background `rgba(20,25,26,.94)`; 1px hairline border `rgba(255,255,255,.07)`;
  drop shadow `0 30px 90px rgba(0,0,0,.6)`.
  In the app the panel is user-resizable — the body scrolls, header and footer stay pinned.
- Vertical stack of three regions: header (fixed), scroll body (flexible), footer (fixed).

### Header
- Padding `11px 16px`. Background `rgba(255,255,255,.03)`, 1px bottom border `rgba(255,255,255,.06)`.
- Left: "help" — 13px, `#cfd8d8`, letter-spacing `.01em`.
- Right (pushed with auto margin): "⌘F to find" — 12px, `#69797b`.

### Scroll body
- `overflow-y: auto`, top padding `4px`. Custom scrollbar: width `9px`,
  thumb `rgba(255,255,255,.10)` fully rounded, transparent track.
- **Section header**: sticky to top of the scroll container, `z-index 2`.
  Padding `16px 34px 7px` for the first, `22px 34px 7px` for later ones.
  Background `rgba(20,25,26,.97)` (opaque enough to hide rows sliding under it).
  10.5px, uppercase, letter-spacing `.16em`, color `#4fb3a4`.
- **Row**: CSS grid, `172px 1fr`, column gap `22px`, padding `5px 0`, horizontal padding `34px`
  on the wrapping group.
  - Key cell: right-aligned, 14.5px, `#e2eaea`, `white-space: nowrap`.
    Menu-item names rather than key glyphs use `#aeb9ba`.
  - Description cell: 14.5px, `#93a2a3`.
  - Multiple alternative keys in one row are joined by a middot: `⌘+ · ⌘− · ⌘0`, with the
    separators in the key color.

### Footer
- Same padding and background treatment as the header (`11px 16px`, `rgba(255,255,255,.03)`),
  1px top border `rgba(255,255,255,.06)`, 12px `#69797b`.
- Left: "scroll with ↑ · ↓ · mouse wheel". Right: "esc to dismiss".

### Backdrop (prototype only)
The HTML shows the panel over a radial gradient
(`radial-gradient(120% 90% at 50% 0%, #1b3238, #0d1719 55%, #080d0e)`) purely to present it.
In the app the panel sits over the note as it does today.

## Content
Sections in order, keys → description, verbatim:

**WISP**
- `⌃⌥⇧⌘.` — summon · dismiss panel
- `⌘↑ · ⌘↓` — move to beginning · end
- `⌘R` — refresh
- `⌥⌘R` — reveal note in finder
- `⌘+ · ⌘− · ⌘0` — larger · smaller · reset text
- `⌘,` — settings

**EDIT**
- `⌘F` — find… — ↵ · ⇧↵ to step
- `↵ · ⇧↵` — find next · previous
- `⌘D` — duplicate line or selection

**FORMAT**
- `⌘L` — toggle bullet list
- `⌥↑ · ⌥↓` — move line or selection
- `⌘B · ⌘I · ⌘H · ⌘U` — bold · highlight · italic · underline
- `⇥ · ⇧⇥` — increase · decrease indentation

**INSERT**
- `- · * · +` — bulleted list
- `1. · A. · a.` — numbered list
- `# · ## · ###` — headings
- `---` — horizontal rule
- `:) · :rocket:` — emojis — 🙂 · 🚀 · etc

Emoji shortcodes are deliberately one line, not an enumerated list.

## Interactions & behavior
- Panel is a modal overlay over the note. Opens from the menu-bar menu or the app's help shortcut;
  `esc`, clicking outside, or re-triggering closes it.
- Section headers stick while their section is in view and are pushed up by the next header.
- Body scrolls with wheel, `↑`/`↓`, and `⌘↑`/`⌘↓`.
- No hover states, no clickable rows — the screen is read-only reference.
- No animation beyond the panel's existing show/hide.

## State
None beyond `isHelpVisible` and scroll offset. Content is static; no data fetching.

## Design tokens
Colors
- Panel background `rgba(20,25,26,.94)`; sticky header background `rgba(20,25,26,.97)`
- Chrome fill (header/footer) `rgba(255,255,255,.03)`
- Hairlines `rgba(255,255,255,.06)`; panel border `rgba(255,255,255,.07)`
- Accent (section labels) `#4fb3a4`
- Key text `#e2eaea`; menu-item text `#aeb9ba`; description text `#93a2a3`
- Chrome text `#cfd8d8` (header title) and `#69797b` (secondary)
- Scrollbar thumb `rgba(255,255,255,.10)`
- Link `#5fbfb3`, hover `#7fd4c8`

Type — system font stack (`-apple-system`), regular weight throughout
- 14.5px rows · 13px header title · 12px chrome secondary · 10.5px section labels (uppercase, `.16em`)

Spacing
- Content inset `34px` · chrome inset `16px` / `11px`
- Row padding `5px 0` · key column `172px` · column gap `22px`
- Section gap `22px` above a header, `7px` below · body bottom padding `28px`

Radius / shadow
- Panel radius `12px` · shadow `0 30px 90px rgba(0,0,0,.6)`

## Assets
None. All glyphs are Unicode key symbols and two emoji; no images or icon files.

## Files
- `Wisp Help.dc.html` — the design
- `support.js` — browser runtime for the prototype; not part of the design
