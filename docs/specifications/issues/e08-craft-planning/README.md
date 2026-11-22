# E08 — Craft planning

## Summary

The Crafts tab stops at "this craft is profitable". This epic adds the three things that decide whether the profit is real: the cheapest way to get each material, how many the market takes, and which cooldown crafts are ready.

## Context

- Research and sources: [WoW gold making market strategies](../../../research/gold-making-market-strategies.md), section "Crafting margins persist where capacity is capped".
- `EvaluateCraftScenario` (`Tradewright_CraftsEngine.lua`) computes `profit = saleNet × outQty - matCost` and ROI. A material is priced from: vendor price when the recipe marks it vendor-sourced, the ledger buy average, the TSM `Crafting` string, then the market fallback. Owned materials are handled by `crafts.reagentSourceMode` (`owned_first`, `mixed`).
- `craftOpportunityCostIndex` already holds the lowest craft cost per output item across characters.
- Recipes are stored per character, so the addon knows who can craft what. No cooldown data is read anywhere.
- The research's findings: tools agree on "cheapest of vendor, auction, craft it yourself" for materials; profits on items that do not sell are paper profits; margins last where capacity is capped, which in a Classic-style game means cooldown crafts.
- Design: [Crafts, sources and restock](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldCrafts).

## Scope

- F60: cheapest way to get each material
- F61: how many to make
- F62: cooldown crafts

## Acceptance criteria

- [x] F60 to F62 done
- [x] Retail-only systems (concentration, crafting orders, quality tiers) behave as before
- [x] A craft with no sells-a-day estimate never gets a "Make" number
- [x] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: scan professions on two characters, full auction scan → Crafts → a craft with a craftable material shows "Craft" as its source → Make shows a number for items that sell → a cooldown recipe shows ready or the time left.

## Dependencies

- E06 Market signals: F42 (sells a day), F43 (fees); F40 for the usual price as sale basis
- E03 Craft mail (implemented): the craft queue and its "To craft" / "To buy" lists

## Out of scope

- Disenchant, prospecting, milling and conversion values (candidate F63: the published yield tables conflict, so they would have to be learned from the player's own results)
- Retail proc maths (multicraft, resourcefulness)
- Profession leveling plans (now [E14](../e14-profession-leveling/README.md))
