# F113 — Tests for the core logic, then break up the most complex functions

## Summary

Put meaningful offline tests in front of the logic a refactor is most likely to break, then break the functions with complexity over 40 into named steps and pure helpers.

## Context

- None of `AuctionHelper_AuctionData`, `AuctionHelper_Professions`, `AuctionHelper_Inventory` or `AuctionHelper_UI` is loaded by a test.
- Functions with complexity over 40 (from `scripts/lint-baseline.json`):
  - `Data.lua CollectSpecializationTreeForSkillLine` 64
  - `LiveUpdate.lua ApplyLiveProfessionMergeForSkillLineID` 61 (two algorithms: full merge and incremental merge)
  - `CraftingOrdersMaterials.lua getOrderReagentDescriptor` 59 (the same six lookup paths written out for four fields)
  - `ProfessionCraftPanel.lua OnProfessionRecipeCraftedResult` 56 (F112 does the queue part)
  - `Auction.lua BuildAuctionCraftCartRows` 53, `GetLiveAuctionSearchAggregate` 52 (a commodity loop and an item loop)
  - `CraftingOrdersMaterials.lua CraftingOrderViewRefreshButtons` 53
  - `InventoryUI.lua FilterInventoryRows` 47 (almost pure)
  - `ProfessionCraftPanel.lua renderProfessionRecipe` 46
  - `CraftsEngine.lua FilterCraftRows` 43 (its `profitState` chain fits a table), `ExtractCrafterShoppingReagentsFromOrder` 43
  - `Chart.lua paint` 42, `SpecCatalog.lua AttachSpecCatalogMetadata` 42
- Pure logic worth testing first: the reagent planner (`PickCheapestReagentsPerSlot`, target-quality search), `FilterCraftRows`, `FilterInventoryRows`, order reagent resolution, the live-search aggregate fold, the cart merge, the chart's axis steps (`niceStep` / `niceScale`).

## Scope

- One slice per function, in the order above by risk (pure first, hot path last)
- Each slice: characterization tests of today's behaviour → move pure parts to a logic file (`ForeverLogic`, `MaterialLogic`, or a new `*Logic.lua`) → split the rest into named functions → tests still green
- `getOrderReagentDescriptor`: a path list and one `firstField(entry, paths, key)`
- `FilterCraftRows` / `FilterInventoryRows` / `FilterMarketRows`: a list of `{name, predicate}` filters
- Tests are about behaviour that could break: profit and cost numbers, which reagent wins, which rows a filter keeps, Forever vs retail branches. No tests for getters or layout

## Acceptance criteria

- [ ] Every listed function is at or under complexity 10 and 40 lines, or its baseline entry shrank and the remaining work is a named follow-up
- [ ] Each pure part has tests that fail if its result changes
- [ ] No behaviour change in-game
- [ ] Lint baseline shrinks; `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: Crafts tab shows the same profit for five known recipes as before; inventory filters give the same rows; profession window live update still picks up a newly learned recipe. On retail: a crafting order's reagents list as before.

## Dependencies

- F105, F109, F111 (cart and aggregate use the normalizers), F112 (queue part of `OnProfessionRecipeCraftedResult`)

## Out of scope

- Moving functions between files (F114 to F116, F118), except new pure logic files
