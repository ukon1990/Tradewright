local _, AuctionHelper = ...

--- Pure helpers for reagents that vendors sell: what they cost there, who sells them, the nearest
--- seller and how to buy an amount. No WoW API.
---
--- Two sources. `KNOWN` is a built-in list of common crafting supplies at their usual price, without
--- a place. Sellers the player has visited are recorded with their exact price and position, and win
--- over the list: `sellers = { [npcName] = { price, zone, mapID, x, y, seenAt } }` per item.
local VendorLogic = {}
AuctionHelper.VendorLogic = VendorLogic

local TAILOR, SMITH, ENGINEER = "tailoring and leatherworking suppliers", "blacksmithing suppliers", "engineering suppliers"
local TRADE, ENCHANT, COOK = "trade goods vendors", "enchanting suppliers", "cooking suppliers"

-- { [itemID] = { price in copper, kind of vendor } }
VendorLogic.KNOWN = {
	[2320] = { 10, TAILOR }, [2321] = { 100, TAILOR }, [4291] = { 500, TAILOR }, [8343] = { 2000, TAILOR },
	[14341] = { 5000, TAILOR }, [4289] = { 50, TAILOR },
	[2324] = { 25, TRADE }, [2604] = { 50, TRADE }, [2605] = { 100, TRADE }, [6260] = { 50, TRADE },
	[6261] = { 100, TRADE }, [4340] = { 350, TRADE }, [4341] = { 500, TRADE }, [2325] = { 1000, TRADE },
	[4342] = { 2500, TRADE }, [10290] = { 2500, TRADE },
	[2880] = { 100, SMITH }, [3466] = { 2000, SMITH }, [3857] = { 500, SMITH }, [18567] = { 150000, SMITH },
	[4399] = { 200, ENGINEER }, [4400] = { 2000, ENGINEER }, [10647] = { 2000, ENGINEER },
	[6217] = { 124, ENCHANT }, [4470] = { 38, ENCHANT }, [11291] = { 4500, ENCHANT },
	[8925] = { 500, TRADE }, [18256] = { 4000, TRADE },
	[2678] = { 10, COOK }, [2692] = { 40, COOK }, [3713] = { 160, COOK }, [30817] = { 25, COOK },
	[159] = { 25, COOK }, [1179] = { 125, COOK }, [2894] = { 50, COOK }, [4536] = { 25, COOK },
}

-- A whole number of at least `minimum`.
local function atLeast(value, minimum)
	return math.max(minimum, math.floor(tonumber(value) or minimum))
end

-- Paid for with plain coin.
local function soldForCoin(item)
	return item.itemID and (tonumber(item.price) or 0) > 0 and not item.extendedCost
end

--- What to remember from an open merchant. `items = { { itemID, price, stack, available, extendedCost } }`,
--- `place = { zone, mapID, x, y }`. Only items that cost plain coin are kept:
--- `{ [itemID] = { price (one unit), limited, zone, mapID, x, y, seenAt } }`. `limited` is true for an
--- item the vendor holds only a few of (`available` is its stock; negative means endless).
function VendorLogic.SellerEntries(items, place, now)
	local entries = {}
	place = place or {}
	for _, item in ipairs(items or {}) do
		if soldForCoin(item) then
			entries[item.itemID] = {
				price = item.price / atLeast(item.stack, 1), limited = (tonumber(item.available) or -1) >= 0 or nil,
				zone = place.zone, mapID = place.mapID, x = place.x, y = place.y, seenAt = now,
			}
		end
	end
	return entries
end

local function withName(name, entry)
	return {
		name = name, price = entry.price, zone = entry.zone, mapID = entry.mapID, x = entry.x, y = entry.y,
		seenAt = entry.seenAt, world = entry.world, limited = entry.limited,
	}
end

-- 0 for a seller with endless stock and a known price, 1 for limited stock, 2 for no known price.
local function supplyRank(seller)
	if not seller.price then
		return 2
	end
	return seller.limited and 1 or 0
end

-- Endless stock first, then limited stock, then sellers without a price; the cheapest first, then by name.
local function cheaperFirst(a, b)
	local rankA, rankB = supplyRank(a), supplyRank(b)
	if rankA ~= rankB then
		return rankA < rankB
	end
	if a.price ~= b.price then
		return a.price < b.price
	end
	return a.name < b.name
end

-- Visited sellers, plus the directory's sellers that were not visited, in buying order.
local function sellerList(sellers, directory)
	local list = {}
	for name, entry in pairs(sellers) do
		list[#list + 1] = withName(name, entry)
	end
	for name, entry in pairs(directory) do
		if not sellers[name] then
			list[#list + 1] = withName(name, entry)
		end
	end
	table.sort(list, cheaperFirst)
	return list
end

--- What is known about buying `itemID` from a vendor, or nil when no vendor is known to sell it:
--- `{ price, exact, kind, sellers = { { name, price, zone, mapID, x, y, seenAt, world }, … } }`.
--- `sellers` are the ones the player has visited (with a price); `directory` are sellers from a
--- vendor database, in the same shape but without a price, used for those not visited yet.
--- `exact` is true when the price was read from a vendor; `price` is nil when a vendor sells the
--- item but nothing says for how much. `limited` is true when every seller with a known price holds
--- only a few, so the rest may have to come from the auction house.
function VendorLogic.Lookup(itemID, sellers, directory)
	local known = VendorLogic.KNOWN[tonumber(itemID)]
	local list = sellerList(sellers or {}, directory or {})
	if not (known or list[1]) then
		return nil
	end
	local first = list[1] or {}
	known = known or {}
	return {
		price = first.price or known[1], exact = first.price ~= nil, kind = known[2], sellers = list,
		limited = first.limited == true and known[1] == nil,
	}
end

--- Whether to buy at the vendor. `auctionPrice` is the auction unit price, nil when there is none.
--- Returns `{ price, exact, cheaper, limited }`, or nil when no vendor sells it. A tie goes to the
--- vendor: its stock does not run out. Without a vendor price nothing is called cheaper.
function VendorLogic.Advice(info, auctionPrice)
	if not info then
		return nil
	end
	auctionPrice = tonumber(auctionPrice)
	local cheaper = info.price ~= nil and (not auctionPrice or auctionPrice <= 0 or info.price <= auctionPrice)
	return { price = info.price, exact = info.exact, cheaper = cheaper, limited = info.limited }
end

--- "Jannos Ironwill in Stormwind City and 2 more", or the kind of vendor when none has been visited.
function VendorLogic.Where(info)
	local first = info and info.sellers[1]
	if not first then
		return info and info.kind or nil
	end
	local text = first.zone and first.zone ~= "" and (first.name .. " in " .. first.zone) or first.name
	if #info.sellers > 1 then
		text = text .. " and " .. (#info.sellers - 1) .. " more"
	end
	return text
end

local function distanceSquared(seller, here)
	return (seller.x - here.x) ^ 2 + (seller.y - here.y) ^ 2
end

-- Lower is nearer: sellers on the player's map by distance on it, then sellers on the player's
-- continent by distance in the world, then the rest by how recently they were seen.
local function rank(seller, here)
	if here and here.x and here.y and seller.mapID == here.mapID then
		return 0, distanceSquared(seller, here)
	end
	local world, hereWorld = seller.world, here and here.world
	if world and hereWorld and world.continent == hereWorld.continent then
		return 1, distanceSquared(world, hereWorld)
	end
	return 2, -(seller.seenAt or 0)
end

--- The seller to walk to from `here = { mapID, x, y, world = { continent, x, y } }`: the closest one
--- on the same map, otherwise the closest on the same continent (sellers and `here` that carry
--- `world`), otherwise the one seen most recently. Sellers without a position are skipped. Returns
--- the seller and whether it is on the player's map.
function VendorLogic.Nearest(sellers, here)
	local best, bestTier, bestScore
	for _, seller in ipairs(sellers or {}) do
		if seller.mapID and seller.x and seller.y then
			local tier, score = rank(seller, here)
			if not best or tier < bestTier or (tier == bestTier and score < bestScore) then
				best, bestTier, bestScore = seller, tier, score
			end
		end
	end
	return best, bestTier == 0
end

--- How to buy `amount` units of an item sold `stack` at a time, at most `maxStack` per purchase.
--- Returns the purchases (units each) and their total; an item sold in bundles is rounded up to
--- whole bundles. At most `limit` purchases (default 40), so one click cannot flood the server.
function VendorLogic.BuyPlan(amount, stack, maxStack, limit)
	amount, stack, maxStack = atLeast(amount, 0), atLeast(stack, 1), atLeast(maxStack, 1)
	local purchases, total = {}, 0
	while total < amount and #purchases < (limit or 40) do
		local units = stack > 1 and stack or math.min(maxStack, amount - total)
		purchases[#purchases + 1] = units
		total = total + units
	end
	return purchases, total
end

return VendorLogic
