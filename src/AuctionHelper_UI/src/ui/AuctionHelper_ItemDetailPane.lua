local _, AuctionHelper = ...

-- Item detail pane beside the inventory table: header, key facts, a history graph and the recipes
-- that make or use the item.

local DETAIL_WIDTH = 288
local PAD = 10
local MAX_RECIPE_ROWS = 6
local METRICS = { { "market", "Price" }, { "crafting", "Craft cost" }, { "quantity", "Quantity" } }

local ItemDetailPaneMixin = {}

--- `opts`: width, onClose (adds a close and a pop-out button), metricSettingKey (setting for the graph metric).
function AuctionHelper:CreateItemDetailPane(parent, opts)
	local pane = self:CreateInset(parent)
	for name, method in pairs(ItemDetailPaneMixin) do
		pane[name] = method
	end
	pane.pe, pane.opts = self, opts or {}
	pane:SetWidth(pane.opts.width or DETAIL_WIDTH)
	if pane.SetClipsChildren then
		pane:SetClipsChildren(true)
	end
	pane:CreateParts()
	return pane
end

function ItemDetailPaneMixin:CreateParts()
	local pe, opts = self.pe, self.opts
	self.header = pe:CreateDetailHeader(self, opts.onClose, opts.onClose and function() pe:ShowItemDetailsWindow(self.itemID) end)
	self.header:SetPoint("TOPLEFT", PAD, -PAD)
	self.header:SetPoint("TOPRIGHT", -PAD, -PAD)
	self.facts = pe:CreateKeyValueList(self)
	self.facts:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -10)
	self.facts:SetPoint("TOPRIGHT", self.header, "BOTTOMRIGHT", 0, -10)
	self.metricButtons = {}
	for index, metric in ipairs(METRICS) do
		local button = pe:CreateButton(self, metric[2], function()
			pe:SetSetting(opts.metricSettingKey, metric[1])
			self:ShowItem(self.itemID, self.context)
		end, { small = true })
		button.metric = metric[1]
		self.metricButtons[index] = button
	end
	self.graph = pe:CreateTimeSeriesGraph(self, { showTitle = false, plotHeight = 92, emptyText = "No history in this range." })
	self.madeHeading = pe:CreateHeading(self, "Made by")
	self.madeList = pe:CreateKeyValueList(self)
	self.usedHeading = pe:CreateHeading(self, "Used in")
	self.usedList = pe:CreateKeyValueList(self)
	self.usedEmpty = pe:CreateText(self, "GameFontHighlightSmall", "textMuted")
	self.madeEmpty = pe:CreateText(self, "GameFontHighlightSmall", "textMuted")
end

-- A heading below `anchor` with its list (or its empty text) below; returns what is shown.
function ItemDetailPaneMixin:PlaceSection(section, anchor, width)
	section.heading:ClearAllPoints()
	section.heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
	section.heading:SetWidth(width)
	for _, part in ipairs({ section.list, section.empty }) do
		part:ClearAllPoints()
		part:SetPoint("TOPLEFT", section.heading, "BOTTOMLEFT", 0, -6)
		part:SetWidth(width)
	end
	return section.empty:IsShown() and section.empty or section.list
end

function ItemDetailPaneMixin:Layout()
	local inner = self:GetWidth() - PAD * 2
	local buttonWidth = math.floor((inner + #self.metricButtons - 1) / #self.metricButtons)
	for index, button in ipairs(self.metricButtons) do
		button:ClearAllPoints()
		button:SetWidth(buttonWidth)
		button:SetPoint("TOPLEFT", self.facts, "BOTTOMLEFT", (index - 1) * (buttonWidth - 1), -10)
	end
	self.graph:ClearAllPoints()
	self.graph:SetPoint("TOPLEFT", self.metricButtons[1], "BOTTOMLEFT", 0, -6)
	self.graph:SetWidth(inner)
	local last = self:PlaceSection({ heading = self.madeHeading, list = self.madeList, empty = self.madeEmpty }, self.graph, inner)
	self:PlaceSection({ heading = self.usedHeading, list = self.usedList, empty = self.usedEmpty }, last, inner)
end

local function itemKindText(pe, itemID)
	local desc = pe:ResolveItemDescriptor(itemID) or {}
	if not desc.itemType then
		return "Item " .. tostring(itemID)
	end
	return desc.itemSubType and (desc.itemType .. " · " .. desc.itemSubType) or desc.itemType
end

local function ownedText(pe, totals)
	local owned = string.format("%s bags · %s bank", pe:FormatNumberGrouped(totals.bags or 0), pe:FormatNumberGrouped(totals.bank or 0))
	if pe.IS_RETAIL and (totals.warband or 0) > 0 then
		owned = owned .. " · " .. pe:FormatNumberGrouped(totals.warband)
	end
	return owned
end

function ItemDetailPaneMixin:ShowFacts(itemID, detail)
	local pe = self.pe
	local economy, crafting = detail.economy or {}, detail.crafting or {}
	self.header:SetItem(itemID, pe:GetItemDisplayName(itemID), itemKindText(pe, itemID), detail.icon)
	self.facts:SetRows({
		{ "Auction price", pe:FormatCopperFull(economy.currentMarket) },
		{ "Average auction price", pe:FormatCopperFull(economy.avgObservedPrice) },
		{ "Average craft cost", pe:FormatCopperFull(crafting.avgCraftCost) },
		{ "Owned", ownedText(pe, economy.inventoryTotals or {}) },
		{ "Price seen", pe:FormatScanTimestamp(economy.currentMarketAt) },
	})
end

-- The graph for the chosen metric, with the craft cost overlaid when a scanned recipe makes the item.
function ItemDetailPaneMixin:ShowGraph(itemID, detail)
	local pe, settingKey = self.pe, self.opts.metricSettingKey
	local metric = pe:GetSetting(settingKey, "market")
	for _, button in ipairs(self.metricButtons) do
		pe:StyleShellButton(button, button.metric == metric)
	end
	local produced = (detail.crafting or {}).producedBy or {}
	local canCraft = #produced > 0
	local materialCost = canCraft and pe:EstimateBestMatCostPerUnitAmongSelection(pe.db, itemID, self.context.selectedCharacters, nil) or nil
	pe:ApplyItemDetailTimeSeriesGraph(itemID, self.graph, {
		metricSettingKey = settingKey,
		rangeKey = detail.rangeKey or pe:GetInventoryMetricRange(),
		quantityCharacterFilter = self.context.selectedCharacters,
		secondaryCraftingOverlay = canCraft and materialCost ~= nil,
		currentCraftCostCopper = materialCost,
		quantityOverlay = pe:GetSetting("inventory.detailsGraphShowQuantity", true) ~= false,
	})
end

local function showRecipeRows(list, empty, rows, emptyText)
	list:SetRows(rows)
	list:SetShown(#rows > 0)
	empty:SetShown(#rows == 0)
	empty:SetText(emptyText)
end

function ItemDetailPaneMixin:ShowRecipes(crafting)
	local produced, used = crafting.producedBy or {}, crafting.usedBy or {}
	local madeRows, usedRows = {}, {}
	for index = 1, math.min(MAX_RECIPE_ROWS, #produced) do
		local entry = produced[index]
		madeRows[index] = { tostring(entry.recipeName), tostring(entry.characterLabel) .. " · " .. tostring(entry.professionName) }
	end
	for index = 1, math.min(MAX_RECIPE_ROWS, #used) do
		local entry = used[index]
		usedRows[index] = {
			string.format("%s x%d", tostring(entry.recipeName), tonumber(entry.quantityRequired) or 0),
			tostring(entry.characterLabel),
		}
	end
	showRecipeRows(self.madeList, self.madeEmpty, madeRows, "No scanned recipe makes this item.")
	showRecipeRows(self.usedList, self.usedEmpty, usedRows, "No scanned recipe uses this item.")
end

function ItemDetailPaneMixin:ShowItem(itemID, context)
	self.itemID, self.context = itemID, context or {}
	if not itemID then
		return
	end
	local detail = self.pe:BuildItemDetailSnapshot(itemID, self.context)
	self:ShowFacts(itemID, detail)
	self:ShowGraph(itemID, detail)
	self:ShowRecipes(detail.crafting or {})
	self:Layout()
end
