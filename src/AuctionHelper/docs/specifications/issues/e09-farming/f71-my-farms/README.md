# F71 — My farms, re-valued at today's prices

## Summary

A new Farming tab lists your saved farms with their gold an hour when you ran them and at today's prices, so you can see which farm is best now. Selecting a farm shows what dropped per hour and what each item is worth.

## Context

- F70 saves runs as item counts, coin and time. Because counts are stored, not gold, any past run can be valued again with current prices.
- Prices move whole categories after patches and as a fresh economy matures; a farm that paid last week may not pay today. Re-valuing your own loot tables is the one way to compare farms that does not rely on anyone's self-reported numbers.
- Short runs are dominated by luck on rare drops, so the list shows the number of runs and the time behind each figure.
- Main tabs are declared in `AuctionHelper_UIShell.lua`.
- Design: [Farming, my farms](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldFarms).

## Scope

- Saved farms in `AuctionHelperInventoryDB.farm.farms[name] = {zone, runs = {…}}`; each run keeps its counts, coin, vendor sales, active seconds, end time and its value when saved
- `ForeverLogic.SummarizeFarm(farm, priceFn)`, pure → `{runs, activeSeconds, thenPerHour, nowPerHour, changePct, liquidShare, coinShare, perHourByItem}` where "then" is the saved value and "now" re-values the summed counts
- New tab "Farming" between Crafts and Export: `AuctionHelper_FarmingTab.lua` and `AuctionHelper_FarmingUI.lua` in `AuctionHelper_UI`, in all four TOCs
- A segmented control: "My farms (N)" and, with F72, "What to farm"
- Stat row: best farm at today's prices, farmed in 7 days, time farming in 7 days, coin and vendor items in 7 days
- Table: Farm (second line: zone, kind, last run), Runs, Time, Then, Now, Change. Sorted by Now. Footer: "Gold an hour: Then at the day's prices, Now at today's".
- Side pane: gold an hour now and then, share that sells within a day, share from coin and vendor items, "What dropped, an hour" (Item, An hour, Worth now, with Vendor items and Coin rows), and the value-rule note
- Buttons: "Start this farm" (starts F70 with this name), Rename, Delete (with a confirm)
- Period filter: 7 days, 30 days, all
- Empty state: "No farms yet. Press Start farm, loot for a while, then save it."

## Status

Implemented:

- `FarmLogic.SummarizeFarm(farm, priceFn, opts)` (pure, offline-tested): every run folded into one, valued when saved ("Then") and at today's prices ("Now")
- `GetFarmRows()` and `DeleteFarm(name)` in `AuctionHelper_Farm.lua`
- New tab "Farming" between Crafts and Export (`AuctionHelper_FarmingTab.lua`): status and a Start farm button, four stats, the farms table (Farm, Runs, Time, Then, Now, Change, sorted by Now), and a side pane with gold an hour now and then, the two shares and up to seven items with their rate and worth an hour
- Buttons: "Start this farm" and Delete (a second click confirms)

Differs from the scope:

- **No Rename** and **no period filter** (all runs are counted)
- **The stats are over all runs,** not the last 7 days
- **Vendor items and coin are one share** in the side pane, and are not listed as separate rows under the items
- The farm column is one line of text (name, then zone and last run in grey), not the item column: table cells do not wrap

## Acceptance criteria

- [ ] Saving a run under a new name creates a farm; saving under an existing name adds a run to it
- [ ] After a scan that raises an item's usual price, that farm's Now rises and Then stays
- [ ] A farm with one 5-minute run shows "1" under Runs and its short time, not hidden
- [ ] The per-item rows add up to the farm's gold an hour
- [ ] Rename keeps the runs; Delete asks first and removes them
- [x] Offline tests of `SummarizeFarm`: several runs, re-valuing up and down, shares, a farm with no priced items

## Verification

```bash
npm test
```

In-game on Forever (restart the client: new files): save two runs in different zones → Farming → both listed → run a full scan → Now changes for farms whose loot moved in price.

## Dependencies

- F70

## Out of scope

- Charts of a farm over time
- Merging farms
- Comparing with other players' rates
