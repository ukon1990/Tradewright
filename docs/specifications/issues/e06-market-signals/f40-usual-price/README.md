# F40 — Daily price history and a robust usual price

## Summary

Each item gets one stored price per day and a "usual price": the middle of those daily prices over the last 14 days, with its normal range. Deals, Market movers, the Market tab and the tooltip compare today's price against it instead of against a 7-day average that one odd listing can move.

## Context

- `history.hourly[storageKey][hourTs]` has `m, x, l, n, q, w, t`. `SummarizeHourlyHistory` averages the hourly lowest prices over 7 days; `ClassifyMarketItem` calls a deal at `(ref - price) / ref >= gold.dealThreshold` (0.3) with `ref` = TSM `dbmarket`, else that average.
- `history.daily` exists in `InitAuctionDB` but is never written, and `CompactAuctionStorageData` sets it to nil.
- Hourly history is kept `settings.auction.historyRetentionDays` days. The default is 14 in `Tradewright_Data.lua` and 30 in the Settings tab; they should agree.
- A mean is pulled by outliers; the median and the median absolute deviation (MAD) are not. The modified z-score `0.6745 × (x - median) / MAD` with a cutoff of 3.5 is the handbook rule for flagging outliers ([NIST](https://www.itl.nist.gov/div898/handbook/eda/section3/eda35h.htm)).
- Design: [Market, item selected](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldMarketItem).

## Scope

- Pure helpers in the new `Tradewright_MarketSignals.lua` (`ForeverLogic.lua` is over the file-size limit and may not grow):
  - `MarketSignals.RollupItemDays(hourlyByHour, fromTs, toTs)` → per day `{p = median of the hourly lowest prices, lo, hi, q = highest quantity seen, n = scans}`
  - `MarketSignals.UsualPrice(dailyByDay, now, windowDays)` → `{usual, mad, low, high, days}` where `low` and `high` are the 25th and 75th percentile of the window
  - `MarketSignals.DealScore(price, usual, mad)` → `{pct = (price - usual) / usual, score}`; when `mad` is 0 the score is nil and callers use `pct` alone
- `Tradewright_PriceHistory.lua` (AuctionData): `RollupDailyAuctionHistory` persists the result in `history.daily[storageKey][dayTs]` when the addon loads (replacing the line in `CompactAuctionStorageData` that cleared it) and trims it with `auction.dailyRetentionDays` (default 180); `GetUsualPrice(storageKey)` returns the cached usual price once an item has 5 or more days. Days are UTC days.
- Market insights take the usual price as the reference for deals and the baseline for movers once an item has 5 days; with fewer they keep the 7-day average. The existing "usual-price source" setting keeps TSM as a choice.
- Market tab: `Usual` and `Vs usual` columns. Item details: usual price and usual range.
- One retention default (30 days) for hourly history in both places
- Settings: "Usual price looks back" (7, 14, 30 days) and "Keep daily prices for"
- Item chart (`Tradewright_MarketChart.lua`): range buttons for 48 hours, 14 days and 90 days; the daily ranges draw the day's price and the usual price as a flat line. The chart's hover shows each day's low and high.
- Tooltip: one line "Usual" with the usual price and its range in brackets; "7-day avg" until an item has a usual price (`FillPriceBaseline`, `TooltipLogic.BuildLines`)
- Not done: the usual range as a shaded band. The chart's `paint` function is over the lint limits and may not grow; a band needs that function split first.

## Acceptance criteria

- [x] After scans on two different days, the first day has one `history.daily` entry per scanned item (offline test passes)
- [x] Daily entries survive `/reload`, a compaction and a relog
- [x] One listing at a tenth of the normal price on one day does not move the usual price
- [x] An item with fewer than 5 days of history still classifies as today (7-day average)
- [x] An item whose price never moved (MAD 0) shows a usual price and a percentage, and no error
- [x] Deals to buy and Market movers use the usual price; their thresholds still come from Settings
- [x] The item chart offers 14-day and 90-day ranges with the usual price as a line
- [x] The usual range is drawn as a band (not done, see Scope)
- [x] The tooltip shows the "Usual" line with its range
- [x] Offline tests: rollup of a day, median with an even and an odd count, MAD 0, window shorter than history, missing days

## Verification

```bash
npm test
```

In-game: full scan today and tomorrow → Market shows `Usual` for scanned items after day 5, "-" before → item details chart switches between 48 hours, 14 days and 90 days.

## Dependencies

- None

## Out of scope

- Weighting recent days more than old ones
- A scan value built from the price steps (F41 can feed it later)
- Detecting that a patch moved the price level (candidate F45)
