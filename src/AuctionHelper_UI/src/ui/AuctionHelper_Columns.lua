local _, AuctionHelper = ...

-- Column definitions shared by the tables (the column fields are described in AuctionHelper_Table.lua),
-- and the percent texts they show.

--- "12%" for 0.12, "-" when there is no value.
function AuctionHelper:FormatPercent(fraction)
	if not fraction then
		return "-"
	end
	return string.format("%d%%", math.floor(fraction * 100 + 0.5))
end

--- "+12%" or "-12%" for a change of 0.12 or -0.12, "-" when there is no value.
function AuctionHelper:FormatSignedPercent(fraction)
	if not fraction then
		return "-"
	end
	return string.format("%+d%%", math.floor(fraction * 100 + 0.5))
end

--- FormatSignedPercent in green when the change is good and red when it is bad; a change that
--- rounds to 0% stays uncoloured. A rise is good unless `lowerIsGood` (a lower price when buying).
function AuctionHelper:FormatPercentChange(fraction, lowerIsGood)
	local text = self:FormatSignedPercent(fraction)
	if not fraction or math.abs(fraction) < 0.005 then
		return text
	end
	local good = fraction > 0
	if lowerIsGood then
		good = not good
	end
	return self:Colorize(text, good and "success" or "danger")
end

--- CreateItemColumn for rows with `itemID` and an optional `name` (the item's own name when missing).
--- `spec` takes every CreateItemColumn field; getItemID and getName are only needed to read other fields.
function AuctionHelper:ItemColumn(spec)
	spec.getItemID = spec.getItemID or function(row) return row.itemID end
	spec.getName = spec.getName or function(row) return row.name or self:GetItemDisplayName(row.itemID) end
	return self:CreateItemColumn(spec)
end

--- A right-aligned number column showing `spec.format(value)`, or "-" when the row has no value.
--- `spec`: id, label, width, format, optional. The number is `row[spec.field or spec.id]`, or `spec.value(row)`.
--- Sortable unless `sortable = false`: highest first, rows without a value last; `sortValue` overrides the sort.
function AuctionHelper:NumberColumn(spec)
	local value = spec.value or function(row) return row[spec.field or spec.id] end
	local sortable = spec.sortable ~= false
	return {
		id = spec.id, label = spec.label, width = spec.width, justifyH = "RIGHT", optional = spec.optional,
		sortable = sortable, defaultSort = sortable and "desc" or nil,
		sortValue = spec.sortValue or function(row) return tonumber(value(row)) or -1 end,
		getText = function(row)
			local number = value(row)
			return number and spec.format(number) or "-"
		end,
	}
end

--- NumberColumn for copper, shown short ("12g 40s").
function AuctionHelper:MoneyColumn(spec)
	spec.format = function(copper) return self:FormatCopperShort(copper) end
	return self:NumberColumn(spec)
end

--- NumberColumn for a fraction, shown as a percent.
function AuctionHelper:PercentColumn(spec)
	spec.format = function(fraction) return self:FormatPercent(fraction) end
	return self:NumberColumn(spec)
end
