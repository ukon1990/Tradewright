# F142 — Data quality check

## Summary

A pure check that says whether salvage values are good enough to act on: "good", "weak" or "not enough", with the reasons in words the player can act on. The Destroying tab shows it, and the auction house search uses it to decide whether to show rows.

## Context

- The value of a destroyed item rests on three things: the yield (shipped estimate or counted casts, from `SalvageLogic.Yield`), the prices of what it gives (usual price with days of history, `GetUsualPrice` / `GetEarlyUsualPrice`), and how fresh the last full scan is (`GetLastFullAuctionScanAt`, `AuctionLogic.FULL_SCAN_PRICE_FRESH_SEC`).
- The Opportunities tab judges history with `FlipLogic.HistoryCoverage`; this check should read the same way to the player.
- `GetSalvageValue` already reports `unvalued`: results with no price.

## Scope

New `src/Tradewright/src/util/Tradewright_SalvageCheckLogic.lua`, no game API:

- `Check(facts)` with facts gathered by the caller: last full scan age, for each result material its usual price days (or none), yield basis and casts per input group in use
- Returns `{ level = "good" | "weak" | "none", reasons = { { code, itemID? } } }`
- "none": no full scan, or the materials that make up most of the value have no price
- "weak": prices from fewer days than the usual price needs, a scan older than the fresh limit, or yields that are only estimates
- "good": otherwise
- Reasons are codes; the UI turns them into texts such as "Do a full scan" or "Arcane Dust has 2 days of prices; 5 are needed"
- Thresholds are named constants at the top of the file, with a comment saying why
- A small game-side gatherer in the Professions module builds the facts

## Status

Implemented; offline tests and lint pass. Nothing shows it yet: F143 and F144 turn the reasons into text.

- Changed after a check in game: researched yields alone no longer make the level "weak". The shipped tables agree with about 20,000 counted disenchants within a few points, and a player could only replace them with 20 own disenchants of every kind of gear, so the badge would never leave "rough". They are still named in the strip, and each value carries "~"
- `SalvageCheckLogic.Check({ now, lastFullScanAt, yields, priceOf })` returns `{ level, reasons }`
- `Tradewright:CheckSalvageValues(action, inputs)` (`Tradewright_CraftsEngine.lua`) gathers the facts: one yield per item valued, so a kind held often weighs more; a material is priced by its AH estimate (with its days of scans) or, failing that, its vendor price (no history needed)
- `Tradewright:GetItemPriceDays(itemID)` (`Tradewright_PriceHistory.lua`): days of scans behind an item's price

Thresholds: a usual price needs 5 days (as in Opportunities); a full scan older than 24 hours weakens; more than half of what the yields give, by quantity, without a price makes it "none".

Differs from the scope:

- A material's weight is its share of the quantity the yields give, not of the value: a material with no price has no value to weigh. So a rare, valuable result (Nexus Crystal) weighs little; it is still named as a reason, as every unpriced or thin material is
- Reasons: `no_full_scan`, `no_yields`, `old_scan` (hours), `no_price` (item), `few_price_days` (item, days), `estimated_yields` (count of total)
- Researched yields always make the level at most "weak". On Forever every value starts as an estimate, so it reads "weak" until 20 own disenchants of a kind are counted

## Acceptance criteria

- [x] Offline tests: each level, each reason, and that a material with no price but little weight in the value does not drop the level to "none"
- [x] No game API in the logic file; new file in all four TOCs

## Verification

```bash
npm test
```

## Dependencies

- E18 F135 (yield basis), E06 (usual price days)

## Out of scope

- Scanning or searching to fix the reasons (the player does that; the reasons say how)
