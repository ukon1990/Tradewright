# F53 — Weekday pattern in the Market item view

## Summary

The Market item view shows, per weekday, how far an item's price usually sits above or below its own trend, once your scans cover enough weeks to say so. It tells you when this item tends to be cheap or dear on your realm, from your data.

## Context

- The research found no study or dataset at any evidence tier showing weekday or hour-of-day price cycles in WoW; the "buy on day X" advice is community lore and its sources disagree. A pattern is therefore learned per item from the player's own history and shown only when the data supports it.
- The method is classical decomposition with medians: divide each day's price by a centred 7-day rolling median, then take the median ratio per weekday ([Hyndman & Athanasopoulos, section 3.4](https://otexts.com/fpp3/classical-decomposition.html)). It gives no estimate at the ends of the series and assumes the pattern does not change.
- Scans happen when the player is at the auction house, so hour-of-day buckets would be mostly empty; this feature works on days.
- Design: "By weekday" in [Market, item selected](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldMarketItem).

## Scope

- `ForeverLogic.WeekdayPattern(daily, opts)`, pure → `{byDay = {[1..7] = pct}, weeks, cheapest, dearest}` or nil:
  - ratio per day = daily value ÷ median of the 7 days centred on it (days without 4 or more neighbours are skipped)
  - per weekday the median ratio, normalised so the seven average 1
  - nil unless every weekday has `opts.minPerDay` (3) ratios, the history spans `opts.minWeeks` (4) weeks, and the spread between weekday medians is larger than the typical spread within a weekday
- Weekdays follow the realm's calendar day, the same day boundary F40 uses
- Item details: a "By weekday" strip of seven cells (percentage and day name) and the line "Cheapest on X, dearest on Y · from N weeks of scans"
- When the function returns nil the strip is replaced by one muted line: "Not enough scans yet to show a weekday pattern."
- The same function run on daily quantity is kept for F72; not shown here

## Status

Implemented:

- `Tradewright_WeekdayPattern.lua` (core, pure): `WeekdayPattern.Build(daily, opts)` with the rules above. The history must span 5 weeks. The gap between the cheapest and dearest weekday must be at least 3% and more than 8 standard errors of a weekday median. That strictness was measured on simulated prices: with pure noise about 2% of items show a false pattern at 6 weeks of daily prices and under 0.5% at 12 weeks, while a 10% weekday bump is found whenever day-to-day noise is 3% or less. A first, looser rule reported a pattern for 71% of pure-noise items and was dropped.
- `GetWeekdayPattern(storageKey)` (AuctionData), cached like the usual price
- Item details: one line, "By weekday: Cheapest Wed -6%, dearest Tue +8% (6 weeks)", or "Not enough scans yet"

Differs from the scope:

- One line of text instead of a strip of seven cells: the item view is built by a function that is over the lint limits and may not grow
- Weekdays are UTC days, as in F40
- The quantity pattern for F72 is not computed yet; `Build` reads the daily price only

## Acceptance criteria

- [ ] An item with 6 weeks of daily prices that are 10% higher every Tuesday shows Tuesday near +10% and names it dearest
- [ ] An item with random daily prices shows the "not enough" line, not a pattern
- [ ] An item with 2 weeks of history shows the "not enough" line
- [ ] No weekday pattern is shipped with the addon; nothing appears for an item without its own history
- [x] Offline tests: planted weekly pattern, noise only, short history, missing weekdays, a level shift in the middle of the window

## Verification

```bash
npm test
```

In-game: after 4 or more weeks of scans, open a commodity you scan often → the strip shows or the "not enough" line does.

## Dependencies

- F40 (daily history)

## Out of scope

- Hour-of-day patterns
- Suggesting a day to buy or sell on the Opportunities lists
- Patch and reset-day calendars
