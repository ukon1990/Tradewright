# E14 — Profession leveling

## Summary

A leveling guide per profession, as a third view in the side panel docked to the profession window. It shows the cheapest route from the current skill to as far as the known recipes go, worked out from current prices, and redone whenever skill or prices change. Steps for recipes the character knows can be put in the craft queue.

## Context

- Nothing in the pack plans leveling today; E08 listed it as out of scope.
- No recipe database ships with the addon, and none is needed. A saved Forever scan (Leatherworking, 593 recipes, 551 of them not learned) shows the client reports for every recipe, learned or not: `info.maxTrivialLevel` (the skill at which it turns grey), `info.relativeDifficulty` (0 orange, 1 yellow, 2 green, 3 grey), `info.numSkillUps`, its reagents and its output item. Retail's `C_TradeSkillUI.GetRecipeInfo` has the same fields.
- Forever has its own recipes and its grey levels differ from Classic (Fine Leather Belt turns grey at 115 on Forever, 130 in Classic), so published Classic tables cannot be used.
- What the client does not report, and how this epic handles it:
  - The skill where a recipe turns yellow and green: estimated from the grey level, then narrowed from the colours the client has shown for that recipe (F120, F122)
  - The skill needed to learn a recipe and where it comes from: estimated; a trainer visit records the real requirement and cost (F124)
  - The stored colour goes stale after a skill-up, because the live update only re-stamps profession fields (`AuctionHelper_LiveUpdate.lua`, `stampProfessionMetadataOnly`): fixed in F122
- Pricing is the existing crafts engine: `EvaluateCraftScenario` (`AuctionHelper_CraftEvaluation.lua`) gives material cost, sale after the cut and the reagent plan for any recipe.
- The side panel (`AuctionHelper_ProfessionCraftPanel.lua`, 400 px, docked right of `ProfessionsFrame`) has two views, Recipe and Queue. The craft queue (`AuctionHelper_CraftQueue.lua`) already produces the "To craft" and shopping lists and feeds the auction cart.
- Design: [Leveling, cheapest route](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-ProfessionLeveling), [materials only and step tooltip](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-ProfessionLevelingDetail), [working and no prices](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-ProfessionLevelingEmpty).

Decisions taken with the user:

- A dropdown picks the recipes: "Trainer recipes first" (default: recipes the character knows and ones a trainer has been seen to teach; any other recipe only for skill points none of those can give), "All recipes" (cheapest of everything scanned) or "Only known"
- "Learn" on a step is off when no trainer has been seen teaching the recipe, or the trainer asks for more skill than the character has
- Cost is net of what the crafted items give back, switchable between vendor sale, auction sale and nothing; the materials total is always shown next to the net cost
- The route runs to the profession's highest skill (300 on Forever), not as far as recipes stay orange; rank caps appear as "train the next rank" steps
- Queueing is per step for recipes the character knows, or for a range: "Queue the route up to skill N" adds every step up to N, recipes still to be learned included. Such a line reads "learn first" in the Queue view and cannot be crafted until the recipe is learned

## Scope

- F120: skill-up maths (colour bounds and skill-up chance)
- F121: route maths (cheapest route, steps, craft-queue entries)
- F122: leveling data (candidates from the scan and prices, colour upkeep, craft-queue integration)
- F123: Leveling view in the profession side panel
- F124: trainer recipes (skill requirement and cost from a trainer visit)

## Acceptance criteria

- [ ] F120 to F124 done
- [ ] With a profession scan and auction prices, the Leveling view shows a route from the current skill, with materials and net totals
- [ ] The route is redone after a skill-up and after new prices, without a manual scan
- [ ] A known-recipe step can be queued; its materials show in the Queue view's shopping list and the auction cart
- [ ] Recipe and Queue views behave as before
- [ ] A client whose recipes carry no grey level shows a clear "not available" message and no error
- [ ] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever (full client restart, new files): full auction scan → open Leatherworking → Leveling shows a route → queue the first step → Queue view lists the crafts and what to buy → craft until a skill-up → the route and the queued count update → visit a Leatherworking trainer → "Learn" steps for trainer recipes show cost and skill.

Retail: open a profession → a route, or the "not available" message.

## Dependencies

- E03 Craft mail (implemented): the craft queue and its lists
- E08 F60 (implemented): cheapest material source used by the crafts engine

## Out of scope

- A shipped recipe or trainer database
- Auction depth: prices are unit prices, so buying a large amount may cost more than shown
- Routes for gathering professions (no crafts to cost)
- Retail knowledge points, specializations, first-craft bonuses and concentration
- Buying recipes automatically or finding recipe items at the auction house
