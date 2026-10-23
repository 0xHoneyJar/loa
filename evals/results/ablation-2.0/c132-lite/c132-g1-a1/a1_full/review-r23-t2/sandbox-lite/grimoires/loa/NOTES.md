# NOTES

## Session Continuity

- 2026-10-21 review-sprint sprint-1 (task review-r23): CHANGES_REQUIRED written to a2a/sprint-1/engineer-feedback.md; 3 HIGH — pipeline-run.bats:498/503 inert `!` leak assertions, ablation-grade.sh:864 envelope_texts ignores anchor_line, ablation-grade.bats:16 hard-coded BATS_BIN. Local bats runs of pr/head are not meaningful (snapshot drops exec bit; freeze.sh/no-secrets.sh/smoke not in PR).
- 2026-10-21 audit-sprint sprint-1 (task review-r23): CHANGES_REQUIRED written to a2a/sprint-1/auditor-sprint-feedback.md (verdict-derive consistent); 4 HIGH — pipeline-run.bats:498 inert leak guard, ablation-grade.sh:574 output-derived paths opened on host, :631 forgeable score (parse-fallback/all_pass), :864 anchor_line ignored; 13 MEDIUM, 10 LOW. Security dissent 2/2 voices, 11 findings, 0 rejected (a2a/sprint-1/adversarial-audit.json). Ran despite review CHANGES_REQUIRED per task order. Working file: a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md.

## Learnings
- [2026-10-21T18:06:06Z] [auditing-security] In bats a bare '! cmd' mid-test never fails the test; use 'run !' or '|| false' (verified bats 1.13.0) → skills-pending/learning-20261021T180606Z-bats-neg
- [2026-10-21T18:06:06Z] [auditing-security] shutil.copyfile materialises sparse files in full; lstat size/blocks before copying untrusted trees → skills-pending/learning-20261021T180606Z-sparse-copy
- [2026-10-21T18:06:06Z] [auditing-security] tarfile.data_filter needs Python ≥ 3.11.4 (PEP 706); check the floor or fall back → skills-pending/learning-20261021T180606Z-tarfile-floor
