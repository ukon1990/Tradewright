# F143 — Destroying tab

## Summary

A new dashboard tab, "Destroying", lists the disenchantable items the player owns on every character, with what each is worth sold, vendored and disenchanted, and which is best. A strip at the top shows the data quality from F142.

## Context

- Dashboard tabs are listed in `Tradewright.DASHBOARD_TABS` (`Tradewright_TabOrder.lua`); tables use the shared table, pager and column helpers (`Tradewright_Table.lua`, `Tradewright_Columns.lua`, `MoneyColumn`).
- Owned items across characters, bags and bank come from the inventory snapshot (`Tradewright_Inventory`).
- Item values: `GetSalvageValue` / `GetSalvageInput` (E18), usual price (E06), vendor price.
- The other tabs have an "open item details" button (commit 2fccdff); this tab gets the same.

## Scope

- Tab after Crafts, label "Destroying"; module `Tradewright_SalvageTab.lua` in `Tradewright_UI`
- Rows: owned items with a salvage value. Columns: item, where (character, bags or bank), count, AH price after the cut, vendor price, disenchant value, best choice; sortable, best gain first
- Best choice and the gain over the next best come from a pure function (in `SalvageCheckLogic` or beside it), offline tested
- The value cell marks estimates and shows the casts behind counted yields in its tooltip
- Data quality strip at the top: level and reasons from F142
- Retail: an action filter (Disenchant, Prospecting, Milling); prospecting and milling only for characters that have the profession. Forever: disenchanting only, no filter
- Empty state explains why: nothing owned can be disenchanted, or no values are known yet

## Status

Implemented; offline tests and lint pass. Not yet checked in game.

- Tab "Destroying" after Crafts: `Tradewright_SalvageTab.lua` (UI), rows from `Tradewright:GetSalvageHoldingRows(action)` in `Tradewright_Inventory/src/modules/Tradewright_SalvageHoldings.lua`
- Columns: item, held by (character, "bank" when banked), quantity, auction after the cut, vendor, the action's value ("~" for researched yields), best use, gain for the stack over the next best use; sorted by gain
- Best use from `SalvageLogic.BestUse` (a tie goes to the use with the least work: vendor, then auction, then destroying)
- Strip at the top: badge for the F142 level and one line per reason; `Tradewright:SalvageCheckReasonText(reason)` turns a reason into text and is there for F144 too
- Side pane with item header (opens the item details window), the values, where the yield comes from, and the gain
- Actions: `Tradewright:GetSalvageActions()`; disenchanting always, prospecting and milling on retail once a character has the profession (`SomeCharacterHasProfession`, now public, from the tooltip code). The dropdown shows only when there is more than one action
- Choice saved as `salvage.action`

Differs from the scope:

- Pure best-use function lives in `SalvageLogic`, not `SalvageCheckLogic`
- No empty state per reason: an empty table says nothing owned has a value, and the strip above says why values are missing

Known limits:

- Soulbound is known only for banked copies (holdings save `boundInBank`) and for bind-on-pickup items; a bind-on-equip item worn once and back in the bags still shows an auction price
- Items whose info the game has not loaded yet are left out until the tab is shown again
- The warband bank (retail) is not read

## Acceptance criteria

- [ ] Items in bags and bank on several characters show up with the right counts
- [ ] Soulbound gear shows disenchant and vendor, never an AH price
- [ ] The best choice matches the highest of the three values
- [ ] The tab opens, sorts and pages without errors on Forever and retail
- [x] Offline tests for the best-choice function (and for the rows)
- [x] New files in all four TOCs; new texts written as `L["..."]` (no translation file exists yet)

## Verification

```bash
npm test
```

In game on Forever (full client restart): `/tw`, Destroying tab, compare a few rows with item tooltips.

## Dependencies

- F142, E18 F138

## Out of scope

- Moving or mailing items to the character that can disenchant
- Disenchanting from the tab
