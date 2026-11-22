---
name: wow-addon-issue-planning
description: Plan and split Tradewright work into local markdown issues under src/Tradewright/docs/specifications/issues/. Confirm with the user before writing issue files.
---

# Issue planning (Tradewright)

Adapted from QuestPlanner / Master of Dungeons planning — **workflow**, not an external toolchain.

## Golden rule

**Never write plan/issue files until the user confirms.**

1. Discover — problem, outcome, Forever vs retail API touch points
2. Draft — epic / feature / task outline in chat (dry-run)
3. Overlap — search `src/Tradewright/docs/specifications/` and issue folders
4. Confirm — user says yes
5. Write — markdown under `src/Tradewright/docs/specifications/issues/` and update the backlog index

## Issue shape

English sections: `Summary`, `Context`, `Scope`, `Acceptance criteria`, `Verification`, `Dependencies`, `Out of scope`.

## Touch map

| Area | Paths |
| --- | --- |
| Flags | `src/Tradewright/src/util/Tradewright_ForeverLogic.lua`, `src/Tradewright/src/core/Tradewright.lua` |
| Pure helpers | `src/Tradewright/src/util/Tradewright_*Logic.lua` (Auction, Market, Mail, Income, Filter, Material, …) |
| Export | `src/Tradewright/src/core/Tradewright_ExportBuild.lua`, `Tradewright_JsonCodec.lua` (util) |
| SavedVariables / session state | `src/Tradewright/src/core/Tradewright_Data.lua`, `Tradewright_DataInit.lua` |
| Events | `src/Tradewright/src/core/Tradewright_Events.lua` |
| Classic / retail AH | `Tradewright_AuctionData/src/modules/Tradewright_Auction*.lua` (`FullScan`, `Store`, `LiveSearch`, `Panel*`, `Sell*`, …) |
| Profession scan | `Tradewright_Professions/.../Tradewright_Scan.lua`, `LiveUpdate.lua` |
| Crafts / orders | `Tradewright_Professions/src/modules/`: `CraftsEngine.lua` (basics), `CraftEvaluation.lua`, `CraftOpportunities.lua`, `Craft*.lua`, `CraftingOrder*.lua` |
| Inventory | `Tradewright_Inventory/.../Tradewright_Inventory.lua` |
| UI | `Tradewright_UI/src/ui/*` |
| Tests | `src/Tradewright/tests/` |
| Lint / quality gate | `scripts/lint.py`, `scripts/lint-baseline.json`, `.luacheckrc` |

When an issue touches an over-limit file or function (see `scripts/lint-baseline.json`), size it to include extracting helpers — lint forbids growing it.
