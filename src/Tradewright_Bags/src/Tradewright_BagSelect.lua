local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Selecting stacks in the bag window. The slots are the game's item buttons and
-- must keep running the game's own click code, so nothing here touches them: a transparent catcher
-- lies over the slots while Ctrl or Alt is held, or while something is selected, and takes the
-- clicks. Click: select or unselect. Right-click: the actions menu.

local GAP = 4

local selection = {} -- BagLogic.SlotKey -> item ID
local selectionView -- the tab and view the selection belongs to
local picked = {} -- the selected stacks as of the last redraw
local armed = false -- Destroy was chosen: each click on the bar's button deletes one stack

local function auctionPriceOf(itemID)
	return Tradewright:GetBagItemAuctionPrice(itemID)
end

function Tradewright:ClearBagSelection()
	selection, armed = {}, false
	self:RefreshBagWindow()
end

function Tradewright:IsBagSlotSelected(item)
	return item.bag ~= nil and selection[self.BagLogic.SlotKey(item.bag, item.slot)] ~= nil
end

--- Called on every redraw with the stacks shown: forgets the selection when the view changed or
--- is read-only, drops stacks that are gone, and returns the selected stacks.
function Tradewright:SyncBagSelection(view, items)
	local key = view.live and (view.tab .. ":" .. view.mode) or nil
	if key ~= selectionView then
		selection, armed, selectionView = {}, false, key
	end
	picked = self.BagLogic.SelectedItems(selection, items)
	return picked
end

--- Destroy was chosen for `items`: select them and arm the bar's button. Nothing is deleted yet.
function Tradewright:ArmBagDestroy(items)
	local queue, total, refused = self.BagLogic.DestroyQueue(items, auctionPriceOf)
	if #queue == 0 then
		self:PrintMessage(string.format(L["Nothing to destroy. %s"], self.BAG_DESTROY_KEPT_TEXT))
		return
	end
	selection = {}
	for _, item in ipairs(items) do
		selection[self.BagLogic.SlotKey(item.bag, item.slot)] = item.itemID
	end
	armed = true
	self:PrintMessage(string.format(L["Destroying %d stacks worth %s: click \"Destroy next\" once for each. It cannot be undone.%s"],
		#queue, self:FormatCopperShort(total), refused > 0 and (" " .. self.BAG_DESTROY_KEPT_TEXT) or ""))
	self:RefreshBagWindow()
end

local function destroyNext()
	local pe = Tradewright
	local item = pe.BagLogic.DestroyQueue(picked, auctionPriceOf)[1]
	if armed and item then
		pe:DestroyBagStack(item)
	end
end

local function itemUnderMouse(f)
	for _, placed in ipairs(f.placed) do
		if not placed.item.free and placed.button:IsMouseOver() then
			return placed.item
		end
	end
	return nil
end

local function onCatcherClick(catcher, mouseButton)
	local pe, f = Tradewright, catcher.window
	local item = itemUnderMouse(f)
	if mouseButton == "RightButton" then
		local items = #picked > 0 and picked or { item }
		if #items > 0 then
			pe:ShowBagActionMenu(items, f.view.place)
		end
	elseif item then
		pe.BagLogic.ToggleSelected(selection, item)
		armed = false
		pe:RefreshBagWindow()
	end
end

local function createCatcher(f)
	local catcher = CreateFrame("Button", nil, f)
	catcher:SetAllPoints(f.scroll)
	catcher:SetFrameLevel(f.scroll:GetFrameLevel() + 20)
	catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	catcher:SetScript("OnClick", onCatcherClick)
	catcher.window = f
	catcher:Hide()
	return catcher
end

--- Show the catcher over a live view while Ctrl or Alt is held or something is selected. It steps
--- aside while a spell is targeting, so Pick Lock and the like reach the game's own item button.
function Tradewright:UpdateBagCatcher()
	local f = self.ui.bagWindow
	if not f then
		return
	end
	local wanted = f:IsShown() and f.view.live and not SpellIsTargeting()
		and (next(selection) ~= nil or IsControlKeyDown() or IsAltKeyDown())
	f.catcher:SetShown(wanted == true)
end

--- The bar shown while something is selected: the count, Destroy next (once armed), Actions, Clear.
--- Also creates the catcher of the window `f`.
function Tradewright:CreateBagSelectBar(f)
	local pe = self
	local bar = CreateFrame("Frame", nil, f)
	bar:SetHeight(self:GetTheme().size.control)
	bar.text = self:CreateText(bar, "GameFontHighlightSmall", "gold")
	bar.text:SetPoint("LEFT", bar, "LEFT", 4, 0)
	bar.clear = self:CreateButton(bar, L["Clear"], function() pe:ClearBagSelection() end, { small = true })
	bar.clear:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	bar.actions = self:CreateButton(bar, L["Actions"], function(button)
		pe:ShowBagActionMenu(picked, f.view.place, button)
	end, { small = true, tooltip = L["Move, sell or destroy the selected stacks. Right-clicking a slot opens the same menu."] })
	bar.actions:SetPoint("RIGHT", bar.clear, "LEFT", -GAP, 0)
	bar.destroy = self:CreateButton(bar, L["Destroy next"], destroyNext, { small = true })
	bar.destroy:SetPoint("RIGHT", bar.actions, "LEFT", -GAP, 0)
	bar:Hide()
	f.catcher = createCatcher(f)
	return bar
end

--- Fill the bar from the selected stacks. Returns whether it is shown.
function Tradewright:RefreshBagSelectBar(bar)
	local left = armed and #self.BagLogic.DestroyQueue(picked, auctionPriceOf) or 0
	armed = left > 0
	bar:SetShown(#picked > 0)
	bar.text:SetText(string.format(L["%d selected"], #picked))
	bar.destroy:SetShown(armed)
	if armed then
		self:SetButtonLabel(bar.destroy, string.format(L["Destroy next (%d left)"], left), true)
	end
	return #picked > 0
end

local events = CreateFrame("Frame")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
events:SetScript("OnEvent", function()
	Tradewright:UpdateBagCatcher()
end)
