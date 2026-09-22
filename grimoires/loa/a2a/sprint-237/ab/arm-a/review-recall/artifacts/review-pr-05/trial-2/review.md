# Review: refactor(hooks,cheval,state): single-token find roots, plain 4xx handling, historical sprint counting

## Overall Assessment

Three independent, unrelated changes bundled in one PR. The `anthropic_adapter.py` simplification is clean and does what the title says. The other two changes each introduce a real correctness regression that the stated rationale does not cover:

1. The `block-destructive-bash.sh` find-root regex change silently drops the old "reject if more than one root token" safety check, which reopens a `find`-based `rm -rf` bypass the multi-root guard existed to close.
2. The `workflow-state.sh` sprint-counting rewrite switches from "count sprint dirs 1..N with a COMPLETED marker" to "count every directory under `a2a/` matching `sprint-*` with a COMPLETED marker," which now also counts non-sprint-plan directories such as `sprint-bug-*` (a real, documented directory shape per `.claude/rules/skill-invariants.md`'s own reference to `sprint-bug-102`), inflating `completed_sprints` past `total_sprints` and corrupting downstream state/progress math.

**Verdict: CHANGES REQUIRED** — item 1 is a security-relevant regression in a safety hook; item 2 is a functional correctness bug in workflow-state detection.

## Critical Issues

### 1. `find` multi-root safety check silently dropped → `rm -rf` bypass reopened

`head/.claude/hooks/safety/block-destructive-bash.sh:776`, `head/.claude/hooks/safety/block-destructive-bash.sh:806-807`

Old code (`base/.claude/hooks/safety/block-destructive-bash.sh:803-811`):
```bash
read -r -a _find_span_toks <<<"${BASH_REMATCH[3]}"
_find_root_count=0
for _ftok in ${_find_span_toks[@]+"${_find_span_toks[@]}"}; do
  case "$_ftok" in
    -*|'!'*|'('*|')'*|'\'*) break ;;
    *) _find_root_count=$((_find_root_count + 1)); _seg_find_root="$_ftok" ;;
  esac
done
[[ "$_find_root_count" -ne 1 ]] && _seg_find_root=""
```
walked *every* token between `find` and `-exec`, and explicitly cleared `_seg_find_root` when it found anything other than **exactly one** root token. That was the mechanism that made `find A B -exec rm -rf {} \;` (two roots) fall through to the conservative per-arg classifier instead of being treated as a "safe find-exec root" segment.

New code:
```bash
_re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)[:space:]]+)[^;&|)]*-exec$'
...
if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
  _seg_find_root="${BASH_REMATCH[3]}"
fi
```
`BASH_REMATCH[3]` is now unconditionally *the first whitespace-delimited token after `find`*, regardless of how many additional root arguments follow before `-exec`. The multi-root check is gone entirely — the comment at `head/.claude/hooks/safety/block-destructive-bash.sh:773-775` only documents the "flags before the root" gap (`find -L root -exec`), not this one, so the loss looks unintentional rather than a deliberately scoped-down behavior.

**Concrete bypass**, using the actual allow/block ladder at `head/.claude/hooks/safety/block-destructive-bash.sh:850-878`:

```bash
find ./build /etc -exec rm -rf {} \;
```

- `_seg_find_root` = `"./build"` (first token only; `/etc` is silently dropped from consideration).
- The `rm` operands are all find-exec placeholders (`-rf`, `{}`, `;`), so `_seg_placeholder_only=1` (line 850-859).
- `./build` matches `_re_allow_list` (`^(\./[^/*.][^*]*|...|build$|build/|...)`, `head/.claude/hooks/safety/block-destructive-bash.sh:765`) → the segment is allowed outright (`head/.claude/hooks/safety/block-destructive-bash.sh:874-875`).
- The actual command still walks **both** `./build` and `/etc`, and `find`'s `-exec rm -rf {} \;` deletes everything it matches under `/etc` too.

With the old code, the same command would have found 2 root tokens, cleared `_seg_find_root`, fallen into the per-arg classifier, hit the `{}` placeholder (which matches none of dotdot/block/allow-exclude/allow-list), and been blocked as `FR-2-AMBIGUOUS`. This PR turns a blocked command into an allowed one that can delete an arbitrary catastrophic path, as long as an allow-listed path is listed first. This is exactly the shape of hazard C15/cycle-119 was written to close (see the surrounding comment block) — recommend restoring the root-count check (or rejecting the segment outright whenever the captured span between `find` and `-exec` contains a second non-flag token) before merging.

## High-Priority Issues

### 2. `get_completed_sprints` now counts non-sprint-plan directories, corrupting state detection

`head/.claude/scripts/workflow-state.sh:79-91`

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

vs. the old bounded version (`base/.claude/scripts/workflow-state.sh:78-89`) that only checked `a2a/sprint-1 .. sprint-<total_sprints>`.

`get_total_sprints` (`head/.claude/scripts/workflow-state.sh:70-76`) still counts only `## Sprint N` headings in `sprint.md` — i.e. plan sprints. But `get_completed_sprints` now globs *every* directory under `a2a/` named `sprint-*`, which also matches ad-hoc `/bug` sprint directories. This framework's own convention names those `sprint-bug-<id>` — see `.claude/rules/skill-invariants.md`'s reference to `sprint-bug-102` as a real sprint directory shape, and `CLAUDE.loa.md`'s `/bug` workflow, which creates such directories under the same `a2a/` tree and marks them `COMPLETED` on completion.

Consequences, both reachable from `determine_state()` (`head/.claude/scripts/workflow-state.sh:142-151`) and `get_progress_percentage()` (`head/.claude/scripts/workflow-state.sh:240-248`):

- If a project has, say, `total_sprints=3` (from `sprint.md`) and has also completed 2 `/bug` sprints (`sprint-bug-101`, `sprint-bug-102`, both with `COMPLETED`) plus 1 real plan sprint, `completed_sprints` becomes `3` while only 1 of the 3 plan sprints is actually done. `completed_sprints -ge total_sprints` trips at line 148, and the script reports `STATE_COMPLETE` ("All sprints complete. Ready for deployment.") and suggests `/deploy-production` — while 2 of 3 real sprints are still unimplemented.
- Even short of full completion, `get_progress_percentage`'s `sprint_progress=$((completed_sprints * 70 / total_sprints))` (line 243) can now exceed the intended 70-point sprint budget, or otherwise misreport progress, whenever bug-sprint completions inflate the numerator relative to the plan-sprint denominator.

This is a real regression, not a hypothetical: the framework actively creates `sprint-bug-*` directories in the same `a2a/` tree this glob now scans. Recommend either scoping the glob to `sprint-[0-9]+` (numeric plan sprints only) or continuing to bound the count by `get_total_sprints()` as before, while still using `find` for whatever the original historical-counting motivation was (e.g. sprints that no longer sequentially align with `sprint.md`).

## Non-Critical / Questions

### 3. Anthropic adapter: billing-class 4xx errors are now terminal instead of triggering provider fallback

`head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139-141`, `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:221-223`

The removed `_is_billing_class_error()` (previously `base/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:41-66`) special-cased 4xx bodies containing tokens like `credit balance`, `quota_exceeded`, `payment_required`, etc., and raised `ProviderUnavailableError` for them instead of `InvalidInputError`. Per the adapter framework's typed-exception contract (see the streaming-path comment at `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:144-152`), `ProviderUnavailableError` is what lets the retry/chain-walk layer fail over to another provider, while `InvalidInputError` is terminal.

This PR makes *all* 4xx responses — including a billing-exhausted account, which is not a request-shape problem — terminal `InvalidInputError`s. That is consistent with the PR title ("plain 4xx handling") and may be a deliberate simplification, but it is a behavior change with operational impact: a cheval chain that previously failed over automatically when the primary Anthropic account ran out of credit will now hard-fail the request instead. Worth confirming this is intended (and, if so, whether it should be called out as a behavior change in the PR description) rather than treating it purely as dead-code removal.

## Adversarial Analysis

### Concerns Identified
1. `find` multi-root bypass reopens an `rm -rf` safety hole for catastrophic paths (`head/.claude/hooks/safety/block-destructive-bash.sh:776`, `:806-807`) — see Critical #1.
2. `get_completed_sprints` glob scope mismatch vs. `get_total_sprints` produces incorrect `STATE_COMPLETE` detection (`head/.claude/scripts/workflow-state.sh:83`) — see High #2.
3. Billing-class 4xx errors lose their chain-walk fallback path with no note in the PR description that this is an intended operational change (`head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139-141`).
4. No tests are included in this diff for any of the three changes (no `base/`/`head/` test files present), so none of the above would be caught by CI as currently exercised by this PR.

### Assumptions Challenged
- **Assumption**: the engineer treated "single root token" as equivalent to "first token, since multi-root finds are rare/theoretical." The PR's own in-code comment (`head/.claude/hooks/safety/block-destructive-bash.sh:773-775`) documents only the `find -L root` flag-ordering gap, not the multi-root gap — suggesting the multi-root regression is accidental, not a scoped-down deliberate tradeoff.
- **Risk if wrong**: a previously-blocked catastrophic-path deletion (`find <safe-looking-root> <dangerous-root> -exec rm -rf {} \;`) is now silently allowed.
- **Recommendation**: restore the root-count/single-root invariant explicitly, and add a fixture/test case for the multi-root shape (this hook's test suite almost certainly has a fixtures file that isn't included in this PR's diff — this needs a regression test either way).

### Alternatives Not Considered
- **Alternative** for `get_completed_sprints`: keep bounding the loop by `get_total_sprints()` (as before) but switch the existence check from a hardcoded `sprint-${i}` path to a `find`-based existence check only for `i in 1..total`, which would fix whatever motivated the historical-counting rewrite (e.g. non-contiguous sprint numbering) without picking up unrelated `sprint-bug-*` directories.
- **Tradeoff**: slightly more code than the blanket glob, but preserves the numerator/denominator correspondence with `sprint.md`.
- **Verdict**: should reconsider — the blanket glob as written is a strictly worse choice than a bounded existence check for the stated goal ("historical sprint counting").

## Next Steps

1. Fix the `find` multi-root regression (Critical #1) — either restore the token-walk/count check, or reject any find-exec prefix whose captured span (between `find` and `-exec`) contains more than one non-flag token.
2. Fix or bound the `get_completed_sprints` glob (High #2) so it doesn't count `sprint-bug-*` (or any other non-numeric `sprint-*`) directories against `total_sprints`.
3. Confirm the billing-class 4xx behavior change (Non-Critical #3) is intentional; if so, note it explicitly in the PR description since it changes provider-fallback behavior in production.
4. Add regression tests/fixtures for the multi-root find-exec case and for the mixed plan-sprint/bug-sprint `a2a/` directory shape.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":1,"low":0},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
