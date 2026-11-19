# E05 — Paging in the shared table

## Summary

Long lists are no longer cut off. The shared table shows one page at a time and its footer carries Prev, "Page N of M" and Next, so every row of Market, Inventory, Crafts and the auction house side-panel can be reached.

## Context

- Every list in the addon is drawn by one widget, `CreateReusableTable` (`AuctionHelper_Table.lua`).
- A table created with `maxRows` showed only its first `maxRows` rows and wrote "Showing 450 of 2,329" in its footer. The rest could only be reached by searching or filtering.
- Tables that set `maxRows` today, all with a footer: Market (500), Inventory (550), Crafts (450), and the auction house side-panel's Sell and Cart (120) and Auctions (200) lists.
- Rows are sorted once per change of rows or sort column (`GetSortedRows`), so a page is a slice of an already sorted list.

## Scope

- `ForeverLogic.PageBounds(count, pageSize, page)`: clamps the page and returns page, page count and the first and last row index on it
- `AuctionHelper_Table.lua`:
  - `maxRows` becomes the page size; `RefreshRows` shows the current page's slice of the sorted rows
  - `SetPage(page)` to move between pages
  - a pager in the footer (Prev, "Page N of M", Next), shown only when there is more than one page; the caller's right-hand footer text moves left of it
  - the footer's left text reads "Showing A-B of N" while paged and keeps its full width; the caller's text is cut short first when the table is narrow
  - `SetRows` updates the footer, because some callers set their footer text before the rows
- No change in the tabs themselves: they already hand all their rows to the table

## Acceptance criteria

- [x] A table with `maxRows` and a footer shows `maxRows` rows per page; Prev and Next move between pages; the footer reads "Showing A-B of N" and "Page P of M"
- [x] With everything on one page the pager is hidden and the caller's own footer text is shown
- [x] Sorting applies to the whole list and returns to page 1
- [x] Changing page scrolls back to the top
- [x] When a search or filter leaves fewer pages, the current page is clamped to the last one; a refresh with the same rows keeps the page
- [x] A table with `maxRows` but no footer still shows only the first `maxRows` rows and does not error
- [x] Tables without `maxRows` behave as before
- [x] Offline tests cover the paging maths: first, middle, short last page, clamping above and below, exact multiple, single page, no page size

## Verification

```bash
npm test
```

In-game: Market with more than 500 items → footer shows the pager → Next shows rows 501 onward → click a column header → back on page 1 with the whole list sorted → type a search that leaves under 500 rows → the pager disappears.

## Dependencies

- None

## Out of scope

- Choosing the page size in Settings
- Jumping straight to a page number
- Returning to page 1 on every search or filter change (the page is only clamped)
- Keyboard or mouse-wheel paging
- Queueing the Crafts tab's price refresh for the rows of a newly opened page. It is queued on scroll, so a page change (like a sort) at the top of the list waits for the next scroll or tab refresh
