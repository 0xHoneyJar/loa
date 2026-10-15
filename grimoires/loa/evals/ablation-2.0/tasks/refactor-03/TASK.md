# Task: make the planner settings an explicit dependency

`fetchq` (under `src/fetchq/`) plans HTTP fetches: URLs, timeouts and retry back-off. Its settings live in a module-level dict in `fetchq.core`. `configure()` mutates that dict, and every planning function reads it. Two callers with different settings cannot safely share the process, and a test that forgets to reconfigure inherits the previous test's settings.

**Refactor:**
- Replace the dict and `configure()` with a frozen dataclass `Config` in `fetchq.core`. Its fields are `base_url`, `timeout` (default 10.0), `retries` (default 2) and `backoff` (default 0.5). Construction checks the values and raises `ValueError` with the existing messages.
- Every planning function in `fetchq.core` (`build_url`, `backoff_delays`, `should_retry`, `request_plan`) and every batch function in `fetchq.jobs` (`plan_batch`, `simulate`) takes the settings as an explicit first parameter named `config`.
- The public functions `plan` and `replay` build a `Config` from their keyword arguments and pass it down.
- When you are done, no module in the package holds mutable module-level state (`__all__` aside), uses `global`, defines `configure` or refers to the old settings dict.

**Unchanged behaviour:** `plan` and `replay` keep their signatures, results and error messages. The existing suite must stay green without edits. Run it with `python3 -m pytest -q tests`.
