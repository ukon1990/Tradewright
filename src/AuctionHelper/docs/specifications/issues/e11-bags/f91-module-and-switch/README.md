# F91 — Bags module and its on/off switch

## Summary

`AuctionHelper_Bags` is its own addon. When it is on, the bag key, bag buttons, merchants and mail open the AuctionHelper bag window instead of the game's. A checkbox, `/ah bags`, or a right-click on the window's title bar turns it off at once; disabling the addon does the same.

## Context

- Each addon ships four TOCs (`npm test` checks them); the TOC test and `.luacheckrc` list addons and globals by name.
- Bag opening goes through `ToggleAllBags`, `OpenAllBags`, `CloseAllBags`, `ToggleBackpack`, `OpenBackpack`, `CloseBackpack`, `ToggleBag`, `OpenBag`, `CloseBag`. Hooking them with `hooksecurefunc` and then mirroring whether a game bag frame is shown avoids replacing any global.

## Scope

- `src/AuctionHelper_Bags/`: four TOCs, `Bootstrap.lua`, depends on the other five addons. Its SavedVariable `AuctionHelperBagsDB` is only read once, to move counts saved by the first version into the inventory database
- `AuctionHelper_BagSwitch.lua`: `IsBagWindowEnabled`, `SetBagWindowEnabled`, `ApplyBagTakeover`
  - on: the game's bag frames are reparented to a hidden frame; after each bag function the window is shown or hidden to match them
  - off: the frames get their parents back and the window hides
  - closing the window (button or Escape) closes the game's bags too
- Setting `bags.enabled` (default on)
- `/ah bags [on|off]` by wrapping `HandleSlash`; right-click on the title bar switches to the game's bags and prints how to switch back
- Settings → Inventory & mail → "Bags" group, shown only when the module is loaded: the switch with a note, other characters as tabs, junk sell value, bag row open, slots per row, slot size
- TOC test, `.luacheckrc`, `AGENTS.md`, `README.md` and the wow-addon-dev skill name the sixth addon

## Acceptance criteria

- [ ] Module enabled and switch on: the bag key opens and closes the AuctionHelper window; the game's bag frames are not visible
- [ ] Opening a merchant or the mailbox opens the window; closing them closes it, as the game does with its own bags
- [ ] Switch off (checkbox, `/ah bags`, title bar right-click): the game's bags open instead, without `/reload`
- [ ] Module disabled in the AddOns list: no Bags group in Settings, nothing else changes
- [ ] Escape closes the window

## Verification

```bash
npm test
```

In-game on Forever: bag key, B, a bag button on the bag bar, a merchant and the mailbox each open the window → `/ah bags` → each opens the game's bags → `/ah bags` again → back.

## Dependencies

- F92 for the window it shows

## Out of scope

- Detecting other bag addons; the player chooses with the switch
