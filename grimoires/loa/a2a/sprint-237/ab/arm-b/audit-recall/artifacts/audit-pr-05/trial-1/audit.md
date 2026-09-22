# Security Audit — refactor(hooks,cheval,state): single-token find roots, plain 4xx handling, historical sprint counting

**Scope**: `head.diff` against `base/` for three files: `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/adapters/loa_cheval/providers/anthropic_adapter.py`, `.claude/scripts/workflow-state.sh`. No sprint plan, beads DB, or `grimoires/loa/a2a/` context exists for this evaluation; audited from the diff and full `head/` file contents only.

## Finding 1 — CRITICAL: `find`-exec root capture accepts only the first argument, letting a second (unchecked) `find` root reach `rm -rf`

**File**: `head/.claude/hooks/safety/block-destructive-bash.sh:776`, `head/.claude/hooks/safety/block-destructive-bash.sh:805-807`

The destructive-bash guard special-cases `find ROOT ... -exec rm ... {} \;` shapes: when it can identify a single, unambiguous `ROOT`, it classifies `ROOT` itself through the normal block/allow/ambiguous ladder (`head/.claude/hooks/safety/block-destructive-bash.sh:850-878`) instead of the placeholder arguments (`{}`, `+`, `\;`) that `rm` actually receives.

Before this change, root extraction walked every token following `find` and only trusted the result when **exactly one** non-flag token preceded any flag/operator:

```bash
# base/.claude/hooks/safety/block-destructive-bash.sh (pre-change)
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

`find` accepts **multiple** path operands before its expression/flags (e.g. `find dist / -exec rm -rf {} \;` searches *both* `dist` and `/`). The old loop counted every leading non-flag token, and when it found more than one, it discarded `_seg_find_root` entirely (`_find_root_count -ne 1`), which routes the segment to the ordinary per-argument ladder and lands on the `{}` placeholder — an unrecognized shape that falls to `any_ambiguous=1` (conservative block).

The new code drops that loop and the multi-root check completely:

```bash
# head/.claude/hooks/safety/block-destructive-bash.sh:776
_re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)[:space:]]+)[^;&|)]*-exec$'
...
# head/.claude/hooks/safety/block-destructive-bash.sh:805-807
_seg_find_root=""
if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
  _seg_find_root="${BASH_REMATCH[3]}"
fi
```

Group 3 (`[^;&|)[:space:]]+`) captures only the **first** whitespace-delimited token after `find`, unconditionally — with no check for what follows it. Any second, third, etc. path operand before `-exec` is silently ignored.

**Failure scenario**: `find dist / -exec rm -rf {} \;`
- `_seg_find_root` is set to `"dist"` (the first token only); the real second root, `/`, is never inspected.
- The `rm` operands are exclusively find-exec placeholders (`-rf`, `{}`), so `_seg_placeholder_only=1` (`head/.claude/hooks/safety/block-destructive-bash.sh:850-859`) and the root-classification path at `head/.claude/hooks/safety/block-destructive-bash.sh:861-878` runs instead of the normal per-argument ladder.
- `"dist"` matches `_re_allow_list` verbatim (`dist$` is one of the listed bare tokens, `head/.claude/hooks/safety/block-destructive-bash.sh:765`), so the segment is classified as an **explicit safe relative root** and the whole command is allowed to execute (`head/.claude/hooks/safety/block-destructive-bash.sh:874-875`).
- At runtime, `find` still walks **both** `dist` and `/`, and executes `rm -rf` on every matched entry under `/` — i.e. the guard is bypassed for a command that recursively deletes the filesystem root.

The same pattern works with any allow-listed first token (`node_modules`, `build`, `target`, `./anything-not-dotfile`, `out`, `coverage`, `/tmp/...`) paired with any real catastrophic second root (`/`, `$HOME`, `/etc`, `..`, etc.), because only the first token is ever evaluated.

This is a straight regression from "ambiguous → conservative block" to "silently permitted" for a class of inputs the mechanism exists specifically to catch (destructive `find -exec rm -rf`). The PR's own comment acknowledges narrowing scope ("`find -L root -exec ...` (flags before root) is not covered and keeps today's conservative behavior") but that framing is incomplete and misleading: it discusses only the *flags-before-root* gap, not the *multiple roots* gap this diff actually introduces, and in the multiple-roots case the outcome is not conservative — it is a bypass.

**Recommendation**: Restore multi-token detection — reject (or set `_seg_find_root=""` / mark ambiguous) whenever more than one non-flag token appears before the first flag/operator in the captured span, exactly as `base/.claude/hooks/safety/block-destructive-bash.sh` did. If narrowing to "first argument only" is intentional, it must also positively reject (not merely ignore) any additional non-flag operand before `-exec`, rather than truncating the regex capture and dropping the rest of the span unchecked.

**CWE**: [CWE-863: Incorrect Authorization](https://cwe.mitre.org/data/definitions/863.html) (the guard authorizes based on an incomplete view of the command it is checking) / [CWE-20: Improper Input Validation](https://cwe.mitre.org/data/definitions/20.html).

---

## Finding 2 — LOW: billing-class 4xx errors no longer trigger provider failover

**File**: `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139`, `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:171`, `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:223`

The PR removes `_is_billing_class_error()` and the `_BILLING_CLASS_TOKENS` tuple that previously reclassified account-side 4xx conditions (`credit balance`, `quota_exceeded`, `invoice_overdue`, `billing_disabled`, `payment_required`, `insufficient_quota`) as `ProviderUnavailableError` rather than `InvalidInputError`. All three former call sites (streaming path, non-streaming legacy path, and the non-streaming error branch) now raise `InvalidInputError` unconditionally for every 4xx:

```python
# head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139
raise InvalidInputError(
    f"Anthropic API error (HTTP {status}): {_extract_error_message(err_json)}"
)
```

`InvalidInputError` is presumably treated by the cheval orchestrator as a terminal, non-retryable, request-side fault (that was the entire purpose of the removed distinction, per the deleted docstring: "Billing-class errors should chain-walk via ProviderUnavailableError; param errors stay terminal via InvalidInputError"). Collapsing the distinction means an exhausted-credit or suspended-billing account now surfaces as if the *request itself* were malformed, which will suppress any failover/retry-to-another-provider behavior that keys off `ProviderUnavailableError`. This is an availability/reliability regression rather than an exploitable vulnerability, but it removes a control that existed specifically to keep multi-provider routing resilient to one provider's account-side failures, so a billing lapse on the Anthropic account degrades silently (misclassified as a caller input bug) instead of failing over.

**Recommendation**: Confirm with the orchestrator's error-handling contract whether this simplification was deliberate (e.g. billing-class detection moved elsewhere, or judged not worth the token-matching fragility) and, if not, restore the classification or move it to a shared location so it isn't lost for other providers' adapters either.

**CWE**: N/A (availability/reliability, not a security boundary).

---

## Finding 3 — Informational: `get_completed_sprints` iterates an unquoted directory list

**File**: `head/.claude/scripts/workflow-state.sh:79-88`

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

The change itself (counting every `sprint-*` directory with a `COMPLETED` marker, rather than only sprints numbered `1..get_total_sprints()`) is a legitimate bug fix — the old version undercounted completed sprints once `sprint.md` no longer listed a since-archived sprint, or overcounted/undercounted whenever numbering and `sprint.md`'s `## Sprint N` headings drifted apart. No behavioral objection to the fix itself.

The implementation detail worth flagging: `for dir in ${sprint_dirs}` is an unquoted expansion of a `find`-produced newline list, so a sprint directory name containing a space or shell glob metacharacter would word-split or glob-expand unexpectedly. `_GRIMOIRE_DIR/a2a/sprint-*` directories are created by the framework itself (not from untrusted external input) in every observed workflow, so this is not an attacker-reachable path today, but it is a latent fragility inconsistent with this repo's own documented strict-mode conventions (quote/guard array and word-split expansions). A future caller that creates sprint directories from less-trusted input (e.g. a templated sprint id) would silently misbehave rather than fail loudly under `set -euo pipefail` (`head/.claude/scripts/workflow-state.sh:16`).

**Recommendation**: Iterate with a `while IFS= read -r dir; do ... done < <(find ... -print0 | ...)` or `mapfile -d '' -t` pattern instead of unquoted word-splitting, matching the null-delimited-safe patterns already used elsewhere in this codebase's hooks.

**CWE**: [CWE-88: Argument Injection](https://cwe.mitre.org/data/definitions/88.html)-adjacent word-splitting hazard; not currently reachable by untrusted input.

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 0 |
| Medium | 0 |
| Low | 1 |

(Finding 3 is informational/hygiene, not tallied as a scored severity.)

## Verdict

**CHANGES_REQUIRED** — Finding 1 is a confirmed, exploitable authorization bypass in a safety-critical guard (`block-destructive-bash.sh`) that this exact PR touches and narrates as a scoped, conservative change. The `find dist / -exec rm -rf {} \;`-shaped bypass must be closed (restore multi-token root detection) before this PR can land. Finding 2 should be confirmed as an intentional simplification or reverted; Finding 3 is a low-risk hygiene note, not a blocker.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":0,"low":1},"ts":"2026-09-22T00:00:00Z"} -->
