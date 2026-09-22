All good

This PR fixes a real regression: `ajv-cli@5+` writes a usage error to stderr and exits non-zero when `--version` is passed, and the old code (`ajv --version 2>&1 | head -1 || echo "unknown"`) captured that stderr text as if it were the version string. The rewritten `_loa_probe_ajv_version()` (`head/.claude/scripts/loa-doctor.sh:228-253`) fixes this correctly.

## AC Verification

There is no sprint plan/acceptance-criteria doc for this bug fix (per the review instructions, this is a standalone PR review). Verifying against the PR description's implicit requirements instead:

- **"Probe both shapes"**: `head/.claude/scripts/loa-doctor.sh:243-245` tries `ajv --version` first and validates the output looks like a version (`^[0-9]+\.[0-9]+`) before trusting it — this is the v4 happy path. `head/.claude/scripts/loa-doctor.sh:249-256` falls back to parsing `ajv --help` for a `version X.Y.Z` token — the v5+ path. `head/.claude/scripts/loa-doctor.sh:257-259` provides a labeled `"unknown (ajv-cli@5+)"` placeholder when neither works. Met.
- **"Pin the behaviour with tests"**: `head/tests/unit/bug-725-ajv-version-probe.bats` exercises the v4 path (test 1), the v5+ `--help`-fallback path (test 2), the placeholder path (test 3), the not-installed control (test 4), and two `set -e`/`pipefail`-interaction regression tests (tests 9–10) that specifically verify the fallback doesn't abort the caller when `grep` finds no match. It also has source-level anti-regression checks (tests 5–8) confirming the legacy buggy one-liner doesn't resurface on a code line. Met — good coverage, including the specific `set -euo pipefail` interaction (the whole script runs under `set -euo pipefail` at `head/.claude/scripts/loa-doctor.sh:33`, so this is not a hypothetical concern).

## Correctness walkthrough

- `head/.claude/scripts/loa-doctor.sh:243` — `ajv_ver=$(ajv --version 2>/dev/null) && [[ "$ajv_ver" =~ ^[0-9]+\.[0-9]+ ]]` sits entirely inside an `if` condition, so under `set -e` a non-zero exit from `ajv --version` does not abort the script — this is standard bash `errexit` exemption for `if`-conditions. Confirmed correct.
- `head/.claude/scripts/loa-doctor.sh:252` — `help_text=$(ajv --help 2>&1 || true)` neutralizes a non-zero exit from `ajv --help` itself (covered by bats test `bug-725-10`).
- `head/.claude/scripts/loa-doctor.sh:253-256` — the `grep -oE ... | head -1 | awk ... || true` pipeline is executed under `pipefail`; when `grep` matches nothing it returns 1, `pipefail` propagates that as the pipeline's status, and the trailing `|| true` absorbs it before assignment. Traced through manually — behaves as documented, and is exercised by bats test `bug-725-9`.
- Ordering: `_loa_probe_ajv_version` is defined at line 228, textually *after* its caller `check_optional_tools` at line 195, but since `main` (line 747, calling `check_optional_tools` via line 725) only runs after the whole file is sourced top-to-bottom, the function is registered before it's ever invoked. Not a bug.
- Downstream consumers of the returned string (`_doctor_add_check`, the text renderer at line ~489, and the `jq --arg` JSON builder at line ~634) all treat the version as an opaque string — the placeholder `"unknown (ajv-cli@5+)"` (with its space and parentheses) round-trips safely through both the array storage and the `jq --arg`-based JSON encoding. No escaping issue.

## Observations

- **LOW** (confidence: low) `head/.claude/scripts/loa-doctor.sh:253` — the `--help` fallback assumes ajv-cli's help text contains the literal lowercase token `version X.Y.Z`; if a future ajv-cli release changes that banner's wording or capitalization, the probe will silently degrade to the `"unknown (ajv-cli@5+)"` placeholder rather than mis-report a bogus version — a safe failure mode, not a functional regression, so this is not blocking.

Observations documented and non-blocking. See Observations below.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"sprint_id":"sprint-N","ts":"2026-09-22T00:00:00Z"} -->
