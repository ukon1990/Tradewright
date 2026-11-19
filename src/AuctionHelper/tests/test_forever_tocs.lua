-- Run with: lua5.1 tests/test_forever_tocs.lua (from AuctionHelper root)
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local addonsRoot = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local modules = {
	{ "AuctionHelper", "AuctionHelper.toc" },
	{ "AuctionHelper_AuctionData", "AuctionHelper_AuctionData.toc" },
	{ "AuctionHelper_Professions", "AuctionHelper_Professions.toc" },
	{ "AuctionHelper_Inventory", "AuctionHelper_Inventory.toc" },
	{ "AuctionHelper_UI", "AuctionHelper_UI.toc" },
}

for _, m in ipairs(modules) do
	local path = addonsRoot .. "/" .. m[1] .. "/" .. m[2]
	local f = io.open(path, "r")
	check(m[1] .. " toc opens", f ~= nil, path)
	if f then
		local toc = f:read("*a")
		f:close()
		check(m[1] .. " Interface 16001", toc:find("Interface: 16001", 1, true) ~= nil)
		check(m[1] .. " camelot", toc:find("AllowLoadGameType: camelot", 1, true) ~= nil)
		check(m[1] .. " not standard-only", toc:find("AllowLoadGameType: standard", 1, true) == nil)
		check(m[1] .. " Blizzard_Professions not hard Dep", not toc:match("## Dependencies:[^\n]*Blizzard_Professions"))
		if m[1] == "AuctionHelper_UI" then
			check("UI TOC lists MarketUI", toc:find("AuctionHelper_MarketUI.lua", 1, true) ~= nil)
			check("UI TOC lists MarketTab", toc:find("AuctionHelper_MarketTab.lua", 1, true) ~= nil)
		end
	end
end

-- AGENTS + skills present
local agents = io.open(root .. "/AGENTS.md", "r")
check("AGENTS.md exists", agents ~= nil)
if agents then agents:close() end

local skill = io.open(root .. "/.agents/skills/wow-addon-issue-work/focus/auction-forever.md", "r")
check("auction-forever focus exists", skill ~= nil)
if skill then skill:close() end

if failed > 0 then
	print(string.format("%d failure(s)", failed))
	os.exit(1)
end
print("All forever TOC checks passed")
