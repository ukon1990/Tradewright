# F135 — Yield maths

## Summary

Pure logic for recorded salvage outcomes: the saved shape, adding an outcome, the average yield of an input and its value, and which numbers to trust.

## Context

- Loot tallies in `SourceLogic` count loots that held an item, not quantities, so they cannot give a yield.
- `SourceLogic` is close to the file size limit; this is its own file.
- Outputs are valued like farmed items: `FarmLogic.ItemValue` (better of vendor price and usual price after the cut, the usual price only when the item sells).

## Scope

New `src/Tradewright/src/util/Tradewright_SalvageLogic.lua`, no game API:

- Saved shape per action and input group: casts, inputs destroyed, total quantity per item received; kept in epochs like the loot tallies so it can be shipped, and per character (talents differ per character)
- Input group: the item id for ore and herbs; for disenchanting the item's quality, item level band, armor or weapon, and expansion (exact values are saved, grouped when read)
- `RecordOutcome`, `Yield` (rate per input for each result, with the casts behind it), `Value` (sum of rate times the result's value, given a function that values an item)
- Which numbers win: the character's own records once they hold enough casts, else all own records, else shipped yields; the answer says which and how many casts
- Shipping and pruning of the records, called from the sightings store's `ShipStore` and `Prune`

## Status

Implemented (`Tradewright_SalvageLogic.lua`, `tests/test_salvage_logic.lua`). Differs from the scope:

- Records are not kept per character. A store holds one record per action and input; the player's own store wins over everything else from 20 casts, which covers skill and talents for the usual case of one character per profession
- Researched yields are a separate source (`{ [groupKey] = { [itemID] = quantity per input } }`), not counts, so they never mix with counted outcomes: counted outcomes replace them from 20 casts
- Shipping and pruning stayed in `SourceLogic`, made to work for any table of counts per epoch (`tallies` and `yields`)
- Disenchanted gear is grouped in bands of five item levels; F137 may change the band for retail

## Acceptance criteria

- [x] Offline tests: recording, yield with quantities, value, the order of trust and its threshold, disenchant grouping, shipping once per epoch, pruning
- [x] No game API in the file

## Verification

```bash
npm test
```

## Dependencies

- E16 F129 (sightings store, epochs)

## Out of scope

- Detecting outcomes in game (F136)
- Splitting records by skill level or talent choice
