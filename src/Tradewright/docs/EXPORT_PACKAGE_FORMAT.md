# Tradewright export package format

Tradewright exports are not JSON.

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
