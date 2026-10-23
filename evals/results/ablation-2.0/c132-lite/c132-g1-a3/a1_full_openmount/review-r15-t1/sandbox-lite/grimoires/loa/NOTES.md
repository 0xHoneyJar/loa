# NOTES

## Session Continuity

### 2026-10-21 — /review-sprint sprint-1 (task review-r15)
- Reviewed `pr/head.diff` (sprint-251 operator decisions: agy opt-in, Opus 5.5 effort default, headless ceiling probe, 936K catalog bound).
- Verdict CHANGES_REQUIRED: 2 high, 8 medium, 8 low — `grimoires/loa/a2a/sprint-1/engineer-feedback.md`; brief-format copy at `review.md`.
- High 1: cheval chain walk surfaces `AgyOptInRequiredError` instead of planning around the hop (`head/.claude/adapters/cheval.py:2544`); under prefer-cli a Google voice dies at hop 1 while planners count it planned.
- High 2: `claude-opus-5-5` HTTP entry calibrated at 936,000 from a partial Bedrock-CLI probe; calibrated bounds ignore observed limits; estimator under-counts ~1.8× (`head/.claude/defaults/model-config.yaml:494`).
- Dissent: 2 voices (codex-headless, claude-headless), 8 findings, 0 rejected; DISS-C-001 BLOCKING = High 1.
- PR test suites NOT run: workspace tree is a later revision of the repo (its codex adapter already cites r251-1 fixes) and the sandbox hook blocks staging a `.claude/` overlay under /tmp.
- Known-failures surface was unreadable at session start (`grimoires/loa/known-failures.md` missing).
- Learning (retrospective): in pr/-style review tasks the workspace can be a later revision than `pr/head`; diffing head against the workspace points at defects fixed later, but every finding must be re-verified and cited in head. The sandbox hook blocks staging a `.claude/` overlay anywhere, so plan on static verification rather than running the PR's suites.

### 2026-10-22 — /audit-sprint sprint-1 (task review-r15)
- Pre-flight deviation: the review verdict is CHANGES_REQUIRED (not "All good"); the task brief directed the audit to run anyway. Recorded in the feedback; no COMPLETED marker.
- Verdict CHANGES_REQUIRED: 0 critical, 2 high, 8 medium, 10 low — `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md`; JSONL at `grimoires/loa/a2a/audits/2026-10-22/findings.jsonl`.
- High 1 (confirmed independently): cheval chain walk surfaces `AgyOptInRequiredError` as terminal (`head/.claude/adapters/cheval.py:2544`); the workspace's later revision has `_plan_around_agy` (review r251-1 G1) for this gap.
- High 2: calibrated 936K HTTP bound from a partial Bedrock-CLI probe (`head/.claude/defaults/model-config.yaml:494`); the probe's own clean-only write guard was bypassed by hand.
- New vs the review: MED-002 opt-in read from the cwd-walked (untrusted in CI) tree (dissent DISS-C-001); LOW-008 `build_headless_argv` unvalidated (DISS-C-002); LOW-009 raw cli_model/host_route in a catalog YAML comment. Simplicity finding downgraded to LOW.
- Security dissent: primary gpt-5.5-pro (codex-headless) clean; companion claude-headless 2 findings; 0 rejected; 2/2 voices, not degraded. Envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json`.
- Local checks: catalog checksum matches; PyYAML `yes`/`on` → True vs yq v4.40.5 → off (MED-003 verified). Suites not run (sandbox; workspace is a later revision). `br` not installed — beads steps skipped. known-failures.md still absent.
