# F42 — Estimated sells per day and days of supply

## Summary

Each item gets "Sells a day, estimated": how many units leave the auction house per day, worked out from how the listed quantity changes between your scans and checked against your own sales. With it the addon can tell an item that sells from one that only looks cheap, and say how long the listed supply lasts.

## Context

- The addon has no sales figure of its own. The Inventory "SR" column and the tooltip use TSM `DBRegionSaleRate` when TSM is installed.
- Auction data shows listings, never sales. The accepted workaround is to compare successive scans: units that are gone were sold, cancelled or expired. A 2014 conference paper used this on hourly WoW data without validating its accuracy ([Hsu, Togelius & Sun](https://www.cse.unr.edu/~sushil/pubs/newestPapers/aux/paper_104.pdf)). The result is an upper bound.
- Scans happen only when the player is at the auction house, so gaps are uneven.
- Your own sales (ledger) are a lower bound for an item's sales.
- Design: `Sells a day` in [Market](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldMarketItem) and [Crafts](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldCrafts).

## Scope

- `ForeverLogic.EstimateSoldBetween(prev, next)` → units, where `prev` and `next` are snapshot entries:
  - with price steps on both (F41): the drop in quantity at or below `next`'s lowest price plus levels of `prev` that vanished below it
  - without steps: `max(0, prev.q - next.q)`
  - nil when the gap between the two scans is longer than `maxGapHours` (default 26)
- When a scan replaces an item's snapshot entry, add the estimate and the covered hours to that day's `history.daily` entry as `s` and `g`
- `ForeverLogic.SellsPerDay(daily, windowDays, ownSalesPerDay)` → `{perDay, confidence}`:
  - `perDay = max(sum(s) / sum(g) × 24, ownSalesPerDay)`
  - `confidence` is "good" with 5 or more covered scan pairs in the window, "few" with 2 to 4, nil below that (nothing shown)
- `ForeverLogic.DaysOfSupply(quantity, perDay)`
- Market tab column `Sells a day`; Inventory optional column; item details "Sells a day, estimated" and "Listed supply lasts about N days"; tooltip line
- Rows with confidence "few" carry the note "few sales seen"
- Docs tab: a short section on how the estimate is made and why it runs high

## Acceptance criteria

- [ ] Two scans 12 hours apart where an item's quantity fell by 30 give 60 a day for that pair
- [ ] A quantity that rose between scans counts as 0, not as negative
- [ ] Scans 3 days apart add nothing
- [ ] An item with one scan shows "-" for sells a day
- [ ] An item you sold 10 of per day never shows less than 10
- [ ] The word "estimated" appears wherever the figure is explained (details, tooltip, Docs)
- [ ] Offline tests: with and without steps, restock between scans, long gap, confidence levels, own-sales floor, days of supply with perDay 0 or nil

## Verification

```bash
npm test
```

In-game: scan, wait a few hours, scan again → Market shows `Sells a day` for items whose quantity dropped → compare a fast commodity and a rare item for plausibility.

## Dependencies

- F40: daily history carries the estimate
- F41 improves the estimate; without it the plain quantity difference is used
- F44 for own sales per day (the existing sale events are enough to start)

## Out of scope

- Telling sales from cancels and expiries of other players
- TSM's sold-per-day as an alternative source
- Hour-by-hour sales
