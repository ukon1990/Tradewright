# F115 — Split the UI files

## Summary

Break the long UI builder functions into named parts and split the UI files that are over the limits.

## Context

- `Tradewright_Chart.lua`: `CreateTimeSeriesGraph` is one 524-line closure; `paint` 184 lines, complexity 42; `BuildSharedTooltip` complexity 30. The file stands alone with a small API.
- `Tradewright_GoldDashboard.lua`: `CreateGoldDashboard` 287 lines building four cards inline.
- `Tradewright_CraftsUI.lua` (819): toolbar, details and queue pane, opportunities table, detail rendering.
- `Tradewright_InventoryUI.lua` (1041): column definitions (237 lines), filter, `CreateItemDetailPane`, panel.
- `Tradewright_UIShell.lua` (809): frame chrome, minimap button, Blizzard settings.
- `Tradewright_Widgets.lua` (942): dropdowns are about 180 lines of it.
- `Tradewright_Table.lua` (929): layout, header, pager, rows; `UpdateRow` complexity 27.
- `Tradewright_MailPanel.lua`: the send queue.
- `Tradewright_ProfessionCraftPanel.lua` (702): what is left after F112 and F113.
- `Tradewright_MarketUI.lua`, `OverviewTab`, `SalesDashboard`, `ExportTab`: long `Create` functions.
- `Tradewright_Bags/Tradewright_BagWindow.lua` (633, lint-clean): frame construction can move out to bring it under 500.
- Names: `expSel` → `expansionSelection`, `filter` (search text) → `searchText`, `yAtQ` → `yAtQuantity`.

## Scope

- Chart: a mixin with pools, series and geometry on `self`; `paint` becomes `drawAxes`, `drawQuantityColumns`, `drawSeries`, `drawAverage`, `drawLastValue`, `drawLegend`, `buildHoverTargets`
- Dashboards and tabs: one function per card or toolbar row
- New files: `CraftsToolbar`, `CraftsDetails`, `InventoryColumns`, `ItemDetailPane`, `MinimapButton`, `BlizzardSettings`, `Dropdowns`, `TableLayout` / `TableHeader` / `TablePager`, `MailSendQueue`, `BagWindowFrame` (names may change during the work)
- One file per commit; all four TOCs

## Acceptance criteria

- [ ] No UI file over 700 lines; no UI function over 40 lines or complexity 10 except entries left in the baseline with a reason
- [ ] `BagWindow.lua` under 500 lines
- [ ] Lint baseline shrinks; `npm test` passes

## Verification

```bash
npm test
```

In-game (full client restart): every dashboard tab, the item detail graph with hover, table sorting, column reorder and paging, mail send, minimap button, Blizzard settings page, bag window — on Forever and retail.

## Dependencies

- F117 (shared UI helpers), F113 (`FilterInventoryRows` and chart maths already tested)

## Out of scope

- Visual changes
