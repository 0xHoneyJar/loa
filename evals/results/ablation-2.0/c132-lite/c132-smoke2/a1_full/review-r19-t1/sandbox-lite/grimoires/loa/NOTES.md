# NOTES

## Session Continuity

- 2026-10-21 — `/review-sprint sprint-1` (task review-r19) complete. Feedback: `grimoires/loa/a2a/sprint-1/engineer-feedback.md` (CHANGES_REQUIRED: 1 high, 5 medium, 9 low; verdict-derive CONSISTENT). Root-level `review.md` carries the brief's one-line-per-finding shape. Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` (two voices, 3 advisory, 0 rejected).
- Blocking finding: `evals/harness/run-arms.sh` re-run on the same batch appends duplicate trial rows and resets counters (lines 126, 255-257, 264, 408).
- 2026-10-21 — `/audit-sprint sprint-1` (task review-r19) complete. Feedback: `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md` (CHANGES_REQUIRED: 0 critical, 1 high, 5 medium, 11 low; excluded_confirmed 0). Ran despite the review's CHANGES_REQUIRED per the task directive; no COMPLETED marker. Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (primary clean, companion 1 MEDIUM + 4 LOW, 0 rejected). Findings JSONL: `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`. New vs review: LOA_AUDIT_REPLAY flag trusted from env (fence :528, run-arms :337), reviewer prompt red-flag list removed (reviewing-code/SKILL.md:284).
- Verification notes: `/tmp` is mounted `noexec` and `pr/head/` copies have no exec bit — bats runs need a scratch root under `/workspace/.eval/tmp` with `chmod u+x`; the System-Zone fence blocks `cp`/redirects into any path containing `.claude/`, so build the tree as `sys/` and `ln -s sys .claude`. Scratch root used: see `.run/r19-scratch-root`.
