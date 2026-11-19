# Code quality (AuctionHelper)

Adapted from QuestPlanner / Master of Dungeons.

## KISS / DRY / minimal LOC

- Simplest design that meets acceptance criteria
- Extract duplication only when the same semantics repeat 2+ times
- Delete dead code; no speculative frameworks
- Put Forever-pure helpers in `AuctionHelper_ForeverLogic.lua` so tests can load them without the full UI stack

## File size & responsibility

- Soft threshold ~500–700 LOC per production file; AuctionHelper_Auction.lua and AuctionHelper_Data.lua are legacy monoliths — prefer focused helpers for new Forever paths instead of growing them further without need
- Keep Midnight-only early returns at the top of order/mail modules

## Complexity

- Prefer early returns over deep nesting
- Cyclomatic complexity > ~10 per function → split or justify
- Long methods (> ~40 lines) → named helpers

## Leftovers

- No debug spam outside existing debug settings
- No commented-out blocks or bare TODOs without an issue id
