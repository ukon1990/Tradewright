# E20 — Destroying

## Summary

Disenchanting gets its own place in the pack: the leveling route can count crafted items at what disenchanting them gives, a new dashboard tab shows which owned items are worth more destroyed than sold, and a search finds auctions of gear listed below their disenchant value. Every view says how good the numbers behind it are, and the search refuses to suggest buys when they are not good enough. Forever has disenchanting only; on retail the same views also cover prospecting and milling.

## Context

- E18 gives every disenchantable item a value: shipped classic yields on Forever (F137), the player's own counted outcomes (F136), and `Tradewright:GetSalvageValue(action, input)` with `GetSalvageInput` (F138). Tooltips already show it.
- F138 left out, on purpose: suggesting which items to disenchant, and auction house searches for items worth destroying. This epic picks those up.
- The leveling route's give-back choice (`professions.leveling.giveBack`: vendor, auction, none) is read by `LevelingRouteLogic.GiveBack`; a crafted item's disenchant value is not one of the choices, so leveling with a disenchanter on hand looks more expensive than it is.
- The Opportunities tab already lists auctions worth buying from the last full scan ("Sure things", "Flips") and judges its history with `GetHistoryCoverage`; the destroy search follows that pattern.
- Yields on Forever are shown as estimates: the research note ([salvage yields](../../../research/salvage-yields.md)) has the classic table well supported, but whether Forever uses it is not confirmed, and Forever's own new items appear in no source.

Decisions taken with the user:

- A new dashboard tab for destroying; the auction house search is a view in that tab
- The leveling route gets "Disenchant" as a give-back choice, usable whether or not any of the player's characters can disenchant
- The search tells the player when the data is not good enough, and why, instead of showing doubtful rows

Terms: code keeps **salvage** (E18) for the three actions together. The player sees the game's own action names; the tab is called "Destroying" as the user asked. "Destroy" in code still means deleting an item, so new code names the tab and its logic after salvage (`SalvageTab`, `SalvageCheckLogic`), the label only says "Destroying".

## Scope

- F141: "Disenchant" as a give-back choice in the leveling route
- F142: data quality check, pure and offline tested
- F143: Destroying tab with owned items
- F144: auction house search for gear below its disenchant value
- F145: chances per material for disenchanting
- F146: Destroying tab with stat tiles, kind of gear, empty state
- F147: who can disenchant an owned item

## Acceptance criteria

- [ ] F141 to F147 done
- [ ] With "Disenchant" chosen, a leveling route of Leatherworking on Forever counts gear it crafts at its disenchant value and other items at their vendor price
- [ ] The Destroying tab lists owned disenchantable items with the better choice for each
- [ ] The search lists auctions below disenchant value, or says what data is missing
- [ ] Nothing casts, buys or destroys by itself
- [ ] `npm test` passes

## Verification

```bash
npm test
```

In game on Forever (full client restart, new files) and retail: see each feature.

## Dependencies

- E18: F136 and F138 are implemented but not yet checked in game; check them on Forever first, as every number here rests on them
- E06 (usual price, sales a day), E07 (Opportunities patterns, history coverage)

## Out of scope

- Casting or automating Disenchant, Prospecting or Milling
- Buying without a click per purchase
- Yields for Forever's own new items (no source exists)
- Sending items to an enchanter by mail
