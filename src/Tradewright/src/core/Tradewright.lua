local _, addonTable = ...

local Tradewright = _G.Tradewright or addonTable or {}
_G.Tradewright = Tradewright

Tradewright.VERSION = "2.0.0"
Tradewright.SCHEMA_VERSION = 12
-- Forever shares retail's project ID; detect by interface band via ForeverLogic (loaded next).
-- Temporary defaults until Tradewright_ForeverLogic.lua runs ApplyClientFlags.
local interfaceVersion = select(4, GetBuildInfo()) or 0
Tradewright.IS_FOREVER = interfaceVersion >= 16000 and interfaceVersion < 17000
Tradewright.IS_RETAIL = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) and not Tradewright.IS_FOREVER
Tradewright.IS_SUPPORTED = Tradewright.IS_RETAIL or Tradewright.IS_FOREVER
Tradewright.SCAN_WAIT_SECONDS = 0.25
Tradewright.MAX_SANITIZE_DEPTH = 8
Tradewright.MAX_EXPORT_BYTES = 2 * 1024 * 1024
Tradewright.MAX_SAVEDEXPORT_BYTES = Tradewright.MAX_EXPORT_BYTES
Tradewright.COPYBOX_PREVIEW_BYTES = 48 * 1024
Tradewright.COPYBOX_PAGE_BYTES = 48 * 1024
Tradewright.JSON_ENCODE_YIELD_STEPS = 1000
Tradewright.EXPORT_PROGRESS_STAGE_COUNT = 2
Tradewright.EXPORT_PROGRESS_GATHER_WEIGHT = 0.30
Tradewright.EXPORT_PROGRESS_GATHER_CREEP_CAP = 0.95
Tradewright.EXPORT_PROGRESS_GATHER_CREEP_MAX_SEC = 5
Tradewright.EXPORT_PROGRESS_ENCODE_PROGRESS_K = 80000
Tradewright.DASHBOARD_ACCOUNT_KEY = "__AH_ACCOUNT__"
Tradewright.EXPORT_FORMAT = "AHCBOR1"
Tradewright.frame = Tradewright.frame or CreateFrame("Frame")

--- Server time, so timestamps saved by every character and module share one clock.
function Tradewright:Now()
	return (GetServerTime and GetServerTime()) or time()
end

function Tradewright:PrintMessage(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Tradewright|r: " .. tostring(message))
end

--- The debug log lives in the Professions module, which loads after this one and after Auction
--- Data. Until it replaces this, log calls made while those modules start up do nothing.
function Tradewright:DebugLog() end

-- The reagent bag's index when this client has one: from Enum.BagIndex, else bag 5 when it has slots.
local function reagentBagIndex()
	local reagent = Enum and Enum.BagIndex and tonumber(Enum.BagIndex.ReagentBag)
	if reagent then
		return reagent
	end
	local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(5)
	return (tonumber(slots) or 0) > 0 and 5 or nil
end

--- Highest bag index the player carries: backpack 0, bags 1-4, and the reagent bag when the client
--- has one. Every bag walk (mail, auction, inventory) goes 0..this.
function Tradewright:GetLastBagIndex()
	return math.max(4, tonumber(NUM_BAG_SLOTS) or 4, reagentBagIndex() or 0)
end
