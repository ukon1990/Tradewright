# F134 — Cheapest input for prospecting and milling

## Summary

On retail, a recipe that destroys an item of the player's choice (Prospecting, Milling) is priced with the cheapest usable ore or herb, so it gets a cost in the leveling route and a reagent in the craft queue's cart.

## Context

- The scan saves the game's recipe info whole, so `info.isSalvageRecipe` is already saved, but nothing reads it. The usable inputs (`C_TradeSkillUI.GetSalvagableItemIDs`) and how many one craft uses are not saved.
- `EvaluateCraftScenario` (`Tradewright_CraftEvaluation.lua`) returns nil without a crafted item. Only the profession window's queue path passes `allowMissingOutput`, which stands the spell id in for the item; profit stays unknown and the reagent plan is empty.
- `priceCandidate` (`Tradewright_LevelingRoute.lua`) drops a recipe without an evaluation; it counts as "recipes without a price".
- A finished craft is counted off its queue line by the crafted item (`Tradewright_ProfessionCraftAction.lua`), which cannot match random results.
- On Forever Prospecting is a spell cast on the ore, not a recipe: nothing to route.

## Scope

- Scan: save a salvage recipe's usable inputs and the quantity one craft uses; read them live when a saved recipe lacks them, so no rescan is forced
- A pure pick of the cheapest input with a price (in `MaterialLogic`)
- `EvaluateCraftScenario` gives such a recipe a one-line reagent plan from that pick, priced like any reagent, without needing a crafted item
- Leveling route: the recipe is a candidate with its reagent cost, and the step names the input
- Craft queue: the cart lists the input; a finished craft is counted off the line by its recipe
- Craft button: craft with the chosen input when the game allows the call from a click, else open the recipe and name the item to place (checked in game)

## Status

Implemented; offline tests and lint pass. Not yet checked in game. Assumptions to confirm on retail:

- `C_TradeSkillUI.GetSalvagableItemIDs` lists every item the recipe accepts, not only those in the bags
- The schematic's `quantityMax` is how many items one craft destroys (5 is assumed when it is missing)
- `C_TradeSkillUI.CraftSalvage` may be called from the Craft button's click, with the largest bag stack of the planned item
- Each craft fires `UNIT_SPELLCAST_SUCCEEDED` for the player with the recipe's spell id, which counts the queue line down

Differs from the scope:

- No new pick function: the recipe gets one reagent slot holding every accepted item (`MaterialLogic.MakeSalvageSlot`), and the existing per-slot pick chooses the cheapest
- The Craft button crafts as many as the one stack allows; without a large enough stack it opens the recipe and says what it needs

## Acceptance criteria

- [ ] A queued Legion Prospecting line shows a reagent cost and its ore in the cart
- [ ] The leveling route includes prospecting or milling steps where they are cheapest, with the input named
- [ ] Crafting counts the line down
- [ ] No input with a price: the recipe stays "no price", as today
- [ ] Offline tests for the pick and for the evaluation of a salvage recipe
- [ ] Forever unchanged

## Verification

```bash
npm test
```

In game on retail: queue Prospecting and Milling from the Recipe view and from a leveling step.

## Dependencies

- None

## Out of scope

- A sale value or profit for the results (F138)
- Picking the input by profit instead of cost (F138)
