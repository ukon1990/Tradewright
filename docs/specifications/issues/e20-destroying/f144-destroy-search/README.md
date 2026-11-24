# F144 — Auction house search for gear below its disenchant value

## Summary

A second view in the Destroying tab lists auctions from the last full scan whose buyout is below the item's disenchant value, less a margin the player sets. Each row has a Search button that runs the normal live search at the open auction house, so the player can buy by hand. When the data is not good enough, the view lists what is missing instead of rows.

## Context

- The full scan keeps the cheapest buyout per item (`Tradewright_AuctionStore.lua`, market insights); the Opportunities views build buy lists from it ("Sure things": listed below vendor price) and run live searches from a row.
- Live search and buying go through public APIs on a click (`Tradewright_AuctionLiveSearch.lua`, `Tradewright_AuctionClassicBuy.lua`, `Tradewright_AuctionBuy.lua`). No protected API, no buying without a click.
- Disenchant value per item: `GetSalvageValue("disenchant", GetSalvageInput(...))`. On Forever these are often estimates.

## Scope

- View "Below disenchant value" beside "Owned" in the Destroying tab
- Rows: scanned gear with a buyout and a disenchant value, where buyout is below value minus margin. Columns: item, buyout, disenchant value, gain, gain in percent, count listed
- Margin setting (percent, default 15) saved per account; the pure filter and gain maths offline tested
- Search button per row: with the auction house open it runs the live search for that item and refreshes the row with what the search found; closed, the button is disabled with a tooltip saying to open the auction house
- Quality gate from F142: "none" shows the reasons only; "weak" shows rows under a warning naming the reasons; "good" shows rows
- Rows whose own yield is an estimate carry a mark, even when the check is "good"

## Status

Implemented; offline tests and lint pass. Not yet checked in game.

- View "Below disenchant value" beside "Owned" in the Destroying tab; the choice is saved as `salvage.view`. The views live in `Tradewright_UI/src/ui/Tradewright_SalvageViews.lua`, and `Tradewright_SalvageTab.lua` is the shell both share (view buttons, data strip, table, side pane)
- Rows from `Tradewright:GetSalvageBuyRows(onReady)` in `Tradewright_Inventory/src/modules/Tradewright_SalvageBuys.lua`: every scanned item with a disenchant value goes through `SalvageLogic.BuyBelowValue(items, margin)`; rebuilt when the scan, the margin or (every 30 seconds) item info changes
- A row passes when its cheapest buyout is below value × (1 − margin). Units listed below that limit and their cost come from the price steps (only the cheapest unit without them); gain = units × value − cost; gain % = gain ÷ cost. No auction cut, as nothing is sold
- Columns: item, buyout, disenchant value ("~" for researched yields), gain, gain %, units listed below the limit; sorted by gain
- Margin dropdown (5–30%, default 15%) saved as `salvage.buyMargin`
- Quality gate: the check runs over every scanned item with a disenchant value, so it judges the data the search rests on. "none" leaves the table empty and the strip names what is missing; "weak" shows rows under the warning strip; "good" shows rows
- Search: a button in the side pane, and right-click on a row, open the item at the auction house (`OpenItemInAuctionHouse`, the same as Opportunities). With the auction house closed the button is disabled and a line under it says to open it. A live search refreshes the view (`RefreshViewsAfterLiveSearch`)
- The prospecting/milling choice shows only in the Owned view; the auction view is for gear and disenchanting

- The strip gathers per-material reasons into one sentence per kind ("Under 5 days of prices for Strange Dust, Soul Dust and 10 more."), via `SalvageCheckLogic.GroupReasons`; hovering it lists every reason (up to 20)
- Found while checking in game: the daily price history was rolled up only during a one-time storage migration, so on most installs it stayed empty and every item read 0 days of prices (and had no usual price). The rollup now runs at every login (`Tradewright_Events.lua`, tested in `test_events.lua`)

Differs from the scope:

- The Search button sits in the side pane for the selected row (plus right-click on any row), not in each row: the table has no button cells. The disabled state is explained by a line of text, not a tooltip, as in Opportunities

Known limits:

- Gear whose item info the game has not loaded yet is left out until the next rebuild
- On Forever most values rest on researched yields until 20 own disenchants of a kind are counted, so the strip will usually read "rough"

## Acceptance criteria

- [ ] With a fresh full scan and priced materials, the view lists gear below value, and Search finds it at the auction house
- [ ] Without a full scan, the view says to do one and lists no rows
- [ ] A material with too few days of prices is named in the warning
- [ ] Nothing is bought without the player's click
- [x] Offline tests for the filter and the gain maths
- [x] New texts written as `L["..."]` (no translation file exists yet)

## Verification

```bash
npm test
```

In game on Forever: full scan, open the view, Search a row, buy one, disenchant it, and compare with the value shown.

## Dependencies

- F142, F143

## Out of scope

- A search for ore or herbs below prospecting or milling value (can follow on retail with the same view)
- Buying in bulk
