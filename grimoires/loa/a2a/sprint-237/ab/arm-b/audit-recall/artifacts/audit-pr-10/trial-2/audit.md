# Security Audit — fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe

## Scope

Codebase audit of a single PR against the Loa framework repository. Input: `PR.md`, `head.diff`,
`base/`, `head/` (no sprint plan, beads database, or `grimoires/loa/a2a/` artifacts present — per
`AUDIT-INSTRUCTIONS.md` these pre-flight steps are skipped).

Files touched:
- `head/.claude/scripts/loa-doctor.sh` — replaces a single-line `ajv --version | head -1` probe
  with a new `_loa_probe_ajv_version()` helper (three-tier fallback: `--version` → `--help` parse
  → placeholder).
- `head/tests/unit/bug-725-ajv-version-probe.bats` — new bats test file (217 lines) covering the
  new helper.

`loa-doctor.sh` is a **read-only diagnostic** tool (per its own header comment, `head/.claude/scripts/loa-doctor.sh:6`: "Design: Read-only checks, educational output, no mutations"). It runs local
health checks and prints results; it does not process untrusted network input, does not run with
elevated privileges, and does not persist or transmit its output anywhere by default.

## Analysis

### Data flow into `_loa_probe_ajv_version()`

- `head/.claude/scripts/loa-doctor.sh:245` — `ajv_ver=$(ajv --version 2>/dev/null)`: stdout only
  (stderr discarded), gated by a regex anchor (`^[0-9]+\.[0-9]+`) before use. Malformed or hostile
  output that doesn't match the version shape falls through to the next tier rather than being
  trusted.
- `head/.claude/scripts/loa-doctor.sh:252-256` — `help_text=$(ajv --help 2>&1 || true)` then piped
  through `grep -oE 'version [0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | awk '{print $2}'`. The
  extracted value is a tightly-anchored numeric substring, not the raw help text — this is what
  fixes the original bug (bug-725: previously `ajv --version 2>&1 | head -1` captured the raw
  usage-error text from ajv-cli v5+'s stderr and displayed it verbatim as the "version").
- The resulting `$ajv_ver` is passed to `_doctor_add_check` (`head/.claude/scripts/loa-doctor.sh:218`)
  and stored in a plain bash array (`_doctor_add_check` at `head/.claude/scripts/loa-doctor.sh:122-129`,
  unchanged by this PR). It is never `eval`'d.

### Output rendering — checked for injection, not just presence of a fix

- Text renderer (`head/.claude/scripts/loa-doctor.sh:489`): `local version="${_DOCTOR_CHECK_VERSIONS[$i]}"`,
  printed as a plain variable — no `eval`, no unescaped interpolation into a shell command.
- JSON renderer (`head/.claude/scripts/loa-doctor.sh:634-642`): uses `jq -nc --arg v "$version" ...`,
  i.e. `jq --arg`, which correctly escapes the value for JSON — this path is untouched by the PR and
  remains safe.

So even in the pre-fix code, a hostile `ajv` binary's output could not have achieved command
injection or JSON injection through this field — the original bug was purely a *display*/misreporting
defect (wrong string shown to the user), not a security vulnerability. This PR does not change that
risk profile; it only tightens what is accepted as a "version" via regex validation, which is a net
improvement (rejects unrecognized shapes instead of echoing them).

### Trust boundary: PATH-resolved `ajv` binary

`command -v ajv` / invoking `ajv` resolves through `$PATH` (`head/.claude/scripts/loa-doctor.sh:215-217`,
`228` region). A malicious binary named `ajv` earlier in `$PATH` could execute arbitrary code when
this script runs — but this is a pre-existing pattern shared by every other optional-tool check in
the same function (`br` at `head/.claude/scripts/loa-doctor.sh:197-199`, `sqlite3` at
`head/.claude/scripts/loa-doctor.sh:206-208`, and hard dependencies `git`/`jq` elsewhere in the file).
This PR does not introduce a new trust-boundary crossing; it is out of scope as a PR-specific finding.

### `set -e` / `pipefail` interaction

The file sets `set -euo pipefail` at `head/.claude/scripts/loa-doctor.sh:33`. The new helper is
correctly guarded against this:
- `ajv_ver=$(ajv --version 2>/dev/null) && [[ ... ]]` (`head/.claude/scripts/loa-doctor.sh:245`) —
  the `&&` means a non-zero `ajv --version` exit is caught by the `if`, not propagated by `set -e`
  (command substitution exit status feeding a conditional is exempt from errexit by POSIX rule).
- `help_text=$(ajv --help 2>&1 || true)` (`head/.claude/scripts/loa-doctor.sh:252`) — explicit guard.
- The `grep | head | awk || true` pipe (`head/.claude/scripts/loa-doctor.sh:253-256`) — the `|| true`
  attaches to the whole pipeline (a single compound command), so a `grep` no-match (exit 1,
  propagated by `pipefail`) does not abort the script before the placeholder assignment. Verified
  independently by test `bug-725-9` and `bug-725-10` in
  `head/tests/unit/bug-725-ajv-version-probe.bats:224-263`, which exercise exactly this path under
  `set -eo pipefail`.

This matches the PR's own stated rationale (BB #916 F1) and is correctly implemented — no
availability/DoS regression (a doctor script that unexpectedly aborts mid-run would itself be a
minor quality/availability issue, and the tests specifically pin against it).

### Test file (`head/tests/unit/bug-725-ajv-version-probe.bats`)

- Uses hermetic stub binaries under a `mktemp -d` directory placed first on `$PATH`
  (`head/tests/unit/bug-725-ajv-version-probe.bats:79-89`, `100-102`) — no real `ajv` invoked, no
  network access, no interaction with the real project state. Test-only code, appropriately scoped.
- The function-extraction technique (`awk '/^_loa_probe_ajv_version\(\)/,/^}/'` at
  `head/tests/unit/bug-725-ajv-version-probe.bats:107`) interpolates `$PROJECT_ROOT` into a
  `bash -c "..."` string. `PROJECT_ROOT` is derived deterministically from `$BATS_TEST_FILENAME`
  (`head/tests/unit/bug-725-ajv-version-probe.bats:80-82`), not from untrusted input, so this is not
  an injection vector in practice — flagged only as an observation, not a finding, since a future
  change to how `PROJECT_ROOT` is populated could reintroduce risk if it ever became attacker
  influenced.
- Anti-regression tests (`bug-725-8-source` at `head/tests/unit/bug-725-ajv-version-probe.bats:265-278`)
  correctly filter out comment lines before asserting the legacy vulnerable pattern is gone, avoiding
  a false pass/fail from the explanatory comments earlier in the same diff.

## Coverage note

No CRITICAL, HIGH, or MEDIUM findings. No LOW findings either — the change is a narrowly scoped,
well-tested bugfix to a read-only diagnostic tool's output-formatting logic, with no new trust
boundary, no injection path (command or JSON), and correct `errexit`/`pipefail` handling verified by
dedicated tests. The two items above (PATH-resolved binary trust, test extraction string
interpolation) are recorded under Observations because they are pre-existing patterns / not
attacker-influenced in this diff, not defects introduced by this PR.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

## Observations

- `head/.claude/scripts/loa-doctor.sh:215-217` / `228`: `ajv` is resolved via `$PATH`, same as the
  pre-existing `br`/`sqlite3`/`git`/`jq` checks in this file. Not a new risk introduced by this PR;
  noted for completeness of the trust-boundary review.
- `head/tests/unit/bug-725-ajv-version-probe.bats:107`: test harness interpolates `$PROJECT_ROOT`
  into a `bash -c` string for function extraction. Currently safe because the value is
  deterministically derived from the bats runner, not external input — worth keeping in mind if the
  test harness is ever generalized.

## Verdict

APPROVED - LET'S FUCKING GO

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"ts":"2026-09-22T00:00:00Z"} -->
