# AGENTS.md — Tradewright (Forever)

## Product

**Tradewright** — multi-module auction / profession / inventory helper pack, adapted for **WoW Forever** (`Interface 16001`, game type `camelot`). Prices come from the classic auction house when retail replicate APIs are missing; profession recipes and craft profit still drive the dashboard.

## Runnable pieces

| Piece | Path | Notes |
| --- | --- | --- |
| Core | `src/Tradewright/` | Shared runtime, flags, export, events |
| Auction | `src/Tradewright_AuctionData/` | Snapshot / full scan / AH panel |
| Professions | `src/Tradewright_Professions/` | Scan, crafts engine (orders stay retail-only) |
| Inventory | `src/Tradewright_Inventory/` | Bags/bank snapshot, ledger |
| UI | `src/Tradewright_UI/` | Dashboard, craft panel, mail |
| Bags (optional) | `src/Tradewright_Bags/` | Bag and bank window grouped by category, other characters as tabs, multi-select; own on/off switches |
| Pure helpers | `src/Tradewright/src/util/Tradewright_*Logic.lua` | No WoW API, offline-testable: `ForeverLogic` (client flags, storage keys, export encoding), `AuctionLogic`, `MarketLogic`, `MailLogic`, `IncomeLogic`, `FilterLogic`, `MaterialLogic`, `SkillUpLogic`, `LevelingRouteLogic`, … |
| Tests | `src/Tradewright/tests/run_tests.py` | Offline Lua 5.1 (no WoW client) |
| Lint | `scripts/lint.py`, `.luacheckrc`, `scripts/lint-baseline.json` | luacheck + file/function size + complexity, ratcheted |
| Specs | `src/Tradewright/docs/specifications/` | Issues / backlog |
| Deploy | `scripts/deploy.mjs`, `deploy.config.json` | Copies `src/*` into the game AddOns folders |
| Saved-data move | `scripts/migrate-saved-data.mjs` | One-time: carries saved data from the old name (AuctionHelper) over to Tradewright |

## Repo layout

- `src/` holds only the addon folders; each `src/<Addon>/` is copied verbatim into `Interface/AddOns/<Addon>/`.
- Repo tooling (agents, skills, scripts, `package.json`) lives at the root and is never deployed.
- `tests/`, `docs/`, dotfiles and `*.md` inside addon folders are excluded from deploy (see `deploy.config.json`).

## Dependencies

| Dep | TOC | Usage |
| --- | --- | --- |
| Blizzard_Professions | `OptionalDeps` | Soft; Forever may ship a subset of DF profession UI |
| Questie, QuestieDB | `OptionalDeps` (AuctionData) | Soft; vendor places for vendors not visited yet |
| TomTom | none | Soft; waypoint arrow when the game's own is unavailable |

Load order: `Tradewright` → `Tradewright_AuctionData` + `Tradewright_Professions` → `Tradewright_Inventory` → `Tradewright_UI` → `Tradewright_Bags` (optional; the pack works without it).

## Hard rules

- **Code must be maintainable by a human**: a developer new to a file can read, understand and safely change it. Lint limits, names, comments and tests serve this; passing lint is not enough. Details: `.agents/skills/wow-addon-issue-work/focus/code-quality.md`.
- Clear names, one word per concept (see the glossary in `focus/code-quality.md`). Comments explain why, API quirks or invariants; no feature or epic ids in code comments (they belong in commit messages and issue files).
- Tests guard behaviour that could break (math, selection, saved formats, Forever-vs-retail branches); no tests for their own sake.
- Forever detection is by **interface version** `16000–16999`, not `WOW_PROJECT_ID` alone (Forever shares mainline project id).
- `IS_RETAIL` = true mainline only; `IS_SUPPORTED` = retail **or** Forever.
- Midnight-only systems (crafting orders, concentration, commodity auto-buy, warband when API missing) stay behind `IS_RETAIL` / capability checks.
- No protected API automation (ToS). AH scan and profession craft clicks use public APIs only.
- KISS / DRY / minimal LOC — see `.agents/skills/wow-addon-issue-work/focus/code-quality.md`.
- Quality gate (enforced by `npm test`): files ≤ 700 lines, functions ≤ 40 lines, complexity ≤ 10, ≤ 5 params, luacheck clean. Existing debt is frozen in `scripts/lint-baseline.json`; new code must meet the limits and legacy offenders may not grow. Fix failures in code, never by loosening the baseline; run `npm run lint:baseline` only when lint reports debt went down.
- New WoW API / SavedVariable / slash command → add it to `.luacheckrc` (`read_globals` / `globals`).
- `Tradewright_Bags` must stay optional: nothing outside it may require it (check `pe.ApplyBagTakeover ~= nil`), and it replaces no game global, so its switch works without `/reload`.
- Each addon ships **four TOCs**: `<Addon>_Mainline.toc` (retail, `120000, 120001` / `standard`), `<Addon>_Forever.toc` + `<Addon>_Camelot.toc` (Forever, `16001…` / `camelot`), and `<Addon>.toc` (fallback, Forever headers). The client loads the flavor-suffixed one. When adding/removing a `.lua` or changing a header, edit **all four** — only `Interface` and `AllowLoadGameType` may differ (`npm test` enforces this).
- New `.lua` files need a **full client restart**; `/reload` only reloads already-listed TOC files.

## Agent skills

Load from `.agents/skills/` (`.claude/skills` is a symlink to the same folder):

- `wow-addon-dev` — TOC, SavedVariables, Forever vs retail flags
- `wow-addon-issue-planning` — draft → confirm → write issues
- `wow-addon-issue-work` — implement + review + verify
- `focus/code-quality.md`, `focus/lua-wow.md`, `focus/auction-forever.md`

## Verify

```bash
npm test             # offline Lua tests, then lint
npm run lint         # lint only (luacheck + size/complexity ratchet)
npm run lint:baseline  # lock in reduced debt after a cleanup
```

Lint requires `luacheck` on PATH (`sudo pacman -S luacheck`, or `luarocks install luacheck`; `LUACHECK=/path` overrides). Full tool setup: [README.md](README.md#setup).

## Deploy

```bash
npm run deploy           # all targets
npm run deploy:forever   # Forever only
npm run deploy:retail    # retail only
npm run deploy:dry       # show what would be replaced
```

Each deploy deletes and recopies every addon folder found in `src/` in the target `Interface/AddOns`, and removes the folders listed under `retired` in `deploy.config.json` (the pack's earlier name). Target paths are in `deploy.config.json`; per-machine overrides go in untracked `deploy.config.local.json` (`{"targets": {"forever": "..."}}`).

In-game: enable the five core modules (and `Tradewright_Bags` for the bag window), `/reload` (or restart if TOC changed), `/ah` (or `/tradewright`) opens UI, full AH scan with house open fills prices, profession Scan stores recipes/reagents, Crafts tab shows profit.
