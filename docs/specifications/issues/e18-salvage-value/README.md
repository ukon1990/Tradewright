# E18 — Value of disenchanting, prospecting and milling

## Summary

Recipes and spells that destroy items of the player's choice for random results get a cost and a value: the leveling route and the craft queue pick the cheapest ore or herb, every disenchant, prospect and mill is recorded with what it gave, researched starting yields ship with the addon, and the player's own records take over as they grow.

## Context

- `EvaluateCraftScenario` returns nil for a recipe with no crafted item, so the leveling route counts Prospecting and Milling as "no price" and the craft queue shows "Profit unknown" with an empty cart.
- Loot from a spell cast on an item is not recorded: `SourceLogic.SourceOfGUID` gives nil for item GUIDs, and loot tallies keep no quantities.
- No yield table exists in the pack. Earlier epics left this out as "candidate F63" because published tables conflict.
- Yields are not fixed: they shift with skill and, on retail, with profession talents. Research: [gold making market strategies](../../../research/gold-making-market-strategies.md), section on destroy chains.

Decisions taken with the user:

- Starting yields are researched on the web and shipped for Forever; retail ships none and fills from own records, as the only retail numbers found are other addons' tables
- Nothing is taken from another addon; web sources such as wikis and published counts are fine
- Own outcomes are recorded from the start, on both clients
- Forever has disenchanting only: it has no Jewelcrafting or Inscription, so prospecting and milling are retail only

Terms: code says **salvage** for the three actions together (the game API's word) and **yield** for what one input gives on average. The player sees the game's own action names, never "salvage". "Destroy" stays the word for deleting an item.

## Scope

- F134: cheapest input for prospecting and milling in the leveling route and craft queue (retail)
- F135: yield maths, pure and offline tested
- F136: record outcomes in game
- F137: researched starting yields, shipped
- F138: use the value for profit, give-back and tooltips

## Acceptance criteria

- [ ] F134 to F138 done
- [ ] A queued Prospecting or Milling line shows a cost and its ore or herb in the cart
- [ ] After disenchanting, prospecting and milling in game, the saved counts match what dropped
- [ ] An item that can be disenchanted, prospected or milled shows a value, marked as an estimate until own records exist
- [ ] `npm test` passes

## Verification

```bash
npm test
```

In game on both clients (full client restart, new files): see each feature.

## Dependencies

- E14 (leveling route), E16 (sightings store, seal and build flow), E06 (usual price and sales a day for valuing outputs)

## Out of scope

- Casting or automating any of the actions
- Other conversions (transmutes, combining essences, scrapping)
- Sharing records between players in game
