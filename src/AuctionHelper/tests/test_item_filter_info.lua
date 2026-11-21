-- Run with: lua5.1 tests/test_item_filter_info.lua (from AuctionHelper root)
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local instantCalls, qualities = 0, {}
_G.C_Item = {
	GetItemInfoInstant = function(itemID)
		instantCalls = instantCalls + 1
		return itemID, "Trade Goods", "Herb"
	end,
	GetItemQualityByID = function(itemID) return qualities[itemID] end,
	GetItemInfo = function(itemID)
		if itemID == 3 then
			return "Old", "link", 4
		end
	end,
}
local pe = {}
local chunk, err = loadfile(root .. "/../AuctionHelper_UI/src/ui/AuctionHelper_Widgets.lua")
assert(chunk, err)
chunk("AuctionHelper_UI", pe)

check("no id gives empty info", next(pe:GetItemFilterInfo(nil)) == nil)
local info = pe:GetItemFilterInfo(1)
check("class labels from the instant API", info.classLabel == "Trade Goods" and info.subclassLabel == "Herb")
check("quality unknown until loaded", info.quality == nil)
qualities[1] = 2
info = pe:GetItemFilterInfo("1")
check("quality retried once loaded", info.quality == 2 and instantCalls == 1, instantCalls)
pe:GetItemFilterInfo(1)
check("cached after quality is known", instantCalls == 1)
check("quality falls back to GetItemInfo", pe:GetItemFilterInfo(3).quality == 4)
_G.C_Item.GetItemInfoInstant = nil
check("no instant API gives no class labels", pe:GetItemFilterInfo(5).classLabel == nil)

if failed > 0 then
	print(failed .. " item filter info check(s) failed")
	os.exit(1)
end
print("All item filter info checks passed")
