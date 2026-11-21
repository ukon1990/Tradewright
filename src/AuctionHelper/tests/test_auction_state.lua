-- Run with: lua5.1 tests/test_auction_state.lua (from AuctionHelper root)
-- Every state.auction* key the auction files use is declared once in AuctionShared's AUCTION_STATE_KEYS.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local addons = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local pe = {}
local chunk = assert(loadfile(addons .. "/AuctionHelper_AuctionData/src/modules/AuctionHelper_AuctionShared.lua"))
chunk("AuctionHelper", pe)
local declared, duplicates = {}, {}
for _, key in ipairs(pe.AuctionShared.AUCTION_STATE_KEYS) do
	if declared[key] then
		duplicates[#duplicates + 1] = key
	end
	declared[key] = true
end
check("No key declared twice", #duplicates == 0, table.concat(duplicates, ", "))

-- Files that touch GetState() auction keys: every AuctionData module, and the core data file.
local files = { addons .. "/AuctionHelper/src/core/AuctionHelper_Data.lua" }
local toc = assert(io.open(addons .. "/AuctionHelper_AuctionData/AuctionHelper_AuctionData.toc", "r"))
for line in toc:lines() do
	local file = line:match("^src\\modules\\(.+%.lua)%s*$")
	if file then
		files[#files + 1] = addons .. "/AuctionHelper_AuctionData/src/modules/" .. file
	end
end
toc:close()

local RECEIVERS = { "state%.(auction%w+)", "GetState%(%)%.(auction%w+)", "%f[%w_]s%.(auction%w+)" }
local used, missing = {}, {}
for _, path in ipairs(files) do
	local f = assert(io.open(path, "r"))
	for line in f:lines() do
		for _, pattern in ipairs(RECEIVERS) do
			for key in line:gmatch(pattern) do
				used[key] = true
				if not declared[key] and not missing[key] then
					missing[key] = path:match("[^/]+$")
					missing[#missing + 1] = key .. " (" .. missing[key] .. ")"
				end
			end
		end
	end
	f:close()
end
check("Every used state key is declared", #missing == 0, table.concat(missing, ", "))
local unused = {}
for key in pairs(declared) do
	if not used[key] then
		unused[#unused + 1] = key
	end
end
table.sort(unused)
check("Every declared state key is used", #unused == 0, table.concat(unused, ", "))

if failed > 0 then
	print(failed .. " auction state check(s) failed")
	os.exit(1)
end
print("All auction state checks passed")
