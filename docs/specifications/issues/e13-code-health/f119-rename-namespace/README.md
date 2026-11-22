# F119 — Rename `ProfessionExporter` to `AuctionHelper`

## Summary

Call the addon object by the addon's name. Every `ProfessionExporter` identifier in code becomes `AuctionHelper`, and the slash command key becomes `AUCTIONHELPER`. The one-time import of the old `ProfessionExporterDB` saved data stays, marked as removable.

## Context

- The addon started as a profession exporter. `AuctionHelper.lua` creates one table and publishes it as both `_G.AuctionHelper` and `_G.ProfessionExporter`; about 1,630 uses of `ProfessionExporter` in 109 files read it, mostly as `local _, ProfessionExporter = ...` and `function ProfessionExporter:Foo()`.
- Saved data already uses the new names (`AuctionHelperDB`, `AuctionHelperProfessionsDB`, …). `AuctionHelper_DataInit.lua RunLegacyMigrationIfNeeded` imports the old `ProfessionExporterDB` / `ProfessionExporterLastExport` once, sets `AuctionHelperMigrationDB.professionExporterImported`, and clears the old globals. That is the migration the rename needs; no new one is required.
- The slash command is registered as `SLASH_PROFESSIONEXPORTER1/2` and `SlashCmdList.PROFESSIONEXPORTER`. The key is not saved anywhere; `/ah` and `/auctionhelper` stay.
- The lint baseline keys functions by name (`ProfessionExporter:BuildAggregate`), so the rename changes the keys, not the debt.

## Scope

- Rename every `ProfessionExporter` identifier in `src/**/*.lua` (code, tests) to `AuctionHelper`; keep the saved-variable names `ProfessionExporterDB` / `ProfessionExporterLastExport` and the migration flag `professionExporterImported`
- Drop `_G.ProfessionExporter`
- Slash key `AUCTIONHELPER`
- Rename the function keys in `scripts/lint-baseline.json` the same way, in the same commit; lint must report "matches baseline" with identical counts
- Mark the legacy import as removable: one comment on `RunLegacyMigrationIfNeeded` saying it can go, together with `ProfessionExporterDB` / `ProfessionExporterLastExport` in the TOCs and `.luacheckrc`, once no player has pre-AuctionHelper saved data
- Test the legacy import: an old `ProfessionExporterDB` with settings and auction data is adopted into empty new storage, the old globals are cleared, and a second run does nothing; existing new data is never overwritten
- Update `AGENTS.md`, `focus/code-quality.md` and any docs that explain the old name

## Acceptance criteria

- [ ] `grep -rn ProfessionExporter src` finds only the legacy saved-variable names, the migration and its test
- [ ] Lint counts are unchanged by the rename (356 functions, 14 files)
- [ ] The legacy import has a test and a removal note
- [ ] `npm test` passes

## Verification

```bash
npm test
grep -rn ProfessionExporter src
```

In-game (full client restart, TOC headers change) on Forever and retail: `/ah` and `/auctionhelper` open the dashboard; prices, recipes, inventory and settings from before the rename are still there.

## Dependencies

- F105, F106

## Out of scope

- Removing the legacy import (later, once no old saved data is expected)
