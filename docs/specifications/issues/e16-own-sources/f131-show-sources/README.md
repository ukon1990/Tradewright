# F131 — Show sources

## Summary

The leveling route and reagent tooltips say where a recipe or reagent comes from, and the waypoint leads to the nearest known place.

## Context

- `LevelingRouteLogic` treats a recipe as within reach only when learned or taught by a seen trainer; the view prints "source unknown" otherwise.
- Cart and queue tooltips show vendor lines only (`AppendCartVendorLines`).

## Scope

- A recipe whose recipe item a vendor sells counts as within reach, with the vendor's price as its learn cost; the row reads "vendor, 5s"
- A recipe whose item was looted reads "drops from <NPC>"
- Reagent tooltips gain "Drops from" and "Gathered from" lines with the share of loots that held the item
- Right-click leads to the nearest vendor, else the nearest drop or node place

## Status

Implemented, in-game check pending. Differs from the scope:

- The skill needed to use a recipe item is not known, so a vendor recipe keeps the estimated skill and Learn is never off for skill
- Nodes and chests have no name in the loot window; the tooltip names the zone instead

## Acceptance criteria

- [ ] A vendor-sold recipe is routed like a trainer recipe and shows its price
- [ ] A looted recipe names the NPC
- [ ] A reagent with only drop sightings gets a waypoint
- [ ] Offline tests for the route's handling of vendor and drop sources

## Verification

```bash
npm test
```

## Dependencies

- F129, F130

## Out of scope

- Farming routes across several mobs
