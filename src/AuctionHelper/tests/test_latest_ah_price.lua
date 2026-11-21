-- Run with: lua5.1 tests/test_latest_ah_price.lua (from AuctionHelper root)
-- GetLatestObservedAhPrice: the newer of the own AH scan price and the stored snapshot price.
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

local pe = {}
local chunk = assert(loadfile(root .. "/../AuctionHelper_Professions/src/modules/AuctionHelper_Integrations.lua"))
chunk("AuctionHelper", pe)

local native, summary
function pe:GetNativeAhPrice()
	if native then
		return native.price, native.source, native.seenAt, native.quantity
	end
end
function pe:GetItemEconomySummary()
	return summary
end

local function latest(opts)
	local price, source, seenAt, quantity = pe:GetLatestObservedAhPrice(7, opts)
	return table.concat({ tostring(price), tostring(source), tostring(seenAt), tostring(quantity) }, ",")
end

local function expect(name, want, opts)
	local got = latest(opts)
	check(name, got == want, "got " .. got .. ", want " .. want)
end

native = { price = 100, source = "full_scan", seenAt = 50, quantity = 3 }
summary = { lastPrice = 90, lastSeenAt = 40, snapshot = { source = "snap", sampleSize = 8 }, freshnessState = "fresh" }
expect("Own AH price newer than the snapshot wins", "100,full_scan,50,3")

summary.lastSeenAt = 60
expect("Newer snapshot wins", "90,snap,60,8")

summary.lastSeenAt = nil
expect("Snapshot without a time loses to an own AH price", "100,full_scan,50,3")

native = nil
expect("Snapshot without a time when there is no own AH price", "90,snap,nil,8")

native = { price = 100, seenAt = 50 }
summary = { lastPrice = 0 }
expect("No snapshot price: own AH price, source defaults to native", "100,native,50,nil")

summary.freshnessState = "stale"
expect("requireFresh with a stale summary", "nil,nil,nil,nil", { requireFresh = true })

summary = nil
expect("No economy summary", "nil,nil,nil,nil")

if failed > 0 then
	print(failed .. " latest AH price check(s) failed")
	os.exit(1)
end
print("All latest AH price checks passed")
