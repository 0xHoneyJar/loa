def paginate(items, page: int, size: int) -> list:
    """Return page `page` (1-based) of `items`, `size` items per page."""
    if page < 1 or size < 1:
        raise ValueError("page and size must be >= 1")
    start = page * size - size + 1
    return list(items[start:start + size])
