# F138 — Use the value

## Summary

The value of disenchanting, prospecting and milling shows where it helps a decision: profit of a queued salvage recipe, give-back in the leveling route, and a tooltip line on the items themselves.

## Context

- After F134 a salvage recipe has a cost but no sale value; after F135 to F137 an input has an expected value.
- Tooltip lines are built in `TooltipLogic.BuildLines` from the summary `BuildItemGoldSummary` fills (`Tradewright_ItemTooltip.lua`).

## Scope

- The evaluation of a salvage recipe gets its sale value from `SalvageLogic.Value`, so the queue line, the Recipe view and the Crafts tab show profit
- Leveling route: the value counts as give-back when crafted items are counted as sold
- Tooltip line on gear, ore and herbs with the value of the action, marked as an estimate or with the number of own casts
- The input for a queued salvage recipe may be picked by best profit; the leveling route keeps cheapest cost

## Status

Implemented; offline tests cover the route's give-back and the tooltip line. Not yet checked in game.

- `Tradewright:GetSalvageValue(action, input)` values what one destroyed item gives: each result at the better of its AH price after the cut and its vendor price
- A salvage recipe's evaluation takes that as its sale, so queue lines, the Recipe view and the Crafts tab show profit when a yield is known
- The leveling route counts it as give-back when crafted items are counted as sold at auction; never as a vendor sale
- Tooltips of gear, ore and herbs show "Disenchant value", "Prospecting value" or "Milling value" per item, followed by "estimate" (researched yields) or the number of counted outcomes

Added on request:

- Prospecting and milling values are for the amount one cast takes ("Prospecting value, for 5"), and a line shows only when one of the player's characters has the profession
- The tooltip of an item got from prospecting or milling lists up to three ores or herbs it has come from, what one cast gives of it, and what one then costs at the input's AH price, cheapest first ("Milled from"). Only counted outcomes; not for disenchanting

Differs from the scope:

- The input of a queued salvage recipe is still picked by cheapest cost, not best profit
- Retail has no researched yields (F137), so retail shows a value only for items with counted outcomes
- The Recipe view's "sale before the cut" shows the same figure as after it for a salvage recipe, as the value mixes auction and vendor prices

## Acceptance criteria

- [ ] A queued Prospecting line shows a profit instead of "unknown" once yields are known
- [ ] The tooltip of a disenchantable item shows its value and where the numbers come from
- [ ] With no yield known, everything reads as before
- [ ] Offline tests for the tooltip line and the profit of a salvage evaluation

## Verification

```bash
npm test
```

## Dependencies

- F134, F135, and F136 or F137

## Out of scope

- Suggesting which items in the bags to disenchant
- Auction house searches for items worth destroying
