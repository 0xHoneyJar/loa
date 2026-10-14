# Release notes: v2.0.0-rc.5 (pre-release) — Earned guards and open voices

Prepared 2026-10-14 by the cycle-129 lead for the post-merge pipeline, which fills the "Release body" section from the merge and finalises the CHANGELOG heading. The full release note is the CHANGELOG `## [Unreleased]` section at the time of the merge (cycle-129, sprints 255–257, FR-1 … FR-10) with its Migration table. Review and audit records: `record/cycle-129-a2a`.

## Cycle ratio (PRD FR-10, AC-10.3)

Produced by `tools/cycle-ratio.sh --from ffd25258 --to <cycle head> --sprint-plan grimoires/loa/sprint.md` on the integrated Sprint 3 tree:

- kinds: mechanical 24 · judgment 5 · operator 0
- volume: script lines changed 164775 (`*.sh *.py *.ts *.js`) · prose bytes changed 2209866 (`*.md`) · model calls 14 (MODELINV rows between the two commits' timestamps) · scope: host

Reading: every sprint task carried a `kind:` token; the five judgment tasks were the register's origin seeding, the record-corpus curation, the KF-041 upstream issue, the kernel-row classification (which took the D-2.4 fallback) and the end-to-end validation; no task needed the operator in the loop. The volume line counts the whole cycle's diff, fixtures included (the eight record fixtures carry verbatim base and head trees), so prose bytes dominate.

## Control arms (PRD FR-2)

The review-recall batch 1 (eight fixtures `pr-01` … `pr-08`, four arms, three trials, executor `global.anthropic.claude-opus-5-5`, source commit `864069f2`) completed on 2026-10-14 (96 of 96 trials, none failed); its report is `grimoires/loa/a2a/sprint-257/arms-report-review-recall-2026-10-14.md` on the record branch. Verdicts: `no_karpathy` and `no_rule_files` **no recall loss** (mean drop 0.000, 90 % interval [0.000, 0.000], no missed labels); `no_companion` no recall loss, informational (drop 0.028; two pr-05 labels missed in one of three trials); baseline recall 1.000 with a refuted share of 0.785. The Sprint 2 kernel task had already taken the D-2.4 fallback (no row deleted; cap lowered to the measured size), so the verdicts inform the deferral bead `bd-2txz1`, not this release. The audit-recall batch 1 (same fixtures, arms `baseline` and `no_audit_delta`, three trials, same executor and source commit) completed on 2026-10-14 (48 of 48 trials, none failed); its report is `grimoires/loa/a2a/sprint-257/arms-report-audit-recall-2026-10-14.md` on the record branch. Verdict: `no_audit_delta` **no recall loss** (mean drop 0.000, 90 % interval [0.000, 0.000], no missed labels; baseline recall 1.000, refuted share 0.751 vs 0.764). Batch 2 (`pr-11` … `pr-18`) is cost-gated (DEC-0173).

## Release body (as published)

(filled by the post-merge pipeline)
