# F61 — How many to make

## Summary

The Crafts tab gains a `Make` number: enough of each profitable craft for a day of sales, less what you already own and have listed. It keeps you from crafting 40 of something that sells 3 a day.

## Context

- The Crafts table has Item, Sale net, Materials, Profit, ROI, Owned. Nothing ties the quantity queued to demand.
- The documented restock rule in TradeSkillMaster is `queue = max(maxRestock - owned, 0)`, zero when the batch or the profit is too small. Sizing `maxRestock` from sales is this addon's addition and rests on the sells-a-day estimate, which runs high.
- Own auctions are indexed in `auction.indexes.byCharacterAuction`; owned counts come from the inventory module.
- Design: `Make` and "How many to make" in [Crafts](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldCrafts).

## Scope

- `ForeverLogic.RestockQuantity(opts)`, pure: `target = round(sellsPerDay × daysOfCover)`, `make = clamp(target - owned - listed, 0, opts.cap)`; 0 when the craft's profit is below `opts.minProfit`; nil when sells a day is unknown
- Crafts table: `Sells a day` and `Make` columns (ROI moves to the optional columns); footer text "Make = a day of sales, less what you own and have listed"
- Row second line shows "N owned" and, when `Make` is 0 because of stock, "N owned, enough for now"
- Detail pane "How many to make": sells a day, owned and listed, make for N days; the queue field and button default to `Make` ("Add 6 to queue")
- Toolbar option "Make enough for" (1, 2, 3, 7 days), stored as `crafts.restockDays`
- Cooldown crafts (F62) cap `Make` at the uses available

## Status

Implemented:

- `MaterialLogic.RestockQuantity(opts)` (pure, offline-tested)
- `Tradewright_CraftPlanning.lua` (UI): `Sells a day` and `Make` columns appended to the Crafts table through `BuildCraftsTableColumns`; values are recomputed at most every 10 seconds
- Setting "Make enough for" (1, 2, 3 or 7 days of sales) in the Crafts group

Differs from the scope:

- **Listed stock is not counted.** The addon only knows your own auctions while the auction house is open, so `Make` subtracts what your characters own, not what is listed.
- **ROI stays where it is**; the new columns are added after the existing ones, and `Sells a day` is optional (dropped first when the table is narrow)
- **Not done:** the footer text, the "N owned, enough for now" row text, the "How many to make" block in the detail pane, and the queue field defaulting to `Make`. Those sit in `Tradewright_CraftsUI.lua`, which is over the file-size limit and may not grow.
- The "Make enough for" choice is in Settings, not in the Crafts toolbar
- Cooldown cap: `RestockQuantity` takes a `cap`, which the Crafts table passes for cooldown recipes (F62)

## Acceptance criteria

- [x] Sells 8 a day, 2 owned, 0 listed, 1 day → Make 6
- [ ] Sells 35 a day, 60 owned → Make 0 with "enough for now" (Make shows 0; the row text is not built)
- [x] Unknown sells a day → Make shows "-" and the queue default stays 1
- [x] A loss-making craft shows Make 0
- [x] Changing "Make enough for" updates the column without a reload
- [x] Offline tests of `RestockQuantity`: the cases above, rounding, cap, listed counted once

## Verification

```bash
npm test
```

In-game: Crafts → an item you already hold plenty of shows 0 → set "Make enough for" to 3 days → numbers triple, less stock.

## Dependencies

- F42 (sells a day)

## Out of scope

- Your share of the market's sales (the whole estimate is used)
- Splitting production across characters
- Posting quantities
