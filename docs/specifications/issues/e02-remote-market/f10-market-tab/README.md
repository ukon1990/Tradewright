# F10 — Market tab shell

## Summary

Add a Market dashboard tab that lists cached AH snapshot rows with search and sortable columns.

## Scope

- `Tradewright_MarketTab.lua` + `Tradewright_MarketUI.lua`
- Register in `Tradewright_UIShell` TAB_ORDER; TOC entry (full client restart)
- Columns: name, min (unit), max (unit), qty, listings, seen

## Acceptance criteria

- [x] Tab visible and switchable
- [x] Empty state when no snapshot
- [x] Search + sort work offline from SavedVariables

## Out of scope

- Live AH queries; history detail (F11)
