# F124 — Trainer recipes

## Summary

When the player opens a profession trainer, the addon records which recipes that trainer teaches, the skill each needs and what it costs. The leveling route then uses real learn requirements for those recipes instead of an estimate.

## Context

- The profession scan does not say where a recipe comes from or at which skill it can be learned. Without that, the route assumes a recipe can be learned a fixed span below its grey level and shows "source unknown".
- The trainer window reports each service's name, whether it is available, its cost and its skill requirement (`GetNumTrainerServices`, `GetTrainerServiceInfo`, `GetTrainerServiceCost`, `GetTrainerServiceSkillReq`). Which of these exist on Forever must be checked in the client; each call is capability-checked.
- The trainer lists services by name, the scan stores recipes by id, so matching is by recipe name within the profession. A trainer's filters can hide services, so only what is listed is recorded and nothing is concluded from a recipe being absent.
- This only reads the open trainer window. Nothing is bought.

## Scope

- New `src/Tradewright_Professions/src/modules/Tradewright_TrainerRecipes.lua`, listed in all four Professions TOCs; own event frame for `TRAINER_SHOW` and `TRAINER_UPDATE`
- Store per profession, shared by all characters: `TradewrightProfessionsDB.trainerRecipes[skillLineID][recipeName] = {skillRequired, cost, seenAt}`
- Pure helper `LevelingRouteLogic.ApplyTrainerData(candidates, trainerRecipes)`: fills `learnSkill`, `learnCost` and `source = "trainer"` on matching candidates
- F123 row detail reads "trainer, 5s" and the tooltip "Trainer: 5s, needs skill 150"
- New globals in `.luacheckrc`

## Status

Implemented, in-game check pending:

- `Tradewright_TrainerRecipes.lua`: `ReadOpenTrainerRecipes` on `TRAINER_SHOW` / `TRAINER_UPDATE`, `GetTrainerRecipes(skillLineID)`; pure `LevelingRouteLogic.TrainerEntries` and `ApplyTrainerData`, tested offline

- Each recipe entry also keeps who teaches it and where (`trainers = { [trainerName] = { zone, mapID, x, y } }`). "Learn" on a route step is a button: it sets a waypoint to the nearest trainer seen teaching the recipe and names it in chat (`ShowRecipeTrainerWaypoint`), with the same nearest-place and waypoint code as vendor reagents (`NearestPlace`, `SetWaypointTo` in `Tradewright_VendorSource.lua`). Trainers seen by a character of the other faction are left out
- Only trainers the player has opened are known; there is no trainer database behind it

Differs from the scope:

- Stored per character at `characters[characterKey].trainerRecipes[skillLineKey][recipeName]` and merged across characters when read; a new top-level store would have needed a saved-variables mapping change
- The trainer is matched to a profession by recipe name alone: a service is kept when it is a scanned recipe of one of the character's professions
- Whether Forever has `GetNumTrainerServices`, `GetTrainerServiceCost` and `GetTrainerServiceSkillReq`, and whether the second return of `GetTrainerServiceSkillReq` is the skill needed, is unverified

## Acceptance criteria

- [ ] After opening a Leatherworking trainer, "Learn" steps for recipes it teaches show the trainer's cost and skill
- [ ] A trainer recipe is not placed in the route below its required skill
- [ ] A recipe the trainer does not list keeps "source unknown"
- [ ] Opening a non-profession trainer (class, riding) stores nothing
- [ ] A client lacking the trainer calls stores nothing and shows no error
- [ ] Offline tests: name matching, learn skill respected, unknown recipes untouched

## Verification

```bash
npm test
```

In-game on Forever: open Leatherworking → Leveling shows "source unknown" on a trainer recipe → visit the trainer → reopen Leveling → the step shows cost and skill.

## Dependencies

- F121 (candidate fields), F123 (where it shows)

## Out of scope

- Vendor-sold and dropped recipes
- Where the trainer is (map pins, waypoints)
- The cost and character level needed to train the next rank
