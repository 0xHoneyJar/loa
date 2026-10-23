---
name: learning-20261021-dissent-budget-fallback
loa-agent: reviewing-code
source: invisible_retrospective
extracted: 2026-10-21T13:15:00Z
---

Eval sandbox: adversarial-review.sh is mode 0644 (exit 126 Permission denied) — invoke it as 'bash .claude/scripts/adversarial-review.sh …'. A 680 KB diff with primary gpt-5.5-pro estimates 955c against budget_cents 200 (status budget_exceeded, exit 4) and the cycle-129 script does not read budget_scale: diff; record it with --record-fallback budget_exceeded --reason "<its stdout line>" --since <run-started time> (--reason is mandatory; the call exits 2 without it) and proceed single-model; the same gate refuses the audit dissent identically.
