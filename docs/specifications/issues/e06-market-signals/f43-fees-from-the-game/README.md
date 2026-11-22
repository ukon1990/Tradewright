# F43 — Fees read from the game and measured from sale mail

## Summary

Profit figures use the fees the game really charges: the deposit the client quotes for a posting, and the auction cut measured from your own sale mail. The fixed 5% becomes a fallback, shown as such.

## Context

- The cut is the literal 0.05 in `ClassifyMarketItem` (`gain = ref × (1 - 0.05) - price`), in the craft profit path ("Auction cut 5%") and in the owned-auction maths.
- Retail's 5% cut and 15/30/60% deposit schedule come from the reference wiki. For Forever no official or wiki source gives the cut, the deposit rule, the listing durations or the minimum deposit; community figures conflict (5% and 10% both appear) and neutral houses are reported at 15%.
- A sale mail carries the numbers: `GetInboxInvoiceInfo(index)` returns `invoiceType, itemName, playerName, bid, buyout, deposit, consignment`. The cut is `consignment / bid`.
- `C_AuctionHouse.CalculateItemDeposit` and `CalculateCommodityDeposit` are listed for the forever game type; the classic frame has `CalculateAuctionDeposit`. `auction.itemDepositPerUnit` already caches deposits seen while posting.
- The ledger writes a sale event when the mail's gold is taken (`Tradewright_Ledger.lua`).
- Design: [Settings, new groups](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldSettings).

## Scope

- Ledger sale events gain `consignmentCopper`, `depositCopper` and `house` (faction or neutral, from where the auction was posted when known, else nil)
- `ForeverLogic.MeasureAuctionCut(saleEvents, minSales)` → `{cut, sales}`: the median of `consignment / bid` over the latest sales, nil below `minSales` (5)
- One accessor, `Tradewright:GetAuctionCut(house)`: measured value → the setting → 0.05. Every literal 0.05 for the cut goes through it.
- Deposits: when the auction house can quote one, store it per item and duration in `itemDepositPerUnit`; `ForeverLogic.ExpectedDepositLoss(deposit, saleChance)` = `deposit × (1 - p) / p`, with `p` from F44 or 0.5 when unknown
- Settings group "Fees": "Auction cut" with choices "Measured from my sales: N%", 5%, 10%, 15%; a line saying how many sales the measurement uses
- Crafts and Opportunities footers name the cut in use ("Auction cut 5%, measured")

## Status

Implemented, in-game check pending:

- Sale events record `consignmentCopper` and `depositCopper`
- `IncomeLogic.MeasureAuctionCut` (median over the latest 50 sales, nil below 5) and `FlipLogic.ExpectedDepositLoss`; they live there, not in `ForeverLogic`, which is kept for client flags and export encoding
- `Tradewright:GetAuctionCut()` and `DescribeAuctionCut()` in `Tradewright_Util.lua`; the one default is `Tradewright.DEFAULT_AUCTION_CUT`. The setting is `fees.auctionCut` ("measured", 5, 10 or 15); the unused `crafts.ahCutPercent` is gone
- Settings → Prices → Fees, and the cut named in the Crafts note and the Opportunities footers

Still open:

- `house` on sale events: the mail does not say which auction house an item was posted in
- Deposits are stored per item, not per duration
- GetAuctionCut takes no `house` argument for the same reason

## Acceptance criteria

- [ ] After 5 collected sale mails the Settings line shows the measured cut and the sale count
- [ ] With fewer than 5 sales the fallback is used and labelled "not measured yet"
- [ ] Changing the setting changes Deals, Crafts profit and owned-auction figures together
- [ ] A client without `GetInboxInvoiceInfo` or without a deposit function keeps working on the fallback
- [x] Sale events saved before this feature still load and are ignored by the measurement
- [x] No literal 0.05 for the cut remains outside the accessor and its default
- [x] Offline tests: median over mixed cuts, fewer than `minSales`, missing fields, expected deposit loss at p = 1 and p unknown

## Verification

```bash
npm test
```

In-game on Forever: sell 5 items, collect the mail → Settings → Fees shows the measured cut → compare with gold received ÷ sale price on one mail. Post an item → the stored deposit matches what the auction house showed.

## Dependencies

- None (F44 later supplies the sale chance)

## Out of scope

- Guessing Forever's deposit formula
- Posting durations and undercut rules
