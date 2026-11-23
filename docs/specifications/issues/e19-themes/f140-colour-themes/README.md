# F140 — Colour themes and own colours

## Summary

Settings → General → Appearance has a Theme choice: Dark (the look until now), Grey, Blue, Red, Parchment, Light and Custom. Custom shows two colour boxes, Background and Highlight; every other colour is worked out from those two with enough contrast to read. A change shows at once in the open windows.

## Context

- All chrome colours come from the token table returned by `GetTheme()`. Callers keep references to its colour tables, so a theme change overwrites the values in place and never replaces a table.
- Frames are coloured once when built, so a change also has to reach what already exists.

## Scope

- Pure helper `src/Tradewright/src/util/Tradewright_ThemeLogic.lua`:
  - `ContrastRatio`, `ReadableOn` (WCAG contrast).
  - `BuildPalette({ background, highlight })`: surfaces, borders, text, status colours, `hover` wash, `textOnAccent`, `isLight`. Text tokens get at least 4.5:1 on all three surfaces, marks 3:1.
  - `PRESETS`; the dark preset carries the earlier hand-tuned values unchanged.
  - `ResolvePalette(themeId, customSeed)`, `GetSeed`, `IsSeed`.
- `Tradewright_Theme.lua`:
  - `ApplyThemeSetting` (at load), `ApplyThemeChange` (after a settings change), `RecolorUI`.
  - Everything coloured through `ColorText`, `ColorTexture`, `TintTexture`, `ColorStatusBar` or the skin functions is remembered and recoloured on a change. Direct `SetTextColor` / `SetColorTexture` calls with theme colours were moved onto these.
  - Labels drop the game's drop shadow on a light theme.
  - `GetQualityColor(quality)`: the game's item quality colour, darkened on a light theme.
- `Tradewright_UI`: new `Tradewright_ColorSwatch.lua` (colour box opening the game's colour picker), setting item kind `color`, the Appearance section, `RefreshThemedWindows`.
- Settings saved for all characters: `appearance.theme`, `appearance.customTheme = { background, highlight }`. Custom starts from the colours of the theme shown before it.

## Acceptance criteria

- [x] Dark theme values are the same as before (offline test)
- [x] Every ready-made theme, and custom themes from hostile colours (white on white, mid greys, highlight equal to background), keep text at 4.5:1 or better (offline test)
- [x] A theme change keeps the palette's table identities and recolours labels already built (offline test)
- [x] `npm test` passes; no lint debt grows
- [ ] Each theme switches without `/reload` in the Tradewright window, auction panel, bag window, mail panel, craft panel and Get started window, with nothing left in the old colours
- [ ] Parchment and Light: row hover, solid buttons, item names of every quality and the chart are readable
- [ ] Custom: the windows follow the colour picker while dragging; Cancel restores the colour; the choice is kept after `/reload`
- [ ] The colour picker opens on Forever and on retail
- [ ] Get started (`/tw intro`): the theme row under the steps changes the theme at once, its menu opens above the window, and it shows the theme chosen in Settings

## Verification

```bash
npm test
```

In-game (new `.lua` files: restart the client):

1. `/tw` → Settings → General → Appearance. Pick each theme with other Tradewright windows open.
2. Pick Custom → the look stays as it was; change Background and Highlight and watch the windows follow.
3. Press Cancel in the colour picker → the earlier colour is back.
4. `/reload` → the theme is kept.

## Known limits

- Windows other than the Tradewright window and the bag window are recoloured at once, but colours they set per row are redrawn at their next refresh.
- A label coloured with a direct `SetTextColor` on each refresh keeps its drop shadow on light themes.
