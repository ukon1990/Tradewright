# F56 — Show how much history there is, and allow rows with little of it

## Summary

Tell the player how complete the price history is and when it will be enough. A setting lets items with 2 to 4 scan days show anyway. Those rows are marked "Early", and the side pane says why to be careful.

## Context

- `computeUsualPrice` (`AuctionHelper_PriceHistory.lua`) returns nothing below `MIN_USUAL_DAYS = 5`. `flipCandidates` and the sell-now and gap candidates then drop the item without a word, so a new player sees an empty list and "Scan the auction house on a few different days".
- Only finished days count: hourly scans are rolled up into daily history the first time the addon loads after the day ends (`RollupDailyAuctionHistory`). Scans from today count from tomorrow.
- `GetUsualPrice` is also used by the Market tab, the market chart, the market insights and farm targets. Those must keep the 5-day rule; only the Opportunities lists may opt into fewer days.
- The flip side pane already names the day count ("Usual price, N days") and the risk text names the range.

## Scope

- `PriceHistory`: `GetUsualPrice(storageKey, minDays)`. `minDays` defaults to 5, and existing callers are unchanged. The cache key includes `minDays`.
- `GetHistoryCoverage()`: for the items in the last scan, how many have a usual price (5+ days), how many have 2 to 4 days, the most days any item has, and whether today's scans are still waiting to be rolled up. Cached with the other signals.
- Stat card "Usual price from" (Flips, Price gaps, Sell now) shows coverage instead of only the window. Example: "312 of 7,071 items · 5 scan days needed"; second line "Most items have 3 days · today's scan counts tomorrow".
- Setting "Also show items with 2 to 4 days of history" (`opportunities.allowEarly`, default off), in Settings → Opportunities.
- With it on, Flips, Price gaps and Sell now ask for `minDays = 2`. Rows under 5 days get `early = true`.
- Early rows:
  - Item line reads "Early · N days of prices" in the warning colour
  - Side pane risk text starts with "Usual price from only N days. One odd day moves it a lot."
  - "Expected profit, all N" and "Gold needed" count only rows that are not early. The second line says "+M early rows not counted".
- Price steps and sell-now rows behave the same way.

## Acceptance criteria

- [ ] With 3 scan days, the coverage card says how many items have a usual price and that 5 days are needed
- [ ] With the setting off, no row under 5 days appears anywhere
- [ ] With it on, a 3-day item that meets the other rules appears in Flips marked Early, with the warning in the side pane
- [ ] Early rows are left out of the stat totals and counted on the second line
- [ ] The Market tab, chart and farm targets still need 5 days
- [ ] Offline tests: `UsualPrice` with 2 and 4 days; the coverage counts; early flag on flip rows
- [ ] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever with 2 to 4 days of scans: Opportunities → coverage card shows the counts → Settings → turn on early rows → Flips shows Early rows → select one → warning text.

## Dependencies

- F40, F50; F52 and F54 for those lists

## Out of scope

- Changing the 5-day rule for the Market tab
- Weighting recent days more than old ones
- Backfilling history from TSM or Auctionator
