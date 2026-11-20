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

## Acceptance criteria

- [ ] Sells 8 a day, 2 owned, 0 listed, 1 day → Make 6
- [ ] Sells 35 a day, 60 owned → Make 0 with "enough for now"
- [ ] Unknown sells a day → Make shows "-" and the queue default stays 1
- [ ] A loss-making craft shows Make 0
- [ ] Changing "Make enough for" updates the column without a reload
- [ ] Offline tests of `RestockQuantity`: the cases above, rounding, cap, listed counted once

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
