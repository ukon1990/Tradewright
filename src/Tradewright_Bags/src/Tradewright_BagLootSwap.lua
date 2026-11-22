local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Loot swap: when loot does not fit because the bags are full, and the loot is worth
-- more than the cheapest stack carried, a prompt offers to delete that stack and take the loot.
-- Nothing is deleted without the player clicking Swap.

local WIDTH, HEIGHT, PAD = 300, 104, 10
local LOOT_ITEM = 1 -- GetLootSlotType: an item (not coin or currency)

local sawFull = false -- the game said "inventory is full" while this loot was open
local pendingSlot -- loot slot to take once the deleted stack has left the bags
local prompt

local function hidePrompt()
	if prompt then
		prompt:Hide()
	end
end

-- What one of an item is worth: the higher of its vendor and auction price.
local function priceEach(pe, link, itemID)
	local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	local vendor = tonumber((select(11, getInfo(link)))) or 0
	return math.max(vendor, pe:GetBagItemAuctionPrice(itemID) or 0)
end

-- The items still in the loot window: { slot, name, count, value }.
local function lootEntries(pe)
	local entries = {}
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		local itemID = link and tonumber(string.match(link, "item:(%d+)"))
		if itemID and GetLootSlotType(slot) == LOOT_ITEM then
			local _, name, count = GetLootSlotInfo(slot)
			count = count or 1
			entries[#entries + 1] = { slot = slot, name = name or "?", count = count, value = priceEach(pe, link, itemID) * count }
		end
	end
	return entries
end

local function onSwap()
	local pe = Tradewright
	local drop = pe:GetBagDropCandidate()
	local shown = prompt.drop.item
	hidePrompt()
	-- Only when the stack offered is still the one that would go.
	if drop and drop.item.bag == shown.bag and drop.item.slot == shown.slot and drop.item.itemID == shown.itemID then
		pendingSlot = prompt.loot.slot
		pe:DeleteBagStack(drop)
	end
end

local function ensurePrompt(pe)
	if prompt then
		return prompt
	end
	prompt = CreateFrame("Frame", "TradewrightLootSwap", UIParent, "BackdropTemplate")
	prompt:SetSize(WIDTH, HEIGHT)
	prompt:SetFrameStrata("DIALOG")
	prompt:EnableMouse(true)
	pe:StyleWindow(prompt)
	prompt.title = pe:CreateText(prompt, "GameFontNormal", "gold")
	prompt.title:SetPoint("TOPLEFT", PAD, -PAD)
	prompt.title:SetText(L["Bags full"])
	prompt.close = pe:CreateIconButton(prompt, "close", hidePrompt)
	prompt.close:SetPoint("TOPRIGHT", -6, -6)
	prompt.text = pe:CreateParagraph(prompt, "textPrimary")
	prompt.text:SetPoint("TOPLEFT", prompt.title, "BOTTOMLEFT", 0, -6)
	prompt.text:SetPoint("RIGHT", prompt, "RIGHT", -PAD, 0)
	prompt.swap = pe:CreateButton(prompt, L["Swap"], onSwap, { primary = true })
	prompt.swap:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	prompt.note = pe:CreateText(prompt, "GameFontHighlightSmall", "textMuted")
	prompt.note:SetPoint("LEFT", prompt, "BOTTOMLEFT", PAD, PAD + 13)
	prompt.note:SetPoint("RIGHT", prompt.swap, "LEFT", -8, 0)
	prompt.note:SetText(L["Destroying cannot be undone."])
	return prompt
end

local function showPrompt(pe, loot, drop)
	local f = ensurePrompt(pe)
	local count = loot.count > 1 and (" x" .. loot.count) or ""
	f.loot, f.drop = loot, drop
	f.text:SetText(string.format(L["Destroy %s to loot %s%s (%s)?"], pe:DescribeBagDrop(drop), loot.name, count,
		pe:FormatCopperShort(loot.value)))
	f:ClearAllPoints()
	if LootFrame and LootFrame:IsShown() then
		f:SetPoint("TOPLEFT", LootFrame, "BOTTOMLEFT", 0, -6)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
	end
	f:Show()
end

-- Offer a swap when loot was refused for lack of room and something carried is worth less.
local function evaluate()
	local pe = Tradewright
	if not sawFull or pendingSlot or not pe:GetSetting("bags.lootSwap", true) then
		return hidePrompt()
	end
	if pe.BagLogic.BagTotals(pe:ScanBags().bags).free > 0 then
		return hidePrompt()
	end
	local drop = pe:GetBagDropCandidate()
	local loot = drop and pe.BagLogic.BestLootSwap(lootEntries(pe), drop)
	if not loot then
		return hidePrompt()
	end
	showPrompt(pe, loot, drop)
end

local handlers = {}

function handlers.LOOT_OPENED()
	sawFull, pendingSlot = false, nil
	hidePrompt()
end

handlers.LOOT_CLOSED = handlers.LOOT_OPENED

function handlers.UI_ERROR_MESSAGE(_, message)
	if message == ERR_INV_FULL and GetNumLootItems() > 0 then
		sawFull = true
		evaluate()
	end
end

-- The deleted stack is gone: take the loot it made room for, then look for another swap.
function handlers.BAG_UPDATE_DELAYED()
	if pendingSlot then
		local slot = pendingSlot
		pendingSlot = nil
		LootSlot(slot)
	elseif sawFull then
		evaluate()
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
for event in pairs(handlers) do
	pcall(events.RegisterEvent, events, event)
end
