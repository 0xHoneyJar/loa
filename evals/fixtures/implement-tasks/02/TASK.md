# Task: compound durations

**Feature:** `parse_duration` must also accept compound values with units in descending order, each unit at most once: `"1h30m"` → 5400, `"2h5m30s"` → 7530, `"1m1s"` → 61.
Single-unit input keeps working exactly as today; anything else (`"30m1h"`, `"1h1h"`, `"1x"`, `""`) still raises `ValueError`.

Files: `src/timekit/duration.py` (the change), `tests/test_duration.py` (the tests). Nothing else needs to change.
Run the suite with `python3 -m pytest -q tests`.
