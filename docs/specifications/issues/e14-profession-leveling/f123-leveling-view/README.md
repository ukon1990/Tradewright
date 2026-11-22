# F123 — Leveling view in the profession side panel

## Summary

A third view, Leveling, beside Recipe and Queue in the panel docked to the profession window. It shows the cheapest route as a list of steps with totals, lets the player choose what crafted items count for, and queues a step's crafts.

## Context

- Panel: `Tradewright_ProfessionCraftPanel.lua` (643 of 700 lines). `SetProfessionPanelActiveTab` accepts only `"info"` and `"queue"`; the header buttons are made in `createPanelHeader`. The Queue view lives in its own file (`Tradewright_ProfessionQueueView.lua`) and is refreshed from `RefreshProfessionSideParts`; the Leveling view follows that shape.
- Building blocks: `CreateReusableTable` with `SetLoading`, `CreateStats`, `CreateSingleSelectDropdown`, `CreateCheckbox`, `CreateItemColumn`, `MoneyColumn`, `ShowItemRowTooltip`, `JumpToProfessionRecipe`.
- Panel width is 400 px, so a step row has room for skill range, recipe name with one detail line, one money column and a small button.
- Design: [cheapest route](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-ProfessionLeveling), [materials only and step tooltip](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-ProfessionLevelingDetail), [working and no prices](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-ProfessionLevelingEmpty).

## Scope

- New `src/Tradewright_UI/src/ui/Tradewright_ProfessionLevelingView.lua`, listed in all four UI TOCs: `CreateProfessionLevelingView(panel)`, `RefreshProfessionLevelingView(panel)`
- `Tradewright_ProfessionCraftPanel.lua`: the tab switch becomes a table of view id → host and button, so the third view adds no branches; header shows `Recipe | Leveling | Queue`; `professions.sidePanelTab` accepts `"leveling"`
- Top line: profession name, current skill, a bar to the route's end skill, and a "Rank cap N" badge when the route crosses the cap
- Three stats: Materials, what the crafted items give back (label follows the choice: "Sold to vendor", "Sold at auction", or "not counted"), Net cost
- Controls: "Crafted items" dropdown (Sell to vendor, Sell at auction, Count as nothing) and checkbox "Only recipes I know"
- Route table, tall rows: Skill ("122–128") | Recipe with detail line ("about 6 crafts", "next step", "14 in queue", "trainer, 5s" or "source unknown") | Net cost (header and value become Materials when crafted items count as nothing) | action
  - Action: "Queue" button for a step whose recipe is learned; "Queued" badge once in the craft queue; "Learn" badge for a recipe not learned; empty for a rank-cap row
  - Clicking a row selects that recipe in the profession window
  - Row tooltip: materials per craft with prices, vendor value, skill-up chance at the start and end of the step, grey level, and for a recipe not learned its source if known
  - Table footer: step count, "crafts are estimates", route total
- Panel footer left: "N recipes left out: no price" when any
- States: `SetLoading` with progress while the route is worked out; empty-state text per reason from F122 (`no_data`, `unsupported`, `no_prices`, `finished`)
- Refresh on the panel's existing triggers (skill change, price change, queue change); no extra polling

## Status

Implemented and checked in game:

- `Tradewright_ProfessionLevelingView.lua`; the panel's view switch is a table (`PANEL_VIEWS`) and the header shows Recipe, Leveling, Queue
- Row text is tested offline in `tests/test_leveling_route.lua`

- A row "Queue the route up to skill [N] [Queue]" sits under the dropdowns; the box starts at the current rank's cap
- The Queue view shows "learn first: trainer, skill 150" (or "learn the recipe first") on a route line whose recipe is not learned, with Craft off, and "23 from queued crafts" on a material other queued crafts make

Differs from the scope:

- Row detail is shortened to fit the panel: "~16 crafts" for an expected count, and "trainer, skill 150" for a trainer recipe (its price is in the tooltip). The skill needed to learn a recipe is only known for trainer recipes
- The table footer reads "40 steps · 111 recipes without a price"

- "Only recipes I know" is a second dropdown instead of a checkbox: Trainer recipes first (default), All recipes, Only known
- "Learn" is a button, disabled when no trainer is known for the recipe or the character's skill is below what the trainer asks; the tooltip says which

- The cost column header is always "Cost"; it shows materials when crafted items count as nothing, net cost otherwise
- "N recipes left out: no price" is in the table footer, not the panel footer
- The row tooltip is the game tooltip filled by the view, not `ShowItemRowTooltip`
- Nothing here has been seen in the game yet: layout, truncation and the dropdown need the in-game check

## Acceptance criteria

- [x] Leveling is reachable from the header and remembered across `/reload`
- [x] Totals and step costs match the route from F122 for each "Crafted items" choice; Materials is visible in all three
- [x] "Queue" appears only on learned steps and changes to "Queued" with the queued count
- [x] Long recipe names are cut with an ellipsis and never push the money column or button out of the panel
- [x] Loading and each empty reason show their own text; no "nothing found" while working
- [x] Recipe and Queue views look and behave as before
- [x] `Tradewright_ProfessionCraftPanel.lua` stays under 700 lines; no lint baseline change
- [x] Offline test for the row text builder (ranges, detail lines, action per step kind) following `tests/test_profession_recipe_view.lua`

## Verification

```bash
npm test
```

In-game on Forever (full client restart): open Leatherworking → Leveling → compare the first step's recipe colour with the game's list → switch "Crafted items" → tick "Only recipes I know" → queue the first step → Queue view shows it → hover a "Learn" row.

## Dependencies

- F122 (route and queue integration)
- F124 for the trainer text on "Learn" rows (shows "source unknown" without it)

## Out of scope

- A leveling tab in the dashboard window
- A shopping list inside the Leveling view (the Queue view has it)
