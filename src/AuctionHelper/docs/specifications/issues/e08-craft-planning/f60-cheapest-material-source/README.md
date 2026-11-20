# F60 — Cheapest way to get each material

## Summary

For every material of a craft the addon picks the cheapest way to get it: buy it at the auction house, buy it from a vendor, or craft it with a recipe one of your characters knows. The Crafts tab shows which, and the profit uses that cost.

## Context

- Material price order today (`EvaluateCraftScenario`): vendor price for vendor-sourced reagents → ledger buy average → TSM `Crafting` → market fallback. A material that is itself craftable is priced as if bought.
- `craftOpportunityCostIndex` holds the lowest craft cost per output item; check first whether the reagent path can read it, and extend that instead of adding a second cost table.
- `GetItemVendorPurchaseCopper` (`AuctionHelper_Util.lua`) knows a vendor's price only for items the game reports as vendor-sold.
- The rule the established tools share is `min(vendor, auction, craft)` evaluated through the recipe tree; cooldown recipes are left out of the craft branch because their output is capped.
- Recipes form a tree with no cycles in normal data, but saved data can be odd, so the walk needs a guard.
- Design: "Cheapest way to get materials" in [Crafts](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldCrafts).

## Scope

- `ForeverLogic.ResolveMaterialCost(itemID, ctx)`, pure, memoised per evaluation → `{cost, source}` with source `"vendor" | "buy" | "craft" | "none"`:
  - `ctx.vendorPrice(itemID)`, `ctx.marketPrice(itemID)`, `ctx.recipesFor(itemID)` (each: reagents, output quantity, cooldown flag, crafter)
  - craft cost = sum of the reagents' resolved costs ÷ output quantity, skipping cooldown recipes
  - a depth limit (4) and a visiting set; a cycle or the limit falls back to buy
- New value "Cheapest way" for `crafts.reagentSourceMode`; `owned_first` and `mixed` keep their meaning and apply before it (owned stock first, the rest by cheapest way)
- Crafts table: `Materials` and `Profit` use the resolved costs; the row's second line notes "bolts made by Brannoc" style text when a material comes from a craft
- Detail pane: "Cheapest way to get materials" with Reagent, Need, From (Craft, Buy, Vendor), Cost; and the line "If you bought every material" with that profit
- Craft queue: adding a craft whose material source is "craft" adds the intermediate crafts to "To craft" for the character who knows them, and their raw materials to "To buy"
- Setting "Use my own recipes when a material is cheaper to craft" (on)

## Status

Implemented, in a smaller form than the scope above:

- `AuctionHelper_MaterialLogic.lua` (core, pure, offline-tested): `CheapestSource(candidates)` and `UnitCostIndex(rows)`
- `AuctionHelper_MaterialSource.lua` (Professions): `GetCraftUnitCost(itemID)` and `CheapestMaterialUnit(itemID, unit, source)`
- The crafts engine's material price (`craftEvalPickUnit`) now goes through `CheapestMaterialUnit`: a material is priced at your own craft cost per unit when that is below what the engine found by its usual rules. Its source reads "Craft", which the existing detail text and queue already show.
- Setting "Use my own recipes when a material is cheaper to craft" (on), in a new Crafts group

How it differs from the scope, and why:

- **No recursive resolver.** The craft cost per unit is read from the engine's own last finished evaluation (cheapest full material cost ÷ output quantity per output item) instead of walking recipes again. That keeps the engine's rules (quality, optional reagents) and cannot loop, but it is one evaluation behind: a material that is cheaper to craft is priced that way from the evaluation after the one that first priced its recipe. A new scan or a settings change triggers the next evaluation.
- **Vendor prices are unchanged.** The engine already prices vendor-sourced reagents at the vendor; widening that to every reagent needs a check of what `C_Item.GetItemVendorPrice` returns for items no vendor sells.
- **Works in every material mode except "market only"**, as a setting, not as a new "Cheapest way" mode.
- **Not done:** the "From" column and the "If you bought every material" line in the detail pane, the row note ("bolts made by …"), and adding intermediate crafts to the queue.
- **Cooldowns:** rows carrying `hasCooldown` are left out of the index; nothing sets that flag until F62.

## Acceptance criteria

- [ ] A bag needing 5 bolts, where a bolt costs 60s to buy and 52s to craft, prices the bolts at 52s each and shows From: Craft
- [ ] A vendor-sold thread is priced at the vendor price even when listed dearer at the auction house
- [ ] A cooldown-made material is never priced through its recipe
- [ ] Two recipes that reference each other do not hang; both fall back to buy
- [ ] With the setting off, costs match today's behaviour
- [ ] Queueing the bag queues the bolts for the right character
- [x] Offline tests of `CheapestSource` and `UnitCostIndex`: each source winning, tie, missing prices, cooldown skip, output quantity
- [ ] Nested crafts price through after two evaluations (in-game check)

## Verification

```bash
npm test
```

In-game: profession scan on a tailor → Crafts → Materials: Cheapest way → a bag's detail pane shows the bolt as Craft with the lower cost → Add to queue → the queue lists the bolts.

## Dependencies

- None hard; F62 supplies the cooldown flag (until then recipes are treated as having none)

## Out of scope

- Buying materials in bulk at rising prices (the lowest price is used for every unit)
- Conversions and destroy values
- Choosing between two characters by travel or mail time
