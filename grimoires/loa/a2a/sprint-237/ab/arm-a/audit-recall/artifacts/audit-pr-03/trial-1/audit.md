# Security Audit Report

**PR**: refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification
**Scope**: `.claude/scripts/ledger-lib.sh`, `.claude/scripts/mount-submodule.sh`, `.claude/scripts/classify-pr-type.sh`
**Audit type**: Ad-hoc PR audit (no sprint plan / beads / a2a directory present — audited from `PR.md` + `head.diff` + `base/`/`head/` snapshots only)

## Executive Summary

This PR frames itself as a refactor ("trim write-guard checks") but it removes three independent, previously-hardened security/integrity controls, two of which were explicitly labeled as security fixes in the surrounding comments (`MED-004 FIX`, `SECURITY (HIGH-001)`). The `mount-submodule.sh` change breaks the anchor point used to resolve relative symlink targets, causing the repo-escape check to silently no-op (`warn`-and-`return 0`) for exactly the relative-target pattern the script's own manifest uses in production. The `ledger-lib.sh` change removes the guard that refused to persist empty/unparseable JSON *and* removes the caller-side error propagation and input validation that fed it, so a single malformed input can silently truncate the entire cycle/sprint ledger to empty while every caller reports success. The `classify-pr-type.sh` change is a narrower functional regression (release-merge PRs silently downgraded to the minimal pipeline) with no direct exploit path found. Overall risk: **HIGH** — two independently-exploitable regressions of previously-hardened controls.

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 1 |
| Low | 0 |

## High Priority Issues

### HIGH-001: Symlink escape-bounds validation silently disabled by loss of resolution anchor

**Component**: `head/.claude/scripts/mount-submodule.sh:370-419`

**Description**

`validate_symlink_target()` used to take both the target and the `source` (the path of the symlink file itself) so that relative targets could be resolved relative to the *symlink's own directory* — the same base the OS uses when it later dereferences the link:

```
base/.claude/scripts/mount-submodule.sh:370-405 (removed)
  local resolve_base=""
  if [[ "$target" != /* ]]; then
    if [[ -n "$source" ]]; then
      resolve_base=$(cd "$(dirname "$source")" 2>/dev/null && pwd)
    fi
    ...
  candidate="$resolve_base/$target"
```

The PR deletes the `source` parameter and the `resolve_base` computation entirely. The new implementation (`head/.claude/scripts/mount-submodule.sh:370-390`) resolves `$target` directly against the **process's current working directory**:

```
head/.claude/scripts/mount-submodule.sh:376-390
  local resolved_target
  if [[ -e "$target" ]]; then
    resolved_target=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")
  else
    local parent_dir
    parent_dir=$(dirname "$target")
    if [[ -d "$parent_dir" ]]; then
      resolved_target=$(cd "$parent_dir" && pwd)/$(basename "$target")
    else
      # Cannot resolve, allow but warn
      warn "Cannot resolve symlink target: $target"
      return 0
    fi
  fi
```

and `safe_symlink()` now calls it without the source at all (`head/.claude/scripts/mount-submodule.sh:409-419`):

```
safe_symlink() {
  local source="$1"
  local target="$2"
  if ! validate_symlink_target "$target"; then
    return 1
  fi
  ln -sf "$target" "$source"
}
```

**Why this is exploitable, not just cosmetic**

`create_symlinks()` runs with `cwd == repo_root` (it never `cd`s) and calls `safe_symlink` with real, nested targets, e.g. `head/.claude/scripts/mount-submodule.sh:493`:

```
safe_symlink ".claude/settings.local.json" "../$SUBMODULE_PATH/.claude/settings.local.json"
```

The symlink `.claude/settings.local.json` lives in `.claude/`, so at dereference time the OS resolves `../.loa/.claude/settings.local.json` relative to `.claude/`, landing at `repo_root/.loa/.claude/settings.local.json` — correctly inside the repo. But the new `validate_symlink_target` resolves that same string relative to `cwd` (`repo_root`), i.e. it computes `dirname(repo_root)/.loa/.claude` — a path **one level above the repository root**. Since that directory does not exist, execution falls into the `else` branch, `parent_dir` (`dirname` of the miscomputed candidate) also does not exist relative to cwd, and the function hits the `# Cannot resolve, allow but warn` branch and **returns 0 — validation is skipped entirely, with only a warning printed**. The same manifest-driven `../$SUBMODULE_PATH/...` shape is used throughout `create_symlinks()` (`head/.claude/scripts/mount-submodule.sh:449-489`), so this is not an edge case — it is the normal call pattern the function was written to check.

The practical consequence: the exact control introduced under "MED-004 FIX: Symlink Target Validation" (`head/.claude/scripts/mount-submodule.sh:359`) to stop a symlink target from escaping the repository is now bypassed (falls through to an unconditional `return 0`) for the realistic case, and gives false confidence via the "cannot resolve" warning rather than failing closed. Any code path that can influence the manifest's target strings (e.g. a compromised `.loa` submodule ref supplying a crafted `lib/symlink-manifest.sh`, or a future manifest entry with a deeper relative target) can point a live repo symlink at an arbitrary out-of-repo path (e.g. `../../../../home/*/.ssh`) without the escape check ever performing a real comparison against `repo_root`.

**Impact**: Loss of a defense-in-depth control against symlink-based path traversal/escape during Loa framework installation, specifically for the class of inputs (relative targets, source path not equal to cwd) the function exists to check. Fails open (`return 0`) rather than closed.

**Remediation**: Restore the `source` parameter and resolve relative targets against `dirname(source)`, not `$(pwd)`:

```bash
validate_symlink_target() {
  local target="$1"
  local source="$2"
  ...
  if [[ "$target" != /* ]]; then
    resolve_base=$(cd "$(dirname "$source")" 2>/dev/null && pwd) || resolve_base="$(pwd)"
  fi
  candidate=$([[ "$target" = /* ]] && echo "$target" || echo "$resolve_base/$target")
  ...
}
safe_symlink() {
  ...
  if ! validate_symlink_target "$target" "$source"; then return 1; fi
  ...
}
```
Also change the unresolvable-parent fallback from "allow but warn" to fail closed (`return 1`) — a target that cannot be resolved cannot be proven safe.

**References**: CWE-59 (Improper Link Resolution Before File Access), CWE-706 (Use of Incorrectly-Resolved Name or Reference), OWASP A01:2021 (Broken Access Control).

---

### HIGH-002: Removal of ledger write-guard + caller error propagation allows silent truncation of the entire ledger

**Component**: `head/.claude/scripts/ledger-lib.sh:146-194`, `head/.claude/scripts/ledger-lib.sh:379,418,459,511,601,822`, `head/.claude/scripts/ledger-lib.sh:576-603`

**Description**

Three coupled controls were removed together, and their combination is what makes this exploitable rather than merely untidy:

1. **The empty/unparseable-content guard in `_write_ledger` is gone.** `base/.claude/scripts/ledger-lib.sh:152-156` refused to proceed if `$content` was empty or failed `jq empty`. In `head/.claude/scripts/ledger-lib.sh:146-153` that check no longer exists — `_write_ledger` now runs straight to `mkdir -p "$(dirname "$ledger_path")"` regardless of what `$content` contains.

2. **The post-timestamp empty-content guard is gone.** `base/.claude/scripts/ledger-lib.sh:172-177` checked that `updated_content` (the result of piping `$content` through `jq --arg ts ... '.last_updated = $ts'`) was non-empty before writing. In `head/.claude/scripts/ledger-lib.sh:167-169` that check is removed:
   ```
   local updated_content
   updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
   ```
   If `$content` is empty or invalid JSON, this `jq` invocation fails and writes nothing to stdout, but its exit status is never inspected — `updated_content` is silently set to `""`, and execution falls straight through to the atomic-write block at `head/.claude/scripts/ledger-lib.sh:172-188`. `echo "$updated_content" > "$tmp_file"` succeeds (it just writes a blank line), and `mv "$tmp_file" "$ledger_path"` then **succeeds in overwriting the real ledger file with empty content**, releases the lock, and returns `0` (`LEDGER_OK`).

3. **Every call site's error propagation was stripped.** All six call sites changed from `_write_ledger "$ledger_content" || return $LEDGER_ERROR` to bare `_write_ledger "$ledger_content"` (`head/.claude/scripts/ledger-lib.sh:379`, `418`, `459`, `511`, `601`, `822`). Even where the guards above still existed, the caller would no longer detect or react to a failed write — but since the guards are also gone, `_write_ledger` will actually report success (`0`) for the destructive case in point 2, so this isn't just "ignoring an error", it's "there is no error to observe."

4. **The input-shape validation that fed the ledger content was also removed.** `update_sprint_status()` at `base/.claude/scripts/ledger-lib.sh:600-604` rejected any non-numeric `$global_id` before it reached `jq --argjson id "$global_id"`. In `head/.claude/scripts/ledger-lib.sh:577,589-599` that check is gone. `--argjson` requires its argument to already be valid JSON; if `$global_id` is not a bare integer (e.g. empty, non-numeric, or a value crafted by an upstream caller), `jq` errors out with nothing on stdout, `ledger_content` becomes `""`, and that empty string is handed straight to `_write_ledger` at `head/.claude/scripts/ledger-lib.sh:601` — which, per points 1–3, now succeeds in wiping the ledger.

**Chained impact**: `update_sprint_status("<non-numeric-or-malformed-id>", "completed")` — with no other prerequisite — silently replaces the entire cycles/sprints ledger with a near-empty JSON document (just a `last_updated` timestamp field on `null`/failed content) and returns `LEDGER_OK`. Every other caller of `_write_ledger` (`create_cycle`, sprint-field updaters, `next_sprint_number` increment, cycle archival) is equally exposed if the upstream `jq` transform ever fails (concurrent modification of the ledger file mid-read, an unexpected ledger shape, a future caller passing attacker-influenced fields into a `jq --arg`/`--argjson` filter that turns out not to be valid JSON, etc.) — none of it will be surfaced anywhere, and nothing downstream will know the ledger just lost all cycle/sprint history.

**Impact**: Silent, unrecoverable (short of restoring from `ensure_ledger_backup`) loss of the framework's cycle/sprint tracking state, triggerable by ordinary malformed input rather than requiring privileged access. This directly undoes the guarantee the surrounding code calls out as `SECURITY (HIGH-001): Atomic write via temp file + mv` (`head/.claude/scripts/ledger-lib.sh:171`) — atomicity of the write was never the actual risk being mitigated; writing *garbage* atomically is just as bad as writing it non-atomically, and that is exactly what the removed guard prevented.

**Remediation**: Restore all four removed checks:
- Reject empty/unparseable `$content` at the top of `_write_ledger` (`head/.claude/scripts/ledger-lib.sh:146-153`).
- Reject empty `$updated_content` after the `jq` timestamp stamp, unlocking the flock before returning (`head/.claude/scripts/ledger-lib.sh:167-169`).
- Restore `|| return $LEDGER_ERROR` on every `_write_ledger` call site (`head/.claude/scripts/ledger-lib.sh:379,418,459,511,601,822`).
- Restore the numeric-`global_id` validation in `update_sprint_status` before it reaches `--argjson` (`head/.claude/scripts/ledger-lib.sh:577`).

**References**: CWE-459 (Incomplete Cleanup) / CWE-703 (Improper Check or Handling of Exceptional Conditions), OWASP A04:2021 (Insecure Design — missing fail-safe defaults).

## Medium Priority Issues

### MEDIUM-001: Release-merge PRs silently downgraded from full pipeline to minimal pipeline

**Component**: `head/.claude/scripts/classify-pr-type.sh:42-72`

**Description**: The rule classifying PR titles matching `from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:` as `"cycle"` was removed (previously `base/.claude/scripts/classify-pr-type.sh:65-69`). Per the file's own documentation (`head/.claude/scripts/classify-pr-type.sh:26-28`), `"cycle"` PRs trigger the Full Pipeline (CHANGELOG, GT, RTFM, Release run) while `"other"` PRs only get a tag. A merge titled e.g. `Release: v2.3.0` or `Merge pull request #123 from org/release/2.3.0` no longer matches any of the remaining four rules (cycle-label, `cycle-NNN` token, `^(Run Mode|Sprint Plan|feat\(sprint|feat\(cycle)`, `^fix`) and now falls through to `"other"`. Both `.github/workflows/post-merge.yml` and `.claude/scripts/post-merge-orchestrator.sh` source this shared classifier (per the file's header), so this silently skips CHANGELOG/GT/RTFM generation for release-merge PRs repo-wide, with no error or warning emitted anywhere — the classification just quietly changes.

**Impact**: Not directly exploitable, but it degrades the audit trail (missing CHANGELOG entries) and release automation coverage for exactly the PRs (release merges) that most need accurate post-merge processing. Given `CLAUDE.loa.md`'s "Post-Merge Automation" section states the orchestrator provides "state tracking, idempotency, and audit trail," this is a real regression of that guarantee, just not a memory-safety/injection-class vulnerability.

**Remediation**: Restore the removed rule (or fold it into an equivalent updated regex if the intent was to generalize rather than delete it) unless there is a documented, deliberate policy change that release-merge PRs should no longer trigger the full pipeline — in which case the PR description should say so explicitly, since nothing in `PR.md` mentions this behavioral change.

**References**: CWE-778 (Insufficient Logging) — relevant only in the "audit-trail gap" sense; this is primarily a correctness/process regression rather than a security vulnerability.

## Security Checklist Status

- [ ] Input validation preserved at all trust-boundary/parse points — **FAILED** (ledger `global_id` validation removed; `_write_ledger` content validation removed)
- [ ] Fail-safe defaults on error (fail closed, not open) — **FAILED** (symlink validation falls through to `return 0` on unresolvable path; ledger write proceeds on `jq` failure)
- [ ] Error propagation from internal helpers to callers — **FAILED** (`_write_ledger` return value ignored at all 6 call sites)
- [x] Atomic write mechanics (temp file + `mv`) — preserved structurally, but see HIGH-002 (atomicity of a bad write is not a safety property)
- [x] No secrets/credentials introduced
- [x] No new injection sinks (`eval`, unsanitized `exec`) introduced
- [ ] Path/symlink escape checks resolve against the correct anchor — **FAILED** (HIGH-001)

## Threat Model Summary

The affected scripts run during Loa framework bootstrap/maintenance (`mount-submodule.sh`) and during every sprint/cycle lifecycle transition (`ledger-lib.sh`), both with local filesystem write access and no external network trust boundary in this diff. The realistic threat actors are: (a) a compromised or malicious `.loa` submodule ref supplying a crafted symlink manifest (HIGH-001), and (b) any caller — even a legitimate one — passing a malformed/unexpected value into a ledger mutation function, whether due to a bug, a race with a concurrent ledger writer, or attacker-influenced input further up the call chain (HIGH-002). Both regressions convert what should be a hard failure into either "silently allowed" (HIGH-001) or "silently destructive but reported successful" (HIGH-002) — the more dangerous failure mode in each case.

## Verdict

**CHANGES_REQUIRED**

Both HIGH findings must be fixed before merge: HIGH-001 restores fail-closed symlink escape validation anchored to the symlink's own directory, and HIGH-002 restores the write-guard, caller error propagation, and input validation that prevented silent ledger corruption. MEDIUM-001 should be resolved or explicitly justified in the PR description.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":0},"sprint_id":"pr-audit","ts":"2026-09-21T00:00:00Z"} -->
