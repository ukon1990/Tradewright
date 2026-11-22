# F122 — Leveling data

## Summary

Builds the route for a character's profession from the stored scan and current prices, keeps recipe colours current after a skill-up, and puts a route step into the craft queue.

## Context

- Stored recipes: `TradewrightProfessionsDB.characters[characterKey].professions[skillLineID].recipes[*]`, each with `info.maxTrivialLevel`, `info.relativeDifficulty`, `info.numSkillUps`, `info.learned`, reagent slots and outputs (`Tradewright_ProfessionScan.lua`, `CollectRecipeData`).
- `EvaluateCraftScenario(characterKey, professionData, recipeID, recipeData, opts)` (`Tradewright_CraftEvaluation.lua`) prices any recipe, learned or not: `fullMatCost`, `saleNet`, `outputQty`, `reagentPlan`, `matMissingPrice`. `BuildCraftOpportunityRows` evaluates in chunks and caches on `dataRevision`; the same pattern fits here.
- The live update re-stamps only profession fields when skill changes (`Tradewright_LiveUpdate.lua`, `stampProfessionMetadataOnly`), so each recipe's stored colour is stale until a full scan.
- Craft queue: `AddCraftToQueue(rowOrContext, quantity)`, `BuildCraftQueueSummary()` (`Tradewright_CraftQueue.lua`). How it treats a recipe that is not learned has to be read before building on it; route steps for such recipes are not queued in any case.
- The rank cap is the profession's stored `maxSkillLevel`.

## Scope

- New `src/Tradewright_Professions/src/modules/Tradewright_LevelingRoute.lua`, listed in all four Professions TOCs
  - `BuildLevelingCandidates(characterKey, professionData)`: every recipe whose grey level is above the current skill, priced through `EvaluateCraftScenario` with market cost for all materials; vendor give-back from `GetItemVendorSellCopper × outputQty`, auction give-back from `saleNet × outputQty`; evaluated in chunks, cached on data revision, skill level and price revision
  - `GetLevelingRoute(characterKey, skillLineID)` → `route` or `nil, reason` with `no_data`, `not_ready` (still evaluating, with progress), `unsupported` (recipes carry no grey level), `no_prices`, `finished` (nothing can give skill)
  - Settings `professions.leveling.giveBack` (`vendor` default, `auction`, `none`) and `professions.leveling.learnedOnly`
- Colour upkeep
  - When the live update sees a skill change, re-read `GetRecipeInfo` for the open profession's recipes and store the new `relativeDifficulty`
  - On every scan and upkeep pass, record the observation (F120) per recipe in `characters[characterKey].professions[skillLineID].difficultyObservations[recipeID]`; documented in `Tradewright_Data.lua` next to the profession row
- Craft queue integration
  - `QueueLevelingStep(step)`: adds the step's crafts through `AddCraftToQueue`, marking the entry as coming from the leveling route
  - After each route rebuild, entries marked that way are adjusted with `LevelingRouteLogic.QueueAdjustment`; entries the player added, and any quantity the player changed by hand, are left alone
  - An entry whose step has left the route (recipe turned grey, cheaper recipe took over) is removed
- New WoW globals, if any, go in `.luacheckrc`

## Status

Implemented and checked in game:

- `Tradewright_LevelingRoute.lua` (Professions): `GetLevelingRoute`, `GetOpenProfessionLevelingRoute`, `GetLevelingSettings`, `InvalidateLevelingRoute`, `RefreshRecipeDifficulties`; recipes are priced 60 per frame
- `Tradewright_LevelingQueue.lua` (Inventory, because `Tradewright_CraftQueue.lua` is at the file-size limit): `QueueLevelingStep`, `TrimLevelingCraftQueue`, `GetLevelingQueuedQuantity`, `HasLevelingCraftQueueLines`
- Colours are re-read from `CommitLiveProfessionMergeResult` when the skill has changed; prices invalidate the route from `InvalidateCraftOpportunityCaches`
- Offline tests in `tests/test_leveling_route.lua`

- The priced recipes depend on skill, the recipe list and prices only, not on bag contents, so a craft without a skill-up does not work the route out again. While recipes are priced again, the previous route stays up
- The Leveling view only gives its table new rows when the row texts have changed

- Learning a recipe changes no skill, so recipes are also read again after `NEW_RECIPE_LEARNED` or `TRAINER_UPDATE` (`RereadRecipesAfterLearning`), and when the Leveling view asks for the open profession's route; a changed learned state works the route out again

- `QueueLevelingRange(route, toSkill)` queues the route up to a skill (`LevelingRouteLogic.QueueEntriesUpTo`), recipes not learned included; such a line carries `levelingLearn = { skill }` until the game reports the recipe as learned
- The craft queue's shopping list (now `Tradewright_CraftQueueSummary.lua`, split out of `Tradewright_CraftQueue.lua`) does not buy what other queued crafts of the same character make: `quantityFromQueue` per material, `MaterialLogic.ToBuyAfterQueuedCrafts`; the auction cart follows

- Buyouts in the classic auction house are credited to the shopping lists when the game confirms them (`Tradewright_AuctionClassicBuy.lua`: a hook on `PlaceAuctionBid`, then the "You won an auction for …" system message), and the craft queue's list counts those credits. Unverified in the client: that Forever buys through `PlaceAuctionBid` and sends that message

- Skill and rank cap of the open profession are read from the character's profession list (`GetPlayerProfessions`) each time its route is asked for: on Forever the profession window's fingerprint does not change with skill, so the stored values went stale

Differs from the scope:

- **The route stops at the profession's highest skill.** No game call reports it: per profession the game gives only the current rank's cap. So it is a constant, 300, outside retail (WoW Forever); on retail it is the profession's own cap
- The setting `professions.leveling.learnedOnly` became `professions.leveling.recipes`: `trainer` (default; known and trainer recipes first, others only to fill skill points none of those can give), `all` or `known`

- **The queue is only ever lowered automatically.** After an unlucky run the step shows "N in queue" and its Queue button again, which adds the difference
- **Only learned recipes are recorded as colour sightings**: the game reports 0 (orange) for every recipe not learned
- Observations are stored at `characters[characterKey].difficultyObservations[skillLineKey][recipeKey]`, beside the professions, because a full scan replaces the profession's table
- A queue line marks its route crafts with `levelingQuantity`; a hand change to the line's quantity is respected only downwards (the route part is capped at the line's quantity)
- Recipes the crafts engine cannot value (no crafted item, such as enchants) are counted as "no price" and left out
- The route for the open profession is kept up while the Leveling view is hidden only when the craft queue holds route crafts

## Acceptance criteria

- [x] A route is returned for a scanned crafting profession with prices; each reason above is returned in its case
- [x] After a skill-up with the profession window open, stored colours match the game's without a full scan
- [x] Observations survive `/reload` and narrow the estimates the next time the route is built
- [x] Queueing a step adds exactly its crafts; the Queue view's shopping list shows its materials
- [x] A skill-up that came early lowers the queued count; a craft the player queued by hand for the same recipe is not lowered
- [x] Building the route does not freeze the game on a profession with 600 recipes
- [x] Retail: crafting orders, concentration and quality tiers behave as before
- [x] Offline tests for the candidate builder's cost fields and the reason selection, with stubbed pricing

## Verification

```bash
npm test
```

In-game on Forever: full auction scan → open Leatherworking → `/run` the route getter or open the Leveling view → craft to a skill-up → colours and route update → queue a step → Queue view and auction cart show the materials.

## Dependencies

- F120, F121
- E03 craft queue

## Out of scope

- Reading other characters' professions live: another character's route uses that character's last scan
- Trainer data (F124)
