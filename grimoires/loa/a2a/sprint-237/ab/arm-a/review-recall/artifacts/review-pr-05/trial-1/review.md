# PR Review: refactor(hooks,cheval,state): single-token find roots, plain 4xx handling, historical sprint counting

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-09-21
**Scope:** Standalone PR review (no sprint plan / beads / a2a context available — reviewed from `PR.md`, `head.diff`, `base/`, `head/` only)

---

## Overall Assessment

This PR bundles three unrelated, independently-reviewable changes into one diff: (1) a rewrite of the `find ... -exec rm` root-detection regex in the destructive-bash safety hook, (2) removal of billing-class 4xx error handling in the Anthropic cheval adapter, and (3) a rewrite of `get_completed_sprints()` in `workflow-state.sh`. Each is described in the PR body as a narrow fix, but two of the three introduce regressions rather than pure fixes: the `find`-exec rewrite silently drops a safety check that existed specifically to reject multi-root `find` invocations, and the sprint-counting rewrite globs in directories (`sprint-bug-*`) that were never part of the counted population, which can flip `/loa`'s workflow-state detection to "complete" prematurely. The Anthropic adapter change is a legitimate simplification only if the billing-class chain-walk behavior it removes was genuinely dead weight — nothing in the diff or PR body establishes that, and the framework's own multi-model docs describe chain-walk-on-retryable-error as a documented capability this code was implementing.

**Verdict:** CHANGES REQUIRED

---

## Critical Issues (Must Fix Before Approval)

### 1. Security — `find`-exec root regression re-enables the multi-root bypass the old code explicitly guarded against

**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:776, 806-808`
**Issue:** The new `_re_find_exec_prefix` capture group 3 is `([^;&|)[:space:]]+)` — it stops at the first whitespace, so it can only ever capture `find`'s *first* bareword token. Everything after it, up to `-exec`, is swallowed by the non-space-excluding `[^;&|)]*` that follows in the same regex (`head/.claude/hooks/safety/block-destructive-bash.sh:776`). The call site then does `_seg_find_root="${BASH_REMATCH[3]}"` unconditionally (`head/.claude/hooks/safety/block-destructive-bash.sh:807`), with no check that this was the *only* root token.

The base version (`base/.claude/hooks/safety/block-destructive-bash.sh:809-820`) tokenized the *entire* span between `find` and `-exec`, and explicitly reset `_seg_find_root=""` whenever more than one bareword token preceded `-exec` (`_find_root_count -ne 1`). That reset was the mechanism that caught **multi-root `find` invocations** — a real, POSIX-legal `find` feature: `find path1 path2 ... -exec cmd {} +` searches *all* listed paths. When more than one root was present, the old code fell through to the untouched per-argument ladder, which treats an unrecognized shape as AMBIGUOUS (conservative block).

The new code has no equivalent check, so a command like:

```
find ./build /etc -exec rm -rf {} +
```

resolves `_seg_find_root` to `"./build"` only. `/etc` is invisible to classification — it's consumed by the swallow-group and never tested against `_re_block_list` or anything else. Because `./build` matches `_re_allow_list` (`head/.claude/hooks/safety/block-destructive-bash.sh:765`, pattern `^(\./[^/*.][^*]*|...)`), the whole find-exec segment is now treated as **allowed** (`head/.claude/hooks/safety/block-destructive-bash.sh:874-875`), even though the actual command recursively deletes matches under `/etc` as well as `./build`.

**Why This Matters:** This is a defense-in-depth safety fence specifically designed to stop catastrophic `rm -rf` execution via `find -exec`. The comment added in this same diff (`head/.claude/hooks/safety/block-destructive-bash.sh:773-775`) documents the "flags before root" gap as an accepted, conservative-by-default limitation ("keeps today's conservative behavior") — but the multi-root case is *not* conservative by default under the new code; it can resolve to an outright ALLOW. That is a strictly worse outcome than the base version, which is conservative-by-default in exactly this case. The old counting loop wasn't dead code — the accompanying old comment ("Group 3 is the FIND ROOT") together with the count check was the mechanism enforcing "exactly one root, or don't trust the shape."
**Required Fix:** Restore a check that the span between `find` and `-exec` contains exactly one bareword token before trusting it as `_seg_find_root` — e.g., keep the old tokenizing loop (it can still use the new, more precise stop-at-first-flag/paren/bang semantics) and reset `_seg_find_root=""` when more than one root-candidate token is found, so multi-root `find` commands fall through to the conservative per-argument ladder as they did before.
**Reference:** CWE-706 (Use of Incorrectly-Resolved Name or Reference) / this repo's own `.claude/rules/stash-safety.md`-style precedent of treating any fence relaxation as requiring explicit test coverage before merge.

---

## Non-Critical Improvements (Recommended — escalated below because of blast radius, see Adversarial Analysis)

### 1. Correctness — `get_completed_sprints()` now globs in non-numbered sprint directories

**File:** `head/.claude/scripts/workflow-state.sh:79-91`
**Issue:** The rewrite replaces the bounded `for ((i = 1; i <= total; i++))` loop (`base/.claude/scripts/workflow-state.sh:83-87`, which only ever checks `a2a/sprint-1` .. `a2a/sprint-${total}`) with `find "${a2a_dir}" -maxdepth 1 -type d -name "sprint-*"` (`head/.claude/scripts/workflow-state.sh:83`). This glob matches **any** directory whose name starts with `sprint-`, including `sprint-bug-*` directories — a real, documented naming convention in this repo for `/bug` fix sprints (see `.claude/rules/skill-invariants.md:62`: "Sprint: `sprint-bug-102`"). Those directories are never counted by `get_total_sprints()` (`head/.claude/scripts/workflow-state.sh:70-76`, which only counts `^## Sprint [0-9]` headings in `sprint.md`), so `completed_sprints` and `total_sprints` are no longer counting the same population.
**Why This Matters:** `determine_state()` (`head/.claude/scripts/workflow-state.sh:148`) does `if [[ "${completed_sprints}" -ge "${total_sprints}" ]] ... then echo STATE_COMPLETE`. If a project has, say, 3 real sprints (2 done, 1 in progress) and one completed `/bug` sprint (`sprint-bug-102/COMPLETED` present), `get_completed_sprints()` now returns 3 (2 real + 1 bug), which is `>= total_sprints (3)`, so the workflow reports `STATE_COMPLETE` — recommending `/deploy-production` — while sprint 3 is still mid-implementation. The same overcounting also skews `get_progress_percentage()` (`head/.claude/scripts/workflow-state.sh:243`, `completed_sprints * 70 / total_sprints`), which can exceed the intended 95% cap. This directly undermines the PR's own stated goal (fixing "historical sprint counting" so completed sprints are tracked correctly) by introducing a different miscount in the opposite direction.
**Required Fix:** Constrain the glob to numeric sprint IDs, e.g. `-name 'sprint-[0-9]*'` with a further guard that the remainder after `sprint-` is all-digits (to also exclude any future `sprint-<n>-suffix` naming), or explicitly exclude `sprint-bug-*`/`sprint-plan-*` before counting `COMPLETED` markers.

### 2. Resilience — Anthropic adapter no longer distinguishes billing-class 4xx errors from request-side 4xx errors

**File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py` (removed `_BILLING_CLASS_TOKENS` / `_is_billing_class_error`, previously at `base/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:43-71`, and both call sites at `base/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:171-176` and `:260-264`)
**Issue:** Before this PR, a 4xx response whose message matched a billing-class token (`credit balance`, `quota_exceeded`, `payment_required`, `insufficient_quota`, etc.) was deliberately raised as `ProviderUnavailableError` instead of `InvalidInputError`. Per this repo's own conventions (`.claude/loa/CLAUDE.loa.md` "Multi-Model Activation": "chain-walk on retryable errors"), `ProviderUnavailableError` is the exception class that triggers cheval's chain-walk-to-next-provider behavior, whereas `InvalidInputError` is terminal (a bad request will fail identically on retry or on a different provider only if the request itself, not the account, is the problem). This PR removes the distinction entirely: every 4xx now raises `InvalidInputError` (`head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139-141, 223`).
**Why This Matters:** Billing-class conditions (out of credits, quota exceeded, invoice overdue) are account-side and orthogonal to whether the *request* was well-formed — they are exactly the "retryable via a different provider" case chain-walk exists for. After this change, if the configured Anthropic account runs out of credit mid-session, cheval will now treat that as a terminal, non-retryable request error rather than failing over to the next configured provider. Neither the diff nor the PR description ("the Anthropic adapter raises one error class for every 4xx") explains why this distinction is being discarded rather than, say, fixed if it had a bug — it reads as a straight capability removal.
**Required Fix:** Either restore the billing-class detection (it can be simplified, e.g., collapsed into a single regex, if the concern was code size) or, if the intent is genuinely to retire this behavior, state why in the PR description and confirm no other adapter/consumer still expects billing-class errors to chain-walk (I could not verify this — `types.py` and sibling provider adapters are not part of this diff's `base/`/`head/` file set, so cross-adapter consistency is unverified from the files available here).

---

## Security Checklist

- [x] No hardcoded secrets or credentials introduced
- [ ] Safety-fence behavior change verified against adversarial input — **NOT verified**: see Critical Issue #1 (multi-root `find -exec` bypass)
- [x] No SQL/XSS injection vectors touched
- [x] Error messages still routed through `sanitize_provider_error_message` in the adapter change (redaction path untouched)
- [ ] Dependencies/consistency across cheval providers — **unverifiable** from the files included in this diff (only `anthropic_adapter.py` is present; sibling adapters and `types.py` are not)

---

## Code Quality Summary

**Strengths:**
- The `find`-exec regex simplification is well-commented and the "flags before root" limitation is explicitly documented as an intentional, conservative gap rather than silently introduced.
- The billing-class removal is a clean, complete deletion (no orphaned imports or dead branches left behind in `anthropic_adapter.py`).
- The `workflow-state.sh` change correctly identifies and fixes a real bug (sequential `1..total` indexing losing track of completed sprints when numbering isn't contiguous/current).

**Areas for Improvement:**
- None of the three changes ship with a test or fixture update visible in this diff, despite each one touching either a security fence or workflow-state logic with directly observable pass/fail behavior (per this repo's own Goal-Driven Execution principle: "Non-trivial logic ... MUST leave at least one runnable check that fails if the logic breaks"). All three changes are exactly this kind of logic.
- Bundling three unrelated fixes (hook regex, adapter error handling, sprint counting) into one PR makes it harder to review, bisect, and revert independently if one turns out to be wrong (as two do here).

---

## Adversarial Analysis

### Concerns Identified (minimum 3)

1. **Security fence regression** — `head/.claude/hooks/safety/block-destructive-bash.sh:776,806-808`
   The new single-token capture drops the old "exactly one root token" validation, so a multi-root `find path1 path2 -exec rm -rf {} +` can resolve to ALLOW as long as the *first* root looks safe, regardless of what the second (or later) root is. See Critical Issue #1.

2. **Workflow-state overcounting** — `head/.claude/scripts/workflow-state.sh:83`
   The `sprint-*` glob matches `sprint-bug-*` directories that this repo's own conventions treat as a distinct category from numbered feature sprints, causing `completed_sprints` to be counted against a different population than `total_sprints`. See Non-Critical Improvement #1 (functionally this is at least as severe as "non-critical" — flagged as escalated).

3. **Silent capability removal without justification** — `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py` (deletion of `_is_billing_class_error` and both call sites)
   The PR description frames this as "raises one error class for every 4xx" as if it were a pure cleanup, but it removes a behavior (billing-class chain-walk) that appears purposeful given the surrounding docstrings and this repo's documented multi-model retry semantics. No test, comment, or PR rationale establishes that this was safe to remove.

4. **No regression tests accompany any of the three changes** — none of `head/`'s three files, nor the diff, include or reference test updates. For a security fence and two pieces of workflow-critical state logic, this is a real gap against this repo's own "Goal-Driven Execution" principle.

### Assumptions Challenged (minimum 1)

- **Assumption**: The engineer assumed that "the root token is `find`'s first argument" is a safe simplification because the flags-before-root case was already conservative — and generalized that assumption to imply single-token capture is safe in general.
- **Risk if wrong**: As shown above, the assumption doesn't extend to the multi-root case: capturing only the first token there is *not* conservative, it's permissive, because a later dangerous root is completely hidden from classification rather than causing a fall-through to AMBIGUOUS.
- **Recommendation**: Make the "exactly one root" invariant explicit again (as the base version did) rather than relying on "first token happens to be representative."

### Alternatives Not Considered (minimum 1)

- **Alternative**: For the `find`-exec change, instead of dropping the token-counting loop, the regex itself could have been tightened to require that group 3 be followed only by flag-looking tokens (`(-\S+|![^-].*)*`) before `-exec`, which would reject multi-root and flags-before-root uniformly at the regex level rather than needing a second pass.
- **Tradeoff**: More complex regex vs. the current split of "simple regex + validation loop" (base) or "simple regex, no validation" (head, this PR). The base approach (regex + loop) is more auditable line-by-line; a single mega-regex would be harder to review but avoids a second BASH_REMATCH pass.
- **Verdict**: The base version's split approach (simple capture + explicit count-based validation) was the right shape and should be restored; this PR's move to "simple capture, no validation" strictly regressed safety for no stated benefit (the PR body doesn't mention the multi-root case at all, suggesting it wasn't considered).

### Adversarial Verdict

**BLOCKING.** The `find`-exec regression (Critical Issue #1) and the sprint-counting overcounting (Non-Critical Improvement #1, escalated) both change observable pass/fail behavior of security- and workflow-critical logic in ways the PR description does not acknowledge. Both must be fixed, with accompanying test/fixture coverage, before this PR can be approved.

---

## Next Steps

1. Restore the multi-root validation in `_re_find_exec_prefix` handling (Critical Issue #1) and add a fixture/test case for `find root1 root2 -exec rm -rf {} +` to the destructive-bash hook's test suite.
2. Scope `get_completed_sprints()`'s directory glob to numeric-only sprint IDs, excluding `sprint-bug-*` and any other non-numbered convention, and add a regression case with a completed bug sprint alongside an in-progress numbered sprint.
3. Either restore billing-class 4xx detection in the Anthropic adapter or justify its removal explicitly (confirm no consumer relies on the chain-walk behavior) in the PR description.
4. Consider splitting this PR into three independent PRs given the unrelated blast radii (safety hook, provider adapter, workflow-state script) — this would have made the two regressions easier to catch in isolation.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":1,"low":0},"sprint_id":"pr-standalone","ts":"2026-09-21T00:00:00Z"} -->
