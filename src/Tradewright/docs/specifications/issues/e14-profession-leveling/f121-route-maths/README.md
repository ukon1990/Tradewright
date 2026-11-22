# F121 — Route maths

## Summary

Pure functions that turn a list of priced recipes into the cheapest leveling route: which recipe to craft over which skill range, about how many times, and what it costs. They also say which craft-queue entries a step needs.

## Context

- For one skill point, the cost of using a recipe is its cost per craft divided by the chance of a skill-up (F120) and by the points it gives per craft. Skill points are independent of each other, so picking the cheapest recipe at each point gives the cheapest route. The exception is a one-off cost to learn a recipe, handled by a separate rule below.
- Cost per craft depends on what the crafted items give back, chosen by the player: nothing, the vendor sale price, or the auction sale after the cut.
- Craft counts are expected values (`points / chance`), so the real count varies. The route is recalculated after each skill-up, and anything queued from it is adjusted (see `QueueAdjustment`).

## Scope

- New `src/Tradewright/src/util/Tradewright_LevelingRouteLogic.lua`, no WoW API, listed in all four core TOCs
- `LevelingRouteLogic.BuildRoute(request)` with `request = {fromSkill, rankCap, giveBackMode, learnedOnly, candidates}`; a candidate is `{recipeID, name, bounds, learned, learnSkill, learnCost, materialCost, vendorGiveBack, auctionGiveBack, skillUpsPerCraft}`
  - Per skill point: the candidate with the lowest `(materialCost - giveBack) / (chance × skillUpsPerCraft)` among those usable at that skill (learned, or `learnSkill` reached)
  - Consecutive points on the same recipe merge into one step: `{recipeID, fromSkill, toSkill, crafts, materials, giveBack, net, learned, estimated}`; `crafts` rounds up per step
  - A candidate without a material cost is left out and counted in `route.skippedForPrice`
  - A recipe not learned with a known `learnCost` stays in the route only when it saves more than that cost against the route without it
  - A step `{kind = "rankCap", skill}` is inserted where the route crosses `rankCap`
  - The route ends at the first skill point no candidate can give
  - `route.totals = {materials, giveBack, net}`; both materials and net are always filled
- `LevelingRouteLogic.QueueEntries(step)` → `{recipeID, quantity}` for a learned step, nil for a step not learned or a rank-cap step
- `LevelingRouteLogic.QueueAdjustment(queuedQuantity, step)` → how many crafts to add or remove so the queued count matches what the step still needs
- Tests in `tests/test_leveling_route_logic.lua`

## Status

Implemented, in-game check pending:

- `Tradewright_LevelingRouteLogic.lua` with `BuildRoute`, `GiveBack`, `QueueEntry`, `QueueAdjustment`, `ApplyTrainerData`, `TrainerEntries`; offline tests in `tests/test_leveling_route_logic.lua`
- Run against the saved Forever scan with flat prices: Leatherworking 122 → 340 in 14 steps from 514 recipes in about 23 ms

- **Crafted materials count for what they save.** A recipe whose item is a material of a later step (Heavy Leather for a cloak) is valued at the price the route would pay for that material, so it can win a step it would lose on its vendor price. The later step keeps its full material cost; the saving shows as the earlier step's give-back (`reusedQuantity`, `reuseValue`). Only steps after the crafting step count, and what is crafted beyond their need counts at its normal sale value
- The choice is made in two passes: first without reuse, then with every craft of a material recipe valued as reused. When later steps need less than is crafted, the totals are right but the choice may be slightly too generous to the material recipe

Differs from the scope:

- `QueueEntry(step)` (singular) and `QueueAdjustment(queuedQuantity, recipeID, steps)`: the craft queue holds one line per recipe, so the adjustment compares against all of the route's steps for that recipe
- Totals also carry `learnCost`, counted once per recipe and included in `net`
- A route can end early at a gap: when the only recipes for the next points are not learned and assumed not learnable yet, the route stops there

## Acceptance criteria

- [ ] With two recipes usable over the same range, the cheaper per skill point wins at every point
- [ ] A recipe that is cheaper per craft but yellow loses to a dearer orange one when its cost per point is higher
- [ ] Changing the give-back mode changes the chosen recipe when the vendor or auction value tips the comparison
- [ ] `learnedOnly` removes every recipe not learned
- [ ] A recipe with a learn cost above its saving is not used
- [ ] Rank-cap step appears at the cap and not when the route ends below it
- [ ] Recipes without prices are counted, not silently dropped
- [ ] `QueueAdjustment` shrinks after a skill-up that came early and grows after an unlucky run
- [ ] Offline tests cover the above

## Verification

```bash
npm test
```

Offline: build a route from the saved Forever scan (Leatherworking at 122) with made-up flat prices and read it for sense: no grey recipes, ranges continuous, no gaps.

## Dependencies

- F120 (bounds and chance)

## Out of scope

- Price depth (cost rising with the amount bought)
- Valuing materials the player already owns differently from bought ones: the route uses market value; what is still to buy comes from the craft queue's shopping list
