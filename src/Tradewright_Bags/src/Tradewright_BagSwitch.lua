local _, Tradewright = ...

-- The on/off switch of the bag window. On: the game's bag frames are parked under a
-- hidden frame and the Tradewright window is shown whenever one of them is open, so the bag key,
-- merchants and mail keep driving the game's own open/close logic. Off: the frames get their
-- parents back. Nothing global is replaced, so switching needs no reload.

local BAG_FUNCTIONS = {
	"ToggleAllBags", "OpenAllBags", "CloseAllBags", "ToggleBackpack", "OpenBackpack", "CloseBackpack",
	"ToggleBag", "OpenBag", "CloseBag",
}

local hiddenParent
local originalParents = {}
local hooked, syncPending = false, false

local function gameBagFrames()
	local frames = {}
	if ContainerFrameCombinedBags then
		frames[#frames + 1] = ContainerFrameCombinedBags
	end
	-- ContainerFrame1 is the backpack, then one per bag and the reagent bag.
	for index = 1, (tonumber(NUM_TOTAL_BAG_FRAMES) or tonumber(NUM_BAG_FRAMES) or 4) + 1 do
		local frame = _G["ContainerFrame" .. index]
		if frame then
			frames[#frames + 1] = frame
		end
	end
	return frames
end

local function anyGameBagOpen()
	for _, frame in ipairs(gameBagFrames()) do
		if frame:IsShown() then
			return true
		end
	end
	return false
end

local function sync()
	syncPending = false
	local pe = Tradewright
	if pe:IsBagWindowEnabled() then
		pe:SetBagWindowShown(anyGameBagOpen())
	end
end

-- One bag function often calls another; look once, after they have all run.
local function requestSync()
	if syncPending then
		return
	end
	syncPending = true
	C_Timer.After(0, sync)
end

local function installHooks()
	if hooked then
		return
	end
	hooked = true
	for _, name in ipairs(BAG_FUNCTIONS) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, requestSync)
		end
	end
end

local function hideGameBags()
	hiddenParent = hiddenParent or CreateFrame("Frame")
	hiddenParent:Hide()
	for _, frame in ipairs(gameBagFrames()) do
		if frame:GetParent() ~= hiddenParent then
			originalParents[frame] = frame:GetParent()
			pcall(frame.SetParent, frame, hiddenParent)
		end
	end
end

local function showGameBags()
	for frame, parent in pairs(originalParents) do
		pcall(frame.SetParent, frame, parent)
	end
	originalParents = {}
end

function Tradewright:IsBagWindowEnabled()
	return self:GetSetting("bags.enabled", true) == true
end

--- Bring the game in line with the setting: park or restore the game's bag frames.
function Tradewright:ApplyBagTakeover()
	if self:IsBagWindowEnabled() then
		installHooks()
		hideGameBags()
		sync()
	else
		showGameBags()
		self:SetBagWindowShown(false)
	end
	self:ApplyBankTakeover()
end

function Tradewright:SetBagWindowEnabled(enabled)
	self:SetSetting("bags.enabled", enabled and true or false)
	self:ApplyBagTakeover()
	self:PrintMessage(enabled and "Tradewright bags are on."
		or "Tradewright bags are off: the game's bags open instead. /ah bags turns them back on.")
	if self.SettingsTab then
		self.SettingsTab:Refresh()
	end
end

--- The window was closed by its button or Escape: close the game's parked bags too, so the next
--- press of the bag key opens again. It also ends the bank session it stood in for.
function Tradewright:OnBagWindowClosed()
	self:CloseBagBank()
	if self:IsBagWindowEnabled() and anyGameBagOpen() and CloseAllBags then
		CloseAllBags()
	end
end

-- `/ah bags [on|off]`: Tradewright_Data.lua is at its size limit, so the command is added here.
local baseHandleSlash = Tradewright.HandleSlash
function Tradewright:HandleSlash(input)
	local command, rest = string.match(string.lower(self:Trim(input)), "^(%S+)%s*(.-)$")
	if command ~= "bags" then
		return baseHandleSlash(self, input)
	end
	if rest == "on" or rest == "off" then
		self:SetBagWindowEnabled(rest == "on")
	else
		self:SetBagWindowEnabled(not self:IsBagWindowEnabled())
	end
end
