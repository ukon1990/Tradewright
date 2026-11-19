local addonName, addonTable = ...

local shared = _G.AuctionHelper or {}
_G.AuctionHelper = shared
_G.ProfessionExporter = shared

shared.__addonNames = shared.__addonNames or {}
shared.__addonNames[addonName] = true
shared.ui = shared.ui or {}

setmetatable(addonTable, {
	__index = shared,
	__newindex = shared,
})

addonTable.shared = shared
