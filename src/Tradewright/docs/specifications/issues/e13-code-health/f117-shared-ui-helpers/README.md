# F117 — Shared UI helpers

## Summary

Replace the UI building blocks that were copied between dashboards and tabs with one shared version each.

## Context

- Table columns `moneyColumn`, `itemColumn`, `percent`: `GoldDashboard`, `OpportunityViews`, `IncomeDashboard`, `MailReviewPanel`, `Tradewright_Auction.lua` around 2077. `pe:CreateItemColumn` already exists in `Tradewright_Widgets.lua`.
- Dashboard card + table `createCard` / `attachTable`: `GoldDashboard`, `SalesDashboard`, `IncomeDashboard`.
- Tab adapters `CraftsTab.lua`, `MarketTab.lua`, `InventoryTab.lua` are line for line the same.
- Setting-backed dropdowns: `CraftsUI createFilter` / `createSelect` (7 and 8 params), `InventoryUI createFilterDropdown`, `SettingsTab createSelect`.

## Scope

- `Tradewright_Columns.lua` with money and percent columns; the item column reuses `CreateItemColumn`
- `pe:CreateTableCard`, `pe:MakePanelTab(id)`, `pe:CreateSettingDropdown(parent, options)` taking one options table
- Replace every copy; delete the three tab adapter files (all four TOCs)
- Move the shared dashboard helpers `CreateDashboardCard`, `CreatePeriodButtons` and `CreateStats` out of `Tradewright_SalesDashboard.lua` into the new dashboard widgets file, next to `CreateTableCard`

## Acceptance criteria

- [ ] One definition of each helper
- [ ] The three tab adapters are one call each; the files are gone from all four TOCs
- [ ] No touched function takes more than 5 parameters
- [ ] Lint baseline shrinks; `npm test` passes

## Verification

```bash
npm test
```

In-game (full client restart): every dashboard card, the Crafts, Market and Inventory tabs, their filter dropdowns and money columns look and behave as before.

## Dependencies

- F109

## Out of scope

- Splitting the UI files (F115)
