local addonName, Tradewright = ...

local GAP = 12
local PAD = 10
local MODAL_W, MODAL_H = 760, 640

local function createItemDetailsTitleBar(pe, frame, header)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:ClearAllPoints()
	close:SetPoint("RIGHT", frame, "TOPRIGHT", -6, -(header / 2))
	pe:SkinCloseButton(close)
	local title = pe:CreateText(frame, "GameFontNormalLarge", "gold")
	title:SetPoint("LEFT", frame, "TOPLEFT", GAP, -(header / 2) - 1)
	title:SetText("Item details")
end

-- The right card: the item's auction listing history, or an empty state without auction data.
local function createItemDetailsMarketCard(pe, frame)
	frame.marketCard = pe:CreateInset(frame)
	frame.marketCard:SetPoint("TOPLEFT", frame.itemPane, "TOPRIGHT", GAP, 0)
	frame.marketCard:SetPoint("BOTTOMRIGHT", -GAP, GAP)
	local heading = pe:CreateHeading(frame.marketCard, "Auction house")
	heading:SetPoint("TOPLEFT", PAD, -PAD)
	heading:SetPoint("TOPRIGHT", -PAD, -PAD)
	frame.market = pe:CreateMarketHistoryView(frame.marketCard, { noHeader = true, plotHeight = 120 })
	frame.market:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
	frame.market:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	frame.marketEmpty = pe:CreateEmptyState(frame.marketCard)
	frame.marketEmpty:SetAllPoints()
	frame.marketEmpty:SetMessage("No auction data", "Scan the auction house to see this item's prices and hourly history.")
end

local function createItemDetailsWindow(pe)
	local theme = pe:GetTheme()
	local header = theme.size.header
	local frame = CreateFrame("Frame", addonName .. "ItemDetails", UIParent, "BackdropTemplate")
	frame:SetSize(MODAL_W, MODAL_H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	pe:StyleWindow(frame)
	tinsert(UISpecialFrames, frame:GetName())
	createItemDetailsTitleBar(pe, frame, header)

	-- Left: the item (owned, craft cost, chart, recipes). Right: its auction listing history.
	frame.itemPane = pe:CreateItemDetailPane(frame, { metricSettingKey = "inventory.detailsGraphMetric" })
	frame.itemPane:SetPoint("TOPLEFT", GAP, -(header + GAP))
	frame.itemPane:SetPoint("BOTTOMLEFT", GAP, GAP)
	createItemDetailsMarketCard(pe, frame)
	frame:Hide()
	return frame
end

-- Item details window: everything the Inventory and Market detail panes show, for one item.
-- storageKey picks the auction listing; without one, the item's full-scan listing is used.
function Tradewright:ShowItemDetailsWindow(itemID, storageKey)
	itemID = tonumber(itemID)
	if not itemID then
		return
	end
	local ui = self.ui
	ui.itemDetailsWindow = ui.itemDetailsWindow or createItemDetailsWindow(self)
	local frame = ui.itemDetailsWindow
	frame:Show()
	frame:Raise()
	frame.itemPane:ShowItem(itemID, { selectedCharacters = {}, rangeKey = self:GetInventoryMetricRange() })
	local row = self:GetMarketRowForStorageKey(storageKey)
		or (self.BuildAuctionStorageKey and self:GetMarketRowForStorageKey(self:BuildAuctionStorageKey(itemID, "item", tostring(itemID))))
	frame.market:SetShown(row ~= nil)
	frame.marketEmpty:SetShown(row == nil)
	if row then
		frame.market:ShowRow(row)
	end
end
