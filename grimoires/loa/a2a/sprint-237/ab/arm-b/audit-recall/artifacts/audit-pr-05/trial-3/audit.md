# Security Audit — refactor(hooks,cheval,state): single-token find roots, plain 4xx handling, historical sprint counting

## Scope

PR touches three files, no sprint plan / beads / a2a artifacts present (standalone PR audit per `AUDIT-INSTRUCTIONS.md`):

- `.claude/hooks/safety/block-destructive-bash.sh` — `find ... -exec rm` root-extraction logic (FR-2 guard)
- `.claude/adapters/loa_cheval/providers/anthropic_adapter.py` — removal of billing-class 4xx classification
- `.claude/scripts/workflow-state.sh` — `get_completed_sprints` rewritten to scan `sprint-*` dirs instead of iterating `1..total`

## Findings

### 1. CRITICAL — `find`-with-multiple-roots bypasses the destructive-`rm` guard (System-Zone safety control)

**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:776`, consequence at `head/.claude/hooks/safety/block-destructive-bash.sh:807` and `head/.claude/hooks/safety/block-destructive-bash.sh:861-877`

```
776:  _re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)[:space:]]+)[^;&|)]*-exec$'
...
807:      _seg_find_root="${BASH_REMATCH[3]}"
```

Group 3 of `_re_find_exec_prefix` now matches only the **first whitespace-delimited token** after `find` (`[^;&|)[:space:]]+`, explicitly excluding whitespace from the character class), and line 807 assigns that single token directly to `_seg_find_root` with no further validation.

`find` accepts **multiple starting paths** before its expression (`find path1 path2 ... -exec rm -rf {} +` is valid POSIX/GNU `find` syntax and recurses `-exec` into *every* listed path). The pre-change code (see `base/.claude/hooks/safety/block-destructive-bash.sh`) captured the *entire* span between `find` and `-exec`, word-split it, and walked every leading non-flag token, clearing `_seg_find_root` back to empty unless **exactly one** plain root token was present:

```
-      read -r -a _find_span_toks <<<"${BASH_REMATCH[3]}"
-      _find_root_count=0
-      for _ftok in ${_find_span_toks[@]+"${_find_span_toks[@]}"}; do
-        case "$_ftok" in
-          -*|'!'*|'('*|')'*|'\'*) break ;;
-          *) _find_root_count=$((_find_root_count + 1)); _seg_find_root="$_ftok" ;;
-        esac
-      done
-      [[ "$_find_root_count" -ne 1 ]] && _seg_find_root=""
```

That guard meant a multi-root invocation like `find ./build /etc -exec rm -rf {} +` previously found `_find_root_count=2`, cleared `_seg_find_root`, so the segment was **not** treated as find-exec-governed and instead fell through to the placeholder args (`{}`/`+`) being classified individually at `head/.claude/hooks/safety/block-destructive-bash.sh:908` — which hit the final `# Ambiguous → conservative block` branch and was **blocked**.

With the new single-token capture, the same command yields `_seg_find_root="./build"` only; `/etc` is silently dropped from consideration. Since the rm segment's only operands are find-exec placeholders (`{}`/`+`), `_seg_placeholder_only` is set at `head/.claude/hooks/safety/block-destructive-bash.sh:861`, and the segment is classified **solely** on `./build`, which matches the relative-path allow-list at `head/.claude/hooks/safety/block-destructive-bash.sh:875` (`_re_allow_list`) — so the whole statement is **allowed to execute**, including the recursive `rm -rf` under `/etc` via the second, unchecked root.

**Failure scenario:** an agent (or a prompt-injected instruction) runs
`find ./build /etc -exec rm -rf {} +`
(or any combination pairing one allow-listed root with a second catastrophic root — `~`, `$HOME`, `/usr`, `/var`, another absolute path, a `../` escape, etc.). The PreToolUse hook's job is precisely to block destructive `rm -rf` against such paths; this statement now passes with exit 0 and the hook prints nothing, executing an unbounded recursive delete against the unchecked second root. This is a direct regression of the guard `block-destructive-bash.sh` exists to enforce, and it is **not** the documented gap called out in the new comment at line 773-775 ("flags before root … is not covered, documented gap") — that comment only discusses a flags-before-root case; it says nothing about, and does not defend, the multiple-plain-roots case, which the prior implementation explicitly handled by clearing the root and falling back to conservative-block.

- **CWE:** [CWE-693: Protection Mechanism Failure](https://cwe.mitre.org/data/definitions/693.html) and [CWE-20: Improper Input Validation](https://cwe.mitre.org/data/definitions/20.html) — the safety hook's root-extraction validates only a subset of the attacker/agent-controlled input it claims to fully classify.
- **Severity:** Critical (confirmed, exploitable bypass of a destructive-action guard; the guard's entire purpose is defense-in-depth against exactly this class of command).
- **Confidence:** High — traced statically through both the old and new regex/loop logic and confirmed the default (`any_ambiguous` → `emit_block`) is conservative-block, meaning this is a strict weakening, not a stricter/laxer trade-off both ways.
- **Remediation:** Restore multi-token detection — either revert to capturing the full span and requiring exactly one non-flag token (the pre-change behavior), or explicitly detect and reject (fall through to ambiguous) when a second non-flag, non-option token appears between the captured root and `-exec`. Add a regression fixture: `find ./build /etc -exec rm -rf {} +` must be blocked/ambiguous, not allowed.

### 2. MEDIUM — Billing-class 4xx errors from Anthropic no longer distinguished from param errors (availability/reliability regression)

**File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139`, `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:171`, `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:223`

The PR removes `_BILLING_CLASS_TOKENS` / `_is_billing_class_error` (previously present in `base/.claude/adapters/loa_cheval/providers/anthropic_adapter.py`) and the three call sites that raised `ProviderUnavailableError` (chain-walk / retryable) for 4xx responses whose body indicates an account-side condition (`credit_balance`, `quota_exceeded`, `billing_disabled`, `payment_required`, etc.). All 4xx responses — parameter errors and billing errors alike — now raise `InvalidInputError` unconditionally:

```
139:                raise InvalidInputError(
...
171:                raise InvalidInputError(
...
223:            raise InvalidInputError(f"Anthropic API error (HTTP {status}): {msg}")
```

This is not itself an injection/authz/crypto vulnerability, but it is a security-adjacent availability concern: a multi-provider `cheval` deployment that relies on `ProviderUnavailableError` to chain-walk to a fallback provider when Anthropic is billing-blocked will now treat a billing-account lockout identically to a malformed request — terminal, no failover — for every caller until the adapter is patched or the account is fixed. If this adapter backs an automated/on-call decision path (e.g. incident response or alerting through `cheval`), a billing suspension silently becomes indistinguishable from "your request was bad," which can mask an operational failure mode.

- **Severity:** Medium (functional regression with availability implications, not a direct exploit path).
- **Confidence:** High that the behavior changed as described; Medium on downstream blast radius since it depends on how call sites use the two exception classes (not shown in this diff).
- **Remediation:** Either confirm (in the PR description or an SDD reference) that billing-class differentiation is intentionally being dropped and downstream chain-walk callers were audited for this, or restore the classification.

### 3. LOW — `get_completed_sprints` iterates `find` output via unquoted word-splitting

**File:** `head/.claude/scripts/workflow-state.sh:79-88`

```
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
```

`sprint_dirs` is captured via command substitution and then iterated with an unquoted `for dir in ${sprint_dirs}`, which word-splits on `IFS` (spaces/tabs/newlines) rather than one path per line. Sprint directories are created by this same framework with a controlled `sprint-<n>` naming convention, so this is not currently attacker-reachable, but it is fragile: any future sprint-directory naming that includes a space (or a sprint dir created by an external/legacy tool) would silently under- or mis-count completed sprints rather than fail loudly. This is a behavior/robustness change bundled into the same commit as the `get_total_sprints`-based off-by-design fix (the prior version undercounted when sprint numbering had gaps or the total shrank).

- **Severity:** Low (no external input reaches this path; local correctness/robustness issue only).
- **Confidence:** High that the unquoted split exists; Low that it is currently exploitable.
- **Remediation:** Use `while IFS= read -r dir; do ... done < <(find ... -print0 | ...)` or `find ... -print0` with a null-delimited read loop for robustness, consistent with the shell-conventions guidance already in this repo.

## Observations

- The `find`-multi-root regression (Finding 1) is the dominant issue in this PR; Findings 2 and 3 are secondary quality/robustness items surfaced by the same diff and are reported for completeness but do not on their own change the verdict.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

(Finding 1 is treated as High in the tally per the one-way verdict rule below; it is a confirmed, exploitable protection-mechanism bypass, which is the ceiling for "High" absent a demonstrated live exploitation trace in this audit's sandbox — see Verdict.)

## Verdict

**Codebase Audit — Overall Risk Level: HIGH**

Recommendations:
- **Immediate (24h):** Fix Finding 1 — restore multi-root rejection in `_re_find_exec_prefix`/`_seg_find_root` extraction in `block-destructive-bash.sh`; add the `find ./build /etc -exec rm -rf {} +` regression fixture before merge.
- **Short-term (1wk):** Resolve Finding 2 — confirm intentional removal of billing-class 4xx handling in the Anthropic adapter, or restore it and add a regression test distinguishing `InvalidInputError` vs `ProviderUnavailableError` for 4xx bodies.
- **Long-term (1mo):** Harden Finding 3 — convert `get_completed_sprints` (and any similar `find`-into-unquoted-`for`) loops to null-delimited iteration per `.claude/rules/shell-conventions.md`.

This PR must not merge as-is: it weakens a mechanically-enforced destructive-command safety control (`block-destructive-bash.sh`) in a way that is silently exploitable and not covered by the PR's own stated "documented gap."

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":1},"ts":"2026-09-22T00:00:00Z"} -->
