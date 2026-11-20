# Code quality (AuctionHelper)

Adapted from QuestPlanner / Master of Dungeons.

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

## Leftovers

- No debug spam outside existing debug settings
- No commented-out blocks or bare TODOs without an issue id
