# Sprint 4 (global 244) Security & Quality Audit — round 1 (final)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1, inline under `/run sprint-plan`)
**Date:** 2026-09-23
**Scope:** commits `49dd7b2a` … `01437730` (review-approved round 1 at `13009350`; later commits are a hook-header comment, a test hardening and a repo-map regeneration) — breaker CLI/reset, `cheval --reset-breaker`, `/loa` Providers block, KF template + mount seeding + `check-loa` warning, pricing ladder, ledger/adapter fields, `cost-report.sh` legacy include/migrate/unpriced share, enforcer unpriced guard + payload schemas, the FR-1 command-position refinement, four new pytest files and four new bats files
**Methodology:** Phase 0.5 scope; recon of every new input (operator CLI args, env credentials, `.env.local`/`.env`, catalog aliases, ledger rows, legacy ledger file, `.run/circuit-breaker-*.json`, bats seams); forward tracing to sinks (state-file writes, journal append, ledger append, audit-event emission, session/stdout); independent cross-model dissent (`adversarial-audit.json`, gpt-5.5-pro, diff only: `status: clean`, 0 findings, 0 rejected); Security / Architecture / Code Quality / DevOps; full `tests/unit/` run with ledger hashes before/after.

---

## Executive Summary

This sprint's write paths are few and each is guarded: `reset_bucket` journals before it writes, refuses malformed names, and (after the review dissent) never fabricates a bucket that did not exist; the legacy migration appends only through `loa_cheval.metering.ledger.append_ledger` (O_NOFOLLOW — CR-4 proves a symlinked target is refused), de-duplicates by `request_id` or a content key, tags every migrated row, and leaves a receipt with paths, counts and hashes and never row contents; the enforcer's new guard adds a `halt-uncertainty` reason through the existing schema-validated audit event (schemas extended, not bypassed). The read paths never leak what they read: credential presence is decided by `[[ -n ]]` on the environment and a `grep -q` on the dotenv files, and both the CLI and the status block are negatively asserted to print no value. The pricing ladder interpolates only digit-free catalog ids it looked up, never the caller's string, into anything executable — it is pure dictionary traversal with a depth cap. The FR-1 refinement narrows a *denylist* to command position; I probed the wrapped forms (`exec`/`env`/`sudo`/`nice read`) and confirmed none can rebind the caller's variable, so the narrowing loses no genuine catch, and the corpus twins pin the command-position forms that do.

The full-suite run is 5,681/5,693 with every failure classified (two pre-existing classes, one load-induced pair now hardened, one repo-map drift fixed by regeneration); the two ledger rows written during the run are the concurrent dissent invocations, and they show the ladder pricing a CLI hop that was `unknown` in every earlier row. No critical or high finding.

**Overall Risk Level:** LOW

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 4 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 4.6/5 | IV:5 AZ:4 CI:5 IN:4 AV:5 |
| Architecture | 4.6/5 | MO:5 SC:5 RE:4 CX:4 ST:5 |
| Code Quality | 4.4/5 | RD:4 TC:5 EH:4 TS:5 DC:4 |
| DevOps | 4.2/5 | AU:4 OB:5 RC:4 AC:4 DS:4 |
| **Overall** | **4.5/5** | |

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] The enforcer's unpriced guard measures all-time history and spawns a ledger scan per verdict

**Severity:** MEDIUM | **Confidence:** high
**Component:** `.claude/scripts/lib/cost-budget-enforcer-lib.sh` (`_l2_unpriced_share_json`, the guard before `allow`)
**Criterion:** ARCH-RE Reliability / availability of a control (CWE-1050 Excessive Platform Resource Consumption in a Loop is the nearest class: https://cwe.mitre.org/data/definitions/1050.html)
**Reasoning Trace:**
> `budget_verdict` now runs `cost-report.sh --json` (Python, full ledger read) on every call and halts when the all-time share of `pricing_source: unknown` exceeds 5 %. On this repository the share is 74 % from rows written before the ladder existed, so every verdict halts until an explicit re-pricing pass exists; on a large ledger the scan adds latency to a hot path.
**Impact:** a correct but blunt control: it reports unknown spend as unknown (the SDD's intent) at the cost of halting on history the operator cannot fix without a new tool, and of one Python start per verdict.
**Remediation:** bd-ypbg (opt-in re-pricing pass marking rows `repriced_at`); consider a windowed share (report period) and a cached snapshot for the verdict path. Documented in the report and the runbook note requested by the review.
**References:** CWE-1050 (nearest); Flatline SKP-019 (design intent)

---

## Low Priority Issues (Technical Debt)

### [LOW-001] `reset_bucket` journal and state write are not one critical section
**Component:** `.claude/adapters/loa_cheval/routing/circuit_breaker.py` (`reset_bucket`)
**Description:** a `record_failure` racing between the marker and `_write_state` is superseded by the reset; the marker still records the pre-reset state. Operator action; acceptable.

### [LOW-002] Absolute state-file paths in `/loa --json .providers`
**Component:** `.claude/scripts/loa-status.sh` (`get_providers_json`)
**Description:** `list_buckets` includes `path`; harmless locally, strip before shipping the envelope off-host.

### [LOW-003] `cheval --reset-breaker` resolves `.run` relative to the working directory
**Component:** `.claude/adapters/cheval.py` (`cmd_reset_breaker`)
**Description:** consistent with `check_state`'s default in `retry.py`, but an operator running cheval from a subdirectory resets nothing (exit 1, "nothing matched"). Safe direction; a `--run-dir` pass-through or repo-root anchoring would remove the surprise.

### [LOW-004] Pre-existing full-run reds carried
**Component:** `tests/fixtures/*_license.json` (8 grace-period cases), `tests/unit/template-safety.bats` (1)
**Description:** unchanged classes from cycle-124; not touched by this sprint. Regenerate the licence fixtures before the next full run.

---

## Cross-Model Security Observations

- Dissent (`gpt-5.5-pro`, diff only): `status: clean`, 0 findings, 0 rejected. The review dissent on the same surface had one ADVISORY (`reset_bucket` fabricating buckets), fixed and pinned before this audit.

---

## Security Checklist Status

- [x] No hardcoded secrets; credential values never printed (negative assertions in pytest and bats)
- [x] Inputs validated before writes: provider/auth-type names (regex + `_validate_auth_type`), only existing buckets reset, migration rows only via the O_NOFOLLOW writer
- [x] Audit trail: `operator_reset` marker before every reset; migration receipt with hashes; enforcer events schema-validated
- [x] No network; no new dependencies; no new config key
- [x] Test seams bats-gated and hermetic (`LOA_STATUS_RUN_DIR`, `LOA_STATUS_ENV_DIR`, `LOA_BUDGET_COST_REPORT_JSON`); KF-033 ledger isolation verified (two concurrent dissent rows, zero test rows)
- [x] FR-1 refinement narrows a denylist only where the builtin cannot execute in the caller; command-position forms pinned by corpus twins

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 4 |

## Verdict

APPROVED - LET'S FUCKING GO

MED-001 is the SDD's intended behaviour with a stated cost and an owned follow-up (bd-ypbg); the LOWs are recorded as debt.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-244","ts":"2026-09-23T06:02:11Z"} -->
