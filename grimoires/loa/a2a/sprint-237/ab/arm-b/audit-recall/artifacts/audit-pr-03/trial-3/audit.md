# Security Audit — refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification

**Scope**: `head.diff` touching `.claude/scripts/ledger-lib.sh`, `.claude/scripts/mount-submodule.sh`, `.claude/scripts/classify-pr-type.sh`. No sprint plan, beads database, or `grimoires/loa/a2a/` context exists for this evaluation; audited directly from PR description + diff + full before/after file contents.

## Summary

The PR frames itself as trimming redundant checks, but two of the three "simplifications" delete security-load-bearing logic. The ledger-lib.sh change removes the last guard against writing empty/invalid content to the single source of truth for cycle/sprint state, and simultaneously removes every caller's checking of `_write_ledger`'s return code — so a write that fails (lock timeout, disk error, or the now-unguarded empty-content case) is reported to the caller as success. The mount-submodule.sh change silently reverts the documented "MED-004" symlink-escape fix by dropping the parameter that anchors relative-target resolution to the symlink's own directory, while leaving the `MED-004 FIX` comment header in place as if the fix were still intact. The classify-pr-type.sh change is a narrower governance/audit-trail regression.

## Findings

### CRITICAL-001: Silent ledger corruption via removed empty/invalid-JSON guard + removed caller error propagation

**Location**: `head/.claude/scripts/ledger-lib.sh:146-194` (`_write_ledger`), and every call site that dropped its `||` guard: `head/.claude/scripts/ledger-lib.sh:379`, `:418`, `:459`, `:511`, `:601`, `:822`.

**What changed**: The base version of `_write_ledger` refused to proceed when `content` was empty or failed `jq empty` validation, and separately aborted if timestamp-stamping (`jq --arg ts ... '.last_updated = $ts'`) produced empty output:

```bash
if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
    echo "ERROR: refusing to write empty or unparseable ledger content" >&2
    return $LEDGER_ERROR
fi
...
if [[ -z "$updated_content" ]]; then
    echo "ERROR: timestamp stamping produced empty content, aborting write" >&2
    ...
    return $LEDGER_ERROR
fi
```

Both guards are deleted in this PR. `head/.claude/scripts/ledger-lib.sh:146-194` now goes straight from computing `content` to `mkdir -p`, `flock`, and `mv "$tmp_file" "$ledger_path"` with no content validation at any point.

At the same time, every caller in this file that previously propagated a write failure now discards it, e.g. `head/.claude/scripts/ledger-lib.sh:601`:

```bash
_write_ledger "$ledger_content"
return $LEDGER_OK
```

(base was `_write_ledger "$ledger_content" || return $LEDGER_ERROR`). The same pattern repeats at `head/.claude/scripts/ledger-lib.sh:379` (`create_cycle`), `:418` (`update_cycle_field`... type function), `:459` (sprint-number increment), `:511` (`add_sprint`), and `:822` (`archive_cycle`).

**Failure scenario**: `update_sprint_status` (`head/.claude/scripts/ledger-lib.sh:576-602`) also had its input-validation guard removed in this same PR (see LOW-001 below): `global_id` is passed unchecked into `jq --argjson id "$global_id" ...` at `head/.claude/scripts/ledger-lib.sh:592` / `:596`. If `global_id` is not valid JSON (e.g. an empty string, a non-numeric label, or any value from an upstream parsing bug), `jq --argjson` fails, prints its error to stderr, and produces **no stdout** — so `ledger_content=$(jq ...)` becomes `""`. That empty string is passed straight into `_write_ledger` at `head/.claude/scripts/ledger-lib.sh:601`, which — with the guard removed — writes it out atomically as the new `ledger.json`, and returns success. `update_sprint_status` then returns `$LEDGER_OK` regardless (the `||` propagation is also gone), so nothing downstream ever learns the ledger was just wiped.

The same collapse happens for any of the other five call sites if the `jq` filter they run ever fails for any reason (malformed existing ledger, a future refactor that changes a field name, disk-full during a subshell, etc.) — previously that surfaced as `LEDGER_ERROR` and a stderr message; now it silently truncates the ledger to an empty/near-empty file and reports success. This is exactly the "output-swallowing produces silent data loss that looks like success" hazard the repository's own `.claude/rules/stash-safety.md` was written to warn about (issue #555) — reproduced here in a different subsystem instead of git stash.

**Impact**: `ledger.json` is the durable record of cycle/sprint lifecycle state that gates (`/run` recovery, sprint status, circuit breaker) read to decide what state the system is in. Silent, unsignaled destruction of that file lets a transient or attacker-influenced input error erase audit history and cycle/sprint tracking with no error surfaced to the operator or to any calling automation — violates CWE-460 (Improper Cleanup on failure path masking) and functionally CWE-703 (Improper Check for Unusual Conditions), with a resulting integrity/availability impact on the framework's own state-tracking control (relevant standard: https://cwe.mitre.org/data/definitions/703.html).

**Remediation**: Restore both guards in `_write_ledger`, and restore `|| return $LEDGER_ERROR` (or equivalent) at every call site that was changed in this diff.

---

### HIGH-001: Symlink-escape validation silently reverted (MED-004 regression)

**Location**: `head/.claude/scripts/mount-submodule.sh:370-405` (`validate_symlink_target`), called from `safe_symlink` at `head/.claude/scripts/mount-submodule.sh:414`.

**What changed**: The base version accepted a second argument, `source` — the path of the symlink itself — and used it to compute `resolve_base`, the directory a *relative* `target` must be resolved against:

```bash
local resolve_base=""
if [[ "$target" != /* ]]; then
  if [[ -n "$source" ]]; then
    resolve_base=$(cd "$(dirname "$source")" 2>/dev/null && pwd)
  fi
  ...
```

This PR deletes the `source` parameter entirely and the `resolve_base`/`candidate` computation with it. The head version resolves `target` directly against the process's current working directory via bash's own relative-path handling:

```bash
validate_symlink_target() {
  local target="$1"
  ...
  if [[ -e "$target" ]]; then
    resolved_target=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")
```

`head/.claude/scripts/mount-submodule.sh:414` now calls `validate_symlink_target "$target"` — the `source` argument that `safe_symlink` still receives (`head/.claude/scripts/mount-submodule.sh:410-411`) is no longer forwarded at all.

**Why this matters**: A relative symlink target's real, on-disk resolution is defined relative to the *directory containing the symlink*, not relative to the calling process's cwd. `create_symlinks` (`head/.claude/scripts/mount-submodule.sh:433-495`) calls `safe_symlink` with `link_path` values that live in subdirectories (e.g. `.claude/settings.local.json`) and relative `target` values computed relative to that subdirectory (e.g. `"../$SUBMODULE_PATH/.claude/settings.local.json"` at `head/.claude/scripts/mount-submodule.sh:493`), while `create_symlinks` itself runs with cwd at the repository root. Concretely:

- Real symlink resolution (correct, from `.claude/`): `../$SUBMODULE_PATH/.claude/settings.local.json` relative to `.claude/` → `<repo_root>/$SUBMODULE_PATH/.claude/settings.local.json` — inside the repo.
- `validate_symlink_target` in `head/` resolves the same string relative to cwd (`<repo_root>`) instead → `<repo_root>/../$SUBMODULE_PATH/.claude/settings.local.json` — **one directory above the repo root**, i.e. outside repo bounds by the check's own logic.

The check and the actual filesystem behavior of the symlink it is validating are now looking at two different paths. This is CWE-59 (Improper Link Resolution Before File Access — https://cwe.mitre.org/data/definitions/59.html): the validator's notion of "where does this link point" no longer matches where the link actually points once created, which can go wrong in both directions — legitimate manifest-relative targets can be misjudged as escaping the repo (breaking the mount flow), and more importantly a relative target genuinely crafted to escape the repo when resolved from the symlink's true directory can be evaluated by the validator against the wrong base and pass. The function header comment `# === MED-004 FIX: Symlink Target Validation ===` (`head/.claude/scripts/mount-submodule.sh:359`) is left in place, which will read to future maintainers as "this protection is intact" when the specific mechanism the fix relied on (anchoring resolution to the link's own directory) has been removed.

**Impact**: `mount-submodule.sh` runs with elevated trust (it wires up `.claude/` from a submodule during repo bootstrap); a validation routine whose resolution base no longer matches on-disk symlink semantics undermines the one guardrail this file has against a submodule manifest entry (`lib/symlink-manifest.sh`, sourced at `head/.claude/scripts/mount-submodule.sh:425`) placing a symlink that escapes the repository.

**Remediation**: Restore the `source` parameter and `resolve_base` computation exactly as in `base/.claude/scripts/mount-submodule.sh:370-420`, and continue passing `$source` from `safe_symlink` (`head/.claude/scripts/mount-submodule.sh:414`).

---

### MEDIUM-001: Release-merge PRs silently drop out of the "cycle" classification, skipping the full post-merge pipeline

**Location**: `head/.claude/scripts/classify-pr-type.sh:42-72` (`classify_pr_type`).

**What changed**: The base version classified titles matching `from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:` as `"cycle"` before falling through to the `^fix` bugfix check. This PR deletes that branch entirely. A PR titled e.g. `Release: v1.2.0` or `Merge pull request #123 from org/release/1.2.0` (which previously matched the removed regex) will now fall through to `"other"` (since it doesn't start with `fix` and has no `cycle-NNN` token or `cycle` label).

**Impact**: Per this file's own header comment (`head/.claude/scripts/classify-pr-type.sh:26-27`), `"cycle"` classification is what triggers the full pipeline (CHANGELOG, GT, RTFM, Release run) in both consumers of this classifier (`.github/workflows/post-merge.yml` and `.claude/scripts/post-merge-orchestrator.sh`, per the file's own docblock at lines 7-9 — not in this PR's diff, so not independently re-verified here, but the classifier's documented contract is unambiguous). A release-merge commit silently downgraded to `"other"` means release merges stop generating the changelog/RTFM/audit-trail artifacts the pipeline exists to produce, without any error or warning — a governance/audit-trail integrity regression (relevant standard: CWE-778, Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html, since the practical effect is the loss of the record-generation step for a release event).

**Remediation**: Restore the removed branch, or provide an equivalent explicit rule for release-merge titles, before removing test coverage for it.

---

### LOW-001: Removed input validation on `global_id` in `update_sprint_status`

**Location**: `head/.claude/scripts/ledger-lib.sh:576-602`.

**What changed**: The base version validated `global_id` was purely numeric before use:

```bash
if [[ ! "$global_id" =~ ^[0-9]+$ ]]; then
    echo "ERROR: update_sprint_status requires a numeric global sprint id (got '$global_id')" >&2
    return $LEDGER_SPRINT_NOT_FOUND
fi
```

This guard, and the `|| { echo "ERROR: failed to build updated ledger content" >&2; return $LEDGER_ERROR; }` wrapped around each `jq --argjson id "$global_id" ...` call, are both removed in the head version (`head/.claude/scripts/ledger-lib.sh:592-597`).

**Failure scenario**: This is the direct trigger condition for CRITICAL-001 above — with the numeric-id guard gone, any non-numeric `global_id` reaching this function (a caller bug, an unresolved lookup that used to be caught earlier, or any future code path that doesn't pre-validate) turns into a `jq --argjson` parse failure, empty `ledger_content`, and — per CRITICAL-001 — a silent ledger wipe reported as success.

**Remediation**: Restore the numeric-id guard at function entry; this is cheap, input-boundary validation for a function whose argument may originate from parsed sprint labels or filenames rather than a value the function itself constructed.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

## Verdict

CHANGES_REQUIRED. This PR's stated intent (trim redundant checks) does not match its effect: it removes the only guard preventing silent ledger corruption on write failure (CRITICAL-001), reverts a previously-fixed, explicitly-labeled symlink-escape vulnerability while leaving the "FIXED" comment in place (HIGH-001), and quietly narrows which PRs get full release-pipeline treatment (MEDIUM-001). None of the removed code was dead or redundant — each removal deletes an input-validation or error-propagation boundary. Recommend reverting all three files to base behavior and, if the goal is genuinely to simplify, doing so by consolidating the guards rather than deleting them.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":1,"low":1},"ts":"2026-09-22T00:00:00Z"} -->
