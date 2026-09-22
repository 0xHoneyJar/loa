# Sprint Review — PR: chore(hooks,scripts): simplify carrier-value regexes, redaction patterns and sprint counting

No sprint plan, beads database, or `grimoires/loa/a2a/` context exists for this review (per `REVIEW-INSTRUCTIONS.md`); this review is scoped to `head.diff` / `base/` / `head/` only. The `## AC Verification` requirement (tied to `sprint.md`) is not applicable here and is skipped.

## Overall Assessment

This is billed as a pure cleanup/simplification chore across three unrelated shell helpers. Two of the three changes introduce real regressions: one is a security-relevant reduction in secret-redaction coverage, the other is a correctness bug that produces malformed output from a function whose result is fed straight into arithmetic comparisons and a `seq` range. **Changes required.**

## Critical Issues

### 1. AWS key redaction coverage silently narrowed from 7 prefixes to 1

`head/.claude/scripts/lib/invoke-diagnostics.sh:50`

```sed
-e 's/AKIA[A-Z0-9]{16}/AKIA***REDACTED***/g' \
```

replaces the base version's

```sed
-e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \
```

(`base/.claude/scripts/lib/invoke-diagnostics.sh:47`). This function exists specifically to strip credentials out of diagnostic logs before they're written to disk (`redact_secrets`, used by `setup_invoke_log`/`log_invoke_failure`). Dropping `ASIA` (STS temporary/session credentials — arguably the *most* commonly-leaked, actively-usable AWS credential type, since they show up in env vars and assumed-role output), `AROA` (role IDs), `AGPA`, `AIPA`, `ANPA`, and `ANVA` means any of those key shapes now flow into the on-disk invoke log completely unredacted. The PR description calls this "trimmed back to the documented AWS access-key shape," but AWS's own documentation for [resource ID prefixes](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_identifiers.html) lists all of these as valid IAM-identifier prefixes — "documented shape" does not mean "only AKIA." This is a coverage regression, not a simplification, and should be reverted unless there's a specific reason (not stated in the PR) that the other prefixes are no longer relevant.

### 2. `get_total_sprints` can emit two lines instead of one, breaking every caller

`head/.claude/scripts/workflow-state.sh:70-76`

```bash
get_total_sprints() {
    if [[ -f "${SPRINT_FILE}" ]]; then
        grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}
```

`grep -c` writes its match count to stdout *and* exits with status `1` whenever the count is zero — it does not need `-c` to fail in order to print "0"; it prints "0" itself. So when `SPRINT_FILE` exists but has no `## Sprint N` headings, this function emits:

```
0
0
```

— once from `grep -c` itself, and once again from the `|| echo "0"` fallback that fires because grep's exit status is 1. Every call site captures this via command substitution (`total=$(get_total_sprints)` at `head/.claude/scripts/workflow-state.sh:86`, `head/.claude/scripts/workflow-state.sh:147`, and `head/.claude/scripts/workflow-state.sh:369`), and command substitution only strips *trailing* newlines, so `total_sprints` becomes the literal two-line string `"0\n0"`. That value is then used in:

- `head/.claude/scripts/workflow-state.sh:151`: `[[ "${completed_sprints}" -ge "${total_sprints}" ]]` — a numeric comparison that will throw `integer expression expected` on a multi-line operand.
- `head/.claude/scripts/workflow-state.sh:158`: `for i in $(seq 1 "${total_sprints}")` — `seq 1 "0\n0"` is a malformed argument.

The base version avoided this exact trap by capturing into a variable first (`n=$(grep -c ... || true); echo "${n:-0}"`), which only ever emits grep's own stdout once. The "simplification" reintroduces a bug the original code was written to avoid. Suggested fix, still one line shorter than the base:

```bash
local n
n=$(grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null) || n=0
echo "${n:-0}"
```

This is a realistic trigger, not a hypothetical: any freshly-scaffolded or malformed `sprint.md` that doesn't yet contain a `## Sprint N` heading hits this path.

## Non-Critical Improvements

### 3. Bearer-token redaction narrowed without explanation

`head/.claude/scripts/lib/invoke-diagnostics.sh:48`

```sed
-e 's/(Bearer )[A-Za-z0-9._-]+/\1***REDACTED***/g' \
```

drops `=` from the allowed character class (base had `[A-Za-z0-9=._-]+`, `base/.claude/scripts/lib/invoke-diagnostics.sh:45`). Non-JWT bearer tokens using standard base64 padding (`=`/`==`) will now have their trailing padding characters left outside the match and printed unredacted, e.g. `Bearer abc123==` → `Bearer ***REDACTED***==`. Low severity (padding carries no entropy), but it's an unstated narrowing of a security-relevant regex bundled into a PR that describes itself as touching only the "AWS access-key shape" — worth either reverting or calling out explicitly in the PR description.

### 4. Multi-flag tail loop removal reintroduces a class of false positive

`base/.claude/hooks/safety/block-destructive-bash.sh:236-248` (removed; corresponding region is now `head/.claude/hooks/safety/block-destructive-bash.sh:219-236`)

The removed `_bdb_re_tail` loop handled `git commit -m 'para1' -m 'para2'` (git's documented multi-paragraph commit message idiom) and equivalent multi-flag `br`/`bd`/`gh` invocations by scrubbing every `-m`/`-d`/`--body`/`--title` occurrence, not just the first. After this change, only the first quoted value in a segment is exempted from destructive-pattern scanning; a second `-m` value containing text that happens to look like a destructive command (e.g., a commit message body quoting `rm -rf /tmp/x` for documentation purposes) will now trigger the false-positive block this fence exists to prevent. This fails safe (over-blocking, not under-blocking) per the file's own design note ("an incomplete allowlist only preserves a false positive — it can never open a bypass"), so it's not a security regression, but it is a real usability regression that isn't mentioned in the PR description beyond "loses... the multi-flag tail loop." Confirm this tradeoff is intentional before merging.

## Adversarial Analysis

### Concerns Identified
1. AWS credential redaction coverage dropped from 7 prefixes to 1 (`head/.claude/scripts/lib/invoke-diagnostics.sh:50`) — see Critical #1.
2. `get_total_sprints` emits a malformed two-line result on the zero-match path (`head/.claude/scripts/workflow-state.sh:72`) — see Critical #2.
3. Bearer-token regex silently drops `=` from its character class with no stated reason (`head/.claude/scripts/lib/invoke-diagnostics.sh:48`) — see Non-Critical #3.
4. Multi-flag carrier loop removed, reintroducing false-positive risk for multi-`-m`/`-d`/`--body` commands (`head/.claude/hooks/safety/block-destructive-bash.sh:219-236`) — see Non-Critical #4.

### Assumptions Challenged
- **Assumption**: The author assumed `grep -c PATTERN FILE 2>/dev/null || echo "0"` is a drop-in, purely mechanical simplification of the previous capture-into-variable pattern.
- **Risk if wrong**: `grep -c` prints its own "0" on the zero-match path *before* exiting non-zero, so the `||` fallback adds a second "0" rather than replacing the first — the two forms are not equivalent, and this specific idiom (`grep -c ... || fallback`) is a known bash footgun.
- **Recommendation**: Restore single-capture semantics (`n=$(grep -c ... 2>/dev/null) || n=0; echo "${n:-0}"`), which is both correct and no longer than the current buggy version.

### Alternatives Not Considered
- **Alternative**: For the AWS pattern, if the goal was genuinely to narrow scope, do so with a stated reason (e.g., "we only mint long-term AKIA keys in this org's tooling, and ASIA/AROA/etc. are out of scope because X") and add/keep the enumerated group so the intent is auditable, rather than silently collapsing to a single hardcoded prefix in both the pattern and the replacement string.
- **Tradeoff**: The current diff makes the regex shorter and drops the `\1` back-reference, but a shorter regex is not the goal of a secret-redaction function — coverage is. A one-line comment justifying the narrowed scope would have made this reviewable instead of requiring a diff-level "wait, why did coverage change" catch.
- **Verdict**: Should reconsider — restore the enumerated prefix group (or explicitly justify removing each dropped prefix) before merging.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":1,"low":1},"sprint_id":"pr-review","ts":"2026-09-20T00:00:00Z"} -->
