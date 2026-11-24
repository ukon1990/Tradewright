# Tradewright Profession Export — Agent Analysis Guide

This document explains how profession data is captured, exported, and structured so an analysis agent can consume it correctly (gold/profit apps, spec simulation, recipe catalogs).

---

## 1. Where data lives

| Source                                    | Path / command                                                       | Format                                          |
| ----------------------------------------- | -------------------------------------------------------------------- | ----------------------------------------------- |
| **SavedVariables (raw)**                  | `WTF/Account/<ACCOUNT>/SavedVariables/Tradewright_Professions.lua` | Lua table `TradewrightProfessionsDB`          |
| **JSON export (recommended for scripts)** | `exported-professions/*.json`                                        | One file per character × profession             |
| **In-game package export**                | `/tradewright export <scope>` or profession panel **Export**       | `AHCBOR1:` + Base64 + Deflate + CBOR (not JSON) |

### Export scripts (Lua SavedVariables → JSON)

```bash
# TypeScript (preferred)
npx tsx scripts/exportTradewrightProfessions.ts \
  --input WTF/Account/VEGG1/SavedVariables/Tradewright_Professions.lua \
  --out-dir exported-professions

# Python (requires venv + luadata)
python3 -m venv .venv-export && .venv-export/bin/pip install luadata
.venv-export/bin/python scripts/export_tradewright_professions.py \
  --input WTF/Account/VEGG1/SavedVariables/Tradewright_Professions.lua \
  --out-dir exported-professions --pretty
```

JSON filenames: `{characterKey}__{ProfessionName}__{baseSkillLineID}.json`  
Example: `gletryne-Draenor__Blacksmithing__164.json`

### How to refresh data

1. Open a profession window in WoW.
2. The open profession is saved by itself (when first opened, and again on close if it changed). `/tradewright rescan` re-reads the open profession, `/tradewright scan` goes through every profession, `/tradewright full` scans and then exports the full character.
3. Re-run the export script above.

**Important:** Data is only as fresh as the last scan. Spec tree layout (`paths` / `milestones` / `edges`) requires a scan after schema ≥ 12.

---

## 2. Schema version

Check `meta.schemaVersion` in package exports, or infer from field shapes in JSON.

| Version | Notable changes                                                                                                              |
| ------- | ---------------------------------------------------------------------------------------------------------------------------- |
| ≤ 10    | Recipe map keys were crafting **spell IDs**                                                                                  |
| 11      | Recipe map keys = **`skillLineAbilityID`** (Blizzard Game Data recipe id); added `recipeSpellID`                             |
| ≥ 12    | Spec tabs use **`paths`**, **`milestones`**, **`edges`** instead of flat `nodes`; `nodeName` / `nodeDescription` on each row |

Legacy scans may still have flat `tabs[].nodes[]` until rescanned.

---

## 3. Top-level JSON shape (per profession file)

```json
{
  "characterKey": "Ögletryne-Draenor",
  "skillLineID": 164,
  "professionName": "Blacksmithing",
  "currentLevelName": "Midnight Blacksmithing",
  "skillLevel": 100,
  "maxSkillLevel": 100,
  "recipeCount": 715,
  "primarySpecializationSkillLineID": 2907,
  "specializationTierCount": 3,
  "specializationTree": { "... primary tier ..." },
  "specializationTrees": { "... all expansion tiers ..." },
  "specCatalog": { "... metadata about bundled static catalog ..." },
  "specNodeRanks": { "... ranks on primary tier ..." },
  "specNodeRanksByTier": { "... ranks keyed by tier skill line ..." },
  "recipes": [ "... normalized recipe rows ..." ]
}
```

In **raw SavedVariables**, `recipes` is a **map** keyed by `tostring(skillLineAbilityID)`, not an array. The Python/TS export scripts flatten it to an array.

Live-update fields on each profession row (not required for export consumers): `liveFingerprint` / `liveMetaFingerprint` / `liveFingerprintAt`. Tradewright uses these to skip full recipe/spec dumps when opening or closing the profession pane if nothing changed.

---

## 4. Two recipe IDs (do not confuse them)

Every recipe has two IDs:

| Field                                 | Example (Quick Peridot) | Use for                                                                         |
| ------------------------------------- | ----------------------- | ------------------------------------------------------------------------------- |
| **`recipeID`** / `skillLineAbilityID` | `52572`                 | Blizzard Game Data API `/data/wow/recipe/{id}`, map keys, aggregate joins       |
| **`recipeSpellID`**                   | `1230437`               | In-game `C_TradeSkillUI`, Wowhead spell links, **`spec_catalog.recipeMapping`** |

```json
{
  "recipeID": 52572,
  "recipeSpellID": 1230437,
  "name": "Quick Peridot",
  "raw": {
    "info": {
      "recipeID": 1230437,
      "skillLineAbilityID": 52572
    }
  }
}
```

**Rule:** Join to Blizzard REST API and exported recipe rows via `recipeID` (skillLineAbilityID). Join to spec catalog / CraftSim-style mappings via `recipeSpellID`.

---

## 5. Recipe object (analysis fields)

Normalized export row (from `scripts/export_tradewright_professions.py`):

| Field                        | Meaning                                                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------------------- |
| `recipeID`                   | `skillLineAbilityID`                                                                              |
| `recipeSpellID`              | Crafting spell id                                                                                 |
| `name`                       | Recipe name                                                                                       |
| `categoryID`                 | TradeSkillUI category                                                                             |
| `learned`, `craftable`       | Character state at scan time                                                                      |
| `supportsQualities`          | Multi-quality craft                                                                               |
| `reagents[]`                 | `{ slotIndex, slotLabel, quantityRequired, itemID, quality }`                                     |
| `outputs[]`                  | `{ itemID, qualityIndex, name }`                                                                  |
| `specBreakdown`              | Per-recipe spec stat totals from bundled catalog + invested ranks (Midnight crafting professions) |
| `specTotalsSkill`            | Shortcut: `specBreakdown.totals.skill`                                                            |
| `raw.info` / `raw.schematic` | Full sanitized API payloads                                                                       |

Crafting economics at scan time may also exist under `raw` → `crafting` (operation info, bonus skill, etc.) in full SavedVariables exports.

---

## 6. Profession & expansion tiers

Base profession `skillLineID` (e.g. `164` Blacksmithing) holds **all expansion recipes** in one scan.

Specialization trees are **per expansion tier skill line**, in `specializationTrees`:

| Tier key (string) | Expansion           | Example name               |
| ----------------- | ------------------- | -------------------------- |
| `2822`            | Dragonflight (9)    | Dragon Isles Blacksmithing |
| `2872`            | The War Within (10) | Khaz Algar Blacksmithing   |
| `2907`            | Midnight (11)       | Midnight Blacksmithing     |

Each tier object includes:

- `configID`, `skillLineID`, `tierName`, `expansionID`
- `tabs[]` — specialization branches (e.g. Armorsmithing, Craftsmithing)
- `unspentKnowledge` — unspent spec currency

`primarySpecializationSkillLineID` = tier used as “primary” (usually current expansion).

---

## 7. Specialization tree layout (schema ≥ 12)

Each **tab** contains three disjoint collections. **Do not treat milestones as graph nodes or edges.**

### `paths[]` — multi-rank specialization nodes

Branch nodes like **Belts**, **Gauntlets**, **Sapphire**.

```json
{
  "nodeKind": "path",
  "nodeID": 104566,
  "nodeName": "Belts",
  "nodeDescription": "Master the art of crafting waist armor.|n|nGain +1 Skill...",
  "pathDescription": "...",
  "childPathIDs": [104567],
  "nodeInfo": {
    "maxRanks": 26,
    "activeRank": 1,
    "currentRank": 1
  }
}
```

- **`nodeInfo.activeRank`** / **`currentRank`**: invested ranks (UI ring number).
- Catalog rank math uses **`activeRank - 1`** as the rank index for per-point stats.
- **`childPathIDs`**: only other **path** node IDs (never milestones).

### `milestones[]` — single-rank perk unlocks

Small circles along a path (“+5 Skill at rank 5”). **Not edges.**

```json
{
  "nodeKind": "milestone",
  "nodeID": 104499,
  "parentPathID": 104566,
  "parentPathName": "Belts",
  "milestoneRank": 5,
  "unlockRank": 5,
  "nodeName": null,
  "nodeDescription": "Gain +5 Skill when crafting waist armor.",
  "nodeInfo": { "maxRanks": 1, "activeRank": 0 }
}
```

- Link milestones to a path via **`parentPathID`**.
- Display label: prefer `nodeDescription`; many milestones have no `nodeName`.
- **`milestoneRank`** == unlock rank on the parent path.

### `edges[]` — path-to-path links only

```json
{ "fromPathID": 104565, "toPathID": 104566, "kind": "path" }
```

Use **`edges`** to lay out the path tree. Attach **`milestones`** to paths by `parentPathID`, not by edges.

### Legacy format (pre-rescan)

Older data has flat **`tabs[].nodes[]`** mixing paths and milestones. Classify by:

- `nodeInfo.maxRanks > 1` → path
- `nodeInfo.maxRanks == 1` → milestone

---

## 8. Invested ranks for spec math

| Field                 | Location   | Content                                                                |
| --------------------- | ---------- | ---------------------------------------------------------------------- |
| `specNodeRanks`       | Profession | `{ "104566": 0, ... }` ranks on primary tier (rank index, not UI ring) |
| `specNodeRanksByTier` | Profession | `{ "2907": { "104566": 0 }, "2872": { ... } }`                         |

Rank index = `max(0, activeRank - 1)` on path nodes. Milestones don't have rank investment — they're on/off based on parent path rank vs `unlockRank`.

---

## 9. Static spec catalog (offline simulation)

Export scope: `/tradewright export spec_catalog`  
Bundled in addon for **Midnight crafting** professions (no scan needed).

```json
{
  "specCatalog": {
    "catalogVersion": 1,
    "expansionID": 11,
    "professions": {
      "<professionEnum>": {
        "recipeMapping": {
          "1230437": [107012, 106990, ...]
        },
        "nodeData": {
          "104566": { "nodeID": 104566, "maxRank": 25, "stats": { "skill": 1 } },
          "104499": { "nodeID": 104566, "maxRank": 1, "stats": { "skill": 5 } }
        }
      }
    }
  }
}
```

- **`recipeMapping[recipeSpellID]`** → list of perk/node IDs that apply to that recipe.
- **`nodeData[id]`** → static stats (`skill`, `multicraft`, `resourcefulness`, `ingenuity`, etc.).
- Perk entries reference parent via `nodeData[perkId].nodeID`.

### Per-recipe breakdown at scan time

On each recipe (when Midnight catalog matches):

```json
"specBreakdown": {
  "recipeID": 52572,
  "recipeSpellID": 1230437,
  "tierSkillLineID": 2914,
  "totals": { "skill": 42, "multicraft": 0, ... },
  "nodes": [ "... per-path contributions ..." ]
}
```

Compare `specBreakdown.totals.skill` with `crafting.bonusSkill` from scan for validation.

---

## 10. Recommended analysis workflow

```
1. Load JSON (or decode AHCBOR1 package → JSON)
2. For each profession file:
   a. Read skillLineID, specializationTrees, recipes
   b. Build recipe index by recipeID (skillLineAbilityID)
   c. Build secondary index by recipeSpellID for catalog joins
3. For spec / profit simulation:
   a. Load spec_catalog export (once per app)
   b. For each recipe: recipeSpellID → recipeMapping → nodeData
   c. Apply specNodeRanksByTier[tierSkillLineID] for invested ranks
   d. For unlearned simulation: set ranks manually from nodeData
4. For tree UI:
   a. Render paths + edges (path-to-path only)
   b. Render milestones as children of parentPathID (not in edge graph)
5. For Blizzard API enrichment:
   a. Use recipeID (skillLineAbilityID) with Game Data API
   b. Never use recipeSpellID as Game Data recipe id
```

---

## 11. Export scopes cheat sheet

| Scope                     | Best for                                          |
| ------------------------- | ------------------------------------------------- |
| `professions`             | Full profession blobs all chars                   |
| `professions_recipes`     | Recipes + reagents + specBreakdown, no spec trees |
| `professions_talents`     | Spec trees + ranks, no recipes                    |
| `profession_talents <id>` | Single profession spec dump                       |
| `profession_recipes <id>` | Single profession recipe dump                     |
| `spec_catalog`            | Static Midnight catalog only                      |
| `character`               | Everything for one character                      |

`/tw rescan` = re-read the open profession. **Export** = scan + `profession_talents` for that profession.

---

## 12. Common pitfalls

1. **Using `recipeSpellID` as Blizzard `recipe.id`** — wrong ID space; use `skillLineAbilityID`.
2. **Rendering milestones as edges** — use `parentPathID`, not `edges` / `childPathIDs`.
3. **Expecting `nodeName` on every row** — milestones often only have `nodeDescription`.
4. **Mixing expansion tiers** — always key ranks and trees by tier `skillLineID` (e.g. `2907`), not base `164`.
5. **Stale exports** — `exported-professions/*.json` are not auto-updated; re-run export script after scan.
6. **Character key encoding** — watch for `Ö` vs `Ø` in character names (separate SavedVariables keys).

---

## 13. Key source files (for maintainers)

| File                                                                  | Role                                                 |
| --------------------------------------------------------------------- | ---------------------------------------------------- |
| `Tradewright/src/core/Tradewright_Data.lua`                       | Scan capture, spec tree `paths`/`milestones`/`edges` |
| `Tradewright_Professions/src/modules/Tradewright_SpecCatalog.lua` | Catalog registration, `specBreakdown`                |
| `Tradewright_Professions/src/modules/Tradewright_Scan.lua`        | Full scan + `ScanOpenProfession()`                   |
| `scripts/export_tradewright_professions.py`                         | SavedVariables → JSON                                |
| `exportTradewrightProfessions.ts`                                   | Same, TypeScript                                     |

Schema version constant: `Tradewright.SCHEMA_VERSION` in `Tradewright/src/core/Tradewright.lua`.
