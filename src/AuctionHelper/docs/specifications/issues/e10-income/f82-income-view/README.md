# F82 — Income view

## Summary

An Income sub-tab in Overview shows earned, spent and net gold, which sources bring the most, how auction sales split into crafted, resold and farmed, which item types earn, and how fast they sell.

## Context

- Overview has Gold, Sales and Characters sub-tabs. `AuctionHelper_SalesDashboard.lua` is the model: stat row, time-series chart with period buttons (`sales.periodDays`), two reusable tables with item tooltips.
- Item class and subclass come from `C_Item.GetItemInfoInstant` (`classID`, `subclassID`) and their names from `GetItemClassInfo` / `GetItemSubClassInfo`.
- Time to sell matches `posted` events in `auction.transactions.events` to sales of the same item, oldest first.
- `AuctionHelper_OverviewTab.lua` is in the lint baseline; adding the sub-tab must not grow its over-limit functions.
- Design: add a mockup to the "AuctionHelper Screens" canvas before building.

## Scope

- New `AuctionHelper_IncomeDashboard.lua` in `AuctionHelper_UI` (all four UI TOCs), opened from a new "Income" sub-tab
- Period buttons (7 / 30 / 90 days / all time, shared setting with Sales) and the account / character choice the Overview already uses
- Stat row: Earned, Spent, Net, Biggest source (with its share)
- Chart: gold in per day, one stacked series per source
- "Where gold comes from" table: Source, In, Out, Net, Share, A day. The Auction house row expands into crafted, resold, farmed, unknown (F81)
- "What item types earn" table: item class → subclass, Sales, Earned, Share, Sell rate, Time to sell; tooltip lists the top items in that type
- `IncomeLogic.SummarizeIncome(days, now, since)` → totals, per source, daily series
- `IncomeLogic.SummarizeItemTypes(sales, classOf, postings, misses)` → rows per type
- Sell rate = sold ÷ (sold + expired + cancelled) with F44, "-" without it; time to sell is the median, "-" under 3 matches
- Empty state explains that tracking starts when the feature ships

## Acceptance criteria

- [ ] The sources in the table add up to the stat row's Earned and Spent
- [ ] Switching the period changes every number and the chart
- [ ] A Heavy Hide sale shows under Trade Goods → Leather
- [ ] Without F44, Sell rate shows "-" and nothing else breaks
- [ ] Auction house split sums to the Auction house row
- [ ] Choosing one character shows only that character's gold
- [ ] Offline tests: income summary, item-type rows, median time to sell, empty data

## Verification

```bash
npm test
```

In-game on Forever: after F80 has run for a session with vendor, quest, loot and auction income → `/ah` → Overview → Income: each source shows, the largest is named in the stat row, and the item-type table lists sold items under their class.

## Dependencies

- F80 (sources), F81 (auction split), F44 (sell rate; optional)

## Out of scope

- Goals or alerts on income
- Export of the income data (candidate for the Export tab)
