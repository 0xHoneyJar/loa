_UNITS = {"s": 1, "m": 60, "h": 3600}


def parse_duration(text: str) -> int:
    """Parse '90s', '5m' or '2h' into seconds. Raises ValueError on anything else."""
    text = text.strip()
    if len(text) < 2 or text[-1] not in _UNITS or not text[:-1].isdigit():
        raise ValueError(f"invalid duration: {text!r}")
    return int(text[:-1]) * _UNITS[text[-1]]
