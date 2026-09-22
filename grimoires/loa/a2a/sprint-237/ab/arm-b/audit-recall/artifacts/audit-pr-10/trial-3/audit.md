# Security Audit — fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe

## Scope

Single-commit PR touching two files, both inside this repository's own framework
tooling (this is the Loa framework repo itself, not a consumer project, so
`.claude/scripts/loa-doctor.sh` is in-repo framework source under active
development — not a System Zone boundary violation by an external consumer):

- `head/.claude/scripts/loa-doctor.sh` — extracts a new `_loa_probe_ajv_version()`
  helper and calls it from `check_optional_tools()`.
- `head/tests/unit/bug-725-ajv-version-probe.bats` — new bats coverage (10 tests).

No PRD/SDD/sprint-plan/beads artifacts exist for this change (per audit
instructions, expected for this evaluation harness). `loa-doctor.sh` is a
read-only diagnostic script (per its own header comment, `head/.claude/scripts/loa-doctor.sh:5`:
"Design: Read-only checks, educational output, no mutations"); it reads local
tool versions and renders a report. There is no network, no untrusted remote
input, and no privilege boundary crossed by this code path.

## Grounded review

**`head/.claude/scripts/loa-doctor.sh:228-261`** — the new `_loa_probe_ajv_version` function.

- `head/.claude/scripts/loa-doctor.sh:245`: `if ajv_ver=$(ajv --version 2>/dev/null) && [[ "$ajv_ver" =~ ^[0-9]+\.[0-9]+ ]]; then` —
  command substitution inside an `if` condition is exempt from `set -e`
  (`head/.claude/scripts/loa-doctor.sh:33` has `set -euo pipefail` active for the whole
  script), so a non-zero exit from `ajv --version` (the v5+ case) does not abort
  the script. Correct.
- `head/.claude/scripts/loa-doctor.sh:252`: `help_text=$(ajv --help 2>&1 || true)` —
  guards the `--help` invocation itself against non-zero exit under `set -e`.
  Correct, and covered by test `bug-725-10` (`head/tests/unit/bug-725-ajv-version-probe.bats:248-263`),
  which stubs `ajv --help` to exit 2.
- `head/.claude/scripts/loa-doctor.sh:253-256`: the `grep -oE ... | head -1 | awk ... || true`
  pipeline is the one place `pipefail` (also set at `head/.claude/scripts/loa-doctor.sh:33`)
  could bite — `grep` returns 1 on no match, which `pipefail` would propagate as
  the whole pipeline's exit status, which `set -e` would then treat as a
  command failure and abort the script. The trailing `|| true` sits **outside**
  the pipe but **inside** the `$(...)` substitution, so it correctly absorbs
  that failure before assignment. This is exactly the BB #916 "F1" defect
  class the PR's own comments describe, and it is handled correctly here.
  Verified by test `bug-725-9` (`head/tests/unit/bug-725-ajv-version-probe.bats:224-246`),
  which stubs `--help` with no matching "version X.Y.Z" line under
  `set -eo pipefail` and asserts the function returns cleanly.
- The resulting `$ajv_ver` (whether from `--version`, `--help` parse, or the
  literal placeholder) is only ever used as a display string. It reaches
  `_doctor_add_check` (`head/.claude/scripts/loa-doctor.sh:217-218`) as a quoted
  positional argument, and downstream JSON rendering builds each entry with
  `jq -nc --arg ... --arg version "$version" ...` (`head/.claude/scripts/loa-doctor.sh:639-642`),
  which JSON-escapes the value correctly. There is no `eval`, no unquoted
  interpolation into a shell command, and no path where this string is
  re-executed. A malicious or malformed `ajv --help` output (e.g. an attacker
  who can already write an `ajv` binary earlier on `$PATH` — a pre-existing,
  unchanged trust model shared by every other tool probe in this file: `git`,
  `jq`, `yq`, `br`, `sqlite3`) can at worst cause a garbled display string, not
  code execution or injection into the JSON/text report.
- `command -v ajv &>/dev/null` (`head/.claude/scripts/loa-doctor.sh:215`, unchanged)
  gates the whole probe on the tool actually resolving on `PATH`; this mirrors
  the existing pattern for every other optional-tool check in the file, so no
  new trust boundary is introduced.

**`head/tests/unit/bug-725-ajv-version-probe.bats`** — test coverage.

- `head/tests/unit/bug-725-ajv-version-probe.bats:100-115` (`_run_probe`) builds a
  `bash -c "..."` string that interpolates `$stub_path` and `$PROJECT_ROOT`
  directly into a double-quoted string rather than passing them as positional
  arguments to `bash -c script -- "$arg"`. Both values are test-harness
  controlled (`mktemp -d "${BATS_TMPDIR}/bug-725.XXXXXX"` at
  `head/tests/unit/bug-725-ajv-version-probe.bats:84`, and the script's own
  resolved directory at `head/tests/unit/bug-725-ajv-version-probe.bats:80-81`),
  not attacker-influenced, so this is not exploitable in practice — flagging
  only as a low-severity robustness/style note, not a vulnerability.
- Test extraction of the function via `awk '/^_loa_probe_ajv_version\(\)/,/^}/'`
  (`head/tests/unit/bug-725-ajv-version-probe.bats:107`) is fragile (breaks if the
  function body ever contains a brace at column 0, e.g. a nested here-doc), but
  it is test-only tooling exercising the real production function body rather
  than a hand-written replica, which is a genuine improvement over duplicating
  logic in the test file, and the current function body has no such line.
- The anti-regression tests (`bug-725-5` through `bug-725-8-source`,
  `head/tests/unit/bug-725-ajv-version-probe.bats:208-278`) pin the presence of the
  fix and the absence of the old buggy one-liner, and are a reasonable defense
  against silent regression.

## What I did not find

- No command injection, no `eval` of untrusted data, no path traversal, no
  secret handling, no privilege escalation, no change to authentication/
  authorization logic, no change to any network-facing code, no change to
  file-write behavior (the script remains read-only as designed).
- No change to the JSON/text output schema beyond the value of one optional
  field (`ajv` version string), and that field's rendering path is unchanged
  and already safe (`jq --arg`).

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 1 |

Low: test-harness string interpolation into `bash -c` in
`head/tests/unit/bug-725-ajv-version-probe.bats:102` (style/robustness only, not
exploitable — both interpolated values are test-controlled).

## Verdict

APPROVED - LET'S FUCKING GO

The change is a narrow, well-scoped bug fix confined to a local, read-only
diagnostic script. The `set -e`/`pipefail` interaction that motivated the
extra tier of fallback (BB #916 F1) is handled correctly and is verified by
dedicated tests exercising the real production code path under the same
strict-mode flags the production script runs under. No new trust boundary,
injection surface, or data-handling risk is introduced.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"ts":"2026-09-22T00:00:00Z"} -->
