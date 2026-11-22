local addonName, Tradewright = ...

-- Vendor buy window: opens beside the merchant window when this vendor sells reagents the cart still
-- needs. Each row has the amount to buy (the missing amount by default) and a Buy button; nothing is
-- bought without a click.

local PAD = 10
local WIDTH = 320
local ROW_HEIGHT = 34
local MAX_ROWS = 8

local function amountOf(row)
	return math.max(0, tonumber(row.amount:GetText()) or 0)
end

local function buy(pe, row)
	if row.offer and amountOf(row) > 0 then
		pe:BuyMerchantCartOffer(row.offer, amountOf(row))
	end
end

local function createAmountBox(pe, row)
	local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	box:SetSize(40, 22)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(4)
	box:SetJustifyH("RIGHT")
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		buy(pe, row)
	end)
	box:SetScript("OnTextChanged", function() pe:RefreshVendorBuyTotal() end)
	pe:SkinEditBox(box)
	return box
end

local function createRow(pe, f, index)
	local row = CreateFrame("Frame", nil, f)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", PAD, -(pe:GetTheme().size.header + PAD + (index - 1) * ROW_HEIGHT))
	row:SetPoint("RIGHT", -PAD, 0)
	row.icon = pe:CreateItemIcon(row, 24)
	row.icon:SetPoint("LEFT")
	row.buy = pe:CreateButton(row, "Buy", function() buy(pe, row) end, { small = true, width = 48 })
	row.buy:SetPoint("RIGHT")
	row.amount = createAmountBox(pe, row)
	row.amount:SetPoint("RIGHT", row.buy, "LEFT", -6, 0)
	row.name = pe:CreateText(row, "GameFontHighlight")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
	row.name:SetPoint("RIGHT", row.amount, "LEFT", -10, 0)
	row.name:SetWordWrap(false)
	row.detail = pe:CreateText(row, "GameFontHighlightSmall", "textMuted")
	row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.detail:SetPoint("RIGHT", row.name, "RIGHT")
	row.detail:SetWordWrap(false)
	return row
end

local function buildChrome(pe, f)
	local header = pe:GetTheme().size.header
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:ClearAllPoints()
	close:SetPoint("RIGHT", f, "TOPRIGHT", -6, -(header / 2))
	pe:SkinCloseButton(close)
	close:SetScript("OnClick", function() f:Hide() end)
	f.title = pe:CreateText(f, "GameFontNormalLarge", "gold")
	f.title:SetPoint("LEFT", f, "TOPLEFT", PAD, -(header / 2) - 1)
	f.title:SetText("Reagents sold here")
	f.buyAll = pe:CreateButton(f, "Buy all", function()
		for _, row in ipairs(f.rows) do
			if row:IsShown() then
				buy(pe, row)
			end
		end
	end, { primary = true })
	f.buyAll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	f.total = pe:CreateText(f, "GameFontHighlightSmall", "textMuted")
	f.total:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, PAD + 13)
	f.total:SetPoint("RIGHT", f.buyAll, "LEFT", -8, 0)
end

local function ensureWindow(pe)
	if pe.ui.vendorBuyWindow then
		return pe.ui.vendorBuyWindow
	end
	local f = CreateFrame("Frame", addonName .. "VendorBuyWindow", UIParent, "BackdropTemplate")
	f:SetWidth(WIDTH)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	pe:StyleWindow(f)
	buildChrome(pe, f)
	f.rows = {}
	for index = 1, MAX_ROWS do
		f.rows[index] = createRow(pe, f, index)
	end
	pe:SkinTree(f)
	f:Hide()
	pe.ui.vendorBuyWindow = f
	return f
end

local function fillRow(pe, row, offer)
	row.offer = offer
	row:SetShown(offer ~= nil)
	if not offer then
		return
	end
	row.icon:SetItem(offer.itemID, offer.icon)
	row.name:SetText(offer.name or pe:GetItemDisplayName(offer.itemID))
	row.detail:SetText(string.format("Need %s · %s each%s", pe:FormatNumberGrouped(offer.need),
		pe:FormatCopperShort(math.ceil(offer.price)), offer.stock and (" · " .. offer.stock .. " in stock") or ""))
	-- Keep what the player is typing; otherwise follow the amount still missing.
	if not row.amount:HasFocus() then
		row.amount:SetText(tostring(offer.need))
	end
end

--- Updates the "Total" line from the amounts in the rows.
function Tradewright:RefreshVendorBuyTotal()
	local f = self.ui and self.ui.vendorBuyWindow
	if not f then
		return
	end
	local total = 0
	for _, row in ipairs(f.rows) do
		if row:IsShown() and row.offer then
			total = total + amountOf(row) * row.offer.price
		end
	end
	f.total:SetText("Total " .. self:FormatCopperShort(math.ceil(total)))
	f.buyAll:SetEnabled(total > 0)
end

local merchantOpen = false

--- Shows the queue materials this merchant sells, or hides the window when there are none.
function Tradewright:RefreshVendorBuyWindow()
	local offers = merchantOpen and self.GetMerchantCartOffers and self:GetMerchantCartOffers() or {}
	if #offers == 0 then
		if self.ui.vendorBuyWindow then
			self.ui.vendorBuyWindow:Hide()
		end
		return
	end
	local f = ensureWindow(self)
	local shown = math.min(#offers, MAX_ROWS)
	for index, row in ipairs(f.rows) do
		fillRow(self, row, offers[index])
	end
	f:SetHeight(self:GetTheme().size.header + PAD + shown * ROW_HEIGHT + PAD + 26 + PAD)
	f:ClearAllPoints()
	if MerchantFrame and MerchantFrame:IsShown() then
		f:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 8, 0)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 260, 60)
	end
	f:Show()
	self:RefreshVendorBuyTotal()
end

-- The refresh waits a frame: the merchant window and its item list are ready only after the event.
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
	local pe = Tradewright
	if event ~= "BAG_UPDATE_DELAYED" then
		merchantOpen = event ~= "MERCHANT_CLOSED"
	end
	if pe.db and pe.ui and (merchantOpen or pe.ui.vendorBuyWindow) then
		C_Timer.After(0, function() pe:RefreshVendorBuyWindow() end)
	end
end)
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED" }) do
	pcall(frame.RegisterEvent, frame, event)
end
