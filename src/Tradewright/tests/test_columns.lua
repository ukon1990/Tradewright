-- Run with: lua5.1 tests/test_columns.lua (from Tradewright root)
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
function pe:Colorize(text, colorKey) return "<" .. colorKey .. ">" .. text end
function pe:FormatCopperShort(copper) return copper .. "c" end
local chunk, err = loadfile(root .. "/../Tradewright_UI/src/ui/Tradewright_Columns.lua")
assert(chunk, err)
chunk("Tradewright_UI", pe)

-- Percent texts
check("FormatPercent: no value", pe:FormatPercent(nil) == "-")
check("FormatPercent: rounds half up", pe:FormatPercent(0.125) == "13%", pe:FormatPercent(0.125))
check("FormatPercent: whole fraction", pe:FormatPercent(1) == "100%")
check("FormatSignedPercent: rise has a plus", pe:FormatSignedPercent(0.18) == "+18%", pe:FormatSignedPercent(0.18))
check("FormatSignedPercent: fall has a minus", pe:FormatSignedPercent(-0.12) == "-12%", pe:FormatSignedPercent(-0.12))
check("FormatSignedPercent: no value", pe:FormatSignedPercent(nil) == "-")
check("FormatPercentChange: rise is good", pe:FormatPercentChange(0.18) == "<success>+18%")
check("FormatPercentChange: fall is bad", pe:FormatPercentChange(-0.12) == "<danger>-12%")
check("FormatPercentChange: lower is good flips the colour", pe:FormatPercentChange(-0.12, true) == "<success>-12%")
check("FormatPercentChange: a change under half a percent stays plain", pe:FormatPercentChange(0.004) == "+0%")
check("FormatPercentChange: no value", pe:FormatPercentChange(nil) == "-")

-- Number columns
local money = pe:MoneyColumn({ id = "price", label = "Price", width = 70 })
check("MoneyColumn: shows the field", money.getText({ price = 120 }) == "120c")
check("MoneyColumn: missing value shows a dash", money.getText({}) == "-")
check("MoneyColumn: zero is shown, not a dash", money.getText({ price = 0 }) == "0c")
check("MoneyColumn: sorts high to low by default", money.sortable and money.defaultSort == "desc")
check("MoneyColumn: missing value sorts below zero", money.sortValue({}) < money.sortValue({ price = 0 }))
local read = pe:MoneyColumn({ id = "then", field = "thenPerHour", width = 74 })
check("MoneyColumn: field other than the id", read.getText({ thenPerHour = 5, ["then"] = 9 }) == "5c")
local fallback = pe:MoneyColumn({ id = "high", width = 86, value = function(row) return row.high or row.low end })
check("MoneyColumn: value function", fallback.getText({ low = 7 }) == "7c" and fallback.sortValue({ low = 7 }) == 7)
local fixed = pe:MoneyColumn({ id = "cost", width = 70, sortable = false })
check("MoneyColumn: not sortable", not fixed.sortable and fixed.defaultSort == nil)
local share = pe:PercentColumn({ id = "share", width = 52 })
check("PercentColumn: shows a percent", share.getText({ share = 0.5 }) == "50%")

if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All column checks passed")
