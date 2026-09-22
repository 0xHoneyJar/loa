All good

This PR has been reviewed and approved. Observations documented and non-blocking. See Observations below.

## Summary

`fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe` replaces the single-line
`ajv --version 2>&1 | head -1 || echo "unknown"` probe in `check_optional_tools()` with a new
`_loa_probe_ajv_version()` helper (`head/.claude/scripts/loa-doctor.sh:228-261`) that:

1. Tries `ajv --version` and accepts it only if the output looks like `X.Y[.Z]`.
2. Falls back to parsing `ajv --help` for a `version X.Y[.Z]` token (ajv-cli 5+ dropped `--version`).
3. Falls back to a labeled placeholder `"unknown (ajv-cli@5+)"`.

`tests/unit/bug-725-ajv-version-probe.bats` adds 10 bats tests exercising the v4 path, the v5
`--help`-parse path, the placeholder path, the missing-tool control, and two anti-regression tests
specifically targeting `set -e`/`pipefail` interaction (BB #916 F1).

## Verification performed

- Read `head/.claude/scripts/loa-doctor.sh:1-40` to confirm the script runs under
  `set -euo pipefail` (`head/.claude/scripts/loa-doctor.sh:33`), which is the exact condition the
  F1 fix (`head/.claude/scripts/loa-doctor.sh:237-241`) claims to guard against.
- Traced both `if` guards (`head/.claude/scripts/loa-doctor.sh:245`, `:252`) and the piped
  assignment (`head/.claude/scripts/loa-doctor.sh:253-256`): the first is a condition of an `if`
  (errexit does not trigger on conditions), and the latter two use `|| true` on the full
  compound command, so a non-zero `ajv --help`/`grep` exit cannot abort the caller under
  `pipefail`. This matches the stated intent and the `bug-725-9`/`bug-725-10` tests.
- Confirmed `_doctor_add_check`'s JSON path (`head/.claude/scripts/loa-doctor.sh:638-644`) escapes
  the version string via `jq --arg`, so a malformed/multi-line version value can't corrupt the
  JSON `--json` output mode.
- Confirmed the diff touches only the probe helper and its test file; base/head diff for
  `check_optional_tools` (`base/.claude/scripts/loa-doctor.sh:214-220` →
  `head/.claude/scripts/loa-doctor.sh:214-221`) is a clean 1:1 call-site swap.
- Spot-checked the bats anti-regression test (`bug-725-8-source`) correctly excludes the
  in-code comment that mentions the legacy pattern by filtering `^[[:space:]]*#` lines before
  asserting absence — it does not false-positive on the doc comment at
  `head/.claude/scripts/loa-doctor.sh:230`.
- `bats` is not installed in this review environment, so the suite could not be executed; the
  above is a manual trace of the bash semantics instead of a live run.

No critical or high-severity issues found.

## Observations

- **LOW** (confidence: medium) `head/.claude/scripts/loa-doctor.sh:245` — the v4 success path
  prints the *entire* captured `ajv --version` output via `printf '%s' "$ajv_ver"`, without the
  `head -1` truncation the old code had. If `ajv --version` ever emits a leading version line
  followed by additional stdout lines (e.g. an update-notifier banner ajv itself doesn't print
  today, but some npm-wrapped CLIs do), the regex only anchors on the *start* of the string
  (`^[0-9]+\.[0-9]+`), so the whole multi-line blob — not just the first line — would be stored
  as the "version" and surfaced in the text/JSON report. Not exploitable with today's real
  `ajv-cli` output (single-line), and not covered by any of the new tests (all stub outputs are
  single-line), so this is a latent robustness gap rather than a live bug. Consider `head -1`-ing
  `ajv_ver` before the regex check for parity with the original code's safety margin.
- **LOW** (confidence: low, speculative) `head/.claude/scripts/loa-doctor.sh:254` — the `--help`
  fallback assumes ajv-cli 5+'s help text contains the literal lowercase token
  `version X.Y[.Z]` (as asserted in the code comment and mirrored by the test stubs). This claim
  could not be verified against the real `ajv-cli` package from this sandbox (no network/npm
  registry access). If the actual v5+ help text differs in wording or capitalization, the
  fallback silently degrades to the `"unknown (ajv-cli@5+)"` placeholder rather than failing —
  which is a safe failure mode, but worth a maintainer double-check against a real `ajv-cli@5+`
  install before merge, since the tests only validate the code against a synthetic stub, not the
  real binary.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":2},"excluded":0,"sprint_id":"pr-10","ts":"2026-09-22T00:00:00Z"} -->
