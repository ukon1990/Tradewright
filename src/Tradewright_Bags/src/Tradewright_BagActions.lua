local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Acting on one stack or several: move to the bank, the warband bank or the bags,
-- sell to a vendor, destroy. A move is the same two calls as dragging a stack to a free slot.
-- Selling uses the item and so runs only while a merchant window is open. One stack per tick.

local STEP_SECONDS = 0.05
local BACKPACK = 0
local KEPT_TEXT = L["Quest items, bags and rare or better items are never destroyed here."]

local running = false
local menu

local function targetBagIDs(pe, target)
	if target == "bank" then
		return pe:GetBankBagIDs()
	elseif target == "warband" then
		return pe:GetWarbandBagIDs()
	end
	local ids, reagentBag = {}, pe:GetReagentBagIndex()
	for bag = BACKPACK, pe:GetLastBagIndex() do
		if bag ~= reagentBag then
			ids[#ids + 1] = bag
		end
	end
	return ids
end

--- The free slots of `target` ("bags", "bank" or "warband") that take any item: { { bag, slot } }.
function Tradewright:FindFreeBagSlots(target)
	local generalBags = {}
	for _, bag in ipairs(targetBagIDs(self, target)) do
		local _, family = C_Container.GetContainerNumFreeSlots(bag)
		if (family or 0) == 0 then
			generalBags[#generalBags + 1] = bag
		end
	end
	local free = {}
	self:ForEachBagSlot(generalBags, function(bag, slot, info)
		if not info then
			free[#free + 1] = { bag = bag, slot = slot }
		end
	end)
	return free
end

-- Whether the stack is still the one that was listed, and free to act on.
local function stillThere(item)
	local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
	return info ~= nil and tonumber(info.itemID) == item.itemID and not info.isLocked
end

-- Calls `step(entry)` for one entry per tick, then `done()`. `step` returning false ends the run.
-- While a spell is targeting, picking up or using an item would cast it on that item, which the
-- game blocks for addons, so the run waits until targeting ends.
local function runQueue(queue, step, done)
	local pe = Tradewright
	if running then
		pe:PrintMessage(L["Still busy with the last bag action."])
		return
	end
	running = true
	local index = 0
	local function tick()
		if SpellIsTargeting() then
			C_Timer.After(STEP_SECONDS, tick)
			return
		end
		index = index + 1
		if not queue[index] or step(queue[index]) == false then
			running = false
			done()
			return
		end
		C_Timer.After(STEP_SECONDS, tick)
	end
	tick()
end

--- Move stacks to the free slots of `target`, as far as they fit.
function Tradewright:RunBagMoves(items, target)
	local pe = self
	local moves, left = self.BagLogic.PlanMoves(items, self:FindFreeBagSlots(target))
	runQueue(moves, function(move)
		if stillThere(move.item) then
			ClearCursor()
			C_Container.PickupContainerItem(move.item.bag, move.item.slot)
			C_Container.PickupContainerItem(move.bag, move.slot)
			-- A stack the target refuses stays on the cursor: put it back.
			ClearCursor()
		end
	end, function()
		if left > 0 then
			pe:PrintMessage(string.format(L["No room for %d of the stacks."], left))
		end
	end)
end

function Tradewright:IsMerchantOpen()
	return MerchantFrame ~= nil and MerchantFrame:IsShown() == true
end

--- Sell stacks to the open merchant. Stops the moment the merchant window closes.
function Tradewright:RunBagSell(items)
	local pe = self
	local sold, total = 0, 0
	runQueue(self.BagLogic.SellQueue(items), function(item)
		if not pe:IsMerchantOpen() then
			return false
		end
		if stillThere(item) then
			C_Container.UseContainerItem(item.bag, item.slot)
			sold, total = sold + 1, total + item.sellPrice * item.count
		end
	end, function()
		pe:PrintMessage(string.format(L["Sold %d stacks for %s."], sold, pe:FormatCopperShort(total)))
	end)
end

--- Delete one stack of a destroy queue. Only ever called from a click of the player.
function Tradewright:DestroyBagStack(item)
	if stillThere(item) then
		local each = math.max(item.sellPrice or 0, self:GetBagItemAuctionPrice(item.itemID) or 0)
		self:DeleteBagStack({ item = item, value = each * item.count })
	end
end

local function addMenuLine(text, onClick, isTitle)
	local info = UIDropDownMenu_CreateInfo()
	info.text, info.func = text, onClick
	info.notCheckable = true
	info.isTitle = isTitle == true
	info.disabled = onClick == nil and not isTitle
	UIDropDownMenu_AddButton(info)
end


--- Menu of what can be done with `items`, which all sit in `place` ("bags", "bank" or "warband").
--- Opens at `anchor`, or at the mouse.
function Tradewright:ShowBagActionMenu(items, place, anchor)
	local pe = self
	local targets = self.BagLogic.MoveTargets(place, { bankOpen = self:IsBankOpen(), hasWarband = #self:GetWarbandBagIDs() > 0 })
	menu = menu or CreateFrame("Frame", "TradewrightBagActionMenu", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(menu, function()
		addMenuLine(#items == 1 and items[1].name or string.format(L["%d stacks"], #items), nil, true)
		for _, target in ipairs(targets) do
			addMenuLine(target.label, function() pe:RunBagMoves(items, target.key) end)
		end
		if #targets == 0 then
			addMenuLine(L["Open the bank to move items"])
		end
		-- A vendor only buys from the carried bags.
		if place == "bags" and pe:IsMerchantOpen() then
			addMenuLine(L["Sell to the vendor"], function() pe:RunBagSell(items) end)
		end
		addMenuLine("Destroy…", function() pe:ArmBagDestroy(items) end)
	end, "MENU")
	ToggleDropDownMenu(1, nil, menu, anchor or "cursor", 0, 0)
end

Tradewright.BAG_DESTROY_KEPT_TEXT = KEPT_TEXT
