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

- Pure helpers in `Tradewright_MarketSignals.lua`:
  - `MarketSignals.EstimateSoldByDay(hourlyByHour, fromTs, toTs, maxGapHours)` → per day `{s = units, g = hours covered, c = scan pairs}` from drops in listed quantity between consecutive scanned hours no more than `maxGapHours` (26) apart; a rise counts as 0; a drop is counted on the day of the later scan
  - `MarketSignals.SellsPerDay(daily, now, windowDays, ownSalesPerDay)` → `{perDay, confidence, pairs}`: `perDay = max(sum(s) / sum(g) × 24, ownSalesPerDay)`; `confidence` is "good" with 5 or more scan pairs in the window, "few" with 2 to 4, nil below that (nothing shown)
  - `MarketSignals.DaysOfSupply(quantity, perDay)`
- The estimate is made from the hourly history when a day is rolled up (F40's `RollupDailyAuctionHistory`), so no scan code changes and it appears the day after two scans of an item. `s`, `g` and `c` are stored on that day's `history.daily` entry.
- `GetSellsPerDay(storageKey)` (AuctionData), cached like the usual price
- Market tab column `Sells a day`; item details "Sells a day, estimated" and "Listed supply lasts"; "(few sales seen)" when confidence is "few"
- The player's own sales per day from the ledger are the floor (`GetSalesSummary`, rebuilt at most once a minute); with no scan estimate they stand alone
- Tooltip: the "Listed" line ends with "~N sold/day"
- Docs tab: section "Usual price and sells a day" on how both are made and why sells a day runs high
- Still open:
  - with price steps (F41): count only the drop at or below the next scan's lowest price
  - Inventory optional column: `Tradewright_InventoryUI.lua` is over the file-size limit and may not grow; it needs a split first

## Acceptance criteria

- [x] Two scans 12 hours apart where an item's quantity fell by 30 give 60 a day for that pair
- [x] A quantity that rose between scans counts as 0, not as negative
- [x] Scans 3 days apart add nothing
- [x] An item with one scan shows "-" for sells a day
- [x] An item you sold 10 of per day never shows less than 10 (offline test)
- [x] The word "estimated" appears wherever the figure is explained (details, tooltip, Docs)
- [x] Offline tests: restock between scans, long gap, pair across midnight, confidence levels, own-sales floor, days of supply with perDay 0 or nil
- [ ] Offline test with price steps (after F41)

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
