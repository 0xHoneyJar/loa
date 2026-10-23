# Reviewer concerns — sprint-1 (PR: sprint-263)

Scope: 35 files. Areas the senior reviewer is probing:
- adversarial-review.sh: budget_scale (fixed|diff) math, budget_cents_max default/validation, envelope metadata fields; anchor_line / anchor_line_end normalisation (1..10,000,000, end >= start, silent drop).
- Schemas (adversarial-finding, wire dissent-review/audit): new optional fields and whether required lists / additionalProperties stay consistent.
- evals/graders/recall-vs-defects.sh 1.3.0: three results, oracle detector, path:line[-end] reduction, versioned re-grade.
- evals/harness/lib/sandbox-mount.sh: closed review-catch mount — what is mounted, whether anything outside the allowlist leaks into the sandbox, symlink/path traversal handling.
- ablation-grade.sh / ablation-row.sh / ablation-report.py / took-effect.sh: multi-site curated labels, re-grade versioning, result aggregation correctness.
- Tests: do bats assertions actually exercise the new branches, or stub them away.
