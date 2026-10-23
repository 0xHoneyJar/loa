# NOTES

## Session Continuity

- 2026-10-22 review-r26: `/review-sprint sprint-1` written to `grimoires/loa/a2a/sprint-1/engineer-feedback.md` (CHANGES_REQUIRED, 2 HIGH / 4 MEDIUM / 5 LOW; verdict-derive CONSISTENT). `review.md` at repo root carries the brief's one-line-per-finding form. Scratch suite used for the report bats lives at `/tmp/r26repo` (the real `evals/suites/ablation-2.0.yaml` and `fixtures/ablation-runs/` are outside the PR); `ablation-row.bats` not executed for that reason.
- 2026-10-22 review-r26: `/audit-sprint sprint-1` written to `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md` (CHANGES_REQUIRED, 0 CRITICAL / 2 HIGH / 3 MEDIUM / 9 LOW; excluded 0, excluded_confirmed 0). Run despite the review's CHANGES_REQUIRED on the task's instruction (Phase 0 deviation noted in the report; no COMPLETED marker). Audit dissent `adversarial-audit.json`: two voices, status clean, not degraded, 0 rejected; its three LOW findings all confirmed. New since the review: superscript-digit `suite_version` → ValueError abort (`:840`), `--suite-version 2.0` not normalised (`:857`), three raw Markdown cells (`:1156`, `:1106`, `:1269`). Scratch tree for reproductions and bats: `/tmp/audit-r26` (synthesized JSON suite; 30/35 report bats pass, AR-11/12/17 fail on the synthesized rule text only, AR-33/34 on jq 1.6). `br` not installed — no beads comment/label. Working file and JSONL under `grimoires/loa/a2a/audits/2026-10-22/`.

## Learnings

- [2026-10-22T13:00:00Z] [auditing-security] Python str.isdigit() accepts characters int() rejects (superscript digits) while re \d matches only Nd digits; a sort key guarding int(k) with k.isdigit() raises ValueError on such input — use re.fullmatch('\[0-9\]+', k) or catch ValueError at the boundary → skills-pending/learning-20261022T130000Z-isdigit-int
- [2026-10-22T13:00:00Z] [auditing-security] jq 1.6 normalises numbers inside string interpolation (1.0 renders 1) while jq 1.7 preserves the literal; bats assertions comparing interpolated numeric strings fail across jq versions although the JSON is correct — compare numerically (jq -e '.x == 1.0') → skills-pending/learning-20261022T130000Z-jq16-interp
