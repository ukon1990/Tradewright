# F30 — Open a deal's buy page in the auction house

## Summary

While the auction house is open, clicking a row in **Deals to buy** or **Market movers** opens that item's buy page in the auction house. With the auction house closed, the click opens the item in the Market tab, as today.

## Context

- Rows are wired in `AuctionHelper_GoldDashboard.lua` through `attachTable(..., { onClick = ..., hint = ... })`; both cards use `openMarket(pe, row)` and the hint "Click to open in Market. Shift-click to link."
- Shift-click is taken by `HandleItemRowModifiedClick` (chat link) before `onClick` runs.
- `OpenAuctionBrowseSearchForItem(itemID, itemName, quantity)` + `TrySelectPendingAuctionBrowseResult()` (`AuctionHelper_Auction.lua`) already search by name and select the result with the same item ID, which opens the commodity or item buy page.
- `SearchAuctionCartRow` shows the intended order: `PauseAuctionScanForManualBuy`, then the browse search, with `SendAuctionPanelSearchQuery` as the fallback.
- `IsAuctionHouseFrameOpen()` covers both `AuctionHouseFrame` and the classic `AuctionFrame`.

## Scope

- `ProfessionExporter:OpenItemInAuctionHouse(itemID)` in `AuctionHelper_Auction.lua`:
  - returns false when the auction house is closed
  - pauses a running scan (`PauseAuctionScanForManualBuy("dashboard_buy")`)
  - modern frame: reuse `OpenAuctionBrowseSearchForItem(itemID, nil, 1)` so the pending selection opens the buy page
  - classic `AuctionFrame` only: Browse tab, item name in the search box, run the browse search
  - when the search cannot start (throttled, item name not cached yet): one chat line, auction house left as is
- Gold dashboard, Deals to buy and Market movers: row click calls `OpenItemInAuctionHouse` when the auction house is open, otherwise `openMarket`
- Row tooltip hint follows the same rule: "Click to buy at the auction house. Shift-click to link." while it is open, else the current Market hint
- Pure decision helper in `AuctionHelper_ForeverLogic.lua`: `ResolveDealRowClick(ahOpen) -> "auction" | "market"`, with an offline test

## Acceptance criteria

- [ ] Auction house open: clicking a deal shows that item's buy page
- [ ] Works for a stackable item (commodity buy page) and for a piece of gear (item buy list)
- [ ] Auction house closed: the click opens the Market tab, as before
- [ ] Shift-click still links the item in chat
- [ ] A running full scan is paused, not broken, and the dashboard says so
- [ ] Nothing is bought: the player still clicks Buy Now
- [ ] Offline test of `ResolveDealRowClick`

## Verification

```bash
npm test
```

In-game on Forever:

1. Open the auction house → `/auctionhelper` → Overview → Gold.
2. Click a commodity deal → its commodity buy page shows.
3. Click a gear deal → its item list shows.
4. Click a deal for an item not seen this session → buy page, or one chat line if the name is not cached yet.
5. Start a full scan, click a deal → the scan pauses.
6. Close the auction house, click a deal → Market tab opens on it.

## Dependencies

- None (reuses the shopping cart's browse search)

## Out of scope

- Buying automatically, or pre-filling a quantity
- A separate Buy button per row
- "Sell what I own" → Sell tab (candidate F31)
- The Market tab's item detail pane
