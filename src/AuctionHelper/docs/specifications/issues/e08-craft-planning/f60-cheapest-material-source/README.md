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

## Acceptance criteria

- [ ] A bag needing 5 bolts, where a bolt costs 60s to buy and 52s to craft, prices the bolts at 52s each and shows From: Craft
- [ ] A vendor-sold thread is priced at the vendor price even when listed dearer at the auction house
- [ ] A cooldown-made material is never priced through its recipe
- [ ] Two recipes that reference each other do not hang; both fall back to buy
- [ ] With the setting off, costs match today's behaviour
- [ ] Queueing the bag queues the bolts for the right character
- [ ] Offline tests of `ResolveMaterialCost`: each source winning, nested craft, cooldown skip, cycle, depth limit, missing prices

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
