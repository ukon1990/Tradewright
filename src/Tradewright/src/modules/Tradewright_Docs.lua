local _, Tradewright = ...

--- Plain-text sections for the in-game Documentation tab.
Tradewright.DOCUMENTATION_SECTIONS = {
	{
		id = "start",
		title = "Getting started",
		body = [=[FIRST STEPS
• Open the window with /ah or /tradewright, or the minimap button.
• Open the auction house and run a full scan. Prices on every tab come from your scans.
• Open each profession window and press Scan below the recipe. Crafts and Inventory then know your recipes.
• Scan the auction house again on later days. Usual prices, sales estimates and Opportunities need several days of scans.

PROFESSION PANEL
Below the profession recipe Tradewright shows the materials, what they cost and the profit. Add to queue puts the craft on the Crafts tab queue. Scan saves every recipe and reagent of the open profession for this character.]=],
	},
	{
		id = "inventory_tab",
		title = "Inventory tab & economy",
		body = [=[INVENTORY TAB
Open the dashboard (/tradewright) and pick Inventory. The table lists the profession-relevant items stored for your characters, one row per item.

Columns: Item, Qty and, by default, Current AH, Avg craft, Profit each and SR. Use Columns in the toolbar to show Bags / bank, Last AH, Avg AH, Last craft, Profit, all and Seen. Drag a column header to move it; click it to sort.

FILTERS
Search matches item name, item ID, role and type. The toolbar dropdowns filter by character, role (Crafted, Crafting reagent, Crafted + reagent, Tracked) and item type. The time range sets how far back averages and charts look. Refresh reads bags and bank again on this character.

ITEM DETAILS
Click a row to open the detail pane: auction price, averages, craft cost, where you hold the item, a chart (Price, Craft cost or Quantity) and the scanned recipes that make or use it. Shift-click a row to link the item in chat.

PRICES
Current AH comes from your auction house scans; an item never scanned has no price. Totals in the table footer add up quantity times price for the rows shown. These are estimates, not official game values.]=],
	},
	{
		id = "prices",
		title = "Usual price and sells a day",
		body = [=[USUAL PRICE
• Each day you scan, Tradewright keeps one price per item: the middle of the lowest prices it saw that day.
• The usual price is the middle of those daily prices over the last 14 days. Settings can change the window.
• One odd listing does not move it. The usual range is where the middle half of those days fell.
• An item needs scans on 5 different days first. Until then deals and movers use its 7-day average.
• A day is added the first time you log in after it ended.

SELLS A DAY, ESTIMATED
• The auction house shows what is listed, never what was sold.
• Tradewright compares an item's listed quantity between two of your scans at most 26 hours apart.
• What is gone counts as sold. Cancelled and expired auctions also disappear, so the figure runs high.
• New listings between two scans hide sales. Read it as "at most about this many".
• Your own sales of an item are the lowest the figure can be.
• It needs two scans of the item within 26 hours and shows the day after.
• "Few sales seen" means it rests on fewer than five pairs of scans.

LISTED SUPPLY LASTS
• Listed quantity divided by sells a day. It counts every listing, also overpriced ones that will not sell.]=],
	},
	{
		id = "opportunities",
		title = "Opportunities",
		body = [=[WHAT TO BUY OR SELL RIGHT NOW
The Opportunities tab has four lists. Each shows the sums behind a row and what could go wrong when you click it.
• Flips: listed well under the usual price and known to sell. Buy, then list at the usual price.
• Sure things: listed under what a vendor pays. Buy, then sell to any vendor.
• Price gaps (risky): a few cheap listings under a much higher next price. Buy them, relist under the next price.
• Sell now: things you own priced 10% or more above usual that sell.

WHAT THE LISTS NEED
• One full scan fills Sure things.
• Flips, Price gaps and Sell now need a usual price: scans on 5 different days. Today's scans count from tomorrow.
• They also need a sales estimate: two scans of an item within a day, so scan twice on some days.
• The "Usual price known for" card shows how far along your scans are.

WHEN A LIST IS EMPTY
The list counts how many items are left after each rule, for example:
• 7,071 items in the last scan
• 312 have a usual price
• 40 are 25% or more under it
• 3 sell 1 or more a day
• 0 make 1g or more
The first step that leaves nothing is marked, with the setting or the scan that gets past it.

HOW SURE A ROW IS
• Early: its usual price rests on only 2 to 4 days. Shown only when you turn it on in Settings, and left out of the totals.
• A "?" after Sells a day: the estimate rests on few pairs of scans or only on your own sales.
• Settings, Opportunities sets how cheap, how busy and how profitable a row must be.]=],
	},
}

function Tradewright:GetDocumentationSections()
	return self.DOCUMENTATION_SECTIONS
end
