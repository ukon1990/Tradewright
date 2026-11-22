# Tradewright export package format

Tradewright exports are not JSON.

Export is a developer tool and is switched off for players. Turn it on in game with
`/tradewright dev export on` (off again with `off`). While it is on, the dashboard shows the Export
tab and these commands work:

- `/tradewright export <scope>` — one of the scopes below
- `/tradewright full` — turns on specialization capture, scans every learned profession, then
  exports the full character

## Wire format

Each export is a single string in one of two forms, chosen by the client:

- WoW Forever (no `C_EncodingUtil` CBOR encoder): `AHLUA1:return { ... }` — plain Lua text.
  Strip the `AHLUA1:` prefix and load the rest as a Lua chunk; it returns the table.
  `meta.format = "AHLUA1"`, `meta.encoding = "lua-text"`.
- Retail: `AHCBOR1:<base64>`, described below.
  `meta.format = "AHCBOR1"`, `meta.encoding = "cbor+deflate+base64"`.

### AHCBOR1

Where the payload is:
1. CBOR-serialized Lua table
2. Deflate-compressed
3. Base64-encoded

In WoW this is produced with:
- `C_EncodingUtil.SerializeCBOR`
- `C_EncodingUtil.CompressString(..., Enum.CompressionMethod.Deflate)`
- `C_EncodingUtil.EncodeBase64`

## Decode pipeline

To decode in an external script:
1. Verify the string starts with `AHCBOR1:`
2. Strip the prefix
3. Base64 decode the remainder
4. Deflate decompress the decoded bytes
5. CBOR decode the decompressed bytes

## Top-level structure

All decoded packages contain a top-level table with at least:
- `meta.scope`
- `meta.generatedAt`
- `meta.addonVersion`
- `meta.schemaVersion`
- `meta.format`
- `meta.encoding`
- `meta.module`

## Scopes

| Scope | Contents |
| --- | --- |
| `character` | Full stored data for the logged-in character: professions, inventory snapshot, meta |
| `account` | All characters in SavedVariables plus the aggregate (largest) |
| `account_summary` | Aggregate only, no per-character profession data |
| `professions` | All professions of the current character, no inventory snapshot |
| `professions_recipes` | As `professions`, without `specializationTree(s)`, `primarySpecializationSkillLineID` and `recipeIDs` |
| `professions_talents` | Character header plus slim professions: identity and skill fields, base/child info, specialization trees, `specCatalog`, `specNodeRanks(ByTier)`; no recipes |
| `professions_compact`, `inventory_compact`, `auction_snapshot`, `auction_history`, `crafting_costs` | Compact scopes, see below |
| `inventory` | Character header plus `inventorySnapshot` |
| `spec_catalog` | Bundled Midnight specialization catalog, no scan needed; join to recipes by `recipeSpellID` |
| `character_meta` | Scan timestamps and identity header only (smallest) |
| `profession <id\|name>` | One profession: character meta plus the full profession object |
| `profession_recipes <id\|name>` | One profession, recipes slice |
| `profession_talents <id\|name>` | One profession, talents slice |

Slash aliases: `items` → `inventory`, `summary` → `account_summary`, `meta` → `character_meta`.

## Record layouts

**Character** (`character`): `meta`, `addonVersion`, `schemaVersion`, `scanStartedAt`, `scanFinishedAt`,
`professions`, `inventorySnapshot`, optional `lastLiveProfessionUpdate` / `lastLiveInventoryUpdate`.
Partial scopes carry the same header without the professions or inventory data.

**Profession** (key `tostring(skillLineID)`): `skillLineID`, `professionName`, levels, icon, categories,
`recipeIDs` (skillLineAbilityIDs), `recipes`, optional `specializationTree` (primary tier) and
`specializationTrees` (every tier with a `C_ProfSpecs` config; each has `configID`, `skillLineID`,
`tierName`, `expansionID`: 9 Dragonflight, 10 The War Within, 11 Midnight), `specCatalog`,
`specNodeRanks` / `specNodeRanksByTier`, base/child profession info. A specialization tab exports
`paths` (multi-rank nodes), `milestones` (single-rank perks with `parentPathID`) and `edges`
(path-to-path links only); path and milestone rows carry `nodeKind`, `nodeName`, `nodeDescription`.

**Recipe** (schema v11, key `tostring(skillLineAbilityID)`): `recipeSpellID`, `skillLineAbilityID`,
`info`, `schematic`, `outputs`, `slots`, `crafting`, optional `specBreakdown`, `links` (reserved).
Rows from schema v3–v10 may still be keyed by spell id until rescanned. All values are sanitized
(depth limit, cycle detection) before packing.

**Inventory snapshot**: `capturedAt`, `itemTypesTracked`, `itemTypesWithStock`, `totalQuantity`,
`items` (itemID string → `{ bags, bank, warband, total }`).

**Aggregate** (`account`, `account_summary`): `updatedAt`, sorted `characterKeys`, `professions`
(by skillLineID, with `characterStates` and sorted `recipeIDs`), `recipes` (by recipeID, with
`characterStates` and sorted `products`), `inventoryByCharacter` (summary fields only, no items).

## Compact website-oriented scopes

These scopes are intended for script ingestion and smaller payloads:
- `professions_compact`
- `inventory_compact`
- `auction_snapshot`
- `auction_history`
- `crafting_costs`

These compact scopes may use shortened keys and companion key tables.

### professions_compact
- `character`: compact character header
- `keys.profession`: field legend for profession rows
- `keys.recipe`: field legend for recipe rows
- `keys.slot`: field legend for slot rows
- `professions`: compact profession records

### inventory_compact
- `character`: compact character header
- `keys`: legend for item rows
- `inventory.items`: array rows ordered as:
  - `itemID`
  - `bags`
  - `bank`
  - `warband`
  - `total`

### auction_snapshot
- `keys`: legend for snapshot rows
- `snapshot.c`: commodity rows
- `snapshot.i`: item rows

Row order:
- `storageKey`
- `seenAt`
- `price`
- `source`
- `sampleSize`

### auction_history
- `keys`: legend for bucket rows
- `history`: rows of `{ storageKey, buckets }`

Bucket row order:
- `hourTs`
- `obsCount`
- `weightedQty`
- `weightedSum`
- `last`
- `min`
- `max`
- `lastSeenAt`

### crafting_costs
`keys` describes the row order:
- `recipeID`
- `outputItemID`
- `recipeName`
- `outputName`
- `skillLineID`
- `professionName`
- `bestCharacterKey`
- `matCost`
- `saleNet`
- `profit`
- `roi`
- `outputQty`
- `qualityIndex`
- `confidence`
- `badges`

## Paging in copy box

If the payload is too large for one copy-box page, Tradewright splits it into multiple pages.
Each page starts with a plain-text paging header:

`AHPAGE:<page>/<pageCount>`

To reconstruct:
1. collect pages in order
2. remove the first header line from each page
3. concatenate the remaining payload fragments
4. run the normal decode pipeline

## SavedVariables

When persistence is enabled and the payload is below the configured limit, the last export is stored in:

`WTF/Account/<account>/SavedVariables/Tradewright.lua`

Under:
- `TradewrightLastExport.payload`
- `TradewrightLastExport.format`
- `TradewrightLastExport.encoding`
- `TradewrightLastExport.scope`
- `TradewrightLastExport.module`
