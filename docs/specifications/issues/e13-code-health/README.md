# E13 — Code health

## Summary

Make the code maintainable by a human: a developer new to a file can read it, understand it and change it safely without an AI. Fix the bugs the audit found, delete dead code, give things clear names, keep only comments that add value, put tests in front of the logic that matters, and split the legacy files and functions that are too big to follow.

## Context

- The quality gate (`scripts/lint.py`, `scripts/lint-baseline.json`) arrived on 2026-11-20. Everything older is frozen as debt: 356 over-limit functions in 34 of 108 Lua files (about 28.5k of 82k lines); 14 files are over 700 lines. Code written since then passes the gate and reads well (the Bags window scored 4/5 in the audit).
- The audit of 2026-11-21 read every debt file against `focus/code-quality.md`, `focus/lua-wow.md` and `focus/auction-forever.md`. Readability scores of the worst files: `Tradewright_Auction.lua`, `Tradewright_Data.lua`, `Tradewright_CraftsEngine.lua`, `Tradewright_ItemAnalytics.lua`, `Tradewright_CraftingOrdersMaterials.lua`, `Tradewright_CraftsUI.lua`, `Tradewright_InventoryUI.lua`, `Tradewright_ProfessionCraftPanel.lua`: 2/5.
- Comments are mostly good (about 85%). The noise is 51 feature or epic ids in comments, a few changelog notes, and section labels inside long functions that go away once those blocks become named functions.
- Only `Tradewright_ForeverLogic.lua`, `MailLogic`, `BagLogic` and a few other pure helpers are tested. No file of `Tradewright_AuctionData`, `Tradewright_Professions`, `Tradewright_Inventory` or `Tradewright_UI` is loaded by a test, so every refactor here needs tests first.
- Line numbers in the feature issues are from the audit and will drift; search for the function name.

## Scope

- F105: conventions — human maintainability, naming, comments, review check
- F106: bugs found by the audit
- F107: delete dead code
- F108: comment sweep
- F109: shared core helpers for repeated code
- F110: lookup tables instead of if-chains
- F111: one item key and snapshot normalizer
- F112: one name for the craft queue; crafting-order queue code out of `CraftQueue.lua`
- F113: tests for the core logic, then break up the functions with complexity over 40
- F114: split the Professions and Inventory files
- F115: split the UI files
- F116: split `Tradewright_Auction.lua`
- F117: shared UI helpers
- F119: rename `ProfessionExporter` to `AuctionHelper`
- F118: split `Tradewright_Data.lua`, `Tradewright_Util.lua` and `Tradewright_ForeverLogic.lua`
- F120: rename the pack from `AuctionHelper` to `Tradewright`

## Acceptance criteria

- [x] F105 to F119 done
- [x] No feature grows `scripts/lint-baseline.json`; every feature that touches baselined code shrinks it and commits the new baseline
- [x] Behaviour is unchanged on Forever and retail, apart from the bugs F106 fixes
- [x] Every feature passed a review against the three focus files and the question "could a developer new to this file change it safely?"

## Verification

```bash
npm test
```

In-game after each feature that moves code (full client restart when a `.lua` file is added): `/ah` opens; full AH dump with the house open fills prices; profession Scan stores recipes; Crafts tab shows profit; bag window opens.

Status: `npm test` passes after F119 and the alias cleanup, and the in-game checks above are done.

## Dependencies

- None. F105 first, because every later feature follows its rules. F106 to F108 are small and independent. F113 comes before the splits (F114 to F116, F118).

## Out of scope

- Showing warband columns in the inventory on Forever
- New features
