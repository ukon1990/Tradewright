# F72 — What to farm

## Summary

A "What to farm" list in the Farming tab ranks materials by how much gold changes hands in them each day, shows whether supply is running low, and names the farm where you have looted each one before with your own rate.

## Context

- The research's advice on finding farms is to start from prices and turnover, then find a source, because published rates are unreliable. The game gives no drop rates and the addon ships no drop table, so the "where" can only come from the player's own runs (F70, F71).
- `GetRecipeMaterialSet` (`AuctionHelper_MarketInsights.lua`) already flags items your own recipes use.
- Market rows carry item class and subclass, so trade goods can be filtered without new data.
- "Traded a day" is usual price × estimated sells a day. It inherits the upward bias of the sells-a-day estimate; it is a ranking, not income.
- Design: [Farming, what to farm](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldWhatToFarm).

## Scope

- `ForeverLogic.BuildFarmTargets(marketRows, lootIndex, recipeMaterials, opts)`, pure. For each item of the chosen kind with a usual price and sells a day:
  - `tradedPerDay = usual × sellsPerDay`
  - `listedVsUsual = quantity now ÷ its 14-day middle quantity - 1`
  - `daysOfSupply` (F42)
  - `source` = the farm with the highest units an hour for this item from `lootIndex`, with that rate; nil when never looted in a run
  - `yoursPerHour = rate × usual × (1 - cut)` when a source exists
- `lootIndex` is built from saved farms: per item, units and active seconds per farm
- Table: Item (second line: "Supply lasts N days · used by N of your recipes"), Usual price, Sells a day, Traded a day, Listed, Where you got it, Yours, an hour. Sorted by Traded a day.
- Items never looted in a run show "Not looted in a farm yet" and "-"
- Filters: kind of item (Trade goods by default, with its subclasses), "My recipes use it", "Only farmed before"
- One line above the table: "Materials that move the most gold each day. AuctionHelper does not know where items drop: the last columns come from your own farms."
- Footer explains Traded a day and Listed

## Acceptance criteria

- [ ] An item with a usual price of 48s that sells 400 a day shows 192g traded a day
- [ ] An item looted in two farms names the one with the higher rate
- [ ] An item never looted in a run shows the "not looted" text and no rate
- [ ] An item without a sells-a-day estimate is not listed
- [ ] "My recipes use it" keeps only materials of recipes your characters know
- [ ] No source or rate appears that did not come from the player's saved runs
- [ ] Offline tests of `BuildFarmTargets`: ranking, best source, never looted, filters, missing turnover

## Verification

```bash
npm test
```

In-game: with a few saved farms and several days of scans → Farming → What to farm → the top rows are the busy materials on your realm → an item from a saved farm names it.

## Dependencies

- F71 (tab and saved farms), F40, F42

## Out of scope

- Zone, mob, node or vendor sources for items you have not farmed
- Links or lookups to outside databases
- Predicted income for a farm you have not run
