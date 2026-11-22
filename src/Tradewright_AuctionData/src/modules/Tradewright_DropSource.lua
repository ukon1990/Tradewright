local _, Tradewright = ...

-- Where a material has been looted, for the tooltip of a shopping row and the way there. The
-- sightings come from the sightings store (Tradewright_Sources.lua): creatures killed or skinned,
-- nodes and chests opened, waters fished.

local SOURCE_LABEL = { kill = "Drops from", gather = "Gathered from", object = "Found in", fishing = "Fished in" }
-- A tooltip names the likeliest sources only.
local MAX_TOOLTIP_SOURCES = 3

-- What to call a source. Nodes and chests have no name in the loot window, so the zone stands in.
local function sourceName(pe, source)
	if source.kind == "fishing" then
		return pe:GetMapName(source.id) or "waters not named yet"
	elseif source.kind == "object" then
		local zone = source.places[1] and pe:GetMapName(source.places[1][1])
		return zone and ("a node or chest in " .. zone) or "a node or chest"
	end
	return source.name or "a creature not named yet"
end

--- Adds where `itemID` has been looted to tooltip lines, the likeliest sources first:
--- { "Drops from", "Adult Plainstrider (3 of 12 loots)" }. Returns whether a place to go to is known.
function Tradewright:AppendDropSourceLines(lines, itemID)
	local placeKnown = false
	for index, source in ipairs(self:GetDropSources(itemID)) do
		if index <= MAX_TOOLTIP_SOURCES then
			lines[#lines + 1] = { SOURCE_LABEL[source.kind], string.format("%s (%d of %d loots)", sourceName(self, source), source.held, source.opened) }
		end
		placeKnown = placeKnown or source.places[1] ~= nil
	end
	return placeKnown
end

-- Every place `itemID` has been looted at, as NearestPlace reads them.
local function dropPlaces(pe, itemID)
	local places = {}
	for _, source in ipairs(pe:GetDropSources(itemID)) do
		for _, place in ipairs(source.places) do
			places[#places + 1] = { name = sourceName(pe, source), zone = pe:GetMapName(place[1]), mapID = place[1], x = place[2], y = place[3] }
		end
	end
	return places
end

--- Points the way to the nearest place `itemID` has been looted at, and says where it is in chat.
--- Returns whether a waypoint was set, or nil when no such place is known (nothing is said then).
function Tradewright:ShowDropWaypoint(itemID)
	local place = self:NearestPlace(dropPlaces(self, itemID))
	if not place then
		return nil
	end
	local name = self:GetItemDisplayName(itemID)
	local marked = self:SetWaypointTo(place, place.name .. " (" .. name .. ")")
	local zone = place.zone and (" in " .. place.zone) or ""
	self:PrintMessage(string.format("%s was looted from %s%s, at %.1f, %.1f.%s", name, place.name, zone,
		place.x * 100, place.y * 100, marked and " Waypoint set." or ""))
	return marked
end

--- Points the way to where `itemID` can be had: the nearest vendor selling it, else the nearest
--- place it was looted at. Says so in chat when neither is known.
function Tradewright:ShowItemSourceWaypoint(itemID)
	local info = self:GetVendorSource(itemID)
	if info and self:NearestPlace(info.sellers) then
		return self:ShowVendorWaypoint(itemID)
	end
	local marked = self:ShowDropWaypoint(itemID)
	if marked == nil then
		return self:ShowVendorWaypoint(itemID)
	end
	return marked
end
