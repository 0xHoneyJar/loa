"""Human-readable text for a listing page."""
from .nav import nav_window
from .pages import page_bounds


def summary(total: int, per_page: int, page: int) -> str:
    """``Showing 11-20 of 45`` (1-based, inclusive); ``No items`` when the listing is empty."""
    start, end = page_bounds(total, per_page, page)
    if total == 0:
        return "No items"
    return f"Showing {start + 1}-{end} of {total}"


def pager_bar(total: int, per_page: int, current: int, width: int = 5) -> str:
    """The pager bar as text: ``1 ... 4 [5] 6 ... 10``; the current page in brackets."""
    parts = []
    for p in nav_window(total, per_page, current, width):
        if p is None:
            parts.append("...")
        elif p == current:
            parts.append(f"[{p}]")
        else:
            parts.append(str(p))
    return " ".join(parts)
