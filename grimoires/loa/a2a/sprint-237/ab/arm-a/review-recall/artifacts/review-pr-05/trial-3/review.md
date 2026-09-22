# Review: refactor(hooks,cheval,state): single-token find roots, plain 4xx handling, historical sprint counting

## Overall Assessment

Three independent, loosely-related simplifications bundled into one PR. Two of the three change
observable behavior in ways the PR description doesn't own up to, and one of those two is a
genuine security regression in a safety-critical file. Not approvable as-is.

## Critical Issues

### 1. `find`-exec root detection now silently ignores all but the first root, creating a bypass for multi-root `find ... -exec rm` commands

`head/.claude/hooks/safety/block-destructive-bash.sh:776` narrows the prefix regex so group 3
captures only `find`'s *first* whitespace-delimited token, with everything else up to `-exec`
absorbed by the uncaptured `[^;&|)]*`:

```
_re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)[:space:]]+)[^;&|)]*-exec$'
```

`head/.claude/hooks/safety/block-destructive-bash.sh:805-808` then assigns that single token to
`_seg_find_root` unconditionally:

```bash
    _seg_find_root=""
    if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
      _seg_find_root="${BASH_REMATCH[3]}"
    fi
```

Compare with the code being replaced (`base/.claude/hooks/safety/block-destructive-bash.sh:803-811`),
which tokenized the *entire* span between `find` and `-exec`, counted how many leading non-flag
tokens it found, and reset `_seg_find_root=""` whenever that count was not exactly 1 (multiple
roots, e.g. `find dir1 dir2 -exec ...`). An empty `_seg_find_root` falls through to the per-arg
ladder at `head/.claude/hooks/safety/block-destructive-bash.sh:880-909`, where a bare `{}`
placeholder matches none of the allow patterns and trips `any_ambiguous=1` — i.e. the old code
conservatively **blocked** any multi-root find-exec-rm shape.

The new code drops that count check entirely. For `find ./safe /etc -exec rm -rf {} \;`:
- group 3 captures only `./safe` (the trailing ` /etc ` is swallowed by `[^;&|)]*`)
- `_seg_find_root="./safe"`, which is non-empty, so the placeholder-only branch at
  `head/.claude/hooks/safety/block-destructive-bash.sh:850-859` fires (the rm's only operand is
  `{}`, a placeholder)
- the classification ladder at `head/.claude/hooks/safety/block-destructive-bash.sh:861-878`
  checks **only** `./safe` against `_re_allow_list`, matches, and takes the `:` ("explicit safe
  relative root — allow this find-exec segment") branch at line 875
- `/etc`, the actual second root that `rm -rf {}` will also recurse into, is never classified at
  all — it was consumed into the discarded middle of the regex match.

Net effect: a command this hook used to block (ambiguous → refuse) is now allowed to execute,
purely because an attacker (or an innocent multi-root find invocation) puts a benign-looking path
first. This is a filter bypass in a hook whose entire job is to stop exactly this class of command.

The updated comment at `head/.claude/hooks/safety/block-destructive-bash.sh:773-775` only
documents the "flags before the root" gap (`find -L root -exec`) as an accepted, conservative
limitation — it says nothing about, and doesn't appear to have considered, the multi-root case,
which is not conservative: it flips from block to allow.

**Fix**: restore the root-count check (or explicitly reject/treat-as-ambiguous whenever a second
bare token appears between the captured root and `-exec`) before assigning `_seg_find_root`
unconditionally.

## Non-Critical / Needs Confirmation

### 2. `get_completed_sprints` scope no longer matches `get_total_sprints` scope, can misreport workflow state as complete

`head/.claude/scripts/workflow-state.sh:79-91`:

```bash
get_completed_sprints() {
    local count=0
    local sprint_dirs
    local a2a_dir="${_GRIMOIRE_DIR}/a2a"
    sprint_dirs=$(find "${a2a_dir}" -maxdepth 1 -type d -name "sprint-*" 2>/dev/null || true)

    for dir in ${sprint_dirs}; do
        if [[ -f "${dir}/COMPLETED" ]]; then
            count=$((count + 1))
        fi
    done
    echo "${count}"
}
```

This now counts *every* `sprint-*` directory under `a2a/` with a `COMPLETED` marker — i.e. every
sprint ever completed in this grimoire, across cycles — rather than the sprints belonging to the
plan currently in `sprint.md`. `get_total_sprints()` (`head/.claude/scripts/workflow-state.sh:70-76`,
unchanged) still counts `^## Sprint [0-9]` headers in the *current* `sprint.md` only.

Both values are then compared directly:
- `head/.claude/scripts/workflow-state.sh:148`: `if [[ "${completed_sprints}" -ge "${total_sprints}" ]] ... STATE_COMPLETE`
- `head/.claude/scripts/workflow-state.sh:390`: `progress=$(get_progress_percentage ... "${total_sprints}" "${completed_sprints}")`, echoed to the user as `Sprints: X/Y complete` (line 357).

If `a2a/` isn't wiped between cycles (nothing in this diff or the touched files establishes that
it is), any grimoire with a prior completed cycle will have `completed_sprints` counting stale
directories from that older cycle. A fresh sprint plan with 3 sprints, none yet started, sitting
next to 5 old completed `sprint-*` dirs from a prior cycle, now reports `STATE_COMPLETE` and
`166%` progress immediately. The PR title's "historical sprint counting" framing suggests this is
intentional, but if so `get_total_sprints` needed a matching scope change (or the comparison at
line 148 needed to change) — as written the two functions answer different questions and are
compared as if they answer the same one. Please confirm whether `a2a/` is guaranteed cycle-scoped
elsewhere (e.g. by `/archive-cycle` relocating old sprint dirs) — if so, say so in a comment here,
since nothing in the touched files enforces it.

Secondary, non-blocking: `for dir in ${sprint_dirs}` (line 85) is unquoted, so it both
word-splits and globs the `find` output — inconsistent with this repo's own
`.claude/rules/shell-conventions.md` guidance on safe iteration, and fragile if a grimoire dir
ever contains a space. Low risk in practice (`sprint-*` names are hyphenated tokens) but worth a
`while IFS= read -r -d ''`/`-print0` pass while touching this function.

### 3. Billing-class 4xx errors are now always terminal instead of chain-walk-eligible — confirm this is deliberate, not just deleted

`base/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:38-71` special-cased HTTP
4xx responses whose message matched a billing/quota/credit token list, re-raising them as
`ProviderUnavailableError` (chain-walk-eligible per this repo's multi-model retry policy) instead
of `InvalidInputError` (terminal). The diff deletes `_BILLING_CLASS_TOKENS` and
`_is_billing_class_error` outright and both call sites now go straight to
`InvalidInputError` — `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139-141`
(streaming) and `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:223` (non-streaming).

This is a real behavior change, not just a code simplification: an Anthropic key that returns
HTTP 400 `"insufficient_quota"` (account-side, arguably retryable via a different key/provider in
the chain) will now be treated identically to a genuine bad-request param error (request-side,
correctly terminal) — no chain-walk, no fallback to the next provider in the chain. Given
`.claude/loa/CLAUDE.loa.md`'s own framing of "chain-walk on retryable errors," this looks like it
removes retry coverage for a real-world failure mode (exhausted credits) rather than just deleting
dead code. If the token-matching approach was judged too fragile/unmaintained and this is a
deliberate "make billing failures terminal" decision, that's a defensible simplification — but the
PR description ("plain 4xx handling") doesn't say that's the intent, and there's no equivalent
handling added elsewhere (e.g. at the retry/chain-walk layer) in this diff. Please confirm which
it is.

## Adversarial Analysis

### Concerns Identified
1. `head/.claude/hooks/safety/block-destructive-bash.sh:776,805-808` — multi-root find-exec bypass, detailed above (Critical Issue 1).
2. `head/.claude/scripts/workflow-state.sh:79-91` vs `:70-76` — scope mismatch between completed/total sprint counting can misreport `STATE_COMPLETE` and >100% progress.
3. `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139-141,223` — silent loss of chain-walk eligibility for billing-class errors.
4. None of the three changes come with a test diff in this PR (no test files touched per `head.diff`) — for a security-hook regex change and a workflow-state comparison-semantics change, that's a gap; the "single-token find roots" framing itself suggests the author's mental model may not have considered the multi-root case at all.

### Assumptions Challenged
- **Assumption**: the engineer treated "capture the find root" and "capture the find root, and only the find root" as equivalent problems — the new regex is written and commented as if reducing "how many roots are there" to "take the first" preserves safety, when in the placeholder-only branch it removes validation of the discarded roots entirely rather than falling back to the old conservative path.
- **Risk if wrong**: a previously-blocked `rm -rf` shape now executes silently.
- **Recommendation**: make explicit — either the multi-root case must retain the old "reset to empty, fall through to per-arg ladder" behavior, or the PR must show a fixture/test proving multi-root find-exec-rm is still caught.

### Alternatives Not Considered
- **Alternative**: for the find-root regex, keep capturing the *entire* span between `find` and `-exec` (as before) and do the "is this exactly one bare token" check inline against the captured group, rather than trying to make the regex itself only match a single token. This keeps the safety invariant (multi-root ⇒ no trusted root ⇒ fall through to conservative per-arg handling) while still fixing whatever the single-token capture was meant to fix.
- **Tradeoff**: slightly more logic in the shell function vs. a shorter regex; the diff already retained a token-processing loop's *shape* in the old code, so this isn't a big lift.
- **Verdict**: should reconsider — the current approach trades a real safety property for regex simplicity without acknowledging the trade.

## Next Steps

1. Fix the multi-root find-exec regression (Critical Issue 1) — required before merge.
2. Either fix the scope mismatch in `get_completed_sprints`/`get_total_sprints`, or explain in the
   PR why `a2a/` is guaranteed to only ever contain the current cycle's sprint directories.
3. Confirm the billing-class 4xx removal is an intentional policy change (terminal instead of
   chain-walk) and not an accidental side effect of deleting what looked like unused code; if
   intentional, say so in the PR description.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":1,"low":1},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
