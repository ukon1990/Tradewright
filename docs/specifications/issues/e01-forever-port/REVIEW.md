# E01 review (issue-work focus)

Reviewed against `.agents/skills/wow-addon-issue-work/focus/*`.

## code-quality

- Forever-pure helpers live in `Tradewright_ForeverLogic.lua` (testable without UI stack).
- Classic reagent empty-schematic bug fixed (`#slots == 0` after schematic walk).
- AH panel docks to `AuctionFrame` when `AuctionHouseFrame` is absent.

## lua-wow

- Optional APIs wrapped in `pcall` / capability checks (`C_EncodingUtil`, warband counts, `C_ProfSpecs`).
- Classic dump driven by `AUCTION_ITEM_LIST_UPDATE` + `CanSendAuctionQuery`.
- New TOC file `Tradewright_ForeverLogic.lua` requires a **full client restart**.

## auction-forever

- Flags: interface band, not project id alone.
- Full dump: replicate → classic `QueryAuctionItems` fallback.
- Orders / commodity buy remain `IS_RETAIL`.
- Export: `AHLUA1` when CBOR unavailable.

## Verify

```bash
cd Tradewright && python3 tests/run_tests.py
```

Result: all test files passed (post-review).
