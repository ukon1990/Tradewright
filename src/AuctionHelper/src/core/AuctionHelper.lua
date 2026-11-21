local _, addonTable = ...

local AuctionHelper = _G.AuctionHelper or addonTable or {}
_G.AuctionHelper = AuctionHelper

AuctionHelper.VERSION = "2.0.0"
AuctionHelper.SCHEMA_VERSION = 12
-- Forever shares retail's project ID; detect by interface band via ForeverLogic (loaded next).
-- Temporary defaults until AuctionHelper_ForeverLogic.lua runs ApplyClientFlags.
local interfaceVersion = select(4, GetBuildInfo()) or 0
AuctionHelper.IS_FOREVER = interfaceVersion >= 16000 and interfaceVersion < 17000
AuctionHelper.IS_RETAIL = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) and not AuctionHelper.IS_FOREVER
AuctionHelper.IS_SUPPORTED = AuctionHelper.IS_RETAIL or AuctionHelper.IS_FOREVER
AuctionHelper.SCAN_WAIT_SECONDS = 0.25
AuctionHelper.MAX_SANITIZE_DEPTH = 8
AuctionHelper.MAX_EXPORT_BYTES = 2 * 1024 * 1024
AuctionHelper.MAX_SAVEDEXPORT_BYTES = AuctionHelper.MAX_EXPORT_BYTES
AuctionHelper.COPYBOX_PREVIEW_BYTES = 48 * 1024
AuctionHelper.COPYBOX_PAGE_BYTES = 48 * 1024
AuctionHelper.JSON_ENCODE_YIELD_STEPS = 1000
AuctionHelper.EXPORT_PROGRESS_STAGE_COUNT = 2
AuctionHelper.EXPORT_PROGRESS_GATHER_WEIGHT = 0.30
AuctionHelper.EXPORT_PROGRESS_GATHER_CREEP_CAP = 0.95
AuctionHelper.EXPORT_PROGRESS_GATHER_CREEP_MAX_SEC = 5
AuctionHelper.EXPORT_PROGRESS_ENCODE_PROGRESS_K = 80000
AuctionHelper.DASHBOARD_ACCOUNT_KEY = "__AH_ACCOUNT__"
AuctionHelper.EXPORT_FORMAT = "AHCBOR1"
AuctionHelper.frame = AuctionHelper.frame or CreateFrame("Frame")

--- Server time, so timestamps saved by every character and module share one clock.
function AuctionHelper:Now()
	return (GetServerTime and GetServerTime()) or time()
end

function AuctionHelper:PrintMessage(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100AuctionHelper|r: " .. tostring(message))
end

--- The debug log lives in the Professions module, which loads after this one and after Auction
--- Data. Until it replaces this, log calls made while those modules start up do nothing.
function AuctionHelper:DebugLog() end

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
function AuctionHelper:GetLastBagIndex()
	return math.max(4, tonumber(NUM_BAG_SLOTS) or 4, reagentBagIndex() or 0)
end
