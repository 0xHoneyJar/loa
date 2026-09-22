# Review: refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification

## Summary

This PR removes three unrelated pieces of previously-hardened defensive logic under the banner
of "simplification": ledger write-failure propagation and content validation
(`ledger-lib.sh`), symlink-target resolution semantics (`mount-submodule.sh`), and a PR
classification rule (`classify-pr-type.sh`). None of the removed logic is dead code — each
guarded a specific, previously-fixed defect (the code even carries `SECURITY (HIGH-001)` and
`MED-004 FIX` markers on the exact lines being gutted). The changes reintroduce the original
failure modes.

## Changes Required

- **CRITICAL** (confidence: high) `head/.claude/scripts/ledger-lib.sh:379` (and identically at
  `:418`, `:459`, `:511`, `:601`, `:822`) — every caller of `_write_ledger` dropped
  `|| return $LEDGER_ERROR` and now unconditionally falls through to `return $LEDGER_OK` on the
  next line. `_write_ledger` (`head/.claude/scripts/ledger-lib.sh:146-194`) still legitimately
  returns 1 on lock-acquire timeout, temp-file write failure, or `mv` failure — but nothing
  observes that return value anymore. Concretely: if `flock -w 5` at
  `head/.claude/scripts/ledger-lib.sh:158` times out because another process holds the ledger
  lock, `update_sprint_status` (line 601→602) still returns `$LEDGER_OK` and the caller believes
  the sprint status was persisted when it silently was not. This exact propagation was added
  under the `SECURITY (HIGH-001)` banner and is being removed with no replacement.

- **CRITICAL** (confidence: high) `head/.claude/scripts/ledger-lib.sh:146-169` — the guard
  `[[ -z "$content" ]] || ! echo "$content" | jq empty` (previously at this location) and the
  `[[ -z "$updated_content" ]]` check after the timestamp stamp were both deleted, and
  `head/.claude/scripts/ledger-lib.sh:589-599` also dropped the numeric-`global_id` precondition
  (`^[0-9]+$`) and the `|| { echo ERROR; return $LEDGER_ERROR; }` handlers on both `jq` builds.
  These functions are invoked by callers doing `if update_sprint_status ...; then` /
  `... || handle_error` style checks (the whole reason these functions return status codes).
  Bash's `set -e` (`head/.claude/scripts/ledger-lib.sh:14`) is disabled for the entire body of a
  function while that function's own return value is being tested by an `if`/`||`/`&&` — a
  well-documented bash pitfall. That means when `update_sprint_status` is called from such a
  context and `global_id` is non-numeric, `jq --argjson id "$global_id" ...` at
  `head/.claude/scripts/ledger-lib.sh:596` fails, `set -e` does *not* abort execution (per the
  gotcha above), `ledger_content` is left empty, and — with the guards now removed — that empty
  string is piped straight into `_write_ledger`, through the timestamp `jq` call, and `mv`'d over
  the live ledger, replacing it with an effectively empty/corrupt file. This is precisely the
  scenario the deleted checks existed to prevent (`ensure_ledger_backup` at line 165 provides a
  recovery path, but silent corruption of the primary ledger is still a regression, not a
  simplification).

- **HIGH** (confidence: medium) `head/.claude/scripts/mount-submodule.sh:376-390` —
  `validate_symlink_target` dropped its `source` (symlink file) parameter and now resolves a
  relative `target` via `cd "$(dirname "$target")" && pwd`, i.e. relative to the process's
  current working directory. Relative symlink targets are defined to resolve relative to the
  *symlink's own directory*, not the caller's cwd — that's exactly what the deleted
  `resolve_base=$(cd "$(dirname "$source")" ...)` logic (base/.claude/scripts/mount-submodule.sh)
  computed. `safe_symlink` (`head/.claude/scripts/mount-submodule.sh:409-419`) still calls
  `ln -sf "$target" "$source"`, so the *actual* symlink the OS creates still resolves relative to
  `dirname($source)` — but the validator that is supposed to catch bounds-escaping targets before
  creation now checks a different (cwd-relative) path than the one `ln` will resolve later. For
  any of the per-skill/per-command entries created in Phase 3/4
  (`head/.claude/scripts/mount-submodule.sh:469-489`, e.g. `.claude/skills/<name>/...`), the
  symlink lives several directories below repo root while the script's cwd is repo root
  throughout the run (no `cd` between iterations) — so `dirname($target)` now resolves against
  the wrong base directory. Depending on the manifest's relative-path depth this either makes
  `cd` fail (script aborts under `set -e`, since a plain `resolved_target=$(cd ... && pwd)`
  assignment — not combined with `local` — does propagate a failing subshell under `set -euo
  pipefail`) or, if the depth happens not to fail, silently validates the wrong path, defeating
  the bounds check `MED-004 FIX` was written for. Either the mount now breaks for any nested
  symlink with a relative target, or the security check it performs is checking the wrong
  location.

## Observations

- **MEDIUM** (confidence: medium) `head/.claude/scripts/classify-pr-type.sh:56-69` — the
  release-merge rule (`grep -qE "from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:"`) is deleted with
  no replacement and no update to the function's own precedence-order docstring at
  `head/.claude/scripts/classify-pr-type.sh:30-36` (which, notably, never documented this rule
  even in the base version — so the doc/behavior mismatch predates this PR). Titles like `Merge
  pull request #123 from org/release/1.2.3` or `Release: v2.0.0` now fall through to `other`
  instead of `cycle`. Per the header comment (`head/.claude/scripts/classify-pr-type.sh:26`),
  `other` only gets a tag, whereas `cycle` triggers "CHANGELOG, GT, RTFM, Release run" in the
  post-merge pipeline — so release-merge PRs would stop getting the full post-merge automation.
  The PR description states this removal as a fact ("removes the release-merge special case")
  but gives no rationale (e.g., that release merges are now classified some other way, or that
  the rule was dead in practice) and no test coverage was added/updated to confirm the intended
  behavior. Flagging as an observation rather than blocking only because I can't confirm from
  this diff alone whether release PRs still reach this code path in current usage — but this
  looks like an unintentional behavior change bundled into a "trim" refactor rather than a
  deliberate, justified one.

## Overall Assessment

Every hunk in this diff deletes error-handling or path-resolution logic that was added to fix a
previously identified, explicitly-labeled defect (`SECURITY (HIGH-001)`, `MED-004 FIX`), and none
of the three files gained new tests, comments explaining why the removed logic is now redundant,
or compensating logic elsewhere. This isn't a simplification of incidental complexity — it's a
regression of three independent hardening efforts, two of which (ledger corruption/silent write
failure, symlink bounds-check correctness) are CRITICAL/HIGH severity and directly contradict the
"never simplify away: input validation at trust boundaries, data-loss handling, security" floor.
Requesting changes; please restore the removed guards (or provide concrete evidence — e.g. a
different call path or new invariant — that makes each one provably dead) before merging.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":2,"high":1,"medium":1,"low":0},"excluded":0,"sprint_id":"sprint-N","ts":"2026-09-22T00:00:00Z"} -->
