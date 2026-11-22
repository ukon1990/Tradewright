local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- The "Reagents" button of the bag window, shown at an open bank: put crafting reagents away in
-- the bank to free bag space, and take back what the craft queue needs. Nothing moves until the
-- player clicks a line of the menu; the moves are the bag window's ordinary stack moves.
-- Which stacks go is decided in Tradewright_ReagentStashLogic.lua.

local menu

-- The carried stacks to deposit under the player's two choices, and how many stay for the queue.
local function depositPlan(pe)
	local reagentBag = pe:GetReagentBagIndex()
	local stacks = pe:ScanBags().items
	for _, stack in ipairs(stacks) do
		stack.inReagentBag = stack.bag == reagentBag
	end
	return pe.ReagentStashLogic.StacksToDeposit(stacks, {
		professionReagents = pe:GetStashOnlyOwnProfessions() and pe:GetOwnProfessionReagents() or nil,
		keep = pe:GetStashKeepsQueueNeeds() and pe:GetOwnQueueNeeds() or nil,
	})
end

local function carriedCounts(pe)
	local carried = {}
	for _, stack in ipairs(pe:ScanBags().items) do
		carried[stack.itemID] = (carried[stack.itemID] or 0) + stack.count
	end
	return carried
end

-- The bank stacks the craft queue still needs in the bags.
local function withdrawPlan(pe)
	local bankStacks = pe:ScanBags(pe:GetBankBagIDs()).items
	return (pe.ReagentStashLogic.StacksToWithdraw(bankStacks, pe:GetOwnQueueNeeds(), carriedCounts(pe)))
end

local function depositLabel(pe, deposit, stayCount)
	local _, scanned = pe:GetOwnProfessionReagents()
	if pe:GetStashOnlyOwnProfessions() and scanned == 0 then
		return L["Scan a profession first, or untick Only reagents my professions use"]
	end
	if #deposit == 0 then
		return L["No reagents to deposit"]
	end
	local stays = stayCount > 0 and string.format(L[" (%d stay for the queue)"], stayCount) or ""
	return string.format(L["Deposit %d %s%s"], #deposit, pe:Plural(#deposit, "stack"), stays)
end

local function addLine(text, onClick)
	local info = UIDropDownMenu_CreateInfo()
	info.text, info.func = text, onClick
	info.notCheckable = true
	info.disabled = onClick == nil
	UIDropDownMenu_AddButton(info)
end

-- A ticked choice. The lines below it count stacks under that choice, so the menu is reopened
-- to show the new counts.
local function addChoice(text, checked, onChange, reopen)
	local info = UIDropDownMenu_CreateInfo()
	info.text, info.checked, info.isNotRadio = text, checked, true
	info.func = function()
		onChange(not checked)
		reopen()
	end
	UIDropDownMenu_AddButton(info)
end

local function fillMenu(pe, reopen)
	local title = UIDropDownMenu_CreateInfo()
	title.text, title.isTitle, title.notCheckable = "Reagents", true, true
	UIDropDownMenu_AddButton(title)
	addChoice(L["Only reagents my professions use"], pe:GetStashOnlyOwnProfessions(), function(checked)
		pe:SetStashOnlyOwnProfessions(checked)
	end, reopen)
	addChoice(L["Keep what my craft queue needs"], pe:GetStashKeepsQueueNeeds(), function(checked)
		pe:SetStashKeepsQueueNeeds(checked)
	end, reopen)
	local deposit, stayCount = depositPlan(pe)
	addLine(depositLabel(pe, deposit, stayCount), #deposit > 0 and function() pe:RunBagMoves(deposit, "bank") end or nil)
	local withdraw = withdrawPlan(pe)
	if #withdraw > 0 then
		addLine(string.format(L["Take %d %s for the craft queue"], #withdraw, pe:Plural(#withdraw, "stack")), function()
			pe:RunBagMoves(withdraw, "bags")
		end)
	else
		addLine(L["Nothing in the bank the craft queue needs"])
	end
end

local function showMenu(pe, anchor)
	menu = menu or CreateFrame("Frame", "TradewrightBagStashMenu", UIParent, "UIDropDownMenuTemplate")
	-- On the next frame: the game closes the menu after the clicked line's handler has run.
	local function reopen()
		C_Timer.After(0, function()
			CloseDropDownMenus()
			showMenu(pe, anchor)
		end)
	end
	UIDropDownMenu_Initialize(menu, function() fillMenu(pe, reopen) end, "MENU")
	ToggleDropDownMenu(1, nil, menu, anchor, 0, 0)
end

--- The header's "Reagents" button. It sits left of `rightNeighbour`.
function Tradewright:CreateBagStashButton(header, rightNeighbour)
	local pe = self
	local button = self:CreateButton(header, L["Reagents"], function(clicked)
		showMenu(pe, clicked)
	end, { small = true, tooltip = L["Deposit crafting reagents in the bank, or take what the craft queue needs."] })
	button:SetPoint("RIGHT", rightNeighbour, "LEFT", -6, 0)
	button:Hide()
	return button
end

--- Shows the button only while the bank is open (stacks cannot move otherwise); the header's info
--- text ends at whichever button is leftmost.
function Tradewright:RefreshBagStashButton(f)
	local shown = self:IsBankOpen() == true
	f.stashButton:SetShown(shown)
	f.meta:SetPoint("RIGHT", shown and f.stashButton or f.rowButton, "LEFT", -8, 0)
end
