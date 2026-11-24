# F146 — Destroying tab: data as stat tiles, kind of gear, clearer empty state

## Summary

Replace the data strip with four stat tiles, each one thing the player can check or fix: Values, Last full scan, Material prices, Yields. Hovering a tile explains it and lists what is behind it. Rows name the kind of gear (armor or weapon, item level, quality), as that is what the yield depends on. With not enough data, the empty table lists the steps to get there.

## Context

- The strip listed reasons as sentences; with many materials it grew long and, with one reason, its tooltip repeated it.
- Design: "Tradewright Screens" canvas, row "Proposed, not built yet: Destroying tab…".

## Scope

- `SalvageCheckLogic.Check` also returns `scanHours`, `materials` (`{ itemID, share, priced, days }`, largest share first) and `kinds` (`{ total, counted }`)
- Four tiles in both views; value coloured by state; a tooltip per tile
- Item column second line: "Armor · item level 29 · uncommon"
- Empty state with steps when the data is not enough
- Owned side pane: what each choice gets, best first, the best in green

## Status

Implemented; offline tests and lint pass. Not yet checked in game.

- `Tradewright_SalvageTiles.lua` (new): Values, Last full scan, Material prices, Yields; each note says what to do; hovering lists what is behind it (materials short of a usual price with their days, the reasons, how yields work)
- `SalvageCheckLogic.Check` adds `scanHours`, `materials` and `kinds`; `GroupReasons` and the strip are gone
- Rows are two lines: the item, and "Armor · item level 29 · Uncommon" (quality from the game's own strings)
- Side pane: the view's facts, then "One disenchant gives" with chances, then where the yield comes from
- Owned side pane lists each use best first, the best in green, a closed use in grey with why
- Below disenchant value with not enough data: the empty table lists numbered steps

Differs from the design: the same four tiles in both views (the Owned design had a gains tile; the gain is in each row); no bars in the side pane.

## Acceptance criteria

- [ ] Each tile says what to do when it is not fine
- [ ] Material prices tooltip lists materials short of a usual price with their days
- [ ] No full scan: rows hidden, steps shown
- [ ] Offline tests for the new check fields

## Verification

```bash
npm test
```

## Dependencies

- F142, F143, F144

## Out of scope

- Bars in the side pane (the design's bars are drawn as plain rows)
