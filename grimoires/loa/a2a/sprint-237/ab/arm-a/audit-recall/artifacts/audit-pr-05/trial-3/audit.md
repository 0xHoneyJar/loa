# Security Audit Report — PR: refactor(hooks,cheval,state): single-token find roots, plain 4xx handling, historical sprint counting

**Audit date**: 2026-09-21
**Scope**: `head.diff` (3 files) — `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/adapters/loa_cheval/providers/anthropic_adapter.py`, `.claude/scripts/workflow-state.sh`
**Auditor**: Paranoid Cypherpunk Auditor (auditing-security)

## Executive Summary

This PR bundles three unrelated "refactor" changes. Two are low-risk simplifications. The third — the rewrite of the `find ... -exec rm` root-extraction logic in the destructive-bash safety hook — introduces a **critical bypass of the primary guard that blocks catastrophic `rm -rf` commands**. The new regex captures only `find`'s *first* start-path as "the root" and silently drops every subsequent start-path from classification. Because POSIX `find` accepts multiple start-paths (`find path1 path2 -exec ...`, searching and acting on both trees), an attacker (or an LLM agent following an injected instruction) can front-load an innocuous, allow-listed path and hide a catastrophic one behind it — e.g. `find ./build /etc -exec rm -rf {} \;` or `find ./x / -exec rm -rf {} \;` — and the hook will now **allow** the command to execute, deleting `/etc` or `/` under a `-rf` exec. The commit's own inline comment acknowledges a narrower gap (`find -L root -exec`) but does not mention — and the PR does not test — this much larger multi-root gap, which the code being replaced explicitly and correctly defended against.

The Anthropic adapter change removes billing-class 4xx detection, which degrades the documented multi-model chain-walk/failover behavior (not a directly exploitable vulnerability, but a resilience regression against this repo's own architecture doc). The `workflow-state.sh` change loosens completed-sprint counting to glob all `sprint-*` directories rather than the validated `1..total_sprints` range, which can inflate the reported completed-sprint count and can flip workflow status to "complete" prematurely.

## Overall Risk Level: **CRITICAL**

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 0 |
| Medium | 2 |
| Low | 0 |

## Critical Issues

### C-1: `find`-exec safety-hook regression allows catastrophic `rm -rf` bypass via multi-root `find`

- **Severity**: CRITICAL
- **Component**: `head/.claude/hooks/safety/block-destructive-bash.sh:776` (new regex), `:805-807` (root capture), `:850-878` (classification of the captured root)
- **CWE**: CWE-693 (Protection Mechanism Failure), CWE-20 (Improper Input Validation)

**Description**

The old extraction logic (`base/.claude/hooks/safety/block-destructive-bash.sh:775-789`) captured the *entire* span between `find` and `-exec` into group 3, then walked every whitespace-separated token in that span and only accepted it as a validated "find root" when **exactly one** plain (non-flag) token preceded any flag/paren/negation token:

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

If `find` was given more than one start-path (a normal, documented POSIX `find` usage: `find path1 path2 -exec ...`), `_find_root_count` would be `2` (or more) and `_seg_find_root` was discarded (`=""`). With an empty root, the code fell through to `_seg_placeholder_only=0` (`head/.claude/hooks/safety/block-destructive-bash.sh:850`), which routes the `rm` invocation's own arguments through the per-arg ladder. Since a `find -exec rm -rf {} \;` invocation has no real operand (only placeholders `{}`/`+`/`\;`), none of those placeholder tokens match the dotdot/block/allow-exclude/allow lists, so the segment fell to the final `else` branch and was marked **ambiguous → blocked** (`head/.claude/hooks/safety/block-destructive-bash.sh:907-908`). In other words, the *old* code was safe-by-default for multi-root `find`: an unrecognized shape was refused, never allowed.

The new regex changes group 3 to `([^;&|)[:space:]]+)` (`head/.claude/hooks/safety/block-destructive-bash.sh:776`):

```bash
_re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)[:space:]]+)[^;&|)]*-exec$'
```

The character class excludes whitespace, so the capture is forced to stop at the **first space** — i.e. it always captures only `find`'s first start-path token, and the code now uses that token directly and unconditionally as `_seg_find_root` (`head/.claude/hooks/safety/block-destructive-bash.sh:805-807`):

```bash
if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
  _seg_find_root="${BASH_REMATCH[3]}"
fi
```

Everything between that first token and `-exec` — including any additional `find` start-paths — is swallowed by the unanchored `[^;&|)]*` and never inspected. If the `rm` invocation has no real operand of its own (only find-exec placeholders), the segment is now classified as `_seg_placeholder_only=1` and the *first token only* is run through the block/allow-list classifier (`head/.claude/hooks/safety/block-destructive-bash.sh:850-878`). A first token that lands in the allow-list (e.g. `./build`, `./x`, `dist`, `target`, …, per `_re_allow_list` at `head/.claude/hooks/safety/block-destructive-bash.sh:765`) causes the **entire command to be allowed**, regardless of what the second (or third, …) `find` start-path is.

**Impact**

Any command of the shape `find <allow-listed-path> <catastrophic-path> -exec rm -rf {} \;` now bypasses the destructive-bash guard entirely and executes. This is a full defeat of the hook's purpose for the most dangerous command shape it exists to catch (`rm -rf` via `find -exec`).

**Proof of Concept**

```bash
# First start-path "./build" is allow-listed and passes the classifier;
# the second start-path "/etc" is never inspected — command is ALLOWED
# and recursively force-deletes everything under /etc.
find ./build /etc -exec rm -rf {} \;

# Same shape targeting the filesystem root — "./x" is allow-listed,
# "/" is invisible to the new classifier.
find ./x / -exec rm -rf {} \;

# Same shape targeting $HOME.
find ./build ~ -exec rm -rf {} \;
```

Trace through `head/.claude/hooks/safety/block-destructive-bash.sh` for `find ./build /etc -exec rm -rf {} \;`:
1. `_re_find_exec_prefix` matches with `BASH_REMATCH[3] = "./build"` (line 776/806-807).
2. `rm_args` = `(-rf {} \;)`; stripping the `-rf` flag leaves only the placeholder `{}` — `_seg_placeholder_only` stays `1` (line 850-858).
3. `unquoted="./build"` matches `_re_allow_list`'s `^\./[^/*.][^*]*` branch (line 874) → the `elif` body is a no-op comment (`: # explicit safe relative root — allow this find-exec segment`, line 875) → no block, no ambiguous flag is set.
4. `any_block=0`, `any_ambiguous=0` → the function falls through to `exit 0` (line 924): **command allowed**, `/etc` is deleted.

For comparison, `base/.claude/hooks/safety/block-destructive-bash.sh` on the identical input produces `_find_root_count=2` (both `./build` and `/etc` are plain tokens) → `_seg_find_root=""` → the segment falls into the per-arg ladder on the `rm` placeholders → none match anything → `any_ambiguous=1` → **command blocked** with `FR-2-AMBIGUOUS`.

**Remediation**

Restore multi-token detection before trusting a single root, e.g. keep capturing the full span (as the old code did) and re-validate that exactly one plain path token precedes `-exec`, or — more robustly — explicitly reject (mark ambiguous) any find-exec prefix whose span contains more than one non-flag token, rather than silently narrowing the capture group to "whatever the first token happens to be." At minimum, extend the new inline comment (`head/.claude/hooks/safety/block-destructive-bash.sh:773-775`) to acknowledge this gap is not "flags before root" but "any additional start-path after root," and add fixture coverage (`find a b -exec rm -rf {} \;` style cases) proving the ambiguous/block outcome is preserved before merging.

**References**: CWE-693, CWE-20; OWASP "Broken Access Control" (guard bypass) analogue for local safety tooling.

## Medium Issues

### M-1: Removal of billing-class 4xx detection breaks documented multi-model chain-walk/failover behavior

- **Severity**: MEDIUM
- **Component**: `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139-141` (streaming path), `:221-223` (non-streaming path)
- **CWE**: CWE-703 (Improper Check or Handling of Exceptional Conditions)

**Description**

The PR deletes `_is_billing_class_error()` and its call sites (`base/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:43-71, 81-86, 97-101`), which previously distinguished account-side billing failures (credit balance exhausted, quota exceeded, payment required, etc.) from request-side param errors. Billing-class 4xx responses were raised as `ProviderUnavailableError` (retryable — chain-walks to another provider per this repo's documented cheval behavior: *"chain-walk on retryable errors; voice-drop on chain exhaustion"*, `.claude/loa/CLAUDE.loa.md` "Multi-Model Activation"). After this change, **every** 4xx from Anthropic — including billing-class ones — raises `InvalidInputError`, which is treated as terminal/non-retryable.

**Impact**

When an Anthropic account hits a billing condition (e.g. `credit_balance` exhausted), requests will now fail terminally instead of chain-walking to the next provider in the configured chain. This does not expose data or allow unauthorized access, but it silently degrades the availability/resilience guarantee the multi-model substrate is documented to provide, and could surface as unexplained hard failures instead of graceful provider fallback.

**Remediation**

Either keep a (more precisely scoped) billing-class detector and route it through `ProviderUnavailableError`, or make the terminal/retryable classification driven by the Anthropic error `type` field (e.g. `"error": {"type": "billing_error", ...}` if provided) instead of ad hoc substring matching on the message — but do not drop the distinction outright while the architecture doc still promises chain-walk-on-retryable behavior.

### M-2: `get_completed_sprints` now counts all `sprint-*` directories, not the validated `1..total_sprints` range

- **Severity**: MEDIUM
- **Component**: `head/.claude/scripts/workflow-state.sh:79-91`, consumed at `:148`, `:367`, `:401`, `:433`
- **CWE**: CWE-682 (Incorrect Calculation)

**Description**

`base/.claude/scripts/workflow-state.sh:76-84` counted completions by iterating `i = 1..$(get_total_sprints)` and checking `sprint-${i}/COMPLETED` — bounded to sprints that actually exist in the current `sprint.md` plan. The new version globs every directory matching `${a2a_dir}/sprint-*` (`head/.claude/scripts/workflow-state.sh:83`) and counts any with a `COMPLETED` marker, with no bound against `total_sprints`. This also matches non-numeric sprint directories such as `sprint-bug-105` created by `/bug` (per `.claude/loa/CLAUDE.loa.md` "ALWAYS Rules"), and any stale/archived sprint directory left over from a prior cycle that still carries a `COMPLETED` marker.

**Impact**

`completed_sprints` can now exceed `total_sprints`. The consumer at `head/.claude/scripts/workflow-state.sh:148` — `if [[ "${completed_sprints}" -ge "${total_sprints}" ]] && [[ "${total_sprints}" -gt 0 ]]; then echo "${STATE_COMPLETE}"` — can therefore report `STATE_COMPLETE` before all sprints in the active plan are actually done, if enough bug-fix or stale sprint directories with `COMPLETED` markers exist. This is a status-reporting integrity bug (surfaced via `/loa`), not a code-execution or data-exposure vulnerability, but it can mislead an operator (or an autonomous run) about true completion state.

**Remediation**

Bound the count to sprint directories whose numeric suffix falls in `1..total_sprints`, or explicitly exclude non-numeric suffixes (`sprint-bug-*`, etc.) from this tally, matching the semantics of the loop it replaced.

## Security Checklist Status

- [x] Secrets & credentials — not touched by this diff (out of scope)
- [ ] **Destructive-command guard integrity** — FAILED (C-1)
- [ ] Error-handling completeness / failover semantics — DEGRADED (M-1)
- [ ] State-reporting correctness — DEGRADED (M-2)
- [x] No new injection surface in the Python adapter (message extraction still routed through `sanitize_provider_error_message`)

## Verdict

**CHANGES_REQUIRED**

C-1 must be fixed (restore multi-root-safe classification, add fixture coverage for `find root1 root2 -exec rm -rf {} \;` shapes) before this PR can land — it is a live bypass of the repo's primary destructive-bash safety control. M-1 and M-2 should be addressed or explicitly deferred with a tracked follow-up before merge.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":2,"low":0},"sprint_id":"pr-audit","ts":"2026-09-21T00:00:00Z"} -->
