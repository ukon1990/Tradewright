# Auction / Forever focus

## Client identity

```lua
local flags = ForeverLogic.DetectClientFlags(select(4, GetBuildInfo()), WOW_PROJECT_ID, WOW_PROJECT_MAINLINE)
-- IS_FOREVER, IS_RETAIL, IS_SUPPORTED
```

Forever shares retail’s project ID. **Interface band 16000–16999** is authoritative.

## Auction house

| Path | When |
| --- | --- |
| `C_AuctionHouse.ReplicateItems` | Prefer when present |
| Classic `QueryAuctionItems` + `GetAuctionItemInfo("list", i)` | Forever / missing replicate |

- Persist via `PersistAuctionDumpObservation` with `source = "classic_full"` or `"replicate_full"`
- Require AH open (`AuctionHouseFrame` or `AuctionFrame`)
- Do **not** call commodity purchase APIs on Forever

Reference pattern: OpenXP `ItemUpgrades.lua` AH scan.

## Professions

- Prefer `C_TradeSkillUI.GetRecipeSchematic`; if empty, classic reagent APIs / `GetTradeSkillNumReagents`
- Store Forever skill line IDs as returned (e.g. Cooking 2939) — no retail remap
- Skip `C_ProfSpecs` / crafting orders when APIs absent
- Economy dock: only when `ProfessionsFrame` exists (`IS_SUPPORTED`)

## Inventory / export

- `pcall` warband `C_Item.GetItemCount`; else bags+bank via `MaterialLogic.ResolveLocationCounts`
- Export: CBOR when `C_EncodingUtil` exists; else `AHLUA1:` plain Lua from `ForeverLogic.BuildPlainLuaExportPayload`
