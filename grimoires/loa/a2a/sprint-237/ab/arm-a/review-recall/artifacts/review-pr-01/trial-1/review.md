# Review: chore(hooks,scripts): simplify carrier-value regexes, redaction patterns and sprint counting

## Overall Assessment

This "cleanup" touches three independent safety/state files, and in all three cases the
"simplification" removes behavior that was deliberately engineered (per the surrounding,
unmodified comments in the same files) to fix a specific class of bug. None of the three
hunks come with a test, and empirical checks below show each one reintroduces the exact
failure mode its removed code was built to prevent. This should not be merged as-is.

## Critical Issues

### 1. `block-destructive-bash.sh` — multi-flag carriers no longer redact the first value (only the last)

`head/.claude/hooks/safety/block-destructive-bash.sh:207-212`

The diff does two things together:
- widens the carrier prefix class from `[^;&|'"]*` to `[^;&|]*` (drops the quote exclusion), and
- deletes `_bdb_re_tail` and the inner `while` loop in `_bdb_scrub` (`head/.claude/hooks/safety/block-destructive-bash.sh:219-236`, was `base/.claude/hooks/safety/block-destructive-bash.sh:214, 236-248`) that consumed additional bare `-m|--message|-d|--description|--body|--title` flag/value pairs after the first match.

The unmodified comment block immediately above (`head/.claude/hooks/safety/block-destructive-bash.sh:203-208`) explicitly documents *why* the prefix excludes quotes: `"[^;&|]* keeps the prefix within one segment"` — the original code (`base/.claude/hooks/safety/block-destructive-bash.sh:210-212`) actually used `[^;&|'"]*`, i.e. the comment was already describing the *intended* narrower class, and the quote-exclusion is what forces the primary regex to stop at the first quoted value instead of a POSIX leftmost-longest match swallowing every subsequent flag into the same match. The tail loop then walks the remaining flag/value pairs one at a time, applying the content gate to each independently. Removing the quote-exclusion removes the reason the tail loop was scoped to "one flag at a time," and removing the tail loop then means only the *first* match's flag gets scrubbed — but since the prefix class no longer stops at quotes, the *first* match now itself expands to swallow every later flag too, and only the trailing flag's value is actually redacted.

Verified empirically (POSIX ERE / glibc regex, same engine `[[ =~ ]]` uses):

```
$ printf '%s' 'gh pr create --title "Fix bug problem" --body "Fixes the login issue"' \
    | grep -oE '(^|[^[:alnum:]_])gh[[:space:]][^;&|]*(issue|pr)[^;&|]*create[^;&|]*(--body|--title)[[:space:]]+('"'"'[^'"'"']*'"'"'|"[^"]*")'
gh pr create --title "Fix bug problem" --body "Fixes the login issue"     # ← ONE match, spans both flags

$ printf '%s' 'git commit -m "first para" -m "second para"' \
    | grep -oE '(^|[^[:alnum:]_])git[[:space:]][^;&|]*commit[^;&|]*(-m|--message)[[:space:]]+('"'"'[^'"'"']*'"'"'|"[^"]*")'
git commit -m "first para" -m "second para"        # ← new code: ONE match, spans both -m flags

$ # with the OLD (quote-excluding) prefix class the match correctly stops at the first flag:
git commit -m "first para"                          # ← old code: match ends at first -m,
                                                      #   "rest" is ` -m "second para"`, which
                                                      #   _bdb_re_tail then picks up separately
```

Given `_bdb_scrub`'s logic (`head/.claude/hooks/safety/block-destructive-bash.sh:219-236`): when the overall match spans both flags, only the trailing captured group (the *last* flag's value) is the "value" that gets tested/redacted; the earlier flag/value text is folded into `po` (`"${m%"$val"}"`) and re-emitted **unredacted**. Concretely, for `gh pr create --title "T" --body "B"`, only `B` is checked/redacted — `T` passes straight through to the destructive-pattern matchers untouched.

This is the exact `gh pr create --title ... --body ...` shape this very framework's own PR-creation convention uses (see the system-level "Creating pull requests" instructions), and it is the shape the surrounding, unmodified comments (`head/.claude/hooks/safety/block-destructive-bash.sh:155-193`, "quote-blind... blocks a harmless command") describe as the whole point of this fence. A PR title or commit subject line containing something that looks destructive (`"chore: drop the legacy staging TABLE"`, `"fix: remove --force push guard"`) will now be scanned raw and can trip a false-positive block that this exact code was built to avoid, whenever it's the *first* of two+ carrier flags in the command.

**Fix**: revert this hunk, or if the tail loop is genuinely dead weight, add a regression test exercising a two-flag `gh pr create --title ... --body ...` / `git commit -m ... -m ...` command and show both values get redacted before removing the loop.

### 2. `invoke-diagnostics.sh` — drops AWS STS/role/profile key prefixes from secret redaction

`head/.claude/scripts/lib/invoke-diagnostics.sh:47`

```
-    -e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \
+    -e 's/AKIA[A-Z0-9]{16}/AKIA***REDACTED***/g' \
```

This narrows AWS credential redaction from all documented AWS key-ID prefixes down to only long-lived IAM user keys (`AKIA`). It silently stops redacting `ASIA*` — AWS STS **temporary session credentials**, which are extremely common in CI/CD and are exactly the kind of short-lived-but-still-live secret that ends up in error logs — plus `AROA`/`AGPA`/`AIPA`/`ANPA`/`ANVA` (role/group/profile identifiers). The commit message frames this as "trimmed back to the documented AWS access-key shape," but the function's own doc comment never listed AKIA (or any AWS prefix) before this PR either (`base/.claude/scripts/lib/invoke-diagnostics.sh:28-35` has no AKIA line at all) — there is no prior "documented shape" that only covered `AKIA`; this is a real reduction in secret-redaction coverage, not a restoration of documented behavior.

The same hunk also tightens the `Bearer` token character class from `[A-Za-z0-9=._-]+` to `[A-Za-z0-9._-]+`, dropping `=`. Base64url tokens commonly contain `=` padding; a token containing `=` will now only be redacted up to the character before the `=`, leaking the remainder (e.g. `Bearer ***REDACTED***==...`) into diagnostic logs instead of the whole token being masked.

**Fix**: restore the full AWS prefix alternation (or explicitly confirm none of the Hounfour call paths this file diagnoses can ever emit STS credentials, and document that), and restore `=` to the Bearer token class.

## Non-Critical Improvements

### 3. `workflow-state.sh` — `get_total_sprints` prints "0" twice when the sprint count is zero

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

`grep -c PATTERN file` prints the match count to stdout *and* exits non-zero when the count is `0` (grep's exit status reflects "no lines matched," independent of `-c`'s printed value). So when `sprint.md` exists but has no `## Sprint N` headings yet (a normal pre-sprint-plan state), this line **prints `0` from `grep -c`, then — because grep's exit code is 1 — also runs `|| echo "0"`**, emitting a second `0` line. The output becomes `"0\n0"` instead of `"0"`.

The removed `base/.claude/scripts/workflow-state.sh:71-73` version avoided this by capturing grep's stdout into a local variable (`n=$(... || true)`) and echoing it exactly once (`echo "${n:-0}"`) — the `|| true` there suppresses `set -e` without duplicating output, because it's attached to the assignment, not wrapped around a second `echo`.

Any caller doing `total=$(get_total_sprints)` (this script runs under `set -euo pipefail`, `head/.claude/scripts/workflow-state.sh:16`) will get `total="0\n0"` in the zero-sprint case, which breaks numeric comparisons (`[[ "$total" -eq 0 ]]` → integer expression error) or corrupts `--json` output assembly. This is a straightforward regression, not a simplification — the old code was already minimal for what it needed to do (suppress a `set -e` abort while capturing output once).

**Fix**: `grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null | tail -1` won't fix it either (still runs once, fine actually) — simplest correct form: keep the capture-then-echo pattern, or `printf '%s\n' "$(grep -c ... || true)"` reduced to one line, e.g. `n=$(grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null) || n=0; echo "$n"`.

## Adversarial Analysis

### Concerns Identified
1. `head/.claude/hooks/safety/block-destructive-bash.sh:210-212` — multi-flag carriers (the framework's own `gh pr create --title/--body` convention) only get their *last* value redacted; earlier values pass through raw to the pattern matchers (Critical #1).
2. `head/.claude/scripts/lib/invoke-diagnostics.sh:47` — AWS STS/role/profile key prefixes (`ASIA`, `AROA`, `AGPA`, `AIPA`, `ANPA`, `ANVA`) are no longer redacted from diagnostic logs (Critical #2).
3. `head/.claude/scripts/lib/invoke-diagnostics.sh:45` — `=`-padded Bearer tokens are only partially redacted (Critical #2).
4. `head/.claude/scripts/workflow-state.sh:72` — `get_total_sprints` double-prints `"0"` under `set -e` when the sprint count is zero, corrupting any `$(...)` capture of its output (Non-Critical #3).
5. No test file is included anywhere in this diff for any of the three behavior changes, despite two of them (the regex fence, the redaction patterns) being explicitly security-relevant code with dense in-file commentary describing prior, hard-won edge-case fixes (cycle-120 C-D3a, issue #1047 references in the unmodified comments).

### Assumptions Challenged
- **Assumption**: the PR author assumed the `_bdb_re_tail` loop and the quote-excluding prefix class were independent, droppable pieces of complexity ("simplify carrier-value regexes").
- **Risk if wrong**: as shown above, they are a matched pair — removing the quote exclusion changes the primary regex's match span (via POSIX leftmost-longest semantics), which is what makes the tail loop's removal actually lose coverage rather than become redundant.
- **Recommendation**: revert both changes together, or land a bats/regex test asserting `gh pr create --title "safe title" --body "safe body"` redacts *both* values before resubmitting.

### Alternatives Not Considered
- **Alternative**: if the goal was genuinely to reduce regex complexity, the safer direction would have been to keep the tail loop but generalize the single primary-regex pattern per carrier (git/br/gh) to also use the tail-loop's flag-agnostic pattern from the start, eliminating the *duplication* between `_bdb_re_git`/`_bdb_re_brbd`/`_bdb_re_gh` and `_bdb_re_tail` without changing which values get redacted.
- **Tradeoff**: more invasive than this PR, but wouldn't regress redaction coverage.
- **Verdict**: should reconsider — the current PR optimizes for fewer lines at the cost of the specific behavior those lines existed for.

## Previous Feedback Status

N/A — no prior `engineer-feedback.md` exists for this change (no sprint/a2a context provided).

## Next Steps

1. Revert or fix the `block-destructive-bash.sh` carrier-regex change (Critical #1) — add a two-flag regression case before resubmitting.
2. Restore full AWS key-prefix coverage and the `=` character in the Bearer token class in `invoke-diagnostics.sh` (Critical #2).
3. Fix the double-`0` output in `get_total_sprints` (Non-Critical #3).

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":2,"high":0,"medium":1,"low":0},"sprint_id":"pr-review","ts":"2026-09-20T00:00:00Z"} -->
