# auditing-security — Security Dissenter (Phase 1C) detail

SKILL.md Phase 1C names the gate, the hook, the override and the invocation. This file carries
the merge rules and the failed-run record.

## Independence

The dissenter receives the diff only — never `--context-file` with your Phase 1A/1B findings —
so it evaluates the code without anchoring on your conclusions.

## Merging dissenter findings into Phase 2

1. CRITICAL/HIGH findings go into the audit report as findings of your own (they may change the
   verdict and must appear in the Phase 2.5 tally).
2. MEDIUM/LOW findings go under a "Cross-Model Security Observations" section.
3. A dissenter finding that duplicates one of yours is marked "Confirmed by cross-model review".

## Failed or unavailable dissenter

Output file: `grimoires/loa/a2a/{sprint_id}/adversarial-audit.json`. The
`adversarial-review-gate.sh` hook checks that this file exists, not its contents, so on a
timeout, API error or exhausted budget write:

```json
{"findings": [], "metadata": {"status": "failed", "reason": "<what happened>"}}
```

before proceeding, and set a `DEGRADED_SECURITY_REVIEW` marker in the audit report. Empty
findings from a run that completed are a normal pass, not a degraded review.
