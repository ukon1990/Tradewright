# Code quality (AuctionHelper)

Adapted from QuestPlanner / Master of Dungeons.

## The rule: maintainable by a human

A developer new to a file must be able to read it, understand it and change it safely, without an AI. Every rule below serves this one. Passing lint is not enough: code that meets every limit but needs a decoder ring (`c`, `st`, `stats[4]`) fails review.

## KISS / DRY / minimal LOC

- Simplest design that meets acceptance criteria
- Extract duplication only when the same semantics repeat 2+ times
- Delete dead code; no speculative frameworks
- Put Forever-pure helpers in `AuctionHelper_ForeverLogic.lua` so tests can load them without the full UI stack

## Enforced limits (`npm run lint`, also part of `npm test`)

`scripts/lint.py` runs luacheck (`.luacheckrc`) and measures hand-written Lua (`src/**`, excluding `tests/` and generated `data/`):

| Check | Limit |
| --- | --- |
| File length | 700 lines |
| Function length | 40 lines |
| Cyclomatic complexity | 10 per function |
| Parameters | 5 per function |
| luacheck | unused vars/args, undefined or written globals, shadowing, empty branches, lines > 160 chars |

Existing debt is frozen in `scripts/lint-baseline.json` (a ratchet). Lint fails only when code is **new or worse** than the baseline:

- New code must meet every limit. Over-limit legacy files and functions may not grow.
- On failure, **fix the code** (extract helpers, split files, drop unused vars). Never hand-edit or regenerate the baseline to make a failure go away.
- When lint says debt went down, run `npm run lint:baseline` and commit the smaller baseline with the change.
- New WoW API or frame global → add it to `read_globals` in `.luacheckrc` (alphabetical). New SavedVariable / slash command → `globals`.
- Function keys are `file` + name (`M:Foo`, `Outer/<anon>`), so renaming an over-limit function shows up as a new violation: fix it while you're there.

## File size & responsibility

- Aim for ≤ 500 lines; 700 is the hard limit. `AuctionHelper_Auction.lua` and `AuctionHelper_Data.lua` are legacy monoliths — put new Forever paths in focused helpers instead of growing them
- Keep Midnight-only early returns at the top of order/mail modules

## Complexity

- Prefer early returns over deep nesting
- Over-limit complexity or length → split into named helpers; pass a table instead of 6+ parameters

## Naming

- Name things for what they hold or do: `unitPrice`, `searchAggregate`, `planState`, not `u`, `agg`, `st`
- Single letters only for short loop indices (`i`, `k, v` in a 3-line loop) and the established `pe` (the addon object), `f` (the frame being built) and `FL` (ForeverLogic, when aliased)
- No abbreviations a reader must decode: `ev`, `ck`, `expSel`, `oopMatCost` become `evaluation`, `characterKey`, `expansionSelection`, `outOfPocketMatCost`
- Named keys over numbered slots: `stats.gold`, not `stats[1]` with a comment saying what 1 is
- Named constants for magic numbers and timer delays: `PENDING_CRAFT_TIMEOUT_SEC = 20`, not a bare `20`
- One word per concept, everywhere:

| Concept | Use | Not |
| --- | --- | --- |
| Queue of crafts to make | craft queue (`CraftQueue`) | work queue, work order queue, shopping queue (the UI label "shopping list" may stay) |
| Retail crafting orders taken to craft (own store, mirrored into the craft queue as crafting-order lines) | crafting-order queue (`CraftingOrderQueue`) | work queue, work order queue |
| Reading the whole AH | full scan | dump, replicate, classic_full |
| Auction house price seen in game | AH price | native, live, current price |
| Item identity with bonus ids | item key (`itemKey`) | key fields, scan key |


## Comments

A comment earns its place when it tells the reader something the code cannot:

- why the code does it this way
- a WoW API quirk (`-- Create only works once the server has accepted Start Order.`)
- a Forever-vs-retail reason (`-- WoW Forever has no realms: ...`)
- a non-obvious invariant or unit (`-- copper, not gold`)

Remove:

- comments that restate the code (`-- Check button that stores its checked state in ui[uiKey] and refreshes the panel` above a function named for exactly that)
- feature or epic ids (`-- Farm window (E09 F70)`): the commit message and the issue file carry them
- changelog notes (`-- like before the split`)
- `@param` lines that only repeat the signature
- commented-out code

A label for a block inside a long function (`-- Row 1: search and filters.`) means the block wants to be a named function.

## Tests

- Test behaviour that could break: profit and cost math, which reagent or row wins, what a filter keeps, saved data formats, Forever-vs-retail branches
- Write characterization tests before moving or splitting logic, so the refactor is proven not to change results
- Move logic out of WoW-API-bound functions into pure helpers so it can be tested offline
- No tests for getters, layout or anything that cannot realistically break

## Leftovers

- No debug spam outside existing debug settings
- No commented-out blocks or bare TODOs without an issue id
