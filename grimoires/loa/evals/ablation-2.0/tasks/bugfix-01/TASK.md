# Task: the last page of a listing goes missing

`pagekit` (under `src/pagekit/`) does the page arithmetic and draws the pager bar for long listings.

**Bug (observed):**
- A listing of 45 items shown 10 per page reports 4 pages. Asking for page 5 raises `PageError`, although item 45 (index 44) is reported to be on page 5.
- On a 100-item listing (10 pages), the pager bar for page 1 reads `[1] 2 3 4 ... 10`: the run around the current page has four pages, not the default width of five. Page 5 gives `1 ... 3 4 [5] 6 ... 10`.
- The pager bar for an empty listing crashes with `IndexError`.

**Expected:**
- The page count rounds up: 45 items at 10 per page is 5 pages, and page 5 shows items 41-45 (`Showing 41-45 of 45`). An exact multiple (40 items) is still 4 pages. An empty listing is one empty page.
- Every item index maps to a page that exists, and that page's bounds contain the index.
- The pager bar shows a run of exactly `width` consecutive pages around the current page, or every page when the listing is shorter. Page 1 of 10 reads `[1] 2 3 4 5 ... 10`, page 5 reads `1 ... 3 4 [5] 6 7 ... 10`, and an empty listing reads `[1]`. The bar at the end of a listing already looks right (`1 ... 6 7 8 9 [10]`) and must stay that way.

Fix the bug in place and add regression tests of your own. Run the suite with `python3 -m pytest -q tests`.
