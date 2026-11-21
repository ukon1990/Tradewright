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

- `AuctionHelper:OpenItemInAuctionHouse(itemID)` in `AuctionHelper_Auction.lua`:
  - returns false when the auction house is closed
  - pauses a running scan (`PauseAuctionScanForManualBuy("dashboard_buy")`)
  - modern frame: reuse `OpenAuctionBrowseSearchForItem(itemID, nil, 1)` so the pending selection opens the buy page
  - classic `AuctionFrame` only: Browse tab, item name in the search box, run the browse search
  - when the search cannot start (throttled, item name not cached yet): one chat line, auction house left as is
- Gold dashboard, Deals to buy and Market movers: left click opens the item details window; right click calls `OpenItemInAuctionHouse` when the auction house is open, otherwise `openMarket`
- Sell what I own: left click opens the item details window; right click opens Market
- Item details window (`ShowItemDetailsWindow`): the Inventory item pane (owned, craft cost, chart, recipes) next to the Market listing history (facts, hourly price graph, recent hours); movable, closes with Escape
- Row tooltip hint names both clicks: "Click for price history · Right-click to buy at the auction house · Shift-click to link" while it is open, else "… Right-click to open in Market …"
- When the buy page loads, its lowest price, quantity and auction count are saved to the item's full-scan entry (the one Market and the dashboard read) if any of them changed; otherwise the entry is only marked as seen now. The dashboard rebuilds right away.
- Pure decision helper in `AuctionHelper_ForeverLogic.lua`: `ResolveDealRowClick(button, ahOpen) -> "details" | "auction" | "market"`, with an offline test

## Acceptance criteria

- [x] Auction house open: clicking a deal shows that item's buy page (now right click)
- [ ] Left click on a deal, mover or owned item opens the item details window with the price history
- [ ] Works for a stackable item (commodity buy page) and for a piece of gear (item buy list)
- [ ] Auction house closed: right click opens the Market tab, as before
- [ ] Shift-click still links the item in chat
- [ ] A running full scan is paused, not broken, and the dashboard says so
- [ ] Nothing is bought: the player still clicks Buy Now
- [ ] After the search, the deal's price, Listed quantity and "seen" time match the auction house
- [x] Offline test of `ResolveDealRowClick`
- [x] Offline test of `LiveSearchDiffers`

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
- "Sell what I own" → Sell tab (candidate F31)
- The Market tab's item detail pane
