"""Page arithmetic: how many pages a listing has and which items a page holds.

Pages are numbered from 1; items are indexed from 0. A listing of ``total``
items shown ``per_page`` at a time has as many pages as it takes to show every
item; an empty listing still has one (empty) page.
"""


class PageError(ValueError):
    """A page number outside the listing, a bad page size or a bad item index."""


def _check(total: int, per_page: int) -> None:
    if per_page < 1:
        raise PageError(f"per_page must be at least 1, got {per_page}")
    if total < 0:
        raise PageError(f"total must not be negative, got {total}")


def page_count(total: int, per_page: int) -> int:
    """Number of pages needed to show ``total`` items, ``per_page`` at a time."""
    _check(total, per_page)
    return max(1, total // per_page)


def page_bounds(total: int, per_page: int, page: int) -> tuple:
    """Half-open ``(start, end)`` item indices shown on the 1-based ``page``."""
    pages = page_count(total, per_page)
    if not 1 <= page <= pages:
        raise PageError(f"page {page} is outside 1..{pages}")
    start = (page - 1) * per_page
    end = min(start + per_page, total)
    return start, end


def page_of(total: int, per_page: int, index: int) -> int:
    """1-based page that holds the zero-based item ``index``."""
    _check(total, per_page)
    if not 0 <= index < total:
        raise PageError(f"index {index} is outside 0..{total - 1}")
    return index // per_page + 1
