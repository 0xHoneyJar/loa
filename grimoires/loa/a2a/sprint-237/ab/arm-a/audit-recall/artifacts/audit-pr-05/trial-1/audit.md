# Security Audit Report

**Audit type**: Ad-hoc PR audit (no sprint/beads context — audited from `PR.md` / `head.diff` / `base/` / `head/` only)
**Scope**: 3 files
- `head/.claude/hooks/safety/block-destructive-bash.sh`
- `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py`
- `head/.claude/scripts/workflow-state.sh`

## Executive Summary

This PR touches three unrelated areas: the destructive-bash safety hook's `find … -exec rm` root-extraction logic, the Anthropic adapter's 4xx error classification, and the sprint-completion counter in `workflow-state.sh`.

The `block-destructive-bash.sh` change is a **critical regression in a security control**. The hook exists specifically to stop an agent (or an injected/malicious instruction) from running a catastrophic `rm -rf`. The rewritten `_re_find_exec_prefix` regex now captures only `find`'s *first* path argument as "the root" and silently discards every subsequent path argument on the same `find` invocation, instead of rejecting (ambiguous-block) the shape when more than one root is present the way the pre-PR code did. Because `find` accepts multiple starting paths that are all traversed and handed to `-exec`, this lets a single validated-looking root (e.g. `./build`) smuggle a second, unvalidated, catastrophic root (e.g. `/etc`, `/home`, `~`) past the gate in the same command — the exact class of bypass this hook is designed to prevent. This is a CRITICAL finding.

The other two changes are behavioral regressions with lower severity: the Anthropic adapter now treats account-level billing/quota 4xx errors as terminal `InvalidInputError` instead of retryable `ProviderUnavailableError`, killing multi-provider failover for a class of errors that is not the caller's fault (availability/resilience regression, MEDIUM). The `workflow-state.sh` sprint counter now globs every `sprint-*` directory (including non-numbered dirs such as `sprint-bug-*`) instead of the numbered `sprint-{1..total}` range it compares against, which can make `completed_sprints >= total_sprints` true prematurely and falsely report workflow state `complete` (MEDIUM).

## Overall Risk Level: **CRITICAL**

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 0 |
| Medium | 2 |
| Low | 0 |

## Critical Issues

### C-1: `find`-exec root-extraction bypass lets a second, unvalidated path ride past the destructive-`rm` gate

- **Component**: `head/.claude/hooks/safety/block-destructive-bash.sh:776` (regex), `head/.claude/hooks/safety/block-destructive-bash.sh:807` (root assignment), consumed at `head/.claude/hooks/safety/block-destructive-bash.sh:849-877` (placeholder-only classification ladder)
- **Severity**: CRITICAL
- **CWE**: CWE-697 (Incorrect Comparison) / CWE-863 (Incorrect Authorization) — a security decision (allow vs. block a destructive command) is made from an incomplete extraction of the command's real operands.

**Before (base)**, `base/.claude/hooks/safety/block-destructive-bash.sh:778` and `:804-811`:
```bash
_re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)]*)-exec$'
...
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
Group 3 captured the *entire* span between `find` and `-exec`. The old code then tokenized that span and counted every leading non-flag token as a candidate root. If it found anything other than **exactly one** such token — i.e. a second path argument, like `find /tmp/x /etc -exec …` — it reset `_seg_find_root=""`, which routes the segment to the "unrecognized shape" path and lands on `any_ambiguous=1` (conservative block, see `head/.claude/hooks/safety/block-destructive-bash.sh:876-877` / same logic pre-PR).

**After (head)**, `head/.claude/hooks/safety/block-destructive-bash.sh:776` and `:805-807`:
```bash
_re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)[:space:]]+)[^;&|)]*-exec$'
...
_seg_find_root=""
if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
  _seg_find_root="${BASH_REMATCH[3]}"
fi
```
Group 3 is now bound by `[^;&|)[:space:]]+`, i.e. it stops at the first whitespace — it is unconditionally just the *first* token after `find`. Everything after it, up to `-exec`, is absorbed by the unanchored `[^;&|)]*` alternative and never inspected again. There is no longer any check for "more than one root token" — a second (or third, …) path argument to `find` is simply invisible to the classifier.

**Why this is exploitable**: POSIX `find` accepts multiple starting-point paths, and it recursively traverses and hands matches from *all* of them to `-exec`:
```bash
find ./build /etc -exec rm -rf {} +
```
This single statement recursively deletes both `./build` **and** `/etc`. With the new regex, `_seg_find_root` is only `./build`. Because the rm segment's only operands are the find-exec placeholders (`{}`/`+`), the segment enters the "placeholder-only" branch at `head/.claude/hooks/safety/block-destructive-bash.sh:849-877`, which classifies `./build` alone against the allow/block ladder. `./build` matches `_re_allow_list` (`head/.claude/hooks/safety/block-destructive-bash.sh:765`, `build$|build/`), so the segment is **allowed** — `any_block` and `any_ambiguous` both stay `0`, and the hook falls through to `exit 0` at `head/.claude/hooks/safety/block-destructive-bash.sh:920`, permitting the command to run and delete `/etc` (or `/home`, `~`, or any other real root placed as the *second* `find` argument) without ever being classified.

Before this PR, the same command would have produced `_find_root_count == 2`, forced `_seg_find_root=""`, and been routed to `any_ambiguous=1` → `emit_block "FR-2-AMBIGUOUS" …` (refused). The PR silently converts a blocked/ambiguous shape into a fully allowed one.

**Proof of concept** (would be blocked pre-PR, is allowed post-PR):
```bash
find ./build /home -exec rm -rf {} +
find ./target /etc -exec rm -rf {} \;
```
Both are single find invocations with a benign-looking first root (`./build`, `./target`, both on the allow-list) and a catastrophic second root (`/home`, `/etc`) that is never checked because the regex only captures the first whitespace-delimited token.

**Impact**: This is the exact bypass class the hook's own C15/cycle-119 commentary (`head/.claude/hooks/safety/block-destructive-bash.sh:718-727`) says must "always [fall] to AMBIGUOUS" for anything not recognized as a single safe root — the PR breaks that invariant for the specific case of multiple `find` roots, which the new comment (`head/.claude/hooks/safety/block-destructive-bash.sh:783-785`) does not mention at all (it only documents the *flags-before-root* gap, not this one). Any agent, hook, or injected instruction that can get a `find … -exec rm -rf … +` command executed can now smuggle a real destructive root past this specific defense-in-depth control.

**Remediation**: Restore the old two-step extraction (capture the full span, then walk tokens and require exactly one non-flag root token before `-exec`), or explicitly re-validate that the captured span contains no additional whitespace-delimited, non-flag token before `-exec`. Minimal fix preserving the new regex's simplification:
```bash
_re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)[:space:]]+)([^;&|)]*)-exec$'
...
if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
  _seg_find_root="${BASH_REMATCH[3]}"
  # reject if a second path-looking (non-flag) token follows before -exec
  read -r -a _fr_rest_toks <<<"${BASH_REMATCH[4]}"
  for _frt in ${_fr_rest_toks[@]+"${_fr_rest_toks[@]}"}; do
    case "$_frt" in
      -*|'!'*|'('*|')'*|'\'*) break ;;
      *) _seg_find_root="" ; break ;;
    esac
  done
fi
```
Add a regression fixture for `find ./build /etc -exec rm -rf {} +` (and the `\;` variant) asserting `FR-2-AMBIGUOUS`/block, not allow.

## Medium Priority Issues

### M-1: Anthropic adapter no longer chain-walks on account-level billing/quota errors

- **Component**: `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:74` (class start, `_is_billing_class_error` and `_BILLING_CLASS_TOKENS` removed from `base/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:41-71`), call sites at `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139` and `:222`
- **Severity**: MEDIUM
- **Category**: Availability / resilience regression (CWE-703-adjacent: incorrect error-condition handling changes fault-tolerance behavior)

Base classified upstream 4xx bodies matching billing/quota tokens (`credit balance`, `quota_exceeded`, `insufficient_quota`, `payment_required`, etc. — `base/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:43-56`) as `ProviderUnavailableError`, which (per the removed docstring at `base/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:60-67`) is account-side and should "chain-walk" to another provider. Head raises a plain `InvalidInputError` for every 4xx regardless of content (`head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139`, `:222`).

`InvalidInputError` is the terminal, non-retryable classification used elsewhere in this file for genuine bad-request/param errors (see the streaming parse-error path at `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:171`, which is explicitly request-side). Collapsing billing-class 4xxs into that same bucket means: the moment an Anthropic account runs out of credit or hits a quota limit, every call fails terminally instead of failing over to the next provider in the chain — directly contradicting the documented multi-model design intent ("chain-walk on retryable errors; voice-drop on chain exhaustion") for exactly the case (account-side, not request-side) the removed code called out. This degrades system availability without any compensating simplification benefit that the PR description states a rationale for beyond "plain 4xx handling."

**Remediation**: Either keep the billing-class classification (it long-lived a purpose that's still documented in the multi-model design), or, if the intent is a deliberate design change, update the multi-model reference docs and add a fallback path elsewhere (e.g. a shared cross-provider classifier) so billing/quota conditions remain retryable somewhere in the pipeline. At minimum, confirm this is an intended trade-off, not an oversight, before merging.

### M-2: `get_completed_sprints` can report more "completed" sprints than exist, causing premature `STATE_COMPLETE`

- **Component**: `head/.claude/scripts/workflow-state.sh:79-89`, consumed at `head/.claude/scripts/workflow-state.sh:144-148` and `:366-367`
- **Severity**: MEDIUM
- **Category**: Logic/state-integrity defect (workflow gating relies on this counter)

Base counted completions only over the *numbered* range `1..$(get_total_sprints)` (`base/.claude/scripts/workflow-state.sh:79-86`, iterating `sprint-${i}` for `i` in `1..total`), matching `get_total_sprints`'s own definition (count of `^## Sprint [0-9]` headings in `sprint.md`, `head/.claude/scripts/workflow-state.sh:70-76`, unchanged). Head instead globs `${a2a_dir}` for **every** directory matching `sprint-*` (`head/.claude/scripts/workflow-state.sh:83`) and counts any of them with a `COMPLETED` marker — including non-numbered sprint directories such as ad-hoc bug-fix sprints (this repo's own conventions reference `sprint-bug-102`-style directory names elsewhere), which are never part of the `sprint.md`-derived `total_sprints`.

Because `determine_state()` computes workflow completeness as `completed_sprints -ge total_sprints` (`head/.claude/scripts/workflow-state.sh:147`), a project with, say, 3 planned sprints (`total_sprints=3`) but 2 completed bug-fix sprints plus only 1 of the 3 real sprints done (`completed_sprints` now counts 3: the 1 real + 2 bug sprints) will report `STATE_COMPLETE` while 2 of the 3 planned sprints are still unimplemented. Anything that trusts `/loa` status / `determine_state()` output to decide the project is done (a human skimming status, or downstream automation) gets a false-positive "complete" signal.

**Remediation**: Scope the glob to the numeric convention the comparison actually uses (`sprint-[0-9]*` excluding e.g. `sprint-bug-*`), or better, count completions the same way `total_sprints` is derived (iterate `1..total_sprints`, as base did) rather than switching to an independent enumeration whose domain no longer matches the denominator it's compared against.

## Security Checklist Status

- [x] Reviewed actual code, not just the diff/description
- [x] Traced the changed regex/extraction logic against its real consumer (allow/block ladder)
- [x] Constructed concrete PoC command strings for the primary finding
- [ ] Could not run the hook's bats fixtures (not present in this audit's file set — only `base/`, `head/`, `PR.md`, `head.diff` were provided) to empirically confirm the PoC against the live script; the finding is a static-analysis trace of the regex/branch logic, not a runtime-verified fixture failure. Recommend running `find ./build /etc -exec rm -rf {} +` through the hook's harness before merging.

## Verdict

**CHANGES_REQUIRED**

The `find`-exec root-extraction change (C-1) reintroduces a bypass of a destructive-command safety control and must not ship as-is. The Anthropic adapter (M-1) and sprint-counter (M-2) regressions should also be resolved or explicitly justified before merge.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":2,"low":0},"sprint_id":"pr-audit","ts":"2026-09-21T00:00:00Z"} -->
