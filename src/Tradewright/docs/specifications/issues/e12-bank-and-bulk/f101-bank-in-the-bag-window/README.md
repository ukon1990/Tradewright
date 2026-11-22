# F101 — Bank in the bag window

## Summary

At a banker, the Bank view of the logged-in character is live: use, drag, split and take items out. On retail the Warband bank tab is live too. A setting gives the game's bank window back.

## Context

- `Tradewright_Holdings.lua` (inventory module) already knows the bank's and the warband bank's containers and whether the bank is open; it exposes them as `GetBankBagIDs`, `GetWarbandBagIDs` and `IsBankOpen`.
- `ScanBags` and the live slots take any bag ID.
- The game's `BankFrame` must stay shown for the bank session to last (see E12).

## Scope

- `ScanBags(bagIDs)`: scans the given containers; default the carried bags
- View: the logged-in character's Bank mode and the Warband bank tab are live while the bank is open, read-only otherwise. The free-slot tile, the slot count and the footer follow the containers shown
- `Tradewright_BagBank.lua`: setting `bags.bank` (default on). On: `BankFrame` is made invisible; opening the bank opens the bag window on the Bank view; closing the bag window closes the bank. Off: `BankFrame` gets its alpha and scale back
- Settings → Bags: "Use Tradewright for the bank"
- The window redraws on bank slot changes

## Acceptance criteria

- [ ] Opening the bank shows the bag window on Bank, with the bank's items under category headings
- [ ] Right-clicking a bank item moves it to the bags; right-clicking a bag item in the Bags view deposits it
- [ ] Away from a banker, the Bank view is the saved list as before
- [ ] Closing the bag window ends the bank session
- [ ] Setting off: the game's bank window is visible again at once
- [ ] Forever shows no warband tab

## Verification

```bash
npm test
```

In-game: open the bank on Forever and on retail; switch the setting off and on while it is open.

## Dependencies

- F92, F94

## Out of scope

- Buying tabs or bank bag slots, deposit buttons, warband gold
