# F145 — Chances per material for disenchanting

## Summary

Show what one disenchant gives as chances: "75% · 1–2 Soul Dust", not only "1.13 Soul Dust on average". The researched table keeps each material's chance and count range; the player's own disenchants count how many casts gave each material.

## Context

- The shipped table (`Tradewright_SalvageData.lua`) holds averages only, though its source, the reference wikis' disenchanting tables, states chance and count range per material (docs/research/salvage-yields.md). Every shipped average is chance × middle of the range.
- Own outcomes (`SalvageLogic.RecordOutcome`) keep casts, inputs and items received, so a chance per material cannot be read from them.
- Design: "Tradewright Screens" canvas, row "Proposed, not built yet: Destroying tab…", side pane and row tooltip.

## Scope

- Researched disenchant rows give `{ [itemID] = { chance, min, max } }`; the average per input is worked out from them, so values do not change
- Own records gain `single` (casts recorded one at a time) and `hits = { [itemID] = casts that gave it }`; shipping adds them up like the other counts
- `SalvageLogic.Yield` returns `chances = { [itemID] = { chance, min, max } or { chance, each } }`: researched ranges, or counted chance and the average count when it drops
- Destroying tab side pane and row tooltip list the chances

## Status

Implemented; offline tests and lint pass. Not yet checked in game.

- `Tradewright_SalvageData.lua`: each disenchant material is `drop(chance, min, max)`; every one of the 35 rows keeps the same average as before (compared row by row), and each row's chances add up to one
- `SalvageLogic`: researched rows give `perInput` and `chances`; own records gain `single` and `hits`, counted only for casts recorded one at a time; `Yield` returns `chances` and `ownCasts`; old records without the new fields give averages only
- `SourceLogic` ships every table of counts per item, so `hits` add up like `items`
- Shown in the Destroying tab's side pane ("75% · 1–2 Soul Dust", value on average) and row tooltip

## Acceptance criteria

- [ ] Every researched average is unchanged (offline test over the whole table)
- [ ] A counted yield with single casts gives each material's chance
- [ ] Old saved records without `hits` still load and give averages only
- [ ] Side pane and tooltip show chance, count and average value per material

## Verification

```bash
npm test
```

## Dependencies

- F143, F144

## Out of scope

- Chances for prospecting and milling (no researched data)
