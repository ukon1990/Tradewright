local _, Tradewright = ...

--- Plain-text sections for the in-game Documentation tab.
Tradewright.DOCUMENTATION_SECTIONS = {
	{
		id = "overview",
		title = "Overview",
		body = [=[EXPORT FORMAT
Tradewright exports are machine-readable packages, not JSON: one string for copy/paste or SavedVariables.
The form depends on the client:
• WoW Forever (the client has no CBOR encoder): prefix AHLUA1: then plain Lua text, "return { … }".
  Strip the prefix and load the rest as a Lua chunk to get the table.
• Retail: prefix AHCBOR1: then CBOR + Deflate + Base64.
  Strip the prefix, Base64 decode, Deflate decompress, then CBOR decode.
meta.format ("AHLUA1" or "AHCBOR1") and meta.encoding ("lua-text" or "cbor+deflate+base64") name the form.

Every exported package still originates from a table with top-level meta fields such as:
• scope — which slice was exported
• generatedAt — Unix timestamp when built
• addonVersion — addon version string
• schemaVersion — integer internal schema version
• characterKey — present for character-based slices
• professionIdentifier — only for single-profession export
• format / encoding / module — explicit package decoding hints

Large exports may be paged in the copy dialog. When that happens, concatenate the page payload fragments in order and then hand the combined package string to your import script.

Dashboard: use "All characters (account)" in the sidebar for an account roster and account exports; select a character for detail. When on the logged-in character, use per-profession buttons (All / Recipes / Talents) for smaller packages.

For a fresh complete current-character package, use "Fresh scan + full dump" on the Export tab or `/tradewright full`. This enables specialization capture, scans every learned profession, then exports recipes plus the full known/unknown specialization definitions, descriptions, and current allocations.

The source repository's docs/export-format.md (not installed with the addon) has the compact scope
field legends, paging reconstruction and SavedVariables notes.]=],
	},
	{
		id = "scopes",
		title = "Export scopes",
		body = [=[character — Full stored data for the logged-in character (professions + inventory snapshot + meta).

account — All characters in SavedVariables plus aggregate (largest).

account_summary — aggregate only; no per-character profession blobs.

professions — All professions for current character; no inventorySnapshot.

professions_recipes — Same as professions but each profession omits specializationTree, specializationTrees, primarySpecializationSkillLineID, and recipeIDs (recipe keys live in recipes map only).

professions_talents — Character header + professions map of slim objects: identity/skill fields, base/child profession info, specializationTree + specializationTrees (per expansion tier skill line), specCatalog / specNodeRanks / specNodeRanksByTier (no recipes/categories/recipeIDs/recipeCount).

professions_compact — Website/script-oriented compact profession dump with shortened keys and recipe/reagent lists.

inventory — inventorySnapshot + character header only.

inventory_compact — Website/script-oriented compact inventory dump with shortened keys and row arrays.

auction_snapshot — Compact auction snapshot export from the auction data addon.

auction_history — Compact per-hour auction history export from the auction data addon.

crafting_costs — Compact craft opportunity / mat-cost / profit package built from stored profession and pricing data.

spec_catalog — Bundled profession specialization catalog (Midnight): static nodeData stats + recipeMapping keyed by recipeSpellID (crafting spell id). No character scan required; use for offline respec simulation and unlearned node math. Join to scanned recipes via recipeSpellID.

character_meta — Scan timestamps and identity header only (smallest character slice).

profession <id|name> — One profession; character.meta + full profession object.

profession_recipes <id|name> — One profession, recipes slice (no specializationTree, no recipeIDs).

profession_talents <id|name> — One profession, talents slice only.

Dashboard: All / Recipes / Talents per profession when viewing the logged-in character.

Slash: /tradewright export [character|account|account_summary|professions|professions_recipes|professions_talents|professions_compact|inventory|inventory_compact|auction_snapshot|auction_history|crafting_costs|spec_catalog|meta|profession <id|name>|profession_recipes <id|name>|profession_talents <id|name>]
Aliases: items → inventory, summary → account_summary, meta → character_meta]=],
	},
	{
		id = "character",
		title = "Character record",
		body = [=[FULL CHARACTER (scope "character")
Contains: meta (player identity), addonVersion, schemaVersion, scanStartedAt, scanFinishedAt, professions map, inventorySnapshot, optional lastLiveProfessionUpdate / lastLiveInventoryUpdate.

CHARACTER HEADER (partial exports)
Same meta and version/scan/live fields but no professions or inventory blobs—used for professions, inventory, and character_meta scopes.

professions is a map: keys are tostring(skillLineID); values are profession objects (skillLineID, professionName, recipeIDs array of skillLineAbilityIDs, recipes map keyed by tostring(skillLineAbilityID), categories, optional specializationTree / specializationTrees keyed by expansion variant skill line, etc.).]=],
	},
	{
		id = "profession_recipe",
		title = "Profession & recipe",
		body = [=[PROFESSION OBJECT
skillLineID, professionName, levels, icon, categories from C_TradeSkillUI, recipeIDs array (skillLineAbilityID values), recipes map (key = tostring(skillLineAbilityID)), optional specializationTree (primary tier) and specializationTrees map (all expansion tiers with a C_ProfSpecs config—can turn off in settings), specCatalog (bundled static catalog metadata), specNodeRanks / specNodeRanksByTier (invested ranks from scan), base/child profession info (sanitized API tables). Every specializationTrees tier stores configID, skillLineID, tierName, and expansionID (Blizzard expansion index: 9 Dragonflight, 10 The War Within, 11 Midnight). Each specialization tab exports paths (multi-rank nodes like Belts), milestones (single-rank perk unlocks with parentPathID), and edges (path-to-path links only — milestones are never edges). Path/milestone rows include nodeKind, nodeName, and nodeDescription. Recipe-only export scopes omit specialization fields and recipeIDs; talents-only scopes keep identity + specialization fields (+ base/child info) and omit recipe fields.

PROFESSION PANEL — Open any profession window to see the Tradewright panel below the schematic. Scan saves the open profession (recipes + specialization trees) for the logged-in character. Export scans if needed, then opens a profession_talents export for that profession.

RECIPE OBJECT (schema v11)
Map key is tostring(skillLineAbilityID) — Blizzard Game Data recipe id. Each row also stores recipeSpellID (crafting spell id; use for spec_catalog recipeMapping and in-game APIs). Fields: recipeSpellID, skillLineAbilityID, info (sanitized GetRecipeInfo), schematic, outputs, slots, crafting, optional specBreakdown (recipeID = skillLineAbilityID, recipeSpellID for catalog joins), links (reserved empty). Schema v3–v10 legacy rows may still use spell ids as keys until you rescan.

Values are passed through sanitization before packaging (depth limit, cycle detection).]=],
	},
	{
		id = "inventory_agg",
		title = "Inventory & aggregate",
		body = [=[INVENTORY SNAPSHOT
capturedAt, itemTypesTracked, itemTypesWithStock, totalQuantity, items map: itemID string → { bags, bank, warband, total }.

AGGREGATE (account / account_summary)
updatedAt, characterKeys (sorted), professions keyed by tostring(skillLineID) with characterStates + sorted recipeIDs array (entry uses name + skillLineID + currentLevelName in v4), recipes keyed by tostring(recipeID) with characterStates + sorted products item-id array, inventoryByCharacter keyed by characterKey (snapshot summary fields only—no items map).

Use account_summary when you only need cross-character rollups without full recipe data per character.]=],
	},
	{
		id = "inventory_tab",
		title = "Inventory tab & economy",
		body = [=[INVENTORY TAB
Open the dashboard (/tradewright) and pick Inventory. The table lists the profession-relevant items stored for your characters, one row per item.

Columns: Item, Qty and, by default, Current AH, Avg craft, Profit each and SR. Use Columns in the toolbar to show Bags / bank, Last AH, Avg AH, Last craft, Profit, all and Seen. Drag a column header to move it; click it to sort.

FILTERS
Search matches item name, item ID, role and type. The toolbar dropdowns filter by character, role (Crafted, Crafting reagent, Crafted + reagent, Tracked) and item type. The time range sets how far back averages and charts look. Refresh reads bags and bank again on this character.

ITEM DETAILS
Click a row to open the detail pane: auction price, averages, craft cost, where you hold the item, a chart (Price, Craft cost or Quantity) and the scanned recipes that make or use it. Shift-click a row to link the item in chat.

PRICES
Current AH comes from your auction house scans; an item never scanned has no price. Totals in the table footer add up quantity times price for the rows shown. These are estimates, not official game values.]=],
	},
	{
		id = "savedvars_paging",
		title = "SavedVariables & paging",
		body = [=[LAST EXPORT (TradewrightLastExport)
After export, if under the byte limit, the full package string is stored for the next /reload or logout. Fields: savedAt, byteLength, scope, optional characterKey and professionIdentifier, format, encoding, module, and payload.

File: WTF/Account/<account>/SavedVariables/Tradewright.lua.

PAGING (copy dialog)
Over COPYBOX_PAGE_BYTES, each page starts with a Tradewright paging header. Concatenate the page payload fragments in page order before decoding through your script pipeline.

Compact website scopes use shortened keys plus key tables in the package body so a script can decode them without guessing field meanings.]=],
	},
	{
		id = "prices",
		title = "Usual price and sells a day",
		body = [=[USUAL PRICE
• Each day you scan, Tradewright keeps one price per item: the middle of the lowest prices it saw that day.
• The usual price is the middle of those daily prices over the last 14 days. Settings can change the window.
• One odd listing does not move it. The usual range is where the middle half of those days fell.
• An item needs scans on 5 different days first. Until then deals and movers use its 7-day average.
• A day is added the first time you log in after it ended.

SELLS A DAY, ESTIMATED
• The auction house shows what is listed, never what was sold.
• Tradewright compares an item's listed quantity between two of your scans at most 26 hours apart.
• What is gone counts as sold. Cancelled and expired auctions also disappear, so the figure runs high.
• New listings between two scans hide sales. Read it as "at most about this many".
• Your own sales of an item are the lowest the figure can be.
• It needs two scans of the item within 26 hours and shows the day after.
• "Few sales seen" means it rests on fewer than five pairs of scans.

LISTED SUPPLY LASTS
• Listed quantity divided by sells a day. It counts every listing, also overpriced ones that will not sell.]=],
	},
	{
		id = "opportunities",
		title = "Opportunities",
		body = [=[WHAT TO BUY OR SELL RIGHT NOW
The Opportunities tab has four lists. Each shows the sums behind a row and what could go wrong when you click it.
• Flips: listed well under the usual price and known to sell. Buy, then list at the usual price.
• Sure things: listed under what a vendor pays. Buy, then sell to any vendor.
• Price gaps (risky): a few cheap listings under a much higher next price. Buy them, relist under the next price.
• Sell now: things you own priced 10% or more above usual that sell.

WHAT THE LISTS NEED
• One full scan fills Sure things.
• Flips, Price gaps and Sell now need a usual price: scans on 5 different days. Today's scans count from tomorrow.
• They also need a sales estimate: two scans of an item within a day, so scan twice on some days.
• The "Usual price known for" card shows how far along your scans are.

WHEN A LIST IS EMPTY
The list counts how many items are left after each rule, for example:
• 7,071 items in the last scan
• 312 have a usual price
• 40 are 25% or more under it
• 3 sell 1 or more a day
• 0 make 1g or more
The first step that leaves nothing is marked, with the setting or the scan that gets past it.

HOW SURE A ROW IS
• Early: its usual price rests on only 2 to 4 days. Shown only when you turn it on in Settings, and left out of the totals.
• A "?" after Sells a day: the estimate rests on few pairs of scans or only on your own sales.
• Settings, Opportunities sets how cheap, how busy and how profitable a row must be.]=],
	},
}

function Tradewright:GetDocumentationSections()
	return self.DOCUMENTATION_SECTIONS
end
