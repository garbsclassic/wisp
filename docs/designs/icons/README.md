# Handoff: Wisp app icon + menu bar glyph

## Overview
Icon identity for **Wisp**, a macOS menu bar app, alongside its sibling app **Clef**. The mark is an
"aperture" — four concentric bands with a white core — with a vapor trail rising off the top of it.
Two deliverables: the app icon (rounded-rect tile, full colour, 1024px master down to 16px) and the
menu bar glyph (single-ink template image, 18px).

## About the Design Files
`Wisp Icons.dc.html` in this bundle is a **design reference created in HTML** — a prototype showing
the intended artwork, its behaviour at every size, and the light/dark menu bar contexts. It is not
production code to copy wholesale. The task is to recreate this artwork in the target environment:
for macOS that means an `.icon`/`.icns` asset set plus a template `NSImage` for the status item,
authored from the SVG geometry below (or redrawn in a vector tool from the same coordinates). If no
environment exists yet, pick the appropriate one for the platform and implement there.

The HTML file is a design canvas: it holds every explored direction, newest at the top, each with a
short id (`9a`, `8b`, `7d`, …). Only the sections listed under **Screens / Views** matter for
implementation; earlier turns are history.

## Fidelity
**High fidelity.** Colours, band radii, stroke widths, blur radii, and alpha values are final and
given exactly below. Recreate the geometry precisely — the mark's legibility at 16–18px depends on
the band proportions, and the vapor's readability depends on the specific alpha ramp.

## Screens / Views

### 1. Wisp app icon — direction `9a` "Veil" (recommended)
- **Purpose:** Dock, Finder, About window, App Store.
- **Canvas:** square tile, corner radius **22.5% of side** (14.4px at 64px; use the macOS
  squircle/continuous-corner shape, not a plain rounded rect). Artwork drawn on a 50 × 50 unit grid
  scaled to fill the tile at **~81%** of tile width (in the prototype: a 52px SVG inside a 64px tile).
- **Tile background:** two layers, bottom to top:
  - `linear-gradient(180deg, #25292A 0%, #171A1B 46%, #0C0E0E 100%)`
  - `radial-gradient(circle at 50% 62%, rgba(78,203,223,0.22), rgba(78,203,223,0) 66%)` — a cyan bloom
    behind the aperture.
  - Tile edge treatment in the prototype: `inset 0 0.7px 0 rgba(255,255,255,0.11)` top highlight and
    `0 1px 3px rgba(0,0,0,0.55)` drop shadow. These are presentation only; macOS supplies its own.
- **Aperture** (centre `cx 25, cy 33` on the 50-unit grid — deliberately low, to leave room for the trail):
  | band | radius | stroke | colour |
  |---|---|---|---|
  | fringe | 12.5 | 5 | `rgba(143,227,136,0.28)` (green) |
  | mid | 9.5 | 4.4 | `#5BD6C0` (teal) |
  | inner | 6.2 | 4 | `#4EC5DF` (cyan) |
  | core | 3.8 (filled) | — | `#FFFFFF` |
- **Vapor trail:** five ellipses climbing from `cy 18.6` to `cy 1.8`, **widest at the ring**
  (rx 11.2) and narrowing as they rise (rx 2), with opacity falling 0.34 → 0.09; single colour
  `rgb(127,227,242)`. A faint directional stroke (`#DDF7FC`, width 2.6, opacity 0.5) runs through the
  lower half. The whole group is blurred as one body — `feGaussianBlur stdDeviation="2.4"` on the
  50-unit grid (≈ 4.8% of icon width) — which is what removes the banding between ellipses. Do not
  blur the aperture bands.
- **Exact source geometry:**

```svg
<svg width="1024" height="1024" viewBox="0 0 50 50">
  <defs>
    <filter id="vapor" x="-70%" y="-70%" width="240%" height="260%">
      <feGaussianBlur stdDeviation="2.4"></feGaussianBlur>
    </filter>
  </defs>
  <!-- vapor trail: widest where it meets the ring, thinning as it rises -->
  <g filter="url(#vapor)">
    <ellipse cx="25"   cy="18.6" rx="11.2" ry="6.4" fill="rgba(127,227,242,0.34)"></ellipse>
    <ellipse cx="24.8" cy="13.4" rx="8"    ry="5.2" fill="rgba(127,227,242,0.28)"></ellipse>
    <ellipse cx="25.4" cy="8.8"  rx="5.4"  ry="4.2" fill="rgba(127,227,242,0.21)"></ellipse>
    <ellipse cx="25"   cy="4.8"  rx="3.4"  ry="3.2" fill="rgba(127,227,242,0.15)"></ellipse>
    <ellipse cx="25.2" cy="1.8"  rx="2"    ry="2"   fill="rgba(127,227,242,0.09)"></ellipse>
    <!-- faint directional core, blended by the same blur -->
    <path d="M25 18 C22.6 14.4, 26.6 12, 25 8.6" fill="none" stroke="#DDF7FC"
          stroke-width="2.6" stroke-linecap="round" opacity="0.5"></path>
  </g>
  <!-- aperture: four concentric bands -->
  <circle cx="25" cy="33" r="12.5" fill="none" stroke="rgba(143,227,136,0.28)" stroke-width="5"></circle>
  <circle cx="25" cy="33" r="9.5"  fill="none" stroke="#5BD6C0" stroke-width="4.4"></circle>
  <circle cx="25" cy="33" r="6.2"  fill="none" stroke="#4EC5DF" stroke-width="4"></circle>
  <circle cx="25" cy="33" r="3.8"  fill="#FFFFFF"></circle>
</svg>
```

- **Required sizes:** 1024, 512, 256, 128, 64, 32, 16 (plus @2x). The prototype verifies 96, 44, 32
  and 16px. At 16px the vapor reads as a single soft lift above the ring; do not hand-tune it away.

### 2. Wisp menu bar glyph — direction `9a`
- **Purpose:** `NSStatusItem` button image, template (single ink, system-tinted).
- **Canvas:** 30 × 30 unit grid rendered at **18 × 18 px** — the full height a macOS status item
  image should use. Artwork spans the grid vertically from `y 0.2` (vapor tip) to `y 29.7` (ring
  bottom); do not letterbox it smaller.
- **Ink:** one colour, alpha-modulated. Template images are recoloured by the system: draw in black
  and set `isTemplate = true`. The prototype previews `#EAEDEF` on a dark bar (`#31566B`) and
  `#1F2426` on a light bar (`#E5E1D9`).
- **Aperture reduced to two elements:** ring `cx 15, cy 20.7, r 7.5, stroke-width 3`; core
  `r 3.2` filled. The bands cannot survive 18px, so only the outer ring and the core remain.
- **Vapor:** five ellipses, alpha only — a wide low-alpha skirt (rx 9.8 @ 0.30 and rx 6.2 @ 0.20)
  under a brighter body (rx 6.6 @ 0.80, rx 4.1 @ 0.50) and a tip (rx 2.3 @ 0.26). The skirt is what
  makes the trail read as vapor rather than a stack of dots; the widest layer sits nearest the ring.
  No blur — alpha does the work, so the asset stays crisp as a template image.
- **Exact source geometry** (ink shown as `#000` for template use):

```svg
<svg width="18" height="18" viewBox="0 0 30 30">
  <!-- vapor: wide alpha skirt, then the body, then the tip -->
  <ellipse cx="15"   cy="10.4" rx="9.8" ry="4.3" fill="#000" opacity="0.30"></ellipse>
  <ellipse cx="15"   cy="6.2"  rx="6.2" ry="3.2" fill="#000" opacity="0.20"></ellipse>
  <ellipse cx="15"   cy="10"   rx="6.6" ry="3.3" fill="#000" opacity="0.80"></ellipse>
  <ellipse cx="14.7" cy="5.6"  rx="4.1" ry="2.5" fill="#000" opacity="0.50"></ellipse>
  <ellipse cx="15.4" cy="2"    rx="2.3" ry="1.8" fill="#000" opacity="0.26"></ellipse>
  <!-- aperture reduced to ring + core -->
  <circle cx="15" cy="20.7" r="7.5" fill="none" stroke="#000" stroke-width="3"></circle>
  <circle cx="15" cy="20.7" r="3.2" fill="#000"></circle>
</svg>
```

### 3. Context: Clef (sibling app, already designed — do not change)
Present in the prototype only so Wisp can be judged next to it.
- App icon: tile gradient `linear-gradient(180deg, #3A3A39 0%, #2A2A2A 46%, #171817 100%)`; a
  capsule 11 × 48.5px, radius 99px, rotated 26.5°, filled
  `linear-gradient(180deg, #F1F0ED 0%, #F1F0ED 46%, #ED3012 46%, #ED3012 100%)`.
- Menu glyph: two square brackets with a filled dot between them — at 18px: 20 × 14px box, bracket
  stems 5.5px wide with 2.5px strokes and 2px outer radii, dot 5px.

## Interactions & Behavior
The icons are static assets; there is no interactive prototype here. Two behaviours are implied by
the artwork and worth implementing:
- **Menu bar highlight:** rely on the system's template-image tinting for hover/active/selected
  states. Do not ship a second coloured asset.
- **Optional summon animation:** the vapor is drawn as discrete layers precisely so it can be
  animated — rising and fading the layers in sequence (bottom to top, ~120ms apart, ease-out, total
  ~500ms) reads as the light being summoned. Ship the static asset first; treat this as a follow-up.
- **Light/dark menu bars:** verified in the prototype on `#31566B` and `#E5E1D9`. The alpha ramp must
  hold on both — check the 0.20 skirt is still faintly visible on light backgrounds and does not
  turn into a grey smudge.

## State Management
None. Static assets.

## Design Tokens

**Wisp palette**
| token | value | use |
|---|---|---|
| core | `#FFFFFF` | aperture centre |
| inner | `#4EC5DF` | inner band |
| mid | `#5BD6C0` | middle band |
| fringe | `rgba(143,227,136,0.28)` | outer band |
| vapor | `rgb(127,227,242)` @ 0.34 / 0.28 / 0.21 / 0.15 / 0.09 | trail layers |
| vapor core | `#DDF7FC` @ 0.5 | directional stroke |
| tile base | `#25292A` → `#171A1B` (46%) → `#0C0E0E` | icon tile gradient |
| tile bloom | `rgba(78,203,223,0.22)` | radial bloom at 50% 62% |

**Menu bar contexts (for review only)**
dark bar `#31566B`, dark-bar ink `#EAEDEF`; light bar `#E5E1D9`, light-bar ink `#1F2426`.

**Geometry scale** (50-unit app grid): band radii 12.5 / 9.5 / 6.2 / 3.8; strokes 5 / 4.4 / 4 / —;
aperture centre y 33; vapor rx 11.2 → 2 over cy 18.6 → 1.8; blur σ 2.4.
(30-unit menu grid): ring r 7.5 stroke 3, core r 3.2, centre y 20.7; vapor rx 9.8 → 2.3 over
cy 10.4 → 2.

**Corner radius:** 22.5% of tile side (macOS squircle).

**Typography:** none in the assets. The prototype's labels use the system UI font at 11.5px and are
not part of the deliverable.

## Assets
No bitmaps, fonts, or third-party assets. Everything is vector geometry defined above and originates
in this project. Reference imagery the direction was derived from lives in `uploads/` in the design
project (photographic references of will-o'-the-wisp light; not for shipping).

## Files
- `Wisp Icons.dc.html` — the full design canvas. Relevant sections:
  - **turn 9** (`9a` Veil — recommended, `9b` Vapor — no directional stroke, `9c` Drift — leaning column)
  - **turn 8** (`8a` Torch, `8b` Cool, `8c` Sheath — flame-silhouette alternative, warm inner core)
  - **turn 3** (`3c` Aperture — the trail-less original the whole set is built on)
- `support.js` — runtime for the HTML prototype only. Not part of the design; not needed in the app.

Open `Wisp Icons.dc.html` in a browser and read the geometry off the DOM if any value here is ambiguous.
