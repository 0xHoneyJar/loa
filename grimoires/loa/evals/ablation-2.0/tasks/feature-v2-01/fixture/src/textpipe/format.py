"""Formatting the filter listing."""


def listing(filters):
    """One line per filter: the name in a column as wide as the longest, two spaces, the description."""
    width = max(len(flt.name) for flt in filters)
    return [f"{flt.name.ljust(width)}  {flt.description}" for flt in filters]
