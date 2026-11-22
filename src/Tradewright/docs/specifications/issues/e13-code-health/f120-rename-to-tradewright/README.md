# F120 — Rename the pack from `AuctionHelper` to `Tradewright`

## Summary

The pack is going public. "AuctionHelper" covers one of its six modules and is easy to confuse with Auctionator and Auctioneer, so the pack is renamed **Tradewright**. Existing saved data moves over with a one-time script; nothing about the rename ships as migration code in the addon.

## Context

- The game keeps saved data in `WTF/Account/<account>/SavedVariables/<AddonFolder>.lua`. A renamed folder cannot read the old file, so the data has to be moved outside the game.
- Only the author has saved data, in a Forever and a retail install.
- Outside tools parse the export format, so it does not change.

## Scope

- Folders, file names, the four TOCs per addon, the shared global table, saved-variable names and frame names take the new name
- Slash commands: `/ah` and `/ahfarm` stay; `/auctionhelper` becomes `/tradewright`
- `DISPLAY_NAME` in `Tradewright.lua` holds the name players see
- `scripts/migrate-saved-data.mjs` copies `AuctionHelper*.lua` saved data to `Tradewright*.lua` with the variable names renamed, and renames the pack's entries in each character's `AddOns.txt`
- `npm run deploy` removes the `retired` folders listed in `deploy.config.json`
- The one-time `ProfessionExporter` import (F119) is removed together with its saved variables and test

## Deliberately unchanged

- Export tags `AHLUA1`, `AHCBOR1`, `AHPAGE` and `meta.generatedBy = "AuctionHelper"`
- `DASHBOARD_ACCOUNT_KEY = "__AH_ACCOUNT__"`, a key inside saved data
- The short local `pe`, and `AH_*` / `ah*` names, which read as "auction house"

## Acceptance criteria

- [x] `npm test` passes
- [x] `git grep -i auctionhelper` finds only the `generatedBy` line, the migration script, the `retired` list and docs that describe the rename
- [x] The migration script, run on a copy of the Forever data, gives files with the same top-level keys and the same ledger
- [ ] In-game on Forever and retail: history, prices, recipes, holdings and settings from before the rename are present

## Verification

With the game closed:

```bash
npm run migrate:saved-data -- --dry-run
npm run migrate:saved-data
npm run deploy
```

In-game (full client restart): the addon list shows only Tradewright modules; `/ah` and `/tradewright` open the dashboard; ledger, income, price history, profession scans and other characters' holdings are there; the bag and farm windows reopen where they were; an export still starts with `AHCBOR1` or `AHLUA1`.

## Dependencies

- F119
