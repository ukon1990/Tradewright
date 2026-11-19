# F13 — Market offline tests

## Summary

Lua 5.1 tests for aggregate enrichment, market row builders, and history series.

## Scope

- Extend `tests/test_forever_logic.lua` (or dedicated `test_market_browser.lua`)
- Cover filter/sort and history bucket normalization

## Acceptance criteria

- [x] `python3 tests/run_tests.py` green
- [x] No WoW client required

## Verification

```bash
cd AuctionHelper && python3 tests/run_tests.py
```
