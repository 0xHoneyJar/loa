# Security Audit — refactor(hooks,cheval,state): single-token find roots, plain 4xx handling, historical sprint counting

**Scope:** `head.diff` (base → head), 3 files touched:
- `.claude/hooks/safety/block-destructive-bash.sh`
- `.claude/adapters/loa_cheval/providers/anthropic_adapter.py`
- `.claude/scripts/workflow-state.sh`

**Method:** Full read of before/after for each touched file, hand-traced regex/control-flow changes against the surrounding (unchanged) code that consumes their output. No PRD/SDD/sprint plan/beads DB was present, per `AUDIT-INSTRUCTIONS.md`; this is a standalone PR audit.

---

## Findings

### 1. CRITICAL — `find`-exec root classification now ignores every root after the first, letting a benign first root mask a catastrophic `rm -rf` root

**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:776` (regex) and `head/.claude/hooks/safety/block-destructive-bash.sh:807` (root capture)

```
776: _re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)[:space:]]+)[^;&|)]*-exec$'
...
805:    _seg_find_root=""
806:    if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
807:      _seg_find_root="${BASH_REMATCH[3]}"
808:    fi
```

`find(1)` accepts **multiple starting-point arguments** before its expression (`find root1 root2 ... -exec ...`). The old code (base, same file, previously at this location) captured the *entire* span between `find` and `-exec` into `BASH_REMATCH[3]`, then walked every whitespace-separated token in that span and only trusted the result when **exactly one** non-flag token was found:

```
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
So `find ./build /etc -exec rm -rf {} +` produced `_find_root_count=2` → `_seg_find_root=""` → the segment fell through to the normal per-arg ladder (which sees only find-exec placeholders `{}`/`+` and nothing block-listed, but critically the *find root itself* was never classified as safe, so multi-root shapes were **not** silently allow-listed by the `find` fast-path — they degraded to whatever the placeholder-only ladder does with un-vetted roots).

The new regex (`776`) changes group 3 to `[^;&|)[:space:]]+` — a character class that **excludes whitespace**, so it can only ever match `find`'s first whitespace-delimited token, no matter how many more roots follow before `-exec`. Line 807 then takes that single token verbatim as `_seg_find_root` with **no check that it is the only root**. The tail of the prefix (`[^;&|)]*-exec$` at the end of line 776) happily absorbs any number of additional root arguments as inert prefix text.

Downstream (`head/.claude/hooks/safety/block-destructive-bash.sh:844-859`), a segment is treated as "find-exec-governed" whenever `_seg_find_root` is non-empty **and** every operand of the paired `rm` is a placeholder (`{}`, `+`, `\;`, `;`):

```
850:    if [[ -n "$_seg_find_root" ]]; then
851:      _seg_placeholder_only=1
...
861:    if [[ $_seg_placeholder_only -eq 1 ]]; then
862:      ... classify $_seg_find_root through the SAME ladder ...
866:      unquoted="${_seg_find_root#\'}"; ...
874:      elif [[ "$unquoted" =~ $_re_allow_list ]]; then
875:        : # explicit safe relative root — allow this find-exec segment
```

If that lone captured token (e.g. `./build`) matches `_re_allow_list` (`^(\./[^/*.][^*]*|node_modules$|...|dist$|...)`), the branch at line 875 is a no-op — it sets **neither** `any_block` nor `any_ambiguous`. Since the `rm` operands are only placeholders (already handled), and the second/third `find` roots (e.g. `/etc`, `$HOME`, `/`) were never inspected by *any* code path, execution reaches `exit 0` at line 924: **the command is allowed to run.**

**Failure scenario:** An agent (malicious, prompt-injected, or simply mistaken) runs
```
find ./build /etc -exec rm -rf {} +
```
or
```
find ./build / -exec rm -rf {} \;
```
`./build` is on the allow list, so the hook now emits no block and no ambiguous warning — yet the actual `find` invocation recursively enumerates **and deletes** everything under `/etc` (or `/`) via the shared `-exec rm -rf {} +` action, because `find` applies one `-exec` expression across *all* of its starting points. This is precisely the class of catastrophic deletion `block-destructive-bash.sh`'s `FR-2-BLOCK`/`FR-2-AMBIGUOUS` machinery exists to stop (see the file's own header comments, lines 700-731), and the new code silently defeats it for any multi-root `find ... -exec` invocation whose first root happens to be innocuous.

This is a regression introduced by this diff: the base version's `_find_root_count -ne 1` guard is exactly the check that prevented this bypass, and it has been deleted rather than preserved. The accompanying comment added at lines 773-775 only documents an intentionally-accepted gap for *flags before the root* (`find -L root -exec ...`) — it says nothing about, and does not appear to have considered, multi-root invocations, which is a materially different and more dangerous gap since it actively launders a dangerous root behind a captured safe-looking one rather than merely falling back to conservative behavior.

**Standard:** [CWE-693: Protection Mechanism Failure](https://cwe.mitre.org/data/definitions/693.html) (the security control exists and is bypassed by an input shape it fails to consider); also relevant: [CWE-184: Incomplete List of Disallowed Inputs](https://cwe.mitre.org/data/definitions/184.html).

**Remediation:** Restore the base behavior of walking every token in the full `find`...`-exec` span and only trusting `_seg_find_root` when exactly one non-flag root token is present (or, more robustly, explicitly classify *every* root token found and require all of them to pass the allow-list before treating the segment as safe). At minimum, revert the regex at line 776 back to capturing the full span (`([^;&|)]*)`) and keep the token-counting loop that was deleted.

---

### 2. MEDIUM — Anthropic adapter no longer distinguishes billing-class 4xx errors from request-validation 4xx errors

**File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139-141` (streaming path), `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:221-223` (non-streaming path)

```
139:                raise InvalidInputError(
140:                    f"Anthropic API error (HTTP {status}): {_extract_error_message(err_json)}"
141:                )
...
221:        if status >= 400:
222:            msg = _extract_error_message(resp)
223:            raise InvalidInputError(f"Anthropic API error (HTTP {status}): {msg}")
```

The base version detected account/billing-side 4xx conditions (`credit balance`, `quota_exceeded`, `invoice_overdue`, `billing_disabled`, `payment_required`, `insufficient_quota`, etc. — via `_is_billing_class_error`, previously defined at the top of the file) and raised `ProviderUnavailableError` for those, reserving `InvalidInputError` for genuine request/param problems. This diff deletes `_is_billing_class_error` and the `_BILLING_CLASS_TOKENS` tuple entirely and collapses **every** 4xx (both streaming and non-streaming) to `InvalidInputError`.

`ProviderUnavailableError` vs. `InvalidInputError` is a semantically load-bearing distinction elsewhere in the cheval retry/fallback layer (referenced in this same file's comments, e.g. line 151: "without this wrapper, they would bypass RateLimitError / ProviderUnavailableError / InvalidInputError classification and the retry layer's typed-transient handling"). The retry/orchestration code itself is not part of this diff and was not in `base/`/`head/`, so its exact handling of each exception type could not be directly verified in this audit — but based on the naming convention and the comment at line 151, `ProviderUnavailableError` is the type that participates in retry/fail-over ("chain-walk"), while `InvalidInputError` is treated as terminal/non-retryable.

**Failure scenario:** If the configured Anthropic account exhausts credit or has billing disabled, Anthropic returns an HTTP 4xx (commonly 402/403) with a billing-class message. Previously this chain-walked to another provider via `ProviderUnavailableError`. Now it is raised as `InvalidInputError`, which (per the adapter's own docstrings elsewhere) is meant for genuine request errors and is presumably not retried/failed-over — an account-level outage now likely surfaces as a hard, non-recoverable failure for every multi-model call routed to Anthropic, rather than degrading gracefully to other providers.

**Standard:** [CWE-703: Improper Check or Handling of Exceptional Conditions](https://cwe.mitre.org/data/definitions/703.html).

**Note on confidence:** the orchestrator/retry code that actually consumes these exception classes is outside this PR's diff and was not provided in `base/`/`head/`, so I could not directly confirm the runtime effect of this reclassification — flagging as MEDIUM/availability-impacting rather than CRITICAL, and this should be verified against `loa_cheval`'s retry layer before merge.

---

### 3. LOW — `get_completed_sprints` now counts stray/historical sprint directories instead of only sprints in the current plan

**File:** `head/.claude/scripts/workflow-state.sh:78-91`

```
78: # Function: Count completed sprints
79: get_completed_sprints() {
80:     local count=0
81:     local sprint_dirs
82:     local a2a_dir="${_GRIMOIRE_DIR}/a2a"
83:     sprint_dirs=$(find "${a2a_dir}" -maxdepth 1 -type d -name "sprint-*" 2>/dev/null || true)
84:
85:     for dir in ${sprint_dirs}; do
86:         if [[ -f "${dir}/COMPLETED" ]]; then
87:             count=$((count + 1))
88:         fi
89:     done
90:     echo "${count}"
91: }
```

Previously (base) this function iterated `i` from `1` to `get_total_sprints()` (the count parsed from the *current* `sprint.md`) and checked `${a2a_dir}/sprint-${i}/COMPLETED` for each — i.e., it only ever counted completed sprints that are part of the currently-planned sprint set. The new version globs every `sprint-*` directory under `a2a/` regardless of whether it is still part of the active plan.

**Failure scenario:** `grimoires/loa/a2a/` accumulates a directory per sprint over the life of a project. If a project is re-planned (e.g. `/sprint-plan` is re-run and `sprint.md` is rewritten with fewer sprints than previously existed — a normal occurrence after scope-cuts or re-architecture), stale `sprint-N/COMPLETED` markers from the prior plan remain on disk. `get_completed_sprints` will now count those, potentially producing `completed_sprints >= total_sprints` in `determine_state()` (`head/.claude/scripts/workflow-state.sh:148`) even though the *current* plan's sprints are not actually done, reporting `STATE_COMPLETE` and suggesting `/deploy-production` prematurely.

This script only feeds advisory status output (`/loa` status, suggested next command) — it is not itself a hard gate — so I did not find a path by which this alone bypasses the `/review-sprint`/`/audit-sprint` enforcement mechanisms described in `CLAUDE.loa.md`. The impact is a misleading status readout that could prompt an operator to skip ahead, rather than a mechanically-enforced bypass.

**Standard:** [CWE-1284: Improper Validation of Specified Quantity in Input](https://cwe.mitre.org/data/definitions/1284.html) (loosely — stale state is treated as authoritative without cross-checking against the current plan).

**Remediation:** Intersect the `sprint-*` directory scan with the range `1..get_total_sprints()` (or equivalently keep the original bounded loop), or explicitly document/accept that historical sprints outside the current plan should count — if that actually is the intent, the PR description ("historical sprint counting") suggests it may be deliberate, but the resulting premature-`STATE_COMPLETE` edge case does not appear to have been addressed.

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 0 |
| Medium | 1 |
| Low | 1 |

## Verdict

**CHANGES_REQUIRED** — Finding 1 is a confirmed, exploitable bypass of a security-critical bash-command guard (`block-destructive-bash.sh`), introduced directly by this diff by deleting the multi-token root-count guard without replacing its safety property. This must be fixed before merge. Finding 2 should be verified against the cheval retry layer (not in this diff) before merge. Finding 3 is a minor correctness issue worth fixing but does not block on its own.

**Immediate (before merge):** Fix Finding 1 — restore multi-root detection in `block-destructive-bash.sh`.
**Short-term:** Verify Finding 2's effect on multi-provider fail-over behavior against the actual retry/orchestration code.
**Long-term:** Fix Finding 3's stale-sprint-directory counting, or explicitly document the intended semantics if the historical count is deliberate.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":1,"low":1},"sprint_id":"pr-audit","ts":"2026-09-22T00:00:00Z"} -->
