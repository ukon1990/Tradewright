# F151 — Enchants on Forever: cast on gear, not on vellum

## Summary

On WoW Forever an enchant cannot go on an Enchanting Vellum; it has to be cast on a piece of gear. Today the crafts engine prices, shops for and crafts every enchant as if it went on a vellum and made a scroll. On Forever, an enchant should cost only its own materials, keep its place in the leveling route when it is the cheapest way to a skill point, and be crafted from the queue onto a fitting item the player is wearing or carrying.

## Context

- Found while leveling Enchanting on Forever: Enchant Bracer - Inferior Stamina (one Mote of Magic) was for a while the cheapest route step, but the queue's Craft button left the player to pick an item to enchant every time.
- Every enchant gets an Enchanting Vellum (item 38682) as its target material, on every client: `ensureEnchantingVellumInPlan` (`Tradewright_CraftReagentPlan.lua`, used from `Tradewright_CraftTargetQuality.lua`), and the queue context forces it (`forceEnchantingVellum` in `BuildProfessionRecipeQueueContext`, `Tradewright_OpenProfessionRecipe.lua`). The product is the scroll from `Tradewright_EnchantScrollData.lua` or from `GetRecipeOutputItemData` with a vellum.
- On Forever this means:
  - The route cost and the queue's material cost include a vellum the player cannot use.
  - The shopping list, the vendor buy window and the auction cart ask for Enchanting Vellum.
  - A scroll is valued as what the craft gives back (vendor, auction or disenchant mode), although Forever makes no scroll.
- F122 expected enchants to drop out as "no price". They only stay in the route because the vellum happens to have a price.
- The profession window on Forever shows an enchant's target as "Optional Target: Select Item to Enchant". An item can be enchanted again and again: each new enchant replaces the old one. So one fitting item serves every craft of a route step. The game asks the player to confirm replacing an enchant, and to confirm binding an item that is not yet soulbound.
- The queue crafts with `C_TradeSkillUI.CraftRecipe(recipeID, amount)` (`craftUnopenedRecipe`, `craftThroughApi` in `Tradewright_ProfessionCraftAction.lua`). Retail has `C_TradeSkillUI.CraftEnchant(recipeID, count, reagents, itemLocation)` and `C_TradeSkillUI.GetEnchantItems(recipeID)` (the items an enchant can go on). Whether Forever has them is unverified; the profession window's "Select Item to Enchant" suggests it has the second.
- Lint debt: `classifyCraftReagentSlot` and `BuildProfessionRecipeQueueContext` are over the limits (`scripts/lint-baseline.json`). Any change there has to pull helpers out, not add to them.

## Scope

- **Vellum is a client capability.** A flag such as `Tradewright.ENCHANTS_ON_VELLUM` is true on retail only. Every place that adds or forces a vellum, or looks up a scroll as an enchant's product, checks it.
- **Forever pricing.** An enchant's material cost is its own materials. It has no product: no output item, no vendor, auction or disenchant give-back, and no sale in the Crafts tab opportunities (it makes nothing to sell there).
- **Route.** An enchant is a route candidate like any recipe, costed by its materials. A step with an enchant names the gear it needs ("needs a bracer to enchant on"). One fitting item covers the whole step. When the character wears or carries none, the step adds the cheapest fitting item once: its vendor price, else its auction price. When neither exists, it adds nothing and only says what is needed.
- **Queue and shopping list.** On Forever an enchant line puts no vellum in the shopping list, the vendor buy window or the auction cart.
- **Craft from the queue.** On Forever the Craft button on an enchant line casts the enchant on an item it can go on (from `GetEnchantItems` when the client has it), equipped gear and bag items alike. It picks an equipped item first, so the enchant stays on the character, else the bag item worth least by vendor price. One enchant per click. The game's replace and bind confirmations are left for the player to answer.
  - When no equipped or bag item fits, the recipe opens and chat says which kind of gear it needs.
  - When the client lacks `CraftEnchant` with an item location, Craft opens the recipe and says which item to pick, as it does now.
- The queue counts each cast off the line (by `UNIT_SPELLCAST_SUCCEEDED` with the recipe's spell, as salvage lines do), since an enchant makes no item for `TRADE_SKILL_ITEM_CRAFTED_RESULT`.
- Pure helpers (no WoW API) with offline tests: choosing the target item from a list of candidates, and the step's target-item cost.
- New WoW API in `.luacheckrc`.

## Status

Implemented, not checked in game:

- `CraftReagentPlan.enchantCastOnGear` / `enchantGoesOnVellum` decide by client (`IS_RETAIL`); no separate flag. `planEnchantTarget` (was `ensureEnchantingVellumInPlan`) adds the vellum on retail and drops the target entry on Forever; `resolveCraftOutputItemID` gives no scroll on Forever
- The crafts engine treats an enchant on gear like a salvage recipe: no item made (the recipe's spell id stands in as output id), the recipe's icon, no sale; `evaluation.enchantsGear` is passed on
- Leveling route: such a candidate has no give-back in any mode and no output to reuse (`priceGiveBack`)
- Crafts tab: enchants on gear are left out (they make nothing to sell)
- Craft queue: the line keeps `enchantSpellID`; each cast of it counts one craft, a crafted item never does (`castCountedSpell`); its stand-in id is not counted as an item the queue makes
- `Tradewright:FindEnchantTarget(recipeSpellID)` reads `C_TradeSkillUI.GetEnchantItems` and picks with the pure `EnchantLogic.PickTarget` (worn first, then the bag item with the lowest vendor price, unpriced last). Craft casts with `C_TradeSkillUI.CraftEnchant(recipeSpellID, 1, nil, itemLocation)`; without a target, or without those calls, the recipe opens and chat says what to do
- Leveling view step detail: "on <item>", or "no item to enchant (<category>)" when nothing fits; nothing when the client cannot tell

Differs from the scope:

- No cost for buying a target item when nothing fits: the step says "no item to enchant (Bracer Enchants)" instead. Finding the cheapest fitting item would need which slot each enchant takes and a list of gear by slot with prices; a grey bracer costs next to nothing beside a route's reagents
- Unverified in the client: that Forever has `GetEnchantItems`, `C_Item.GetItemLocation` and `CraftEnchant` with an item location, that `GetEnchantItems` lists worn gear as well as bag items, and that the cast fires `UNIT_SPELLCAST_SUCCEEDED` with the recipe's spell id

## Acceptance criteria

- [ ] On Forever, no enchant has Enchanting Vellum in its materials, shopping list, vendor buy window or auction cart.
- [ ] On Forever, an enchant's give-back is nothing in every give-back mode, and its material cost is the sum of its own materials.
- [ ] On Forever, an enchant that is the cheapest way to a skill point is chosen by the route. Its step names the gear it needs, and adds that item's cost once when no equipped or bag item fits.
- [ ] On Forever, Craft on a queued enchant casts the enchant on the equipped fitting item, else the cheapest fitting bag item, and lowers the line by one.
- [ ] Without a fitting item, or without the craft-on-item API, Craft opens the recipe and chat says what to pick. No error.
- [ ] On retail, enchants still use vellum, make scrolls and are priced as before.
- [ ] Offline tests: target choice (equipped first, then cheapest bag item, no fit), target-item cost counted once per step, vellum only when the flag is on.
- [ ] `npm test` passes, with no growth in the lint baseline.

## Verification

```bash
npm test
```

In-game on Forever, Enchanting:

1. Leveling view: an enchant step shows its cost without vellum and names the gear it needs.
2. Queue it: the shopping list and the vendor buy window show no Enchanting Vellum.
3. Wearing bracers, click Craft: the enchant lands on them; take them off with a spare bracer in the bags, click Craft: it lands on the spare. Each time the game asks to replace or bind, and after confirming the queue count drops by one.
4. With no bracer worn or carried, click Craft: the recipe opens and chat says a bracer is needed.

Before building step 3, check in the client: `/dump C_TradeSkillUI.CraftEnchant, C_TradeSkillUI.GetEnchantItems` with Enchanting open.

On retail: an enchant still queues Enchanting Vellum and is valued by its scroll.

## Dependencies

- F121, F122 (route candidates and queue integration), F123 (where the step shows)

## Out of scope

- Enchanting items in the trade window, or for other players
- Accepting the game's replace or bind confirmations on the player's behalf
- Buying the target item automatically
- Valuing an enchant by what an enchanted item sells for
