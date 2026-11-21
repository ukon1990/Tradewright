# F114 — Split the Professions and Inventory files

## Summary

Split the big Professions and Inventory files along the seams the audit found, so each file has one job and stays under 500 lines where it can.

## Context

- `AuctionHelper_CraftsEngine.lua` (2533 lines) does six jobs. Seams: expansion tags and AH cut; categories; reagent planner (slot classification, vellum, target-quality search); craft evaluation (the context table `c`, to be renamed); opportunities (cache, chunked evaluation, filters); reading the open profession window; concentration.
- `AuctionHelper_ItemAnalytics.lua` (1331): quality rank; history store and compaction; quantity history; wallet history; item detail snapshot. `ApplyItemDetailTimeSeriesGraph` (194 lines, UI code) belongs in `AuctionHelper_UI`.
- `AuctionHelper_CraftingOrdersMaterials.lua` (1265, retail only): order reagents (pure); work queue; view buttons; context menus.
- `AuctionHelper_LiveUpdate.lua` (708): fingerprinting can move to its own file.
- `AuctionHelper_Integrations.lua` mixes TSM/Auctionator adapters, money formatting (belongs in core) and material cost estimates. `GetPreferredAddonPrice` returns the latest AH price, not an addon price.
- `AuctionHelper_InventoryTable.lua`: `BuildInventoryRowFromSnapshot` takes 6 params.

## Scope

- One file split per slice and per commit; move code first, then rename, never both in one commit
- New files in all four TOCs of their addon; load order kept
- Rename on the way: `c` → `evaluation`, `st` → `planState`, `w` → `workItem`, `ev` / `ck` / `p` → full words, `oopMatCost` → `outOfPocketMatCost`, `GetPreferredAddonPrice` → `GetLatestObservedAhPrice`
- Concentration code in one file, clearly retail-only
- Options tables instead of 6+ parameters (`RecordItemQuantityObservation`, `EnrichInventoryRowAnalytics`, `BuildInventoryRowFromSnapshot`)

## Acceptance criteria

- [ ] No file in `AuctionHelper_Professions` or `AuctionHelper_Inventory` is over 700 lines; new files are under 500
- [ ] Each new file starts with one sentence saying what it is for
- [ ] All four TOCs list the same files (`npm test` checks)
- [ ] Lint baseline shrinks; `npm test` passes

## Verification

```bash
npm test
```

In-game (full client restart): profession Scan, Crafts tab profit, craft queue, item detail graph, inventory snapshot and ledger work on Forever; crafting orders on retail.

## Dependencies

- F113 (tests in place before code moves)

## Out of scope

- Behaviour changes
