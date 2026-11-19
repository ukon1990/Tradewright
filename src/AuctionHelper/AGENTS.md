# AGENTS.md — AuctionHelper (Forever)

## Product

**AuctionHelper** — multi-module auction / profession / inventory helper pack, adapted for **WoW Forever** (`Interface 16001`, game type `camelot`). Prices come from the classic auction house when retail replicate APIs are missing; profession recipes and craft profit still drive the dashboard.

## Runnable pieces

| Piece | Path | Notes |
| --- | --- | --- |
| Core | `AuctionHelper/` | Shared runtime, flags, export, events |
| Auction | `AuctionHelper_AuctionData/` | Snapshot / full dump / AH panel |
| Professions | `AuctionHelper_Professions/` | Scan, crafts engine (orders stay retail-only) |
| Inventory | `AuctionHelper_Inventory/` | Bags/bank snapshot, ledger |
| UI | `AuctionHelper_UI/` | Dashboard, craft panel, mail |
| Pure Forever helpers | `AuctionHelper/src/util/AuctionHelper_ForeverLogic.lua` | Offline-testable |
| Tests | `AuctionHelper/tests/run_tests.py` | Offline Lua 5.1 (no WoW client) |
| Specs | `AuctionHelper/docs/specifications/` | Issues / backlog |

## Dependencies

| Dep | TOC | Usage |
| --- | --- | --- |
| Blizzard_Professions | `OptionalDeps` | Soft; Forever may ship a subset of DF profession UI |
| TradeSkillMaster / Auctionator | `OptionalDeps` | Pricing fallbacks only |

Load order: `AuctionHelper` → `AuctionHelper_AuctionData` + `AuctionHelper_Professions` → `AuctionHelper_Inventory` → `AuctionHelper_UI`.

## Hard rules

- Forever detection is by **interface version** `16000–16999`, not `WOW_PROJECT_ID` alone (Forever shares mainline project id).
- `IS_RETAIL` = true mainline only; `IS_SUPPORTED` = retail **or** Forever.
- Midnight-only systems (crafting orders, concentration, commodity auto-buy, warband when API missing) stay behind `IS_RETAIL` / capability checks.
- No protected API automation (ToS). AH scan and profession craft clicks use public APIs only.
- KISS / DRY / minimal LOC — see `.agents/skills/wow-addon-issue-work/focus/code-quality.md`.
- New `.lua` files need a **full client restart**; `/reload` only reloads already-listed TOC files.

## Agent skills

Load from `.agents/skills/`:

- `wow-addon-dev` — TOC, SavedVariables, Forever vs retail flags
- `wow-addon-issue-planning` — draft → confirm → write issues
- `wow-addon-issue-work` — implement + review + verify
- `focus/code-quality.md`, `focus/lua-wow.md`, `focus/auction-forever.md`

## Verify

```bash
cd AuctionHelper && python3 tests/run_tests.py
```

In-game: enable all five modules, `/reload` (or restart if TOC changed), `/auctionhelper` opens UI, full AH dump with house open fills prices, profession Scan stores recipes/reagents, Crafts tab shows profit.
