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
