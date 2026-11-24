# F141 — Disenchant as a give-back choice in the leveling route

## Summary

The leveling route's give-back dropdown gets a fourth choice, "Disenchant": each crafted item counts for what disenchanting it gives, and items that cannot be disenchanted count for their vendor price. The player sees the cost of leveling when the crafts are destroyed, even without a character that can disenchant.

## Context

- Give-back choices live in `Tradewright_ProfessionLevelingView.lua` (`vendor`, `auction`, `none`), saved as `professions.leveling.giveBack`, applied by `LevelingRouteLogic.GiveBack(candidate, giveBackMode)`.
- Candidates get `vendorGiveBack` and `auctionGiveBack` in `Tradewright_LevelingRoute.lua` (`giveBackPerCraft`, line ~244).
- `Tradewright:GetSalvageInput("disenchant", itemID)` returns nil for items that are not weapons or armour (bags, ammo pouches, kits); `GetSalvageValue` returns `{ value, basis, casts, unvalued }` per destroyed item.
- `Tradewright_ProfessionLevelingView.lua` is at 600 of 700 lines: new display code goes in a helper or a new file.

## Scope

- Candidate gets `disenchantGiveBack` (value times output quantity) and `disenchantBasis` ("estimate" or counted casts) when the crafted item can be disenchanted and has a value
- `LevelingRouteLogic.GiveBack`: mode "disenchant" returns `disenchantGiveBack`, else `vendorGiveBack`, else 0
- Dropdown: "Disenchant" between "Sell at auction" and "Worth nothing"
- The summary card's second figure is labelled for the chosen mode ("Disenchanted" for this one)
- A step whose give-back rests on shipped yields says so in its detail ("disenchant value is an estimate"); the step tooltip shows the disenchant value next to "Sells to a vendor for"
- No check of whether the player can disenchant: the route is about cost, not who does it

## Status

Implemented; offline tests and lint pass. Not yet checked in game.

- `LevelingRouteLogic.GiveBack` mode "disenchant": `disenchantGiveBack`, else `vendorGiveBack`, else 0
- `priceCandidate` (`Tradewright_LevelingRoute.lua`) sets `disenchantGiveBack` and `disenchantBasis` for every candidate whose crafted item has a disenchant value, whatever mode is chosen, so switching mode only rebuilds the route, not the pricing
- Dropdown choice "Disenchant", card label "Disenchanted", step detail "disenchant estimated" in that mode when the value rests on researched yields, tooltip line "Disenchants for" (with "(estimate)") beside "Sells to a vendor for"

Differs from the scope:

- The view grew by 25 lines (625 of 700), small enough to stay in the file; no new file

Known limit: an item the game has not loaded yet (`GetItemInfo` still empty) gets no disenchant value and counts its vendor price until the route is priced again. Crafted items of an open profession are normally loaded.

## Acceptance criteria

- [ ] With "Disenchant" chosen, green gear crafts lower the route's net cost by their disenchant value; bags and ammo pouches count their vendor price
- [ ] The choice is saved and survives `/reload`
- [ ] On a character with no enchanter on any character, the choice still works
- [x] Offline tests in the leveling route tests: the new mode, the vendor fallback, and a route that changes recipe once disenchant value is counted
- [x] New texts written as `L["..."]` (no translation file exists yet; the locale check passes)

## Verification

```bash
npm test
```

In game on Forever: open Leatherworking, switch the give-back choice between the four values, check the Net cost card and a step tooltip.

## Dependencies

- E18 F138 (`GetSalvageValue`)

## Out of scope

- "Best of" disenchant, auction and vendor per item
- Prospecting and milling of gathered materials in the route (E18 F134)
