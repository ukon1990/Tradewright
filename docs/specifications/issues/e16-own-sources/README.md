# E16 — Own source database

## Summary

The pack stops reading prices from other addons and builds its own record of where things come from: which NPC sells or teaches what, which mobs and nodes yield which reagents, and where they are. The record grows from what the player sees, can later ship inside the addon, and saved data never repeats what the shipped file already says.

## Context

- Four outside addons are read today, all optional: TradeSkillMaster (prices for unscanned items, sale rate, Deals baseline), Auctionator (last-seen price), the Questie database (who sells an item and where, no price) and TomTom (waypoint arrow).
- There is no NPC, drop or source database in the pack. Vendors are remembered on `MERCHANT_SHOW` (`TradewrightAuctionDB.vendorSellers`, by NPC name), trainers on `TRAINER_SHOW` (per character). Drops and gathering are not recorded, so the leveling route shows "source unknown" for every recipe no trainer was seen teaching.
- Vendor stock, drops and NPC positions are not in the game client. Forever adds its own items (ids from 200000), so published Classic data would miss them.
- The Questie database is GPL-3; no data is copied from it.

Decisions taken with the user:

- The database is built from own sightings: vendors, trainers, recipe sources, reagent drops and gathering
- Collected data can later be shipped in the addon; a user's saved data then holds only what differs from or adds to the shipped file
- The TradeSkillMaster and Auctionator fallbacks are removed now; unscanned items have no price and the sale-rate column is hidden until F42 gives an own figure
- The Questie vendor lookup and the TomTom arrow stay as optional extras, each behind one function in `Tradewright_VendorSource.lua`

Size is bounded: at most 12 places per NPC or node per map on a 2 % grid, loot kept as counts, and only crafting-relevant items counted.

## Scope

- F128: drop the TradeSkillMaster and Auctionator price fallbacks
- F129: sightings store and its pure logic
- F130: collect vendors, trainers and loot into the store
- F131: show sources in the leveling route and reagent tooltips
- F132: shipped source data, pruning of saved duplicates, build script

## Acceptance criteria

- [x] F128 to F132 done
- [x] No code reads `TSM_API` or `Auctionator`; no TOC lists them
- [x] With Questie disabled, a reagent sold by a visited vendor still gets a waypoint
- [x] A recipe seen at a vendor or looted no longer reads "source unknown" in the leveling route
- [x] After shipping collected data, the saved store holds no fact the shipped file states
- [x] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever (full client restart, new files): open a vendor and a trainer, loot a mob, gather a node, fish → `TradewrightSourcesDB` in `SavedVariables/Tradewright.lua` holds them → cart tooltip of a looted reagent names the source.

## Dependencies

- E14 F124 (trainer recipes), vendor sources in `Tradewright_VendorSource.lua`
- E06 F42 (own sold-per-day) brings the sale-rate column back

## Out of scope

- Copying data from Questie or any other addon or website
- Removing the Questie lookup and the TomTom arrow
- Drop data for gear and junk
- Sharing sightings between players in game
