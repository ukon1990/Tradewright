# E02 review (focus files)

## code-quality

- Pass: Market UI is a focused module (`MarketUI`/`MarketTab`); Forever-pure builders live in `ForeverLogic`.
- Pass: Replicate dump reuses `AggregateClassicAuctionRow` instead of a third copy of min-only aggregation.
- Pass: No speculative frameworks; enrichment is two compact fields (`n`, `h`).

## lua-wow

- Pass: Lua 5.1 offline tests cover aggregate enrichment, row filter/sort, history series.
- Pass: New TOC entries listed (`MarketUI`, `MarketTab`) — **full client restart required**.
- Pass: UI uses existing table/graph widgets; no unprotected automation.

## auction-forever

- Pass: Browse is snapshot/history only — no live remote AH queries.
- Pass: Classic + replicate dumps both persist listingCount / marketHigh.
- Pass: Retail sell inject / Midnight gates untouched.

## Verify

```bash
cd Tradewright && python3 tests/run_tests.py
```

In-game: full client restart → full AH dump → Market tab search/sort → row detail + history graph.
