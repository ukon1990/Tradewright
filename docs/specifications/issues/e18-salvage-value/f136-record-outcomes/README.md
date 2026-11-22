# F136 — Record outcomes

## Summary

Each time the player disenchants, prospects or mills, the destroyed item and everything received are written to the sightings store.

## Context

- `Tradewright_LootSightings.lua` reads loot windows but skips loot whose source is an item, and reads no quantities.
- The item log (`Tradewright_ItemLog.lua`) already compares bag counts before and after a change; an item that leaves for no known reason is dropped.
- Retail prospecting and milling are crafts (`C_TradeSkillUI.CraftSalvage`, results in `TRADE_SKILL_ITEM_CRAFTED_RESULT`); disenchanting, and prospecting on Forever, are spells followed by a loot window. Which signals each client really gives is not verified.

## Scope

- First: check in game on both clients which signals exist (cast succeeded with the spell id, loot window with quantities, crafted-result event, bag change) and write the findings into this issue
- New module beside `Tradewright_LootSightings.lua` with its own event frame, saving through `SalvageLogic.RecordOutcome` into `TradewrightSourcesDB`
- Start of an outcome: the player's Disenchant, Prospecting or Milling cast succeeding (by spell id, never by name), or the retail salvage craft
- Results: the loot window that follows, or the crafted-result events
- The destroyed item: the item that left the bags
- `/tradewright sources seal` and `npm run sources:build` carry the records like other sightings
- Only watches; casts nothing

## Acceptance criteria

- [ ] After a few disenchants, prospects and mills, the saved casts, inputs and quantities match what dropped, on each client that has the action
- [ ] Loot that follows no such cast is not recorded as an outcome
- [ ] An interrupted or failed cast records nothing
- [ ] New API names in `.luacheckrc`; new file in all four TOCs

## Verification

```bash
npm test
```

In game on Forever and retail (full client restart): do each action a few times, log out, read `TradewrightSourcesDB`.

## Dependencies

- F135

## Out of scope

- Showing the records (F138)
