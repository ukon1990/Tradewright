# F132 — Shipped source data

## Summary

Collected sightings can be built into a data file that ships with the addon. Reads use the shipped file and the saved store together, and the saved store drops whatever the shipped file already states.

## Context

- Facts (a vendor's price, an NPC's place, a trainer's terms) can be compared by content. Loot counts cannot: after shipping, the collector's own counts would be counted twice.

## Scope

- `src/Tradewright/src/data/Tradewright_SourceData.lua` in the four core TOCs, empty at first: the store's content plus `collected = { [collectorID] = epoch }`
- Reads merge shipped and saved; a saved fact wins, tallies add up
- Prune at login: a saved fact equal to the shipped one is deleted
- `/tradewright sources seal` closes the current tally epoch; the build script exports sealed epochs and records the highest per collector; a client that finds its own id deletes its epochs up to that number
- `scripts/build-source-data.mjs` (`npm run sources:build`): reads `TradewrightSourcesDB` from the SavedVariables file, merges into the shipped file, rewrites it

## Acceptance criteria

- [ ] After build, deploy and login the saved store is smaller and every lookup answers as before
- [ ] Another collector's tallies are kept and added to the shipped ones
- [ ] Building twice from the same saved data changes nothing
- [ ] Offline tests: merge order, prune by equality, prune by epoch for own and foreign ids

## Verification

```bash
npm test
npm run sources:build
```

## Dependencies

- F129, F130

## Out of scope

- A separate addon folder for the data (only if the file passes about 1 MB)
