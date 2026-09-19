def dedupe(records, key):
    """Drop records whose key(record) was already seen; keep input order."""
    seen = {}
    for record in records:
        seen[key(record)] = record
    return list(seen.values())
