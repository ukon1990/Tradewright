# F118 — Split `Tradewright_Data.lua`, `Tradewright_Util.lua` and `Tradewright_ForeverLogic.lua`

## Summary

Split the three core files that mix several jobs, so a reader finds the profession scan, the export, the slash commands and the pure logic where their names say.

## Context

- `Tradewright_Data.lua` (2587 lines, 37 over-limit functions): profession scan and spec tree; export building; the copy box (UI inside a core file); slash commands. `CollectSpecializationTreeForSkillLine` has complexity 64.
- `Tradewright_Util.lua` (690): JSON codec; item and recipe descriptors.
- `Tradewright_ForeverLogic.lua` (778, tested): mail planning (`ResolveSellerCharacter`, `BuildMailPlan`, `BuildReturnToSellerPlan`) belongs in `MailLogic`; market browser and history in a new `MarketLogic.lua`.

## Scope

- Data: `ProfessionScan`, `ProfessionSpecTree`, `ExportBuild`, `CopyBox`, `SlashCommands` (names may change)
- Util: `JsonCodec`, `ItemInfo`
- ForeverLogic: mail planning to `MailLogic`, market functions to `MarketLogic`
- One new file per commit, moving code only; renames in separate commits
- All four TOCs of `Tradewright`; full client restart after each new file
- Tests keep passing unchanged except for the files they load

## Acceptance criteria

- [ ] No file in `src/Tradewright/src` over 700 lines; new files under 500
- [ ] `ForeverLogic` holds client flags, storage keys and export encoding only
- [ ] Lint baseline shrinks; `npm test` passes

## Verification

```bash
npm test
```

In-game after every commit (full client restart), on Forever and retail: profession Scan; export copy box; every `/ah` subcommand from `/ah help`; mail plan.

## Dependencies

- F110 (slash dispatch tables first), F113

## Out of scope

- Renaming `ProfessionExporter` (F119)
