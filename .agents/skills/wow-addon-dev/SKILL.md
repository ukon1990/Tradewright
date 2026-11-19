---
name: wow-addon-dev
description: WoW Forever addon development basics for AuctionHelper — TOC camelot flavor, SavedVariables, Forever vs retail flags, protected API / ToS, reload vs restart.
---

# WoW addon development (AuctionHelper)

## Client

- Ships for **Forever** (`## Interface: 16001+`, `## AllowLoadGameType: camelot`) and **retail** (`## Interface: 120000, 120001`, `## AllowLoadGameType: standard`) from the same code.
- Per-flavor TOCs in every addon: `_Mainline.toc` (retail), `_Forever.toc` + `_Camelot.toc` (Forever), plain `.toc` (fallback). Keep all four identical except `Interface` / `AllowLoadGameType`.
- Detect Forever with interface `16000–16999` via `ForeverLogic.DetectClientFlags` — do **not** use `WOW_PROJECT_ID == MAINLINE` alone.

## TOC & load order

- Five addons: `AuctionHelper`, `AuctionHelper_AuctionData`, `AuctionHelper_Professions`, `AuctionHelper_Inventory`, `AuctionHelper_UI`.
- List every `.lua` in each TOC (all four flavor variants). **New files need a full client restart**; `/reload` only reloads files already in the TOC.
- `Blizzard_Professions` is **OptionalDeps** so auction modules still load if it is disabled.

## Flags

| Flag | Meaning |
| --- | --- |
| `IS_FOREVER` | Interface 16000–16999 |
| `IS_RETAIL` | True mainline (not Forever) |
| `IS_SUPPORTED` | Retail or Forever — scan, inventory, craft profit, AH dump |

Keep Midnight-only hooks on `IS_RETAIL` (crafting orders UI/materials, concentration, commodity purchase).

## Protected API / ToS

- **Never** automate movement or unlock protected functions.
- Auction queries (`QueryAuctionItems`) and `C_TradeSkillUI.CraftRecipe` are fine when the player initiated the UI context.

## SavedVariables

| Global | Addon |
| --- | --- |
| `AuctionHelperDB`, `AuctionHelperMigrationDB`, `AuctionHelperLastExport` | Core |
| `AuctionHelperAuctionDB` | AuctionData |
| `AuctionHelperProfessionsDB` | Professions |
| `AuctionHelperInventoryDB` | Inventory |

## Performance

- Chunk full AH dumps and inventory snapshots (`C_Timer`).
- Do not block the main thread on large replicate/classic pages without yielding.
