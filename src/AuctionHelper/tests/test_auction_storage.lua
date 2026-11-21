-- Run with: lua5.1 tests/test_auction_storage.lua (from AuctionHelper root)
-- Pins the saved auction formats (storage keys, compact snapshot rows, hourly history) and the
-- item key / snapshot normalizers, so a SavedVariables file from an older build still loads.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local repo = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local NOW = 1700000000
local HOUR = "1699999200"
_G.C_Timer = { After = function() end }
_G.GetBuildInfo = function() return "1.16.1", "1", "", 16001 end
_G.CreateFrame = function() return {} end
_G.GetServerTime = function() return NOW end
_G.GetCurrentRegion = function() return 3 end
_G.GetNormalizedRealmID = function() return 1084 end

local pe = {}
local function load(path)
	local chunk, err = loadfile(repo .. "/" .. path)
	assert(chunk, err)
	chunk("AuctionHelper", pe)
end
load("AuctionHelper/src/core/AuctionHelper.lua")
load("AuctionHelper/src/util/AuctionHelper_ForeverLogic.lua")
load("AuctionHelper/src/util/AuctionHelper_CoreHelpers.lua")
load("AuctionHelper/src/util/AuctionHelper_Util.lua")
load("AuctionHelper/src/core/AuctionHelper_Data.lua")
load("AuctionHelper_AuctionData/src/modules/AuctionHelper_Auction.lua")
local FL = pe.ForeverLogic

pe.GetSetting = function(_, _, default) return default end
pe.DebugLog = function() end
pe.LedgerPurchaseStats = function() return nil end
pe.LedgerSaleStats = function() return nil end
pe.UpsertNativeAuctionPrice = function() return true end
pe.RollupDailyAuctionHistory = function() end

-- Item keys
local plainKey = { itemID = 2589, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
local bonusKey = { itemID = 19019, itemLevel = 71, itemSuffix = 0, battlePetSpeciesID = 0 }
local petKey = { itemID = 82800, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 39 }
check("Item key, plain item ID", FL.SerializeItemKey(nil, 2589) == "2589")
check("Item key, all-zero key table", FL.SerializeItemKey(plainKey) == "2589")
check("Item key, item level", FL.SerializeItemKey(bonusKey) == "19019:71:0:0")
check("Item key, battle pet", FL.SerializeItemKey(petKey) == "82800:0:0:39")
check("Item key, fields without an item ID", FL.SerializeItemKey({ itemLevel = 71 }, 19019) == "19019:71:0:0")
check("Item key, saved key text is kept", FL.SerializeItemKey("19019:71:0:0", 19019) == "19019:71:0:0")

-- Storage keys
check("Storage key, plain item", pe:BuildAuctionStorageKey(2589, "item") == "3:1084:2589")
check("Storage key, all-zero item key", pe:BuildAuctionStorageKey(2589, "item", plainKey) == "3:1084:2589")
check("Storage key, item level", pe:BuildAuctionStorageKey(19019, "item", bonusKey) == "3:1084:19019:71:0:0")
check("Storage key, battle pet", pe:BuildAuctionStorageKey(82800, "item", petKey) == "3:1084:82800:0:0:39")
check("Storage key, commodity", pe:BuildAuctionStorageKey(2592, "commodity") == "3:2592")

-- Snapshot normalizer: compact (`p/q/n/h/t/s`) and long entries give the same fields.
local shortEntry = { p = 150, q = 10, n = 3, h = 200, t = NOW - 60, s = "classic_full" }
local longEntry = { marketLow = 150, sampleSize = 10, listingCount = 3, marketHigh = 200, seenAt = NOW - 60, source = "classic_full" }
for name, entry in pairs({ short = shortEntry, long = longEntry }) do
	local fields = FL.NormalizeMarketSnapshotFields(entry)
	check("Normalized " .. name .. " entry", fields and fields.price == 150 and fields.marketHigh == 200 and fields.sampleSize == 10
		and fields.listingCount == 3 and fields.seenAt == NOW - 60 and fields.source == "classic_full")
	local snap = pe:NormalizeAuctionSnapshotEntry(entry)
	check("Snapshot of " .. name .. " entry", snap and snap.marketLow == 150 and snap.minBuyout == 150 and snap.marketHigh == 200
		and snap.sampleSize == 10 and snap.listingCount == 3 and snap.seenAt == NOW - 60 and snap.source == "classic_full")
end
check("Price falls back to minBuyout, then price", FL.NormalizeMarketSnapshotFields({ minBuyout = 7 }).price == 7
	and FL.NormalizeMarketSnapshotFields({ price = 8 }).price == 8)
check("Entry without a price normalizes to nil", FL.NormalizeMarketSnapshotFields({ t = NOW }) == nil)
check("Missing counts normalize to zero", FL.NormalizeMarketSnapshotFields({ p = 5 }).sampleSize == 0
	and FL.NormalizeMarketSnapshotFields({ p = 5 }).listingCount == 0)

-- Compact rows: the saved snapshot format.
local compact = pe:BuildCompactAuctionSnapshotEntry(longEntry)
check("Long entry compacts to p/q/n/h/t/s", compact.p == 150 and compact.q == 10 and compact.n == 3 and compact.h == 200
	and compact.t == NOW - 60 and compact.s == "classic_full")
local count = 0
for _ in pairs(compact) do count = count + 1 end
check("Compact row holds only p/q/n/h/t/s", count == 6, count)
local bare = pe:BuildCompactAuctionSnapshotEntry({ price = 9 })
check("Compact row defaults time and source, drops empty counts", bare.p == 9 and bare.t == NOW and bare.s == "unknown"
	and bare.q == nil and bare.n == nil and bare.h == nil)
check("Compact row needs a price", pe:BuildCompactAuctionSnapshotEntry({ t = NOW }) == nil)
check("Compact row floors the listing count", pe:BuildCompactAuctionSnapshotEntry({ p = 1, n = 2.7 }).n == 2)

-- A saved auction table from an older build, with a long and a compact snapshot row.
pe.db = {
	auction = {
		storageKeyVersion = 2,
		snapshot = {
			items = {
				["3:1084:2589"] = { p = 150, q = 10, n = 3, t = NOW - 60, s = "classic_full" },
				["3:1084:19019:71:0:0"] = { marketLow = 5000, sampleSize = 2, listingCount = 1, seenAt = NOW - 120, source = "replicate_full" },
			},
			commodities = {
				["3:2592"] = { minBuyout = 40, sampleSize = 100, seenAt = NOW - 30, source = "replicate_full" },
			},
		},
		history = {
			hourly = {
				["3:1084:2589"] = { [HOUR] = { n = 1, q = 10, w = 1500, l = 150, m = 150, x = 150, t = NOW - 60 } },
			},
		},
		indexes = {
			byItemID = {
				["2589"] = { ["3:1084:2589"] = true },
				["19019"] = { ["3:1084:19019:71:0:0"] = true },
				["2592"] = { ["3:2592"] = true },
			},
		},
		itemLastScanAt = { ["2589"] = NOW - 60 },
	},
}
local summary = pe:GetItemEconomySummary(2589)
check("Saved compact row loads its price", summary and summary.lastPrice == 150, summary and summary.lastPrice)
check("Recent saved row is fresh", summary and summary.freshnessState == "fresh")
summary = pe:GetItemEconomySummary(19019)
check("Saved long row loads its price", summary and summary.lastPrice == 5000, summary and summary.lastPrice)
summary = pe:GetItemEconomySummary(2592)
check("Saved commodity row loads its price", summary and summary.lastPrice == 40, summary and summary.lastPrice)
local snap = pe:GetAuctionSnapshot("3:1084:19019:71:0:0")
check("Snapshot by storage key", snap and snap.marketLow == 5000 and snap.sampleSize == 2)

pe.GetSetting = function(_, key, default)
	if key == "auction.priceFreshnessMinutes" then
		return 1
	end
	return default
end
check("Freshness window is at least a minute", pe:GetAuctionPriceFreshnessWindowSeconds() == 60)
pe.db.auction.itemLastScanAt["2589"] = NOW - 600
pe.db.auction.snapshot.items["3:1084:2589"].t = NOW - 600
check("Row older than the window is stale", pe:GetItemEconomySummary(2589).freshnessState == "stale")
pe.db.auction.snapshot.items["3:1084:2589"].t = NOW - 60
pe.GetSetting = function(_, _, default) return default end

-- A new observation of the same item adds to the saved history instead of starting a new one.
pe:RecordAuctionObservation({ itemID = 2589, itemKey = plainKey, marketLow = 170, sampleSize = 5, seenAt = NOW, source = "classic_full" })
local saved = pe.db.auction.snapshot.items["3:1084:2589"]
check("Observation replaces the saved row with a compact one", saved.p == 170 and saved.q == 5 and saved.t == NOW and saved.marketLow == nil)
local bucket = pe.db.auction.history.hourly["3:1084:2589"][HOUR]
check("Observation adds to the saved hourly bucket", bucket.n == 2 and bucket.q == 15 and bucket.w == 1500 + 170 * 5
	and bucket.l == 170 and bucket.m == 150 and bucket.x == 170 and bucket.t == NOW)
check("Observation keeps one index entry per storage key", pe.db.auction.indexes.byItemID["2589"]["3:1084:2589"] == true)
local keys = 0
for _ in pairs(pe.db.auction.history.hourly) do keys = keys + 1 end
check("Observation adds no new history key", keys == 1, keys)

-- Compacting the saved data turns long rows into compact rows with the same price.
pe:GetState().auctionHistoryTrimmedAt = nil
pe:CompactAuctionStorageData()
local compacted = pe.db.auction.snapshot.items["3:1084:19019:71:0:0"]
check("Compacting keeps the long row's price", compacted and compacted.p == 5000 and compacted.q == 2 and compacted.n == 1
	and compacted.marketLow == nil)
check("Compacting keeps the commodity row", pe.db.auction.snapshot.commodities["3:2592"].p == 40)

if failed > 0 then
	print(failed .. " test(s) failed")
	os.exit(1)
end
print("All auction storage tests passed")
