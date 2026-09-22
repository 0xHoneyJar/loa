# Security Audit — refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification

**Scope**: `head.diff` touching `.claude/scripts/ledger-lib.sh`, `.claude/scripts/mount-submodule.sh`, `.claude/scripts/classify-pr-type.sh`. No sprint plan, beads database, or implementation report was available; audited directly from `base/`/`head/` file pairs and the unified diff.

**Framing**: despite the PR title calling this a simplification, every hunk in this diff *removes* a previously-present guard (input validation, error propagation, or a classification rule) rather than restructuring code. Each removed guard is evaluated on its own merits below — "it was simplification" is not treated as justification for a control that silently disappears.

---

## Findings

### 1. [HIGH] `_write_ledger` no longer validates content before writing, and every caller now ignores its return code — a `jq` failure silently corrupts the ledger instead of aborting

- `head/.claude/scripts/ledger-lib.sh:144-190` (`_write_ledger`)
- `head/.claude/scripts/ledger-lib.sh:379,418,459,511,601,822` (all six call sites)

The base version guarded two failure modes before writing:

```
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
(`base/.claude/scripts/ledger-lib.sh:152-156,174-179`)

Both checks are deleted in `head/.claude/scripts/ledger-lib.sh:146-190`. Simultaneously, every caller's guard was stripped from `_write_ledger "$ledger_content" || return $LEDGER_ERROR` down to a bare `_write_ledger "$ledger_content"` (e.g. `head/.claude/scripts/ledger-lib.sh:379`, `:418`, `:459`, `:511`, `:601`, `:822`), so callers now proceed to `echo`/`return $LEDGER_OK` unconditionally regardless of whether the write actually succeeded.

**Failure scenario**: any caller builds `ledger_content` via a `jq` filter over `"$ledger_path"` (e.g. `head/.claude/scripts/ledger-lib.sh:375-377`). If that `jq` invocation fails or the filter targets a field that no longer matches (stale/renamed id, concurrent edit, malformed prior state), `ledger_content` is captured as an empty string with the `set -euo pipefail`-safe `$(...)` substitution swallowing the non-zero exit. `_write_ledger` used to catch this with the empty/unparseable check; now it proceeds directly to `updated_content=$(echo "$content" | jq --arg ts ... '.last_updated = $ts')` (`head/.claude/scripts/ledger-lib.sh:167-168`), which itself fails on empty input (jq parse error on stdin), again yielding an empty `updated_content` that is *not* checked. That empty string is then written via the (still-present) atomic temp-file+`mv` path (`head/.claude/scripts/ledger-lib.sh:171-186`), which "succeeds" mechanically — it just replaces the ledger with near-empty content. The caller then reports `$LEDGER_OK` and continues. The ledger — this framework's authoritative cycle/sprint state store — is silently destroyed with no error surfaced to the user or calling script, and no backup restoration is triggered because no error path fires. This is exactly the "looks like success, produces silent data loss" hazard called out in `.claude/rules/stash-safety.md` for a different subsystem; here it is a fresh instance in ledger writes.

**Reference**: [CWE-252: Unchecked Return Value](https://cwe.mitre.org/data/definitions/252.html), [CWE-20: Improper Input Validation](https://cwe.mitre.org/data/definitions/20.html).

**Remediation**: restore both validation checks in `_write_ledger` and restore `|| return $LEDGER_ERROR` on all six call sites. If the removal was intended to reduce duplication, do so by having `_write_ledger` itself be the single enforcement point and keep the `||` guards — the current state has neither.

---

### 2. [HIGH] `update_sprint_status` no longer validates `global_id` is numeric before using it in `jq --argjson`, reintroducing the exact corruption path in Finding 1 via a trivial bad input

- `head/.claude/scripts/ledger-lib.sh:586-604` (`update_sprint_status`)
- Removed check was at `base/.claude/scripts/ledger-lib.sh:600-604`:
```
if [[ ! "$global_id" =~ ^[0-9]+$ ]]; then
    echo "ERROR: update_sprint_status requires a numeric global sprint id (got '$global_id')" >&2
    return $LEDGER_SPRINT_NOT_FOUND
fi
```

`head/.claude/scripts/ledger-lib.sh:593-600` now passes `$global_id` straight into `jq --argjson id "$global_id" ...` with no format check. `--argjson` requires its argument to already be valid JSON; any non-numeric `global_id` (empty string, a sprint slug, whitespace, anything not a bare integer) makes the `jq` invocation fail immediately, producing an empty `ledger_content` that flows straight into the now-unguarded `_write_ledger` from Finding 1. Where the base version rejected the bad input with `$LEDGER_SPRINT_NOT_FOUND` before touching the ledger file at all, the head version's first bad call to `update_sprint_status` (e.g. from a caller that passes an unset or malformed sprint id) overwrites the entire ledger with corrupted content.

**Reference**: [CWE-20: Improper Input Validation](https://cwe.mitre.org/data/definitions/20.html).

**Remediation**: restore the numeric-format guard before the `jq --argjson` calls.

---

### 3. [HIGH] `validate_symlink_target` dropped its `source` parameter and now resolves relative targets against the script's cwd instead of the symlink's own directory, defeating the repo-escape check for nested symlinks

- `head/.claude/scripts/mount-submodule.sh:370-405` (`validate_symlink_target`)
- `head/.claude/scripts/mount-submodule.sh:409-419` (`safe_symlink`, no longer passes `source`)

The base implementation (`base/.claude/scripts/mount-submodule.sh:368-401`) took the symlink's own path as a second argument and, for relative targets, resolved them against `dirname("$source")` — matching how the kernel actually resolves a relative symlink target (relative to the directory *containing* the link, not the process's cwd):

```
local resolve_base=""
if [[ "$target" != /* ]]; then
    if [[ -n "$source" ]]; then
        resolve_base=$(cd "$(dirname "$source")" 2>/dev/null && pwd)
    fi
    ...
fi
local candidate
if [[ "$target" = /* ]]; then
    candidate="$target"
else
    candidate="$resolve_base/$target"
fi
```

`head/.claude/scripts/mount-submodule.sh:370-390` deletes the `source` parameter entirely and operates on `$target` directly against whatever `pwd` happens to be when `validate_symlink_target` runs:

```
validate_symlink_target() {
  local target="$1"
  ...
  if [[ -e "$target" ]]; then
    resolved_target=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")
  else
    local parent_dir
    parent_dir=$(dirname "$target")
    if [[ -d "$parent_dir" ]]; then
      resolved_target=$(cd "$parent_dir" && pwd)/$(basename "$target")
    else
      warn "Cannot resolve symlink target: $target"
      return 0
    fi
  fi
```

`safe_symlink` (`head/.claude/scripts/mount-submodule.sh:407-419`) is called throughout `mount_files_and_skills` (e.g. `:452-453`, `:465`, `:476`, `:487`, `:493`) with manifest entries whose `link_path` frequently lives in a subdirectory (`.claude/skills/<name>`, `.claude/commands/<name>.md`, `.claude/settings.local.json`) and whose `target` is a relative path meant to be interpreted from that subdirectory (e.g. `../$SUBMODULE_PATH/...`).

**Failure scenario**: for a manifest entry like `link_path=".claude/skills/foo"`, `target="../../$SUBMODULE_PATH/.claude/skills/foo"`, the *correct* (base) resolution is relative to `.claude/skills/` and lands inside the repo. The head version instead evaluates `-e "$target"` and `dirname "$target"` relative to the script's cwd (repo root, since the script is invoked from there), which for a target with `../../` climbs *above* the repo root — a path that typically does not exist on disk. That drives execution into the `else` branch, `parent_dir` also does not exist relative to cwd, and the function hits `warn "Cannot resolve symlink target: $target"; return 0` — i.e. it reports the target as unresolvable and **allows the symlink anyway**, exactly the fallback the MED-004 fix comment (`head/.claude/scripts/mount-submodule.sh:359`) claims is closed. The bounds check is not merely weakened, it is routed into its own "cannot resolve, allow" escape hatch for the common nested-symlink case, silently disabling the protection this function exists to provide. A manifest (or future manifest edit) that points a nested symlink outside the repo would no longer be caught.

**Reference**: [CWE-59: Improper Link Resolution Before File Access ('Link Following')](https://cwe.mitre.org/data/definitions/59.html), [CWE-706: Use of Incorrectly-Resolved Name or Reference](https://cwe.mitre.org/data/definitions/706.html).

**Remediation**: restore the `source` parameter to `validate_symlink_target` and resolve relative targets against `dirname("$source")`, not the caller's `pwd`. Add a regression test that exercises a manifest entry whose `link_path` is nested (not at repo root) with a relative `target`, asserting both that in-bounds targets are accepted and that a crafted out-of-bounds relative target from a nested source is rejected.

---

### 4. [MEDIUM] `classify-pr-type.sh` drops the release-merge classification rule, likely reintroducing the misrouting bug the file's own history describes fixing

- `head/.claude/scripts/classify-pr-type.sh:63-73`

Removed from `base/.claude/scripts/classify-pr-type.sh:63-68`:
```
if echo "$title" | grep -qE "from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:"; then
    echo "cycle"
    return 0
fi
```

With this rule gone, a PR titled e.g. `Release: v1.16.0` or produced by a merge `from origin/release/1.16` no longer matches any of the remaining rules (label contains "cycle", `\bcycle-[0-9]+\b`, `^(Run Mode|Sprint Plan|feat\(sprint|feat\(cycle)`, `^fix`) and falls through to `"other"` (`head/.claude/scripts/classify-pr-type.sh:73`). Per this file's own header comment, `cycle` classification is what drives "CHANGELOG, GT, RTFM, Release run" in the post-merge pipeline — this is the same class of misrouting the adjacent comment at `head/.claude/scripts/classify-pr-type.sh:52-55` describes as a real, previously-fixed production incident (cycle-114 #971, where a capitalization mismatch caused a release-adjacent PR to be misrouted to `"other"` and skip the Full Pipeline). Removing the release-branch/`Release:` rule outright reopens that class of bug for release-merge PRs specifically, rather than merely tightening a regex.

**Reference**: [CWE-696: Incorrect Behavior Order](https://cwe.mitre.org/data/definitions/696.html) (process/control-flow integrity — the classification gates a downstream automation pipeline, not a memory-safety boundary, so this is scoped as a process-integrity finding rather than a direct security vulnerability).

**Remediation**: restore the release-branch/`Release:` classification rule, or confirm with the PR author that release merges are now intentionally handled by a different mechanism (label-based `cycle` tagging) before merging — if so, document that assumption in the file's header comment so the next reader does not have to reverse-engineer the removal from git history.

---

## Observations

None beyond the findings above — the diff is small and every hunk maps to one of the four findings.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 1 |
| Low | 0 |

## Verdict

**CHANGES_REQUIRED** — three HIGH findings (silent ledger corruption on write failure, a concrete trigger for it via the removed `global_id` format check, and a silently-defeated symlink repo-escape check) must be fixed before this PR merges. The MEDIUM classification regression should also be resolved or explicitly justified.

## Recommendations

- **Immediate (24h)**: restore the `_write_ledger` content validation and all six `|| return $LEDGER_ERROR` call-site guards (Finding 1); restore the `global_id` numeric-format check in `update_sprint_status` (Finding 2); restore `source`-relative resolution in `validate_symlink_target` and re-pass `source` from `safe_symlink` (Finding 3).
- **Short-term (1wk)**: add a bats/shell test exercising a nested symlink manifest entry with both an in-bounds and an out-of-bounds relative target, and a test that calls `update_sprint_status` with a non-numeric id and asserts the ledger file is untouched.
- **Long-term (1mo)**: consider whether `classify-pr-type.sh`'s release-merge rule removal (Finding 4) was intentional; if release routing was moved to labels, document that in the file header so future refactors don't need to reconstruct the history from `git log`.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":1,"low":0},"ts":"2026-09-22T01:19:51Z"} -->
