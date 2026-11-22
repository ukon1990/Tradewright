# F130 — Collect sightings

## Summary

Vendors, trainers and loot are written to the sightings store as the player meets them. Nothing is automated: every record follows a window the player opened.

## Context

- `rememberMerchant` (`Tradewright_VendorSource.lua`) and `ReadOpenTrainerRecipes` (`Tradewright_TrainerRecipes.lua`) already read the open window.
- Loot is not read anywhere. `LOOT_OPENED` with `GetLootSourceInfo(slot)` gives the GUIDs each slot came from; `IsFishingLoot()` marks fishing. Unverified on Forever; each call is capability-checked.
- A mob that is skinned, mined or herbed opens a second loot window from the same GUID; the gathering cast just before it tells the two apart.

## Scope

- Vendors: record the NPC id, faction and place once, items under the NPC key
- Trainers: account-wide, under the NPC key
- Loot: tally per source (`n<npcID>`, `o<objectID>`, `f<mapID>` for fishing, a `g` prefix for gathering from a corpse), add the player's place
- Only items that matter are tallied: item classes trade goods, reagent, gem and recipe
- A recipe item on sale or looted is a source of the recipe it teaches, matched by name

## Acceptance criteria

- [ ] Opening a vendor, a trainer, a corpse, a node and a fishing catch each leaves a record
- [ ] Grey junk and gear leave none
- [ ] A client lacking a loot call records nothing and shows no error

## Verification

```bash
npm test
```

In-game on Forever: do each of the above, `/reload`, read `TradewrightSourcesDB`.

## Dependencies

- F129

## Out of scope

- Loot rolled or master-looted to someone else
