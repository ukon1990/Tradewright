# F120 — Skill-up maths

## Summary

Pure functions that say, for a recipe and a skill level, which colour the recipe has and how likely one craft is to give a skill point. They work from the grey level the client reports and get more exact as the client shows the recipe's colours.

## Context

- The client reports only the grey level (`info.maxTrivialLevel`) and the colour at the current skill (`info.relativeDifficulty`: 0 orange, 1 yellow, 2 green, 3 grey). The yellow and green start points are not reported.
- Classic-style skill-up chance: every craft gives a point while orange; from the yellow start the chance falls in a straight line to zero at grey: `(grey - skill) / (grey - yellowStart)`.
- Forever's spans differ from Classic's, so the default spans are named constants to be checked against the saved scan and adjusted from in-game observation.
- An observation is "recipe R had colour C at skill S". Each one narrows a bound: seen orange at 130 means yellow starts above 130; seen yellow at 138 means yellow starts at or below 138.

## Scope

- New `src/AuctionHelper/src/util/AuctionHelper_SkillUpLogic.lua`, no WoW API, listed in all four core TOCs
- `SkillUpLogic.DifficultyBounds(greyLevel, observation)` → `{yellowStart, greenStart, greyStart, estimated = true | false}`; without observations the starts are `greyLevel` minus the default spans
- `SkillUpLogic.DifficultyAt(bounds, skill)` → `"optimal" | "medium" | "easy" | "trivial"`, plus a lookup from the client's 0 to 3 values to these names
- `SkillUpLogic.SkillUpChance(bounds, skill)` → 0 to 1
- `SkillUpLogic.RecordObservation(observation, skill, difficulty)` → the narrowed observation (`{orangeSeenUpTo, yellowSeenFrom, yellowSeenUpTo, greenSeenFrom, …}`), small enough to save per recipe
- Tests in `tests/test_skill_up_logic.lua`

## Status

Implemented, in-game check pending:

- `AuctionHelper_SkillUpLogic.lua` with `DifficultyName`, `DifficultyBounds`, `DifficultyAt`, `SkillUpChance`, `RecordObservation`; offline tests in `tests/test_skill_up_logic.lua`
- The green start is taken as halfway between the yellow start and the grey level, so the yellow start is the only unknown; an observation is `{ yellowStartMin, yellowStartMax }`
- `RecordObservation` takes the grey level as well: `RecordObservation(observation, greyLevel, skill, difficulty)`
- Default yellow span is 15 below grey: it matched 40 of 42 learned Leatherworking recipes in the saved Forever scan. Spans vary a lot per recipe (Heavy Silk Bandage: 60), so the estimate is rough until the game has shown a recipe's colours

## Acceptance criteria

- [ ] Chance is 1 below the yellow start, 0 at and above the grey level, and falls linearly between
- [ ] Bounds built only from a grey level are flagged estimated
- [ ] An observation inside the estimated span moves the bound and never produces yellow after green or green after grey
- [ ] Observations that contradict each other (stale data) keep the newest and do not error
- [ ] The client's values 0, 1, 2, 3 map to optimal, medium, easy, trivial
- [ ] Offline tests cover the above

## Verification

```bash
npm test
```

Offline: run the bounds over the saved Forever scan and compare the predicted colour at the scanned skill with the stored `relativeDifficulty`; adjust the default spans if most predictions are off.

## Dependencies

- None

## Out of scope

- Learning the chance from counted crafts and skill-ups
- Recipes that give more than one point per craft beyond reading `numSkillUps` (handled as a multiplier in F121)
