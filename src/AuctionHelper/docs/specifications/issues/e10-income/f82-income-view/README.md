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

- New `AuctionHelper_IncomeDashboard.lua` in `AuctionHelper_UI` (all four UI TOCs), opened from a new "Income" sub-tab; the Overview's dashboard views are now one table (`DASHBOARD_VIEWS` in `AuctionHelper_OverviewTab.lua`)
- Period buttons (7 / 30 / 90 days / all time, the setting shared with Sales) and a character dropdown (`income.character`, default all)
- Card, number column and period buttons are shared with the Sales view (`CreateDashboardCard`, `DashboardNumberColumn`, `CreatePeriodButtons`, `StylePeriodButtons`)
- Stat row: Earned, Spent, Net, Biggest source (with its share of gold in)
- Chart: gold in and gold out per day (two lines, net in the tooltip)
- "Where gold comes from" table: Source, In, Out, Net, Share, A day. Hovering Auction house shows the period's auction sales split into crafted, resold, farmed, not known (F81)
- "What item types earn" table: item class · subclass, Sales, Earned, Share, Sold (sell rate); tooltip lists the three best-earning items of that type
- `IncomeLogic.SummarizeIncome`, `SourceRows`, `SplitSalesByOrigin`, `SummarizeItemTypes`
- Sell rate = sold ÷ (sold + expired + cancelled) with F44, "-" while the ledger holds no expired or cancelled auctions
- Time to sell is left for later: posted auctions are only recorded by the bulk poster today, so it would read "-" almost everywhere (candidate once F44 records postings)

## Acceptance criteria

- [ ] The sources in the table add up to the stat row's Earned and Spent
- [ ] Switching the period changes every number and the chart
- [ ] A Heavy Hide sale shows under Trade Goods → Leather
- [ ] Without F44, Sell rate shows "-" and nothing else breaks
- [ ] The Auction house tooltip splits the period's auction sales by origin
- [ ] Choosing one character shows only that character's gold
- [ ] Offline tests: income summary, source rows, sales split, item-type rows, empty data

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
