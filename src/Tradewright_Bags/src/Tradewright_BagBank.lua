local _, Tradewright = ...

-- The bank in the bag window. The game ends the bank session when its bank window
-- hides, so with the setting on that window stays open and is only made invisible. Opening the
-- bank then opens the bag window on its Bank view. Nothing is replaced: off gives the window back.

local TINY_SCALE = 0.001
local OPEN_DELAY_SECONDS = 0.1

local saved -- the game's bank window's own alpha and scale while it is invisible

function Tradewright:IsBagBankEnabled()
	return self:IsBagWindowEnabled() and self:GetSetting("bags.bank", true) == true
end

--- Bring the game's bank window in line with the setting: invisible, or as it was.
function Tradewright:ApplyBankTakeover()
	local frame = BankFrame
	if not frame then
		return
	end
	if self:IsBagBankEnabled() then
		saved = saved or { alpha = frame:GetAlpha(), scale = frame:GetScale() }
		frame:SetAlpha(0)
		frame:SetScale(TINY_SCALE)
	elseif saved then
		frame:SetAlpha(saved.alpha)
		frame:SetScale(saved.scale)
		saved = nil
	end
end

--- End the bank session, when the bag window stands in for the bank window.
function Tradewright:CloseBagBank()
	if not (self:IsBagBankEnabled() and self:IsBankOpen()) then
		return
	end
	if C_Bank and C_Bank.CloseBankFrame then
		C_Bank.CloseBankFrame()
	elseif CloseBankFrame then
		CloseBankFrame()
	end
end

local handlers = {}

function handlers.PLAYER_LOGIN(pe)
	pe:ApplyBankTakeover()
end

function handlers.BANKFRAME_OPENED(pe)
	if not pe:IsBagBankEnabled() then
		pe:RequestBagWindowRefresh()
		return
	end
	pe:ApplyBankTakeover()
	if OpenAllBags then
		OpenAllBags()
	end
	-- After the bag functions have opened the window on its Bags view.
	C_Timer.After(OPEN_DELAY_SECONDS, function()
		if pe:IsBankOpen() then
			pe:ShowBagBank()
		end
	end)
end

function handlers.BANKFRAME_CLOSED(pe)
	pe:LeaveBagBank()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	handlers[event](Tradewright)
end)
for event in pairs(handlers) do
	events:RegisterEvent(event)
end
