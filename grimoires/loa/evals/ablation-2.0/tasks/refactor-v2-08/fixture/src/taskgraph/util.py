"""Odds and ends."""

calls = {"format": 0}


def format_duration(minutes):
    """Render minutes as 1h30m, 2h or 45m."""
    calls["format"] += 1
    h = minutes // 60
    m = minutes % 60
    if h and m:
        return "%dh%dm" % (h, m)
    if h:
        return "%dh" % h
    return "%dm" % m


def _strip(line):
    return line.split("#", 1)[0].strip()
