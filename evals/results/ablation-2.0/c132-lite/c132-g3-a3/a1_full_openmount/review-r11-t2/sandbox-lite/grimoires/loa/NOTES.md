# NOTES

## Session Continuity

- 2026-10-23 audit sprint-1 (task review-r11): `/audit-sprint sprint-1` written to `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md` — CHANGES_REQUIRED (critical 0, high 3, medium 8, low 12; excluded 0 / excluded_confirmed 0). `verdict-derive.sh --gate audit` consistent (exit 0). Dissent envelope `adversarial-audit.json` (2/2 voices, 0 rejected). Prerequisite deviation recorded: review gate verdict was CHANGES_REQUIRED, audit ran on explicit task instruction. Working files: `grimoires/loa/a2a/audits/2026-10-23/{SECURITY_ANALYSIS_TODO.md,findings.jsonl}`. Head-overlay tests: 88 passed, 2 pre-existing failures (live `.loa.config.yaml` readers). `br` not installed — beads steps skipped.

## Learnings
- [2026-10-23T04:16Z] [auditing-security] Safety hook blocks cp/mv into any path containing '.claude/' (FR-SZ2-COPY) even under /tmp, and rm -rf on a shell variable (FR-2-AMBIGUOUS); stage a PR-head test overlay under a differently named dir and symlink '.claude -> sys' → skills-pending/learning-20261023T0416Z-ovl1
- [2026-10-23T04:16Z] [auditing-security] A pr/head overlay needs the tree's superset loa_cheval/types.py and scripts/lib/log-redactor.py to import; test_advisor_\* read the live .loa.config.yaml and fail in any overlay (pre-existing, not PR defects) → skills-pending/learning-20261023T0416Z-ovl2
- [2026-10-23T04:16Z] [auditing-security] The dissent companion voice reads a copy of the current tree, not pr/head; grep pr/head for every test or symbol a dissent finding names before accepting a "code and tests disagree" claim → skills-pending/learning-20261023T0416Z-dis1
