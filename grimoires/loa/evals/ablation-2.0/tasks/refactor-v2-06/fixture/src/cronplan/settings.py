# knobs shared by the parser and the scheduler
FIELD_NAMES = ["minute", "hour", "day-of-month", "month", "day-of-week"]
BOUNDS = {
    "minute": (0, 59),
    "hour": (0, 23),
    "day-of-month": (1, 31),
    "month": (1, 12),
    "day-of-week": (0, 7),
}
horizon_years = 5
max_count = 1000
debug = False
