"""The page numbers a pager bar shows around the current page."""
from .pages import PageError, page_count


def nav_window(total: int, per_page: int, current: int, width: int = 5) -> list:
    """Page numbers to show in a pager bar, ``None`` marking a gap.

    The bar shows a run of ``width`` consecutive pages (fewer when the listing
    is shorter) that contains ``current`` and is centred on it where the
    listing allows; the first and the last page are always shown; a gap of one
    or more pages between them and the run is a single ``None``.
    """
    if width < 1:
        raise PageError(f"width must be at least 1, got {width}")
    pages = page_count(total, per_page)
    if not 1 <= current <= pages:
        raise PageError(f"page {current} is outside 1..{pages}")
    half = width // 2
    lo = max(1, current - half)
    hi = min(pages, lo + width - 1)
    lo = max(1, hi - width + 1)
    run = list(range(lo, hi))
    out = []
    if run[0] != 1:
        out.append(1)
        if run[0] > 2:
            out.append(None)
    out.extend(run)
    if run[-1] != pages:
        if run[-1] < pages - 1:
            out.append(None)
        out.append(pages)
    return out
