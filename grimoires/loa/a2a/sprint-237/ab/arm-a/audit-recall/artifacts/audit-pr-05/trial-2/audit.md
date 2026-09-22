# Security Audit Report — refactor(hooks,cheval,state): single-token find roots, plain 4xx handling, historical sprint counting

**Audit date**: 2026-09-21
**Auditor**: Paranoid Cypherpunk Auditor (auditing-security skill)
**Scope**: `head.diff` — 3 files (`.claude/hooks/safety/block-destructive-bash.sh`, `.claude/adapters/loa_cheval/providers/anthropic_adapter.py`, `.claude/scripts/workflow-state.sh`)

## Executive Summary

This PR touches a safety-critical bash guard, a provider-error classifier, and a workflow-status
script. The `block-destructive-bash.sh` change is a genuine **CRITICAL** regression: it collapses
the previous "exactly one non-flag find-root token" validation down to "grab the first
whitespace-delimited token after `find `", which means a `find` invocation with **more than one
starting path** now has every path *after* the first silently dropped from consideration. An
attacker (or a confused/compromised agent) can put an innocuous, allow-listed path first and a
catastrophic path second, and the destructive-`rm` guard will approve the whole statement while
`find`/`rm` still walks and deletes the second path. The old code deliberately treated multi-root
`find` as ambiguous (conservative block); the new code treats it as single-root and can land in
the ALLOW branch.

The `anthropic_adapter.py` change removes billing-class 4xx detection, which is a real behavior
regression (loses chain-walk-on-billing-error resilience) but is not itself an exploitable
security hole — flagged as MEDIUM for availability impact.

The `workflow-state.sh` change decouples "completed sprints" from the current cycle's sprint
count, which can misreport workflow status/progress across cycle boundaries — flagged as LOW/
correctness, not directly security-relevant, since it only affects informational status output
and does not bypass any enforcement mechanism.

## Overall Risk Level: **CRITICAL**

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 0 |
| Medium | 1 |
| Low | 1 |

---

## Critical Issues

### C-1: Multi-root `find ... -exec rm -rf` bypasses the destructive-bash guard

- **Component**: `head/.claude/hooks/safety/block-destructive-bash.sh:776`, exploited via the consumer at `head/.claude/hooks/safety/block-destructive-bash.sh:806-807`
- **CWE**: CWE-697 (Incorrect Comparison) / CWE-863 (Incorrect Authorization) — the guard's root-token extraction under-covers the actual command surface it is meant to police.
- **Standard**: OWASP A04:2021 (Insecure Design) — a security control that can be trivially defeated by reordering arguments.

**The regression**

Base (`base/.claude/hooks/safety/block-destructive-bash.sh:781-789`):

```bash
_re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)]*)-exec$'
...
if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
  read -r -a _find_span_toks <<<"${BASH_REMATCH[3]}"
  _find_root_count=0
  for _ftok in ${_find_span_toks[@]+"${_find_span_toks[@]}"}; do
    case "$_ftok" in
      -*|'!'*|'('*|')'*|'\'*) break ;;
      *) _find_root_count=$((_find_root_count + 1)); _seg_find_root="$_ftok" ;;
    esac
  done
  [[ "$_find_root_count" -ne 1 ]] && _seg_find_root=""
fi
```

The base logic captures the *entire* span between `find` and `-exec`, tokenizes it, and walks
every token until it hits a flag/negation/paren. If it counts anything other than **exactly one**
non-flag token, it clears `_seg_find_root` back to empty — deliberately treating a multi-root
`find` (e.g. `find ./build /home -exec ...`) as unresolved, which routes the segment through the
per-arg ambiguous-fallback path (conservative block) rather than the allow-list path.

Head (`head/.claude/hooks/safety/block-destructive-bash.sh:776`, `806-807`):

```bash
_re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)[:space:]]+)[^;&|)]*-exec$'
...
_seg_find_root="${BASH_REMATCH[3]}"
```

`([^;&|)[:space:]]+)` matches only the *first* whitespace-delimited token after `find `, then
`[^;&|)]*-exec$` (which **does** allow whitespace) consumes everything else — including any
additional root paths — up to the trailing `-exec`. `_seg_find_root` is now unconditionally set to
that first token, with no check for a second, third, etc. root.

**Proof of concept**

```
find ./build / -exec rm -rf {} +
```

- `_seg_find_root` resolves to `./build` only; the second root `/` is absorbed into the regex's
  `[^;&|)]*` middle group and never inspected.
- The rm segment's only non-flag operands are `{}` and `+` (find-exec placeholders), so
  `_seg_placeholder_only=1` at `head/.claude/hooks/safety/block-destructive-bash.sh:849-859`.
- `_seg_find_root` (`./build`) is classified at `head/.claude/hooks/safety/block-destructive-bash.sh:866-878`
  against `_re_allow_list` (`head/.claude/hooks/safety/block-destructive-bash.sh:765`:
  `^(\./[^/*.][^*]*|...)`), which it matches — the branch at `head/.claude/hooks/safety/block-destructive-bash.sh:874-875`
  is a no-op (`:`), so the entire statement is **allowed**.
- At actual shell execution time, `find` walks **both** `./build` and `/` and executes
  `rm -rf` on every matched entry under `/` — i.e. this command, once approved by the hook,
  recursively deletes the root filesystem (bounded only by permissions of the invoking user).

The same shape works for `$HOME`, `~`, `/etc`, or any other member of `_re_block_list`
(`head/.claude/hooks/safety/block-destructive-bash.sh:763`) placed as the *second* root — as long
as the *first* root is allow-listed, the whole statement clears the guard. Only when the
dangerous path happens to be the *first* token does the guard still catch it (because that token
alone is what gets classified).

This directly regresses the invariant the base code encoded on purpose (see the deleted
`_find_root_count -ne 1` check, and the comment block still present at
`head/.claude/hooks/safety/block-destructive-bash.sh:718-731` in the base file, describing the
single-root design intent). The new in-code comment
(`head/.claude/hooks/safety/block-destructive-bash.sh:773-775`) documents a *narrower*,
different gap ("flags before root," e.g. `find -L root -exec`) and does not acknowledge that
multi-root inputs are now silently truncated to their first token rather than falling back to
ambiguous/block.

**Impact**: Complete bypass of the primary defense-in-depth control against catastrophic
`rm -rf` execution (the hook exists specifically to stop agentic/automated sessions from running
destructive filesystem operations). Exploitable by any actor who can get a `find ... -exec rm -rf
{} +` shaped command through the hook (compromised/careless agent, prompt-injected instructions,
or a user simply mis-ordering `find` arguments) — no privilege escalation needed, only argument
ordering.

**Remediation**: Restore the base behavior — either revert this hunk entirely, or re-derive a
"must resolve to exactly one non-flag root token" check on top of the new capture group (e.g.
tokenize the full pre-`-exec` span as before and only accept a single unambiguous root; clear
`_seg_find_root` on 0 or 2+ roots so multi-root `find` statements fall through to the existing
per-arg ambiguous ladder). Add a regression fixture for
`find ./allowed / -exec rm -rf {} +` (and the `$HOME`/`/etc` variants) asserting `FR-2-BLOCK` or
`FR-2-AMBIGUOUS`, not silent allow.

---

## Medium Issues

### M-1: Billing-class 4xx errors no longer chain-walk to other providers

- **Component**: `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139-141`, `:222-223`
- **Category**: Availability / resilience regression (not directly exploitable, but weakens the
  documented multi-model failover posture described in this repo's `CLAUDE.loa.md`
  ("chain-walk on retryable errors").

The base adapter special-cased 4xx responses whose message matched a billing-class token list
(`credit balance`, `quota_exceeded`, `payment_required`, etc. — base
`base/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:41-66`) and raised
`ProviderUnavailableError` for those, so the retry/chain-walk layer would fail over to the next
provider in the chain instead of terminating the whole request. This PR deletes
`_is_billing_class_error` and its call sites entirely, so **every** 4xx (including "your account
has no credit" / "quota exceeded" / "invoice overdue") now raises `InvalidInputError`
unconditionally at `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:139-141` and
`head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:222-223`.

`InvalidInputError` is the adapter's signal for "this specific request was malformed" (terminal,
not retried) — but a billing-class failure is an account-level condition that has nothing to do
with the current request and would succeed identically on a different provider. Collapsing the
distinction means an exhausted-credit Anthropic account causes every multi-model request to fail
outright instead of failing over, silently reducing the availability guarantees the chain-walk
design is meant to provide. This is a functional/availability regression rather than an
information-disclosure or injection issue, hence Medium rather than Critical/High.

**Remediation**: Restore `_is_billing_class_error` (or equivalent) and keep the
`ProviderUnavailableError` branch for billing-class 4xx bodies, or, if the intent is genuinely to
simplify the classifier, explicitly confirm with the multi-model chain-walk owner that billing
exhaustion should now be a terminal, non-retried condition and update
`.claude/loa/reference/multi-model-reference.md` accordingly so the behavior change is documented
rather than silent.

---

## Low Issues

### L-1: `get_completed_sprints` no longer bounded to the current cycle's sprint count

- **Component**: `head/.claude/scripts/workflow-state.sh:79-91`
- **Category**: Correctness — informational status output only, no enforcement bypass observed
  in the reviewed diff.

Base (`base/.claude/scripts/workflow-state.sh:76-86`) computed `total` from `get_total_sprints`
(parsed from the *current* `sprint.md`) and only checked `COMPLETED` markers for
`sprint-1..sprint-${total}` — i.e. bounded to the sprints the current cycle actually declared.
Head instead globs every `${a2a_dir}/sprint-*` directory and counts any with a `COMPLETED`
marker, regardless of which cycle created it:

```bash
sprint_dirs=$(find "${a2a_dir}" -maxdepth 1 -type d -name "sprint-*" 2>/dev/null || true)
for dir in ${sprint_dirs}; do
    if [[ -f "${dir}/COMPLETED" ]]; then
        count=$((count + 1))
    fi
done
```

If `grimoires/loa/a2a/` retains `sprint-*` directories from a prior cycle (e.g. archival didn't
run, or ran late), `get_completed_sprints` can return a count higher than the current cycle's
`total_sprints`. `determine_state()` at `head/.claude/scripts/workflow-state.sh:148`
(`completed_sprints -ge total_sprints`) would then report `STATE_COMPLETE` prematurely, and
`get_progress_percentage` would compute progress `>100%`-equivalent inputs. This is confined to
the status/progress display used by `/loa` and the golden-path suggestion; it does not appear to
gate `/implement`, `/review-sprint`, or `/audit-sprint`, which are enforced by separate hooks per
`CLAUDE.loa.md`'s Process Compliance table — so the practical blast radius is a misleading status
readout, not a bypassed quality gate.

**Remediation**: Either bound the `find` to only current-cycle sprint directories (e.g. cross-
reference against `get_total_sprints`'s numbering, or key sprint dirs by cycle id), or explicitly
scope this function's contract to "all completed sprints ever" and update
`get_progress_percentage`/`determine_state` call sites to not assume it's cycle-scoped.

---

## Security Checklist Status

- [ ] Destructive-operation guard (`block-destructive-bash.sh`) correctly rejects all multi-root
      `find -exec rm -rf` shapes — **FAILED** (C-1)
- [x] No secrets/credentials introduced or exposed by this diff
- [x] No new injection sinks (SQL/command/template) introduced
- [ ] Provider error classification preserves documented chain-walk/failover semantics —
      **FAILED** (M-1)
- [~] Workflow-status accuracy across cycle boundaries — **PARTIAL** (L-1)

## Verdict

**CHANGES_REQUIRED** — the multi-root `find -exec rm -rf` bypass (C-1) is a critical regression in
a safety-enforcing hook and must be fixed (or the hunk reverted) before this PR lands. M-1 and L-1
should be addressed or explicitly accepted with documentation before merge but do not block on
their own.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":1,"low":1},"sprint_id":"pr-05","ts":"2026-09-21T00:00:00Z"} -->
