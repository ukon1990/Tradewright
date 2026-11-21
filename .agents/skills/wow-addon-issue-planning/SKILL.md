---
name: wow-addon-issue-planning
description: Plan and split AuctionHelper work into local markdown issues under src/AuctionHelper/docs/specifications/issues/. Confirm with the user before writing issue files.
---

# Issue planning (AuctionHelper)

Adapted from QuestPlanner / Master of Dungeons planning — **workflow**, not an external toolchain.

## Golden rule

**Never write plan/issue files until the user confirms.**

1. Discover — problem, outcome, Forever vs retail API touch points
2. Draft — epic / feature / task outline in chat (dry-run)
3. Overlap — search `src/AuctionHelper/docs/specifications/` and issue folders
4. Confirm — user says yes
5. Write — markdown under `src/AuctionHelper/docs/specifications/issues/` and update the backlog index

## Issue shape

English sections: `Summary`, `Context`, `Scope`, `Acceptance criteria`, `Verification`, `Dependencies`, `Out of scope`.

## Touch map

| Area | Paths |
| --- | --- |
| Flags | `src/AuctionHelper/src/util/AuctionHelper_ForeverLogic.lua`, `src/AuctionHelper/src/core/AuctionHelper.lua` |
| Pure helpers | `src/AuctionHelper/src/util/AuctionHelper_*Logic.lua` (Auction, Market, Mail, Income, Filter, Material, …) |
| Export | `src/AuctionHelper/src/core/AuctionHelper_ExportBuild.lua`, `AuctionHelper_JsonCodec.lua` (util) |
| SavedVariables / session state | `src/AuctionHelper/src/core/AuctionHelper_Data.lua`, `AuctionHelper_DataInit.lua` |
| Events | `src/AuctionHelper/src/core/AuctionHelper_Events.lua` |
| Classic / retail AH | `AuctionHelper_AuctionData/src/modules/AuctionHelper_Auction*.lua` (`FullScan`, `Store`, `LiveSearch`, `Panel*`, `Sell*`, …) |
| Profession scan | `AuctionHelper_Professions/.../AuctionHelper_Scan.lua`, `LiveUpdate.lua` |
| Crafts / orders | `AuctionHelper_Professions/src/modules/`: `CraftsEngine.lua` (basics), `CraftEvaluation.lua`, `CraftOpportunities.lua`, `Craft*.lua`, `CraftingOrder*.lua` |
| Inventory | `AuctionHelper_Inventory/.../AuctionHelper_Inventory.lua` |
| UI | `AuctionHelper_UI/src/ui/*` |
| Tests | `src/AuctionHelper/tests/` |
| Lint / quality gate | `scripts/lint.py`, `scripts/lint-baseline.json`, `.luacheckrc` |

When an issue touches an over-limit file or function (see `scripts/lint-baseline.json`), size it to include extracting helpers — lint forbids growing it.
