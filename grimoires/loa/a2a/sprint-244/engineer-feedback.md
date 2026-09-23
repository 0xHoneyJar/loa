All good

Sprint 4 has been reviewed and approved. All acceptance criteria met. Observations documented and non-blocking. See Observations below.

# Sprint 4 (global 244) Review Feedback — round 1

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1, inline under `/run sprint-plan`)
**Date:** 2026-09-23
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 4 (Final): Provider health, cost accounting, docs and E2E
**Implementation Report:** grimoires/loa/a2a/sprint-244/reviewer.md
**Reviewed commit:** `13009350` (sprint commits `49dd7b2a`, `56e4900e`, `6c9d77e2`, `a954bcc1`, `13009350`) · cross-model dissent `adversarial-review.json` (gpt-5.5-pro): `status: reviewed`, 1 ADVISORY (DISS-001), 0 rejected

---

## Overall Assessment

The sprint is two features with one shape: read the truth that already exists on disk (breaker files, the catalog, the ledger), surface it where the operator looks, and never invent a number. I read the breaker CLI, the ladder, the ledger changes, the adapters, the status block, `cost-report.sh` and the enforcer guard end to end, replayed the fixtures, and probed the seams the tests do not reach. The dissenter's one finding was real and is fixed in the reviewed commit: `reset_bucket` with an explicit auth type used to write a fresh CLOSED file for a bucket that never existed (an operator typo would have fabricated healthy state and exited 0); it now resets only an existing bucket, exits 1 otherwise, and a test pins both. Two of my own concerns turned into in-sprint fixes before this round closed: `/loa` reported a credential `absent` that the preflight considered present (it read only the environment; both now share the env → `.env.local` → `.env` presence rule and the status names the source), and legacy rows without a `request_id` would have migrated on every `--migrate-legacy` run (content-key de-duplication, CR-3b).

The report's AC Verification and E2E table are specific, and its stated deviations are the right calls: the chain-walk proof runs the real breaker + retry path with mocked adapters because `--dry-run` never reaches the chain; the all-time unpriced share is the honest denominator even though it halts this repository's own enforcer until a re-pricing pass exists (bd-ypbg). One FR-1 refinement rode along after the sprint's own evidence command was fenced — it is corpus-gated and I probed its boundary (below).

Complexity: `find_pricing` is 40 lines for four rungs with an explicit depth cap; `reset_bucket` 20; the status block's largest function 25. Lean already. Ship.

**Verdict:** APPROVED

---

## Observations

### 1. Design choices worth a line in the runbook

- **MEDIUM** (confidence: high) `.claude/scripts/lib/cost-budget-enforcer-lib.sh` (`_l2_unpriced_share_json`) — the unpriced share is all-time over the current ledger and the enforcer spawns `cost-report.sh --json` (a Python ledger scan) on every verdict. On this repository that is 74 % from pre-ladder history, so `budget_verdict` halts until rows are re-priced or rotated; a large ledger also adds noticeable latency per verdict. Both are stated in the report; the follow-up bead bd-ypbg owns the re-pricing design. Record the operator remedy in `grimoires/loa/runbooks/model-economy.md` when that lands.
- **LOW** (confidence: high) `.claude/adapters/loa_cheval/routing/circuit_breaker.py` (`reset_bucket`) — the journal marker and the state write are two operations without a lock spanning them; a `record_failure` racing between them can be superseded by the reset. For an operator action this is acceptable and the marker still records the pre-reset state.

### 2. Fence refinement boundary (FR-1 follow-through)

- **LOW** (confidence: high) `.claude/hooks/safety/block-destructive-bash.sh` (`_fr2_rebindable`) — probed: `time read`, newline-initial `read`, `then`/`case`-arm `read`, `eval "read T"`, `source`, `read <<<` all still void the proof; `exec read`, `env IFS= read`, `sudo read`, `nice read` do not — correctly, since none of those can rebind a variable in the calling shell (`read` is a builtin, so the wrapped forms fail or run in a child). Worth one line in the hook header's residuals.

### 3. Cosmetic

- **LOW** (confidence: medium) `.claude/scripts/loa-status.sh` (`display_providers_section`) — the block is human-first; `--json .providers.providers.<p>.breakers` carries the absolute `path` of each state file from `list_buckets`. Harmless in a local tool; strip it if the envelope is ever shipped off-host.

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| Breaker `--list` shape, reset journals, OPEN → HALF_OPEN after cooldown; snapshot never prints a value (FR-4 AC 1–2) | Pass | `test_circuit_breaker_cli.py` 13/13 (incl. the DISS-001 case); LSP-1/2/4 |
| Chain-walk on OPEN → CLI hop (FR-4 AC 3) | Pass | `test_breaker_open_walks_to_cli_hop.py` 2/2 — primary `complete` count 0, fallback 1, MODELINV names both; mechanism stated in the report |
| Mount tests assert the seeded `known-failures.md` (FR-4 AC 4) | Pass | KFS-2/3/4/5 |
| Pricing pytest over the fleet ids; unknown counted; per-hop adapter test (FR-5 AC 1–2) | Pass | `test_pricing_resolution_ladder.py` 14/14, `test_headless_resolved_model_metadata.py` 4/4 |
| `cost-report.bats` totals / legacy / receipt / unpriced share; ledger isolation (FR-5 AC 3–4) | Pass | CR-1…CR-5 + CR-3b; `teardown` proves the repository ledgers untouched; full-run hashes in the report's close-out |
| All PRD goals validated in Task 4.E2E with evidence | Pass | G-1…G-5 table with the commands and outputs; G-5's caveat is stated, not hidden |

---

## Security Checklist

- [x] Credential values never printed — presence only, negatively asserted (LSP-1/2/4, `test_cli_output_carries_no_credential_values`)
- [x] Operator reset journaled before the write; never fabricates state
- [x] Legacy migration only through the resolver-validated writer (O_NOFOLLOW proven by CR-4); receipt carries paths/counts/hashes, never row contents
- [x] Test seams bats-gated (`LOA_STATUS_RUN_DIR`, `LOA_STATUS_ENV_DIR`, `LOA_BUDGET_COST_REPORT_JSON`) and hermetic under bats
- [x] Schema-validated audit payloads extended, not bypassed

---

## Code Quality Summary

**Strengths:** one snapshot function feeding CLI, status and JSON; the ladder's rung recorded on the row; `cost-report` never re-prices history; the enforcer reports unknown as unknown; the E2E table runs the framework against itself and reports the uncomfortable number (74 %).

**Areas for Improvement:** the runbook line for the enforcer's new halt reason; the hook header residual line for the wrapped-builtin forms.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":3},"excluded":0,"sprint_id":"sprint-244","ts":"2026-09-23T05:45:00Z"} -->
