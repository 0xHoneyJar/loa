# shared settings for the whole package
DEFAULTS = {
    "max_length": 256,
    "max_range_length": 1024,
    "include_prerelease": False,
}

# the wildcard spellings accepted inside ranges
WILDCARDS = ["x", "X", "*"]

# operator spellings, longest first so that ">=" wins over ">"
OPERATORS = [">=", "<=", "~>", ">", "<", "=", "^", "~"]


def get(key):
    return DEFAULTS[key]
