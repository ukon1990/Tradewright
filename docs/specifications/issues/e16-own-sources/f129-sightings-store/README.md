# F129 — Sightings store

## Summary

One account-wide store for everything seen about NPCs, nodes and what they sell, teach or yield, with the pure rules that keep it small.

## Context

- Vendor sightings live in `TradewrightAuctionDB.vendorSellers[itemID][npcName]`, trainer sightings per character in `TradewrightProfessionsDB`. Both are keyed by NPC name and repeat the NPC's place on every item.
- The NPC id is in the unit's GUID (`Creature-0-…-<npcID>-…`); loot sources give GUIDs too.

## Scope

- New SavedVariable `TradewrightSourcesDB` in the four core TOCs and `.luacheckrc`:
  - `collectorID`, `epoch`
  - `npcs[npcID] = { name, faction, places = { { mapID, x, y } } }`, `objects[objectID] = { places }`
  - `sold[itemID][npcKey] = { price, limited, seenAt }`
  - `taught[skillLine][recipeName] = { skillRequired, cost, seenAt, npcs = { [npcKey] = true } }`
  - `tallies[epoch][sourceKey] = { opened, items = { [itemID] = count } }`
- New pure helper `Tradewright_SourceLogic.lua`: id from a GUID, place list capped at 12 per map on a 2 % grid, tally sums, item source lookups
- New core module `Tradewright_Sources.lua`: owns the store and the reads
- One-time move of `vendorSellers` and per-character `trainerRecipes` into the store under `"name:<npc name>"` keys; an id-keyed sighting of the same name replaces them
- `GetVendorSource` and `GetTrainerRecipes` return the shapes they return today

## Status

Implemented and checked in game. Differs from the scope:

- Places are stored without a zone name; readers name the zone from the map id
- An NPC's `faction` is the faction of the characters that met it ("Horde", "Alliance", "both"); vendors are now filtered by it as trainers were
- `LevelingRouteLogic.MergeTrainerEntry` is gone and `TrainerEntries` no longer carries who was asked: the store keeps that

## Acceptance criteria

- [x] Vendors and trainers known before the update are still known after it
- [x] A mob looted any number of times holds at most 12 places per map
- [x] Offline tests: GUID parsing, place cap and grid, tally sums, move of name-keyed data, name key replaced by id key

## Verification

```bash
npm test
```

## Dependencies

- None

## Out of scope

- Collecting (F130), shipped data (F132)
