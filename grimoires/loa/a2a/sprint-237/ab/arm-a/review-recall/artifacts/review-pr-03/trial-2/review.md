# Review: refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification

## Overall Assessment

**Changes Required.** This PR removes three independent safety nets, and two of the three removals create realistic paths to silent data corruption / silent security-check bypass rather than mere "trimming." The third (release-merge classification) is an undocumented behavior change to production pipeline routing. None of these are cosmetic simplifications — each strips a guard that was added for a specific, cited reason (`HIGH-001`, `MED-004`) and the PR description does not explain why those reasons no longer apply.

## Critical Issues

### 1. `_write_ledger` error is now silently swallowed by every caller — ledger writes can fail while callers report success

`head/.claude/scripts/ledger-lib.sh:146-193` is `_write_ledger`. It can still `return 1` on lock timeout (line 161), temp-file write failure (line 178), or `mv` failure (line 187). But every call site was changed from:

```bash
_write_ledger "$ledger_content" || return $LEDGER_ERROR
```

to:

```bash
_write_ledger "$ledger_content"
```

followed unconditionally by `return $LEDGER_OK` two lines later. See `head/.claude/scripts/ledger-lib.sh:379-381` (`create_cycle`), `:418-420`, `:459-461`, `:511-513`, `:601-602` (`update_sprint_status`), `:822-824` (archive). Concretely: if `flock` times out (`_write_ledger:158-161`) because another process holds the lock, `create_cycle` still echoes a cycle id and returns `$LEDGER_OK` — the caller believes the cycle was persisted when nothing was written. This regresses the exact race-condition protection the `HIGH-001` comments (still present at lines 155, 171) claim to provide.

### 2. Removed content-validation in `_write_ledger` + removed numeric-ID guard in `update_sprint_status` combine into full ledger corruption

The PR removed two validations from `_write_ledger`:
- The empty/unparseable-JSON refusal that used to sit right before the lock/mkdir logic (was: `if [[ -z "$content" ]] || ! echo "$content" | jq empty ...`).
- The `updated_content` empty-check after timestamp stamping (was right after `head/.claude/scripts/ledger-lib.sh:169`).

It also removed the numeric-ID guard from `update_sprint_status` (was immediately after `now=$(now_iso)`, before building `ledger_content` — compare `base/.claude/scripts/ledger-lib.sh:598-602`).

Chained effect, reproducible today: call `update_sprint_status` with a non-numeric `global_id` (or any caller-side bug that produces one — nothing upstream of this function is type-checked). `jq --argjson id "$global_id" ...` at `head/.claude/scripts/ledger-lib.sh:592` or `:596` fails because `--argjson` requires a JSON literal; `jq` exits non-zero with no stdout. `ledger_content=$(jq ...)` at `:592`/`:596` therefore captures an **empty string**, silently (no `set -e`, and the previous `|| { echo ERROR; return $LEDGER_ERROR; }` guards around these two `jq` calls, visible in `base/.claude/scripts/ledger-lib.sh:601-609`, are also gone).

That empty string flows into `_write_ledger("")` at `head/.claude/scripts/ledger-lib.sh:601`. Inside `_write_ledger`, `echo "" | jq --arg ts ... '.last_updated = $ts'` (line 169) also fails on empty/invalid JSON input, so `updated_content` is empty — previously caught, now not. `echo "$updated_content" > "$tmp_file"` (line 173) happily writes an (empty) file, and `mv "$tmp_file" "$ledger_path"` (line 182) **atomically replaces the entire ledger with a blank file**. Per Critical Issue #1, the function then still returns `$LEDGER_OK`.

This is not a hypothetical edge case — `global_id` is caller-supplied and the guard existed specifically to prevent this class of input from ever reaching `jq --argjson`. Removing it, the empty-content refusal, and the error propagation simultaneously turns a defended failure mode into a silent full-data-loss bug.

### 3. `validate_symlink_target` now resolves relative targets against the wrong base directory, effectively disabling the MED-004 symlink-escape check

`head/.claude/scripts/mount-submodule.sh:370-405`. The function dropped its `source` parameter and the `resolve_base`/`candidate` logic that resolved a relative `target` against `dirname(source)` (the symlink's own directory — the correct base, since that's how the OS resolves a relative symlink target). It now does `if [[ -e "$target" ]]` (line 377) directly against **the process's current working directory**.

Every real call site passes relative targets meant to be resolved from the symlink's directory, not the script's cwd. The clearest example is `head/.claude/scripts/mount-submodule.sh:493`: `safe_symlink ".claude/settings.local.json" "../$SUBMODULE_PATH/.claude/settings.local.json"`. With `SUBMODULE_PATH=".loa"` (default, `base/.claude/scripts/mount-submodule.sh:50`), that target is `../.loa/.claude/settings.local.json`, correctly resolving (relative to `.claude/`, the source's directory) to `.loa/.claude/settings.local.json` inside the repo. Resolved against the script's cwd (repo root, since `create_symlinks` runs there) instead, `../.loa/...` points **one directory above the repo root**, which will not exist. That drives execution into the `else` branch at `head/.claude/scripts/mount-submodule.sh:379-390`: `parent_dir=$(dirname "$target")` is also above repo root and not a directory, so the function hits `warn "Cannot resolve symlink target: $target"; return 0` — i.e. it **allows the symlink** rather than validating it. Every normal, legitimate manifest-driven symlink call now silently takes the fail-open branch instead of the actual bounds check; a genuinely escaping target would take the same fail-open path and be let through with only a warning. This guts the "MED-004 FIX: Symlink Target Validation" the surrounding comments (lines 359, 452) still claim is in effect.

## Non-Critical / Needs Justification

### 4. Release-merge classification silently removed from `classify_pr_type`

`head/.claude/scripts/classify-pr-type.sh` drops (previously `base/.claude/scripts/classify-pr-type.sh:66-69`):

```bash
if echo "$title" | grep -qE "from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:"; then
    echo "cycle"
    return 0
fi
```

Per the function's own docstring (`head/.claude/scripts/classify-pr-type.sh:26`), `"cycle"` triggers "CHANGELOG, GT, RTFM, Release run" in the post-merge pipeline. A PR titled `Release: v2.3.0` or merged `from origin/release/2.3` now falls through to `"other"` (tag-only, minimal pipeline) unless it happens to also match `\bcycle-[0-9]+\b`. The PR title states this removal is intentional but neither `PR.md` nor the diff explains *why* release-merge PRs no longer need the full cycle pipeline. This is a production routing behavior change for a real merge pattern, not dead code — the docstring's rule list was already stale before this change (it never listed the release rule either), so "align code to docs" is not sufficient justification on its own. Needs an explicit rationale or a companion change showing release merges are now classified as "cycle" by some other path (e.g. by also matching a `cycle-NNN` tag).

## Adversarial Analysis

### Concerns Identified
1. `head/.claude/scripts/ledger-lib.sh:379-824` — six call sites discard `_write_ledger`'s return code, so lock-timeout and disk-write failures are invisible to callers and to anything scripting against these functions' exit codes.
2. `head/.claude/scripts/ledger-lib.sh:592,596,601` — loss of both the numeric-ID guard and the content/empty-string validation means a single malformed argument can blank out the entire ledger file in one atomic `mv`, with no error surfaced.
3. `head/.claude/scripts/mount-submodule.sh:377-390` — the resolution-base change means `validate_symlink_target` almost always takes the "cannot resolve, allow" branch for real manifest targets, so the function no longer performs the check its name and surrounding comments claim.
4. `head/.claude/scripts/classify-pr-type.sh` — removing the release-merge rule changes which PRs get CHANGELOG/GT/RTFM/Release-run treatment, with no stated reason and no test coverage shown for the new behavior.

### Assumptions Challenged
- **Assumption**: The engineer assumed all six `_write_ledger` call sites are equivalent — either write always succeeds in practice, or callers don't care about the distinction between "write happened" and "write skipped." **Risk if wrong**: any lock contention (concurrent `/run` invocations, concurrent cycle/sprint updates — exactly the scenario `HIGH-001` was written to defend against) now produces a function that reports success without persisting anything. **Recommendation**: restore `|| return $LEDGER_ERROR` at all six sites, or make the intentional swallowing explicit with a comment justifying it.
- **Assumption**: `validate_symlink_target`'s caller always runs from a cwd where relative targets resolve correctly without a source anchor. **Risk if wrong**: as shown in Critical Issue #3, this is false for the actual manifest-driven call sites today, not just a future risk.

### Alternatives Not Considered
- **Alternative**: If the goal was to simplify `validate_symlink_target`'s signature, the source-relative resolution logic could have been kept while only removing dead branches/comments — the simplification bundled a base-directory change that wasn't called for by "trim." **Tradeoff**: keeps the function's actual security property intact while still shortening it. **Verdict**: should reconsider; the current diff conflates "delete unused code" with "change resolution semantics," and only the latter is the actual regression.
- **Alternative**: For the `_write_ledger` guards, if the goal was to eliminate *duplicate* error messages (each call site printing its own vs. `_write_ledger` printing one), the fix should have kept `|| return $LEDGER_ERROR` (propagation) while only trimming the redundant `echo "ERROR..."` wrapper blocks around the `jq` calls. **Tradeoff**: same code-size reduction without losing failure propagation. **Verdict**: current approach conflates message-dedup with error-propagation removal.

## Next Steps

1. Restore `|| return $LEDGER_ERROR` after every `_write_ledger` call in `head/.claude/scripts/ledger-lib.sh` (6 sites).
2. Restore the empty/unparseable-content guard in `_write_ledger` and the empty-`updated_content` guard, or replace with an equivalent check — do not let `mv` overwrite the ledger with unvalidated content.
3. Restore the numeric-ID validation in `update_sprint_status` (or validate at every caller boundary) before it reaches `jq --argjson`.
4. Restore source-relative resolution in `validate_symlink_target` (or pass the symlink's directory explicitly) so the bounds check evaluates the same path the OS will actually create.
5. Either restore the release-merge classification rule in `classify-pr-type.sh` or provide the rationale/tests showing release-merge PRs are correctly classified without it.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":3,"high":0,"medium":1,"low":0},"sprint_id":"pr-03","ts":"2026-09-21T00:00:00Z"} -->
