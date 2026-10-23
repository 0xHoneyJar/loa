# NOTES

## Session Continuity

- 2026-10-22 /review-sprint sprint-1 (eval review-r21): feedback written to `grimoires/loa/a2a/sprint-1/engineer-feedback.md` and `review.md` — CHANGES_REQUIRED (0 critical, 2 high, 4 medium, 9 low). Adversarial envelope `a2a/sprint-1/adversarial-review.json` (2/2 voices, no rejected payloads). Key: `endpoint_policy.py:156` admits opt-in for every adapter type but only OpenAIAdapter applies TransportPolicy; `model-health-probe.sh` has no `local_voices` gate though four docs claim it.
