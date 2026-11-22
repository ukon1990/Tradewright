# F80 — Gold changes by source

## Summary

Every change to the character's gold is filed as gold in or gold out under one source: Vendor, Quests, Loot, Auction house, Mail, Trade or Other. Totals are kept per character, per day and per source.

## Context

- `Tradewright:PLAYER_MONEY` (`Tradewright_Events.lua`) only records the new balance. The change itself is `GetMoney()` minus the last known balance.
- The source comes from what is happening when the change lands:
  - Vendor: between `MERCHANT_SHOW` and `MERCHANT_CLOSED`. A gain is a sale; a loss is a purchase or repair.
  - Quests: a `QUEST_TURNED_IN` (or the quest reward frame closing) just before the change.
  - Loot: a `CHAT_MSG_MONEY` / looted-coin message just before the change.
  - Auction house: in the mailbox, the money of a sale or outbid invoice taken (`TakeInboxMoney` is already hooked for sales); at the auction house, deposits and buyouts.
  - Mail: any other money taken from the mailbox, and COD paid.
  - Trade: between `TRADE_SHOW` and `TRADE_CLOSED`.
  - Other: anything else (trainers, flights, auction house cancel fees no other rule caught).
- These events exist in the Classic code base; each needs an in-game check on Forever. When a window event is missing on the client, its gold falls to Other.
- The addon must not act for the player; this only listens.

## Scope

- New `src/Tradewright/src/util/Tradewright_IncomeLogic.lua` (all four core TOCs, loaded by `run_tests.py`)
- `IncomeLogic.ClassifyMoneyChange(delta, context, now)` → source key. `context` holds the open windows and the times of the latest quest turn-in, coin loot, invoice taken and trade
- `IncomeLogic.AddToDay(days, day, source, delta)` → updates `{gain, spend}` for that day and source
- The source is decided `EVENT_WINDOW` (2 s) after the change, so an event arriving just after the gold still counts; a window that closed within that time still counts
- Saved in `TradewrightInventoryDB.ledger.income[characterKey][day][source] = {gain, spend}` (copper, day = UTC day number); days older than 400 are dropped at login
- A small listener module in `Tradewright_Inventory` keeps the context and the last balance, and writes on each `PLAYER_MONEY`. The first balance after login is a baseline, not income
- Vendor sales also write a ledger event `kind = "vendor"` with item, quantity and the vendor price paid, from the bag item used (right-click) while the merchant is open; one event per item, character and day (`IncomeLogic.MergeIntoDayEvent`)
- Known gaps: an item dragged onto the merchant gets its gold under Vendor but no `vendor` ledger event; gold back from an outbid auction comes without an invoice and counts as Mail
- `.luacheckrc`: any new events or globals

## Acceptance criteria

- [x] Selling an item to a vendor adds its price to Vendor in, and writes one `vendor` ledger event
- [x] Repairing adds to Vendor out
- [x] A quest that pays 1g adds 1g to Quests in
- [x] Looting coin adds to Loot in
- [x] Taking auction sale gold adds to Auction house in; taking gold a player mailed adds to Mail in
- [x] Posting an auction adds the deposit to Auction house out
- [x] Logging in, or a `/reload`, adds nothing
- [x] The days of each source add up to the change in the balance over the same days
- [x] Offline tests: each source rule, overlapping windows (mailbox and merchant never both open; the latest event wins), baseline after login, dropping old days

## Verification

```bash
npm test
```

In-game on Forever: note your gold → sell to a vendor, repair, turn in a quest, loot coin, collect one auction sale and one player mail → `/dump TradewrightInventoryDB.income` shows each under its source, and the totals match the change in gold.

## Dependencies

- None. F70 (farm window) should read its coin and vendor numbers from this listener rather than keep its own.

## Out of scope

- Which mob or zone the coin came from (F70)
- Splitting Other further
