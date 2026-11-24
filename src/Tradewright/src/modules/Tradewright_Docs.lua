local _, Tradewright = ...

--- Plain-text sections for the in-game Documentation tab.
Tradewright.DOCUMENTATION_SECTIONS = {
	{
		id = "start",
		title = "Getting started",
		body = [=[FIRST STEPS
• Open the window with /tw or /tradewright, or the minimap button.
• Open the auction house and run a full scan. Prices on every tab come from your scans.
• Open each of your professions once. Tradewright saves the recipes, so Crafts and Inventory know them.
• Scan the auction house again on later days. Usual prices, sales estimates and Opportunities need several days of scans.

PROFESSION PANEL
• Below the recipe Tradewright shows the reagents, what they cost and the profit.
• Add to queue puts the craft in the craft queue, shown here and on the Crafts tab.
• Recipes are saved again when you close the window, if they changed. /tw rescan reads the open profession anew.]=],
	},
	{
		id = "inventory_tab",
		title = "Inventory",
		body = [=[INVENTORY TAB
One row per item saved for your characters: what your recipes make or use, and other tracked items.

• Always shown: Item and Qty. Shown by default: Characters, Current AH, Avg craft and Profit each.
• Columns in the toolbar shows the others: Sales a day, Bags / bank, Last AH, Avg AH, Last craft, Profit, all and Seen.
• Drag a column header to move it; click it to sort. Hover a header to see what the column holds.

FILTERS
• Search matches item name, item ID, role and type.
• The dropdowns filter by character, role (Crafted, Crafting reagent, Crafted + reagent, Other) and item type.
• The time range sets how far back averages and charts look.
• Refresh reads bags and bank again on this character.

ITEM DETAILS
• Click a row for its auction price, averages, craft cost and where you hold it.
• The chart shows Price, Craft cost or Quantity; below it are the scanned recipes that make or use the item.
• Shift-click a row to link the item in chat.

PRICES
• Current AH comes from your auction house scans; an item never scanned has no price.
• The footer adds up quantity times price for the rows shown. These are estimates.]=],
	},
	{
		id = "crafts",
		title = "Crafts and the queue",
		body = [=[CRAFTS TAB
Every scanned recipe with its sale after the auction cut, reagent cost, profit and return (profit divided by reagent cost).
• Reagents: Use what I own counts reagents you hold as already paid for. Buy everything prices all of them at the auction house.
• Prices from: the auction house, or what you yourself sold and bought for.
• Make: how many to craft for the chosen days of sales, less what you already own.
• Click a row to see its reagents, then Add to queue.

QUEUE AND CART
• The queue is the list of crafts to make. To craft shows them; the profession window has the same list.
• The cart is what the queue still needs on this character. Buy it from the Cart tab of the auction house panel.
• Reagents held by another character are mailed by your bank character. See the Mail topic.]=],
	},
	{
		id = "auction_panel",
		title = "Auction house panel",
		body = [=[The panel opens beside the auction house. It has three tabs.

SELL
• Lists what you can sell from your bags. Click a row to put the item in the sell slot.
• Check prices looks up the prices picked in the list beside it: your crafts, your items or both.
• Full scan reads every auction once. The server allows it only now and then; the button shows when it is ready.
• A lit Full scan button means many prices are older than an hour: one full scan updates them all, faster than checking them one by one.
• Post profitable and Post all queue the shown items. Click Post next once per auction: the game does not let an addon post by itself.
• Keep holds back a number of an item. Ignore leaves it out when posting many.

CART
• The reagents your queued crafts still need. Find selected searches for one, Check all looks up every price, Buy cheapest buys the selected row.

AUCTIONS
• Your own auctions. Check prices shows which are undercut.
• Cancel undercut cancels one per click, most undercut first. The deposit is lost and the item comes back by mail.]=],
	},
	{
		id = "mail",
		title = "Mail",
		body = [=[BANK CHARACTER
Pick one in Settings, Mail: the character that sells at the auction house and holds your reagents.

AT THE MAILBOX
• On the bank character: reagents your queued crafts need go to the crafters.
• Attach fills one mail, Attach all fills them one after another. Press Send in the mailbox for each.
• On other characters: crafted items and surplus go to the bank character.
• Review lists every item, what goes and what stays. Keep sets how many stay on this character and is remembered.]=],
	},
	{
		id = "bags",
		title = "Bags",
		body = [=[Tradewright Bags is optional. Switch it in Settings, Bags, or with /tw bags on and /tw bags off.
• Items are grouped by category. Bags, Bank, Both and Log switch the view; Log lists what entered and left the bags.
• Other characters show as tabs. Their items can be looked at, not moved.
• Select several stacks, then Actions: move, sell or destroy. Destroying needs one click per stack.
• Destroy cheapest destroys the junk stack a vendor pays least for when the bags are full. It cannot be undone.
• Reagents deposits crafting reagents in the bank, or takes out what the craft queue needs.]=],
	},
	{
		id = "farming",
		title = "Farming",
		body = [=[A FARM
• Press Start farm on the Farming tab, or type /twfarm start. Loot for a while, then press Stop and save.
• The farm window shows the gold an hour so far. It pauses when you stand still; Settings, Farming sets after how long.
• A farm records what you looted, not a route. Start this farm adds a new run to a saved farm.

MY FARMS
• Then is the gold an hour at the prices of that day, Now at today's prices.
• Worth is the usual price after the auction cut for items known to sell, and the vendor price for the rest.

WHAT TO FARM
• Trade goods ranked by Traded a day: usual price times estimated sales. It is a ranking, not income.
• An item needs full scans on 5 different days. Early estimates lists the rest from fewer scans.]=],
	},
	{
		id = "prices",
		title = "Usual price and sales a day",
		body = [=[USUAL PRICE
• Each day you scan, Tradewright keeps one price per item: the middle of the lowest prices it saw that day.
• The usual price is the middle of those daily prices over the last 14 days. Settings can change the window.
• One odd listing does not move it. The usual range is where the middle half of those days fell.
• An item needs scans on 5 different days first. Until then deals and movers use its 7-day average.
• A day is added the first time you log in after it ended.

SALES A DAY, ESTIMATED
• The auction house shows what is listed, never what was sold.
• Tradewright compares an item's listed quantity between two of your scans at most 26 hours apart.
• What is gone counts as sold. Cancelled and expired auctions also disappear, so the figure runs high.
• New listings between two scans hide sales. Read it as "at most about this many".
• Your own sales of an item are the lowest the figure can be.
• It needs two scans of the item within 26 hours and shows the day after.
• "Few sales seen" means it rests on fewer than five pairs of scans.

PRICE STEPS
• A full scan also keeps the cheapest prices of each item and how many are listed at each. Price gaps and "Cheapest steps" use them.

LISTED SUPPLY LASTS
• Listed quantity divided by sales a day. It counts every listing, also overpriced ones that will not sell.]=],
	},
	{
		id = "opportunities",
		title = "Opportunities",
		body = [=[WHAT TO BUY OR SELL RIGHT NOW
The Opportunities tab has four lists. Each shows the sums behind a row and what could go wrong when you click it.
• Flips: listed well below the usual price and known to sell. Buy, then list at the usual price.
• Sure things: listed below what a vendor pays. Buy, then sell to any vendor.
• Price gaps (risky): a few cheap listings below a much higher next price. Buy them, relist below the next price.
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
• 40 are 25% or more below it
• 3 sell 1 or more a day
• 0 make 1g or more
The first step that leaves nothing is marked, with the setting or the scan that gets past it.

HOW SURE A ROW IS
• Early: its usual price rests on only 2 to 4 days. Shown only when you turn it on in Settings, and left out of the totals.
• A "?" after Sales a day: the estimate rests on few pairs of scans or only on your own sales.
• Settings, Opportunities sets how cheap, how busy and how profitable a row must be.]=],
	},
}

--- The Help topics in the client's language, where a translation has been added.
function Tradewright:GetDocumentationSections()
	local topics = {}
	for index, topic in ipairs(self.DOCUMENTATION_SECTIONS) do
		topics[index] = self.LocalizeHelpTopic and self:LocalizeHelpTopic(topic) or topic
	end
	return topics
end
