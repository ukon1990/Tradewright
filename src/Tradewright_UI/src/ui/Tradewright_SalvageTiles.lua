local Tradewright = select(2, ...)

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- The four stat tiles at the top of the Destroying tab (Tradewright_SalvageTab.lua), read from
-- SalvageCheckLogic.Check: how far the values can be trusted, the last full scan, the materials'
-- prices and where the yields come from. Each tile is one thing the player can check or fix, its
-- note says how, and hovering it lists what is behind it.

local SalvageTiles = {}
Tradewright.SalvageTiles = SalvageTiles

local TILE_COUNT = 4
-- Lines in a tile's tooltip; retail can list dozens of materials, the largest shares come first.
local TOOLTIP_LINES = 20
-- A scan this many hours old or more is named in days.
local DAYS_FROM_HOURS = 48

local LEVEL = {
	good = { L["Solid"], "success", L["Fresh scan, priced materials"] },
	weak = { L["Rough"], "warning", L["See the tiles beside it"] },
	none = { L["Not enough data"], "danger", L["Values wait for prices"] },
}

--- One line of text per reason SalvageCheckLogic.Check gives.
function Tradewright:SalvageCheckReasonText(reason)
	local item = reason.itemID and self:GetItemDisplayName(reason.itemID)
	if reason.code == "no_full_scan" then
		return L["No full scan yet: run one at the auction house."]
	elseif reason.code == "no_yields" then
		return L["No yields are known for these items yet."]
	elseif reason.code == "old_scan" then
		return string.format(L["The last full scan is %d hours old: run a new one."], reason.hours)
	elseif reason.code == "no_price" then
		return string.format(L["%s has no price: it was not listed in the last full scan."], item)
	elseif reason.code == "few_price_days" then
		return string.format(L["%s has %d days of prices; a usual price needs %d, so scan once a day."], item, reason.days,
			self.SalvageCheckLogic.USUAL_PRICE_DAYS)
	end
	return string.format(L["%d of %d values use researched yields (~). A kind of gear switches to your own results once you have disenchanted %d of it."],
		reason.count, reason.total, self.SalvageLogic.TRUSTED_CASTS)
end

-- Shows a tile's tooltip: a title, then `lines` (text, or `{ left, right }` pairs), capped.
local function showTooltip(tile)
	local lines = tile.tooltipLines
	if not lines then
		return
	end
	GameTooltip:SetOwner(tile, "ANCHOR_BOTTOM")
	GameTooltip:AddLine(tile.label:GetText())
	for index = 1, math.min(#lines, TOOLTIP_LINES) do
		local line = lines[index]
		if type(line) == "table" then
			GameTooltip:AddDoubleLine(line[1], line[2], 0.8, 0.8, 0.8, 1, 1, 1)
		else
			GameTooltip:AddLine(line, 1, 1, 1, true)
		end
	end
	if #lines > TOOLTIP_LINES then
		GameTooltip:AddLine(string.format(L["and %d more"], #lines - TOOLTIP_LINES))
	end
	GameTooltip:Show()
end

--- A row of four tiles under `parent`; lay it out with `row:Layout()` when its width changes.
function SalvageTiles.Create(pe, parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(58)
	row.tiles = {}
	for index = 1, TILE_COUNT do
		local tile = pe:CreateStat(row)
		tile:EnableMouse(true)
		tile:SetScript("OnEnter", showTooltip)
		tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row.tiles[index] = tile
	end
	function row:Layout()
		pe:LayoutEvenRow(self, self.tiles, 0, 12)
	end
	row:SetScript("OnSizeChanged", row.Layout)
	return row
end

local function valuesTile(pe, check)
	local level = LEVEL[check.level]
	local lines = {}
	for _, reason in ipairs(check.reasons) do
		lines[#lines + 1] = pe:SalvageCheckReasonText(reason)
	end
	return { L["Values"], level[1], level[3], level[2], lines }
end

-- "3 h ago", "2 days ago"; under an hour reads "Just now".
local function ageText(hours)
	if hours < 1 then
		return L["Just now"]
	elseif hours < DAYS_FROM_HOURS then
		return string.format(L["%d h ago"], hours)
	end
	return string.format(L["%d days ago"], math.floor(hours / 24))
end

local function scanTile(pe, check)
	local explain = { L["Prices come from full scans at the auction house. Values drift as a scan gets older than a day."] }
	if not check.scanHours then
		return { L["Last full scan"], L["None yet"], L["Open the AH, press Full scan"], "danger", explain }
	end
	local stale = check.scanHours * 3600 > pe.SalvageCheckLogic.STALE_SCAN_SEC
	return { L["Last full scan"], ageText(check.scanHours), stale and L["Run a full scan at the AH"] or L["Scan again after a day"],
		stale and "warning" or "textPrimary", explain }
end

-- One tooltip line per material short of a usual price, then how many have one.
local function materialLines(pe, materials)
	local lines, usual = { string.format(L["A usual price needs scans on %d days. Scan once a day until these reach it."],
		pe.SalvageCheckLogic.USUAL_PRICE_DAYS) }, 0
	for _, material in ipairs(materials) do
		if material.usual then
			usual = usual + 1
		else
			local days = material.priced and string.format(L["%d of %d days"], material.days or 0, pe.SalvageCheckLogic.USUAL_PRICE_DAYS)
				or L["no price yet"]
			lines[#lines + 1] = { pe:GetItemDisplayName(material.itemID), days }
		end
	end
	if usual > 0 then
		lines[#lines + 1] = string.format(L["%d more have a usual price."], usual)
	end
	return lines, usual
end

local function materialsTile(pe, check)
	local total = #check.materials
	if total == 0 then
		return { L["Material prices"], "-", L["Known after the first scan"], "textMuted", nil }
	end
	local lines, usual = materialLines(pe, check.materials)
	local short = total - usual
	local note = short == 0 and L["All have a usual price"] or string.format(L["%d need more scan days"], short)
	return { L["Material prices"], string.format(L["%d of %d"], usual, total), note, short == 0 and "textPrimary" or "warning", lines }
end

local function yieldsTile(pe, check)
	local kinds = check.kinds
	if kinds.total == 0 then
		return { L["Yields"], "-", L["Known once gear is valued"], "textMuted", nil }
	end
	local value = kinds.counted == 0 and L["Researched"] or kinds.counted == kinds.total and L["Counted"] or L["Mixed"]
	local explain = {
		L["Researched yields come from the reference tables, checked against about 20,000 counted disenchants."],
		string.format(L["A kind of gear (armor or weapon, quality, %d item levels) uses counted results after %d disenchants of it."],
			pe.SalvageLogic.DISENCHANT_LEVEL_BAND, pe.SalvageLogic.TRUSTED_CASTS),
	}
	return { L["Yields"], value, string.format(L["%d of %d kinds counted"], kinds.counted, kinds.total), "textPrimary", explain }
end

--- Fills the tiles from a SalvageCheckLogic.Check result; nil `check` while the last scan is read.
function SalvageTiles.Show(pe, row, check)
	if not check then
		for _, tile in ipairs(row.tiles) do
			tile:SetValues("", "…", L["Reading the last scan…"])
			tile.tooltipLines = nil
		end
		return
	end
	local specs = { valuesTile(pe, check), scanTile(pe, check), materialsTile(pe, check), yieldsTile(pe, check) }
	for index, spec in ipairs(specs) do
		local tile = row.tiles[index]
		tile:SetValues(spec[1], spec[2], spec[3], spec[4])
		tile.tooltipLines = spec[5] and #spec[5] > 0 and spec[5] or nil
	end
end
