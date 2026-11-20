# F51 — Sure things: listed under vendor price

## Summary

A "Sure things" list in Opportunities shows auctions priced below what a vendor pays for the item. Buying and vendoring them is a profit that does not depend on anyone else buying.

## Context

- `GetItemVendorSellCopper` (`AuctionHelper_Util.lua`) reads the vendor sell price from the game's item info; today it is used only for vendor-sourced recipes.
- Item info loads asynchronously, so a price can be missing on first ask.
- Vendor prices can change with a hotfix (Blizzard cut two on Forever on 10 November 2026), so they are read fresh, not stored for good.
- No auction cut applies to a vendor sale; the only costs are the purchase and bag space.

## Scope

- `ForeverLogic.BuildVendorRows(items, vendorSellFn, opts)`, pure: for each item whose lowest price is under its vendor price, walk the price steps (F41) while `price < vendorSell`; `qty`, `cost`, `gain = qty × vendorSell - cost`; dropped when `gain < opts.minGain` (default 10s). Without steps the row uses the lowest price and quantity 1.
- Items with no vendor price (0 or unknown) are skipped; unknown ones are retried when their item info arrives
- Evaluation is chunked with the rest of `GetMarketInsights` and cached per scan revision
- List columns: Item, Listed at, Vendor pays, Qty, Gain. Sorted by Gain.
- Side pane: cost, vendor total, gain, bag slots needed
- Setting "Show items listed under their vendor price" (on)
- Empty state: "Nothing is listed under vendor price in the last scan."

## Acceptance criteria

- [ ] An item listed at 1s with a vendor price of 2s 50c appears with the right quantity and gain
- [ ] An item with no vendor price never appears
- [ ] Gain is not reduced by the auction cut
- [ ] The list refreshes after a new scan and after item info loads
- [ ] Offline tests: several steps under vendor price, step exactly at vendor price (excluded), missing vendor price, gain floor

## Verification

```bash
npm test
```

In-game: full scan → Opportunities → Sure things → right-click a row with the auction house open → the listing is there at that price.

## Dependencies

- F50 (tab), F41 (quantities)

## Out of scope

- Disenchant, prospecting and milling value
- Bids
- Selling to the vendor for the player
