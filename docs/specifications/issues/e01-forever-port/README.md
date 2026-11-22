# E01 — Forever port

## Summary

Make the Tradewright pack load and work on WoW Forever 1.60.1 (interface 16001, camelot): classic AH pricing, vanilla profession recipes, inventory, craft profit, dashboard. Midnight-only systems stay off when APIs are missing.

## Context

- Forever shares retail’s `WOW_PROJECT_ID`; detect with interface `16000–16999`.
- Working Forever AH code uses `QueryAuctionItems` / `GetAuctionItemInfo` (see OpenXP).
- Retail pack targeted Interface 120000 + `AllowLoadGameType: standard` + hard `Blizzard_Professions`.

## Scope

- TOC retarget + optional Blizzard_Professions
- `IS_FOREVER` / `IS_RETAIL` / `IS_SUPPORTED`
- Classic full AH dump fallback
- Classic reagent fallback; inventory warband-safe counts
- `AHLUA1` export when `C_EncodingUtil` missing
- Offline tests + AGENTS.md + `.agents` skills

## Acceptance criteria

- [x] Five TOCs load on Forever (`16001`, `camelot`)
- [x] Full dump works without `ReplicateItems`
- [x] Profession scan / crafts / inventory gated on `IS_SUPPORTED`
- [x] Crafting orders remain `IS_RETAIL`
- [x] `python3 tests/run_tests.py` passes

## Verification

```bash
cd Tradewright && python3 tests/run_tests.py
```

In-game: `/tradewright`, AH full dump, profession Scan, Crafts profit.

## Out of scope

- Full vanilla rewrite of shopping-cart commodity auto-buy
- Midnight spec trees / crafting orders feature parity
