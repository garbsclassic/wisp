# Panel background: blur on/off and a 0–1 opacity

Branch: `panel-background` · Started: 2026-09-14

## Goal

Ghostty's two knobs, `background-blur` (a boolean) and `background-opacity` (0–1). `vibrancy`
already was the first; the second is new. Both take effect live, which `vibrancy` never did.

## Decisions

| Decision | Chosen | Why |
| --- | --- | --- |
| Shape | `background.blur: true`, `background.opacity: null` | `vibrancy` renamed under a group so the pair reads together; the old key is dropped, not aliased |
| Default opacity | `null` = the theme's own | Dark's tint is 0.55, light's 0.75; one number for both would change today's look in one theme |
| What opacity applies to | Blur on: the chrome tint. Blur off: the palette's `panel` | Keeps both current looks at their defaults; `panel` is already "what the tint composites to" |
| Live | `adoptSettings` re-runs the chrome callback | The panel controller already re-applies chrome on a theme flip; a config reload now fires the same path |
| Range | Clamped 0…1 at use, not at decode | Same bargain as `fontScale`: a typo stays visible in the file |

## Steps

- [ ] `Background` config struct; `vibrancy` removed; tests moved
- [ ] `PanelController.applyTheme` reads it; `adoptSettings` re-applies chrome
- [ ] README rows; the "everything but `vibrancy`" sentence
- [ ] Visual verification: measured panel luminance at 0.3 / default / 1.0, blur off, both themes
- [ ] Progress line
