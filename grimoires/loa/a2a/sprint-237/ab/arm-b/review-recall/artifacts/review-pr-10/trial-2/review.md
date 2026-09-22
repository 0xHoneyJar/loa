All good

Sprint reviewed and approved. The fix correctly addresses bug-725 (ajv-cli@5+ dropping `--version` support) and is well-tested.

## Verification

**Root cause / fix correctness** — `head/.claude/scripts/loa-doctor.sh:215-221` calls the new `_loa_probe_ajv_version` helper instead of the old `ajv --version 2>&1 | head -1 || echo "unknown"` one-liner, which used to capture ajv-cli@5+'s usage-error stderr text as if it were a version string. The new helper (`head/.claude/scripts/loa-doctor.sh:228-261`):

- Tries `ajv --version 2>/dev/null` first and validates the output against `^[0-9]+\.[0-9]+` (`head/.claude/scripts/loa-doctor.sh:245`) before trusting it — this is what prevents the original defect (stderr usage-errors no longer masquerade as a version, since they're both discarded via `2>/dev/null` and would fail the regex check even if leaked through).
- Falls back to parsing `ajv --help` for a `version X.Y.Z` line (`head/.claude/scripts/loa-doctor.sh:249-256`), which matches how ajv-cli@5+ actually reports its version per the bundled bats fixtures.
- Falls back to a labeled placeholder `"unknown (ajv-cli@5+)"` (`head/.claude/scripts/loa-doctor.sh:257-259`) rather than a bare "unknown", which is more actionable in doctor output.

**`set -e`/`pipefail` safety** — the production script runs under `set -euo pipefail` (`head/.claude/scripts/loa-doctor.sh:33`), and `check_optional_tools` (which calls this helper) is invoked directly from the top-level dispatch loop (`head/.claude/scripts/loa-doctor.sh:725`), so an unguarded failing pipe really would abort the whole health check. I traced the fallback pipe by hand: `head_text=$(ajv --help 2>&1 || true)` (`head/.claude/scripts/loa-doctor.sh:252`) neutralizes a nonzero `ajv --help` exit, and the `grep -oE ... | head -1 | awk ... || true` chain (`head/.claude/scripts/loa-doctor.sh:253-256`) neutralizes `grep`'s exit-1-on-no-match, which `pipefail` would otherwise propagate as the whole pipeline's status and trip `errexit` on the assignment before the placeholder could be set. Both guards are load-bearing, not defensive noise, and bats tests bug-725-9/-10 (`head/tests/unit/bug-725-ajv-version-probe.bats:224-263`) exercise exactly this path with `set -eo pipefail` active.

**Test quality** — `head/tests/unit/bug-725-ajv-version-probe.bats` extracts and runs the *actual* `_loa_probe_ajv_version` function out of the production script via `awk` (`head/tests/unit/bug-725-ajv-version-probe.bats:100-115`) rather than re-implementing the logic in the test, so the tests validate the real code path. Coverage includes the v4 happy path, the v5+ `--help`-parse path, the no-version-found placeholder path, a missing-binary control, and two dedicated pipefail-abort regression tests, plus source-level anti-regression checks that the old buggy one-liner doesn't reappear on a live code line (comment mentions of the old pattern are correctly excluded via the `^[[:space:]]*#` filter in `head/tests/unit/bug-725-ajv-version-probe.bats:270-272`).

## Observations

- **LOW** `head/.claude/scripts/loa-doctor.sh:254` — the `--help` regex `version [0-9]+\.[0-9]+(\.[0-9]+)?` has no support for pre-release/build metadata (e.g. `5.6.0-beta.1`); such a string would still be captured up through the numeric patch component by the regex engine's partial match, so this is cosmetic at worst, not a functional break.
- **LOW** `head/.claude/scripts/loa-doctor.sh:245` — the v4 probe now uses `2>/dev/null` instead of the old `2>&1`, so a hypothetical ajv build that writes its version to stderr on success would silently fall through to the `--help` parse instead of being read directly. No evidence this occurs in any real ajv-cli release; flagging only as a theoretical behavior change from the prior (buggy) code's stream-merging.
- **LOW** `head/.claude/scripts/loa-doctor.sh:243` — `local ajv_ver=""` is immediately shadowed by the reassignment in the `if` condition at line 245; harmless, but the initial empty assignment is unused before being overwritten.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"sprint_id":"pr-10","ts":"2026-09-22T00:00:00Z"} -->
