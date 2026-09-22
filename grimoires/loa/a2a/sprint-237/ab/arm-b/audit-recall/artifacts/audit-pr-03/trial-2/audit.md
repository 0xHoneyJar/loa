# Security Audit — refactor(ledger,mount,classify): trim write-guard checks, symlink resolution, PR classification

**Scope**: `head.diff` touching `.claude/scripts/ledger-lib.sh`, `.claude/scripts/mount-submodule.sh`, `.claude/scripts/classify-pr-type.sh`. No sprint plan / beads / a2a artifacts exist for this PR; audited directly against `base/` → `head/`.

## Summary

This PR is framed as a refactor ("trim ... checks") but every hunk removes a previously landed, explicitly security-tagged control (`SECURITY (HIGH-001)`, `MED-004 FIX`) with no replacement. Two of the three changes are exploitable/consequential regressions; the third is a correctness regression in CI routing logic. None of the removed checks are shown to be redundant or superseded elsewhere in the diff.

## Findings

### 1. CRITICAL — Ledger write-guard removal allows silent corruption of the sprint ledger (data integrity / availability)

`head/.claude/scripts/ledger-lib.sh:146-186` (`_write_ledger`)

The PR deletes both input-validation gates that existed in `base/.claude/scripts/ledger-lib.sh`:

```
-    if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
-        echo "ERROR: refusing to write empty or unparseable ledger content" >&2
-        return $LEDGER_ERROR
-    fi
```
and
```
-    if [[ -z "$updated_content" ]]; then
-        echo "ERROR: timestamp stamping produced empty content, aborting write" >&2
-        flock -u 9
-        exec 9>&-
-        return $LEDGER_ERROR
-    fi
```

`_write_ledger` (head/.claude/scripts/ledger-lib.sh:146-186) now takes `$content` straight from the caller into `jq --arg ts "$(now_iso)" '.last_updated = $ts'` (line 169) with no validation that `$content` is non-empty or well-formed JSON. If any upstream `jq` builder call fails (malformed field name, bad `--argjson` value, concurrent-edit race, disk/lock hiccup) it produces an empty string under `set -euo pipefail`'s command-substitution blind spot (`local x=$(cmd)` does not propagate `cmd`'s exit status — this exact footgun is documented in this repo's own `.claude/rules/shell-conventions.md` "Bash Strict Mode Safety → JSON Construction Safety" section, which the removed code was implementing verbatim: *"Validate before `--argjson`... empty string is not valid JSON"*).

With the guard gone: `echo "$updated_content" > "$tmp_file"` (head:173) succeeds (writing an empty/near-empty file), `mv "$tmp_file" "$ledger_path"` (head:182) succeeds, and the atomic-write "SECURITY (HIGH-001)" comment directly above it (head:171) is now protecting an unvalidated payload. The append-only sprint ledger — the single source of truth for cycle/sprint state per `CLAUDE.loa.md` — can be silently truncated/emptied with no error surfaced to the operator or caller.

**CWE-20: Improper Input Validation** — https://cwe.mitre.org/data/definitions/20.html
**CWE-1284: Improper Validation of Specified Quantity in Input** (structurally malformed data reaching a write sink) — https://cwe.mitre.org/data/definitions/1284.html

**Failure scenario**: a caller passes a field name or value containing characters that break the `jq` filter (or two concurrent invocations race on a transient lock/backup failure); `ledger_content` becomes `""`; the write path in `_write_ledger` accepts it and overwrites the real ledger file with an effectively empty document, losing all cycle/sprint history with no error printed.

### 2. HIGH — Removed error propagation on `_write_ledger` call sites turns explicit error codes into abrupt `set -e` termination (or worse, silent success reporting)

`head/.claude/scripts/ledger-lib.sh:379, 418, 459, 511, 601, 822`

Every call site in `base/` used the pattern `_write_ledger "$ledger_content" || return $LEDGER_ERROR`. All six are reduced to bare `_write_ledger "$ledger_content"`:

```
-    _write_ledger "$ledger_content" || return $LEDGER_ERROR
+    _write_ledger "$ledger_content"
```

e.g. head/.claude/scripts/ledger-lib.sh:379 (`create_cycle`), :418 (`update_cycle_field`), :459 (increment next_sprint_number), :511 (append sprint), :601 (`update_sprint_status`), :822 (archive cycle).

Because `ledger-lib.sh` runs under `set -euo pipefail` (head/.claude/scripts/ledger-lib.sh:14), a bare failing statement should abort the script — but that only holds when the caller itself hasn't disabled `errexit` in a subshell/`if`/`&&` context, which is exactly how several of these functions *are* invoked elsewhere in the framework (status checks, `||` fallbacks). In those contexts the removed `|| return $LEDGER_ERROR` was the only thing converting a lock-timeout or write failure into a caller-visible non-zero return; without it the function falls through to `echo "$cycle_id"` / `echo "$current"` (e.g. head:381-382, immediately after the now-unchecked call at :379) and `return $LEDGER_OK`, reporting success to the caller even though the write never happened.

**CWE-252: Unchecked Return Value** — https://cwe.mitre.org/data/definitions/252.html

**Failure scenario**: `_write_ledger` fails to acquire its flock within `$LEDGER_LOCK_TIMEOUT` (head:158-162, still returns 1) while being called from a context where `errexit` is suppressed (e.g. inside an `if create_cycle ...; then` conditional, which disables `-e` for that command per bash semantics); `create_cycle` proceeds past the failed write, echoes a cycle id, and returns `$LEDGER_OK` — the caller now believes a cycle was durably created when the ledger was never updated.

### 3. HIGH — Removed numeric validation on `global_id` before use in a `jq --argjson` filter

`head/.claude/scripts/ledger-lib.sh:576-601` (`update_sprint_status`)

```
-    if [[ ! "$global_id" =~ ^[0-9]+$ ]]; then
-        echo "ERROR: update_sprint_status requires a numeric global sprint id (got '$global_id')" >&2
-        return $LEDGER_SPRINT_NOT_FOUND
-    fi
```

was removed, and the surrounding `jq ... || { echo "ERROR: failed to build updated ledger content" >&2; return $LEDGER_ERROR; }` wrappers at both call sites (head:592, head:596) were also stripped down to bare assignments. `$global_id` now flows unvalidated into `jq --argjson id "$global_id" ...` (head:592, 596). `--argjson` requires its argument to be valid JSON; a non-numeric, attacker- or bug-supplied `global_id` (e.g. empty string, a sprint identifier with stray whitespace, or JSON-breaking characters) makes the `jq` call fail, which — per Finding #1 — now degrades to a silent empty/corrupt ledger write rather than the `LEDGER_SPRINT_NOT_FOUND`/`LEDGER_ERROR` the removed guards used to return.

**CWE-20: Improper Input Validation** — https://cwe.mitre.org/data/definitions/20.html

**Failure scenario**: any caller (script, hook, or future run-mode automation) passes a non-numeric or malformed sprint id to `update_sprint_status`; instead of a clean `LEDGER_SPRINT_NOT_FOUND` error, the ledger write path silently corrupts state (chains into Finding #1).

### 4. HIGH — `validate_symlink_target` now resolves relative symlink targets against the process's current working directory instead of the symlink's own directory, breaking the repo-escape check it exists to enforce

`head/.claude/scripts/mount-submodule.sh:370-405` (`validate_symlink_target`), call site `head/.claude/scripts/mount-submodule.sh:409-419` (`safe_symlink`)

`base/.claude/scripts/mount-submodule.sh` took a `source` parameter and resolved relative targets against `dirname "$source"` — the correct semantics, since a relative symlink target is resolved by the OS relative to the directory *containing the symlink*, not the caller's cwd:

```
-  local source="${2:-}"
...
-  local resolve_base=""
-  if [[ "$target" != /* ]]; then
-    if [[ -n "$source" ]]; then
-      resolve_base=$(cd "$(dirname "$source")" 2>/dev/null && pwd)
-    fi
-    if [[ -z "$resolve_base" ]]; then
-      resolve_base="$(pwd)"
-    fi
-  fi
-
-  local candidate
-  if [[ "$target" = /* ]]; then
-    candidate="$target"
-  else
-    candidate="$resolve_base/$target"
-  fi
```

The head version drops `source` entirely and resolves `dirname "$target"` directly against whatever the current working directory happens to be at call time (head:377-390):

```
+  if [[ -e "$target" ]]; then
+    resolved_target=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")
```

The call site at `head/.claude/scripts/mount-submodule.sh:414` (`safe_symlink`) now invokes `validate_symlink_target "$target"` with no source argument at all — the function comment at head:361 ("Validate that symlink targets don't escape repository bounds") and the header at head:367-369 ("Returns: 0 if safe, 1 if escapes bounds") are unchanged, but the implementation beneath them no longer does what they describe when cwd and the symlink's directory diverge.

Concretely, `create_symlinks` (head:433) calls `safe_symlink ".claude/settings.local.json" "../$SUBMODULE_PATH/.claude/settings.local.json"` at head/.claude/scripts/mount-submodule.sh:493. Under the old code, the `..` in the target was correctly resolved relative to `.claude/` (the symlink's own directory), canceling out to `repo_root/$SUBMODULE_PATH/...`. Under the new code, `dirname` of the raw relative target is `../$SUBMODULE_PATH/.claude`, and `cd` into that path is relative to whatever the *process* cwd is — under this script's `set -euo pipefail` (head:25), if cwd is the repo root when `create_symlinks` runs, this literally walks one level *above* the repository before descending into `$SUBMODULE_PATH/.claude`, computing a different — and for a directory that doesn't exist there, an outright failing — resolution than the actual filesystem target of the symlink `ln -sf` is about to create (head:418). More generally, any caller that invokes `safe_symlink`/`validate_symlink_target` from a cwd other than the symlink's own directory now validates a path that has nothing to do with where the symlink will actually resolve, silently defeating the repo-escape check for relative targets while still displaying "Security: Symlink target escapes repository bounds" style confidence in its output.

**CWE-59: Improper Link Resolution Before File Access ('Link Following')** — https://cwe.mitre.org/data/definitions/59.html
**CWE-22: Improper Limitation of a Pathname to a Restricted Directory ('Path Traversal')** — https://cwe.mitre.org/data/definitions/22.html

**Failure scenario**: `mount-submodule.sh` (or any future caller of `safe_symlink`) is invoked from a directory other than the repository root, or the manifest in `lib/symlink-manifest.sh` supplies a relative target whose `..` segments were tuned for source-relative resolution; the bounds check computes the wrong absolute path, either falsely rejecting a legitimate in-repo target or — more dangerously — falsely approving a target that actually escapes the repository once `ln -sf "$target" "$source"` (head:418) creates it, because the OS resolves the symlink relative to its own directory while the validator now resolves it relative to cwd.

### 5. MEDIUM — Release-merge classification removed from `classify_pr_type`, misrouting release PRs to the "other" pipeline path

`head/.claude/scripts/classify-pr-type.sh:63-71`

```
-    if echo "$title" | grep -qE "from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:"; then
-        echo "cycle"
-        return 0
-    fi
```

was removed with no replacement rule. Per the file's own docstring (head/.claude/scripts/classify-pr-type.sh:26-31), `classify_pr_type` output ("cycle"/"bugfix"/"other") drives which post-merge pipeline runs — "cycle" triggers the "full cycle (CHANGELOG, GT, RTFM, Release run)" path. A merge-commit title of the form `Merge ... from org/release/1.2.3` or `Release: 1.2.3` no longer matches any of the remaining rules (label check, `cycle-NNN`, `^(Run Mode|Sprint Plan|feat\(sprint|feat\(cycle)`, `^fix`) and now falls through to `echo "other"` (head:71). This routes release merges away from the full pipeline that (per this repo's own merge-constraint rules) is expected to run `semver-bump.sh` and `post-merge-orchestrator.sh`-driven tagging/changelog generation, weakening the audit trail this repo relies on to prevent manually-created tags.

**CWE-841: Improper Enforcement of Behavioral Workflow** — https://cwe.mitre.org/data/definitions/841.html

**Failure scenario**: a release-branch merge with a title like `Release(v1.16.0): ship cycle-118` is classified as `other` instead of `cycle`; the post-merge orchestrator skips the full pipeline gate, and the tag/changelog for that release is produced through a degraded or manual path instead of `semver-bump.sh`.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 3 |
| Medium | 1 |
| Low | 0 |

## Recommendation

Do not merge as-is. Each removed check was landed with an explicit security rationale still visible in the surrounding comments (`SECURITY (HIGH-001)`, `MED-004 FIX`) that the diff leaves stale and now-false. Restore:
- the empty/unparseable-content and empty-timestamp guards in `_write_ledger` (Finding 1),
- `|| return $LEDGER_ERROR` (or equivalent explicit error handling) at every `_write_ledger` call site (Finding 2),
- the numeric `global_id` validation and jq-failure handling in `update_sprint_status` (Finding 3),
- the `source`-relative resolution in `validate_symlink_target`/`safe_symlink` (Finding 4),
- the release-merge classification rule in `classify_pr_type`, or an equivalent (Finding 5).

If the intent was genuinely to simplify, each removal needs its own justification (e.g., "guard X is now redundant because Y validates upstream") — none is given in the PR description, and none is evidenced in the diff.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":3,"medium":1,"low":0},"sprint_id":"pr-03","ts":"2026-09-22T00:00:00Z"} -->
