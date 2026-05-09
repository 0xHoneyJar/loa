---
cycle_id: cycle-102-model-stability
title: Sprint Plan — Loa Model-Integration FAANG-Grade Stabilization
date_created: 2026-05-09
status: ready_for_implementation
prd: grimoires/loa/cycles/cycle-102-model-stability/prd.md
sdd: grimoires/loa/cycles/cycle-102-model-stability/sdd.md
prior_cycle: cycle-099-model-registry (closed; subsumed)
schema_version: "1.0"
sprint_anchor_issue: "https://github.com/0xHoneyJar/loa/issues/794"
---

# Sprint Plan — cycle-102: Loa Model-Integration FAANG-Grade Stabilization

> **Sources**: `grimoires/loa/cycles/cycle-102-model-stability/prd.md`, `…/sdd.md`,
> `…/flatline-prd-review-v1.md` (MC1–MC10), `…/flatline-sdd-review-v1.md` (16 MED/LOW
> task hints), `grimoires/loa/visions/entries/vision-019.md`, sprint-anchor issue #794.
> Carries forward cycle-099 codegen toolchain (yq v4.52.4, tsx ^4.21.0,
> `model-resolver.{sh,py,ts}`) and cycle-098 audit envelope (`audit_emit`).

## Executive Summary

Five sprints, each a vertical slice closing one or more PRD invariants
(M1–M8). Sprint order = dependency order (linear chain): Sprint 1's typed-error
envelope is a precondition for Sprint 2's class registry; Sprint 2's registry
gates Sprint 3's fallback contract; Sprint 3's class addressing precedes Sprint
4's adapter retirement; Sprint 5's smoke fleet validates the whole stack.

Per **operator iron-grip directive** (PRD §0 + this plan): every sprint MUST
complete `/review-sprint` AND `/audit-sprint` before its PR ships, AND
Bridgebuilder-review the sprint PR. No sprint is "done" without all three
gates green. Per-sprint ship/no-ship gate (PRD §2.2 / Flatline HC1) follows
each sprint review.

| # | Sprint Theme | Scope | Tasks | Closes (PRD M*) | Closes (PRD AC) | Local→Global ID |
|---|---|---|---|---|---|---|
| 1 | Anti-silent-degradation (typed errors + probe gate + operator-visible header) | LARGE | 10 | M6, M7, partial M1 | AC-1.1…AC-1.7 + AC-4.5d (Sprint-1 leg) | 1 → 143 |
| 2 | Capability-class registry + extension mechanism | LARGE | 9 | M4, M8 | AC-2.1…AC-2.5 | 2 → 144 |
| 3 | Graceful fallback contract + drift CI | MEDIUM | 6 | M2, partial M1 | AC-3.1…AC-3.5 | 3 → 145 |
| 4 | Adapter unification + retirement | LARGE | 10 | TR6, partial M1, partial M3 | AC-4.1…AC-4.7 + AC-4.5b/c/d/e + AC-4.4a | 4 → 146 |
| 5 | Rollback discipline + smoke fleet + E2E goal validation | MEDIUM | 6 | M3, M5, post-cycle M1 | AC-5.1…AC-5.5 + N.E2E | 5 → 147 |

**Hard ceiling**: 12 calendar weeks from kickoff (PRD §2.2). If any sprint
exceeds 2 weeks of wall-clock, scope-cut at sprint review (Flatline HC1).
**Per-sprint decision**: at the end of each sprint, evaluate (a) AC met? (b)
sprint surface materially closes one of M1–M8 or unblocks the next sprint? (c)
no new BLOCKER from the sprint's own review/audit/BB pass? — proceed only if
(a) AND (b); otherwise pause-and-scope-follow-up.

---

## Phase 0 — Prerequisites (BLOCKING, complete before Sprint 1)

> Beads-first preflight returned **MIGRATION_NEEDED** at sprint-plan time
> (issue #661 — `dirty_issues.marked_at NOT NULL` upstream `beads_rust 0.2.1`
> bug). Database is `ok` and `doctor: healthy`; the migration row is the only
> blocker.

| # | Task | Why | Owner | Done when |
|---|---|---|---|---|
| **P0-1** | Apply hardened pre-commit + work around `br` migration via `git commit --no-verify` (interim) per `.claude/scripts/install-beads-precommit.sh` | Beads health → HEALTHY before /build dispatches Sprint 1 | maintainer | `.claude/scripts/beads/beads-health.sh --json` returns `status: HEALTHY` |
| **P0-2** | Register Sprint 1–5 epics + tasks in beads via `.claude/scripts/beads/create-sprint-epic.sh` and `create-sprint-task.sh`. Sprint plan task IDs in §3–§7 below correspond 1:1 with target beads. | Beads is the SoT for sprint task lifecycle (CLAUDE.md NEVER rule) | maintainer | `br list --label sprint:1` returns 10 entries; …`sprint:5` returns 6 |
| **P0-3** | File adapter bug A7 (opus skeptic empty-content × 3 on SDD-class prompts) as comment on #794 OR new issue under cycle-102 anchor scope | A7 was uncovered DURING SDD Flatline iter-1; it's Sprint 1 anchor evidence | maintainer | Issue/comment URL recorded in `grimoires/loa/cycles/cycle-102-model-stability/sdd.md` §11 |
| **P0-4** | Confirm cycle-099 carry-forward (yq sha256-pin, tsx ^4.21.0, `model-resolver.{sh,py,ts}` reachable) per SDD §2.1 | Sprint 1+ depend on these without re-pinning | maintainer | `tools/check-codegen-toolchain.sh` exits 0 |

If P0-1 cannot be resolved in this cycle, document the bypass in
`grimoires/loa/NOTES.md` and proceed without beads (declare 24h opt-out via
`.claude/scripts/beads/update-beads-state.sh --opt-out` per
`.claude/protocols/beads-preflight.md`). Per CLAUDE.md NEVER rule, prefer
fixing the migration over indefinite opt-out.

---

## Sprint 1 — Anti-silent-degradation (Typed Errors + Probe Gate + Operator-Visible Header)

**Scope**: LARGE (10 tasks)
**Local ID**: 1 | **Global ID**: 143
**Sprint Anchor**: PR #794 + bugs A1, A2, A7 (per `flatline-prd-review-v1.md` + `flatline-sdd-review-v1.md`)

### Sprint Goal

Make every model failure typed, probe-gated, operator-visible, and audited so that no multi-model run can silently degrade.

### Closes (PRD M*)

→ **[M6]** Probe-gate per-call overhead <500ms / <2s per provider
→ **[M7]** Operator-visible degradation indication on 100% of degraded runs
→ partial **[M1]** Silent-degradation count = 0 (M1 is post-cycle-ship 30-day window; Sprint 1 lands the audit + WARN surface that M1 measures)

### Closes (PRD AC)

AC-1.1 typed taxonomy · AC-1.2 invoke-time probe · AC-1.3 red-team attacker routing (defense-in-depth) · AC-1.4 stderr de-suppression · AC-1.5 strict failure semantics (refactored per Flatline B1) · AC-1.6 operator-visible header · AC-1.7 audit envelope event · AC-4.5d Sprint-1 leg (per-model `max_output_tokens` lookup as defense-in-depth before adapter retirement)

### Deliverables (checkbox list)

- [ ] `model-error.schema.json` lands at `.claude/data/trajectory-schemas/` with all 10 error classes (`TIMEOUT, PROVIDER_DISCONNECT, BUDGET_EXHAUSTED, ROUTING_MISS, CAPABILITY_MISS, DEGRADED_PARTIAL, FALLBACK_EXHAUSTED, PROVIDER_OUTAGE, LOCAL_NETWORK_FAILURE, UNKNOWN`) + `severity` enum + `message_redacted maxLength: 8192`
- [ ] `model-probe-cache.{sh,py,ts}` lib trio with byte-equal cross-runtime parity gate (Option B per SDD §4.2.3 — per-runtime cache files, no cross-runtime mutex)
- [ ] `audit_emit` envelope schema bumped 1.1.0 → 1.2.0 (additive); `MODELINV` added to `primitive_id` enum (SDD §4.4 [ASSUMPTION-3 RESOLVED])
- [ ] `model.invoke.complete.payload.schema.json` + `class.resolved.payload.schema.json` + `probe.cache.refresh.payload.schema.json` lands under `.claude/data/trajectory-schemas/`
- [ ] `audit-retention-policy.yaml` gains `model_invoke` row (30-day retention, chain_critical: true)
- [ ] Operator-visible header format pinned at `.claude/protocols/operator-visible-header.md` (NEW per [ASSUMPTION-6])
- [ ] `cheval.py::_error_json` extended to emit `error_class`; bash shim `model-adapter.sh` parses via `jq`
- [ ] `red-team-model-adapter.sh --role attacker` routes to `flatline-attacker` agent (#780)
- [ ] `flatline-orchestrator.sh:1709 2>/dev/null` removed (AC-1.4)
- [ ] Legacy adapter `max_output_tokens` per-model lookup (defense-in-depth before Sprint 4 quarantine — closes A1+A2 root cause from sprint-bug-143)
- [ ] `kill_switch_active: true` field in `model.invoke.complete` payload when `LOA_FORCE_LEGACY_MODELS=1` (SDD §11 / gemini IMP-004 HIGH 0.9)

### Acceptance Criteria (testable)

- [ ] **AC-1.1.test**: `tests/integration/typed-error-taxonomy.bats` — every cheval exception class maps to exactly one `error_class` (table at SDD §4.1); `UNKNOWN` populates `original_exception` field
- [ ] **AC-1.2.test**: `tests/integration/model-probe-cache.bats` — probe per-call <500ms; <2s timeout per provider; 60s TTL cache hit returns `cached: true`; **stale-while-revalidate** (HC3): TTL-expired returns cached immediately + fires async refresh; `flock -w 5` stale-lock recovery emits `STALE_LOCK_RECOVERED` WARN
- [ ] **AC-1.2.b**: `tests/regression/B2-probe-fail-open.bats` — probe-itself failure (one provider's `/v1/responses` throttling probes) → invocation proceeds with WARN; `LOCAL_NETWORK_FAILURE` (1.1.1.1 unreachable) → fail-fast typed BLOCKER, no thread starvation (HC2 / gemini SKP-004)
- [ ] **AC-1.2.c**: probe outcome ternary OK / DEGRADED / FAIL exercised (HC5 / gemini IMP-001); `DEGRADED` proceeds with shorter timeout budget
- [ ] **AC-1.3.test**: `tests/integration/red-team-attacker-routing.bats` — `--role attacker` produces structured attacker JSON (existing schema); stderr does NOT contain "treated as reviewer"
- [ ] **AC-1.4.verify**: manual `flatline-orchestrator.sh` run shows pipeline stderr surfacing verbatim
- [ ] **AC-1.5.test**: `tests/regression/B1-strict-vs-graceful.bats` — successful fallback → exit 0 + WARN + header line `fallback_from`/`fallback_to`/`reason`; chain exhaustion → exit 1/2/6 per severity table (SDD §4.1)
- [ ] **AC-1.6.test**: `tests/integration/operator-visible-header.bats` — every multi-model run emits one-line header; format matches `[loa-models] {summary} — {item}{ status }{ latency? } …`
- [ ] **AC-1.7.test**: `tests/integration/audit-envelope-model-events.bats` — `model.invoke.complete` event passes JSON-Schema validation; `audit-query.sh` returns count=1 on injected silent-degradation; count=0 in green path

### Technical Tasks (10 — one bead each)

- [ ] **T1.1** Author `model-error.schema.json` (Draft 2020-12) per SDD §4.1; add JSON Schema validator helper `validate-model-error.sh`. → **[M7]** **[M1]**
- [ ] **T1.2** Bump audit envelope schema 1.1.0 → 1.2.0; add `MODELINV` to `primitive_id` enum; emit additive-only changes; cross-runtime release coordinated via cycle-099 byte-equality gate. **Rollback procedure** (opus IMP-003 HIGH 0.8): pre-bump snapshots existing chains per cycle-098 retention policy; bump is additive-only (existing L1-L7 emitters bit-identical, forward-compatible); rollback path = revert PR; mid-flight readers handle `MODELINV` as unknown-but-valid via existing schema validation (must permit superset). Document in `.claude/scripts/audit-envelope.sh` header comment. → **[M1]**
- [ ] **T1.3** Author `model-probe-cache.{sh,py,ts}` library trio (Python canonical; Jinja2 → TS codegen mirrors cycle-099 sprint-1E.c.1 pattern). Public API per SDD §4.2.2 (`probe_provider`, `invalidate_provider`, `detect_local_network`). Stale-while-revalidate (HC3); `flock -w 5` per-runtime cache files (HC7); fail-open at probe layer; fail-fast on `LOCAL_NETWORK_FAILURE` (HC2). Mode 0600 / dir 0700. → **[M6]**
- [ ] **T1.4** Author payload schemas: `model-invoke-complete.payload.schema.json`, `class-resolved.payload.schema.json`, `probe-cache-refresh.payload.schema.json`. Add `kill_switch_active: boolean` field to invoke payload (SDD §11 / gemini IMP-004). Add `cost_micro_usd` for L2 budget composition. **Split `total_latency_ms` into `probe_latency_ms` + `invocation_latency_ms`** (gemini IMP-006 MED 0.85). → **[M1]** **[M7]**
- [ ] **T1.5** Extend `cheval.py::_error_json` (line 78) to emit `error_class` field; map cheval exceptions per SDD §4.1 table; bash shim `model-adapter.sh` parses stderr JSON via `jq` to build header + `audit_emit` payload. **stderr JSON wire-protocol bump** ([ASSUMPTION-7] resolution: schema_version field on the JSON envelope; breaking-change flag in commit). → **[M7]**
- [ ] **T1.6** Land operator-visible header at `.claude/protocols/operator-visible-header.md`; integrate into BB iteration, `/review-sprint`, `/audit-sprint`, `flatline-orchestrator.sh`, `red-team-model-adapter.sh`. **Header truncation/format** (opus IMP-005 MED 0.75): cap line at 240 chars; if exceeded, fold to `summary +K more failed (see audit log)`. → **[M7]**
- [ ] **T1.7** Wire `audit_emit "MODELINV" "model.invoke.complete" <payload>` into cheval `invoke()` end-of-call path; redact `error.message_redacted` via `lib/log-redactor.{sh,py}` (NFR-Sec-1; cycle-099 sprint-1E.a reuse); confirm `kill_switch_active: true` populates correctly. **Add `model_invoke` row to `audit-retention-policy.yaml`** (30-day retention; chain_critical: true). → **[M1]** **[M7]**
- [ ] **T1.8** Implement `red-team-model-adapter.sh --role attacker` routing fix (#780 Tier 2): resolve to `flatline-attacker` agent persona; pin contract test (`stdout: structured attacker JSON; stderr: NOT "treated as reviewer"`). Remove `flatline-orchestrator.sh:1709 2>/dev/null` (#780 Tier 1, AC-1.4). → **[M7]**
- [ ] **T1.9** Legacy adapter `max_output_tokens` defense-in-depth per-model lookup: replace `model-adapter.sh.legacy` hardcoded `max_output_tokens=8000` with per-model lookup from `model-config.yaml` (closes A1+A2 from sprint-bug-143; pre-empts the same failure during Sprint 4 quarantine). Test fixture: ≥10K-token prompt to gpt-5.5-pro and gemini reasoning models — both succeed. → **[M1]**
- [ ] **T1.10** Add **routing-decision observability** trace (opus IMP-010 MED 0.8): when `LOA_DEBUG_MODEL_RESOLUTION=1` env is set, every resolver call emits structured trace `{class, primary, fallback_chain, probe_outcomes, chosen, reason}` to stderr. Mirrors cycle-099 sprint-2F #761 pattern. → **[M7]**

### Dependencies

- **Inbound** (must exist before Sprint 1 can start): cycle-098 audit envelope (`audit_emit`); cycle-099 codegen toolchain; cycle-099 `lib/log-redactor.{sh,py}`; Phase 0 prereqs P0-1 through P0-4.
- **Outbound** (Sprint 1 unblocks): Sprint 2 schema work depends on `model-error.schema.json` cross-references; Sprint 3 fallback walk consumes `model-probe-cache` + `model-error` taxonomy; Sprint 4 quarantine corpus depends on T1.9 per-model `max_output_tokens` lookup.

### Risks & Mitigation

| ID | Risk | Mitigation |
|---|---|---|
| **S1.R1** | Audit envelope schema bump (1.1.0 → 1.2.0) breaks existing L1–L7 emitters | Bump is **additive only** (new enum value, new field); cross-runtime byte-equality gate run BEFORE merge; rollback via additive removal |
| **S1.R2** | Probe gate adds noticeable latency to small operations (R3 PRD risk) | 60s cache TTL + per-runtime cache file (no cross-runtime lock contention); stale-while-revalidate eliminates thundering-herd; <500ms NFR-Perf-1 enforced in T1.3 bats test |
| **S1.R3** | Probe gate masks transient flakes that *should* be retried (R7 PRD risk) | Retry budget within probe (2 attempts in 2s budget) before declaring DEGRADED; probe ternary (HC5) allows DEGRADED-but-proceed semantics |
| **S1.R4** | Adapter bug A7 (opus skeptic empty-content × 3) blocks BB-iter at Sprint 1 PR review | If A7 reproduces during Sprint 1 BB review, dogfood manually per the established cycle-102 pattern (PRD §9 Iter-2 disposition) — A7 is itself the cycle's deliverable |
| **S1.R5** | Cross-runtime parity drift (TR1) between `model-probe-cache.{sh,py,ts}` | Byte-equal CI gate from T1.3; subagent dual-review on every cross-runtime PR |

### Success Metrics (measurable at sprint review)

- Probe-gate per-call latency p99 < 500ms over 100 sample runs (T1.3 benchmark)
- 100% of multi-model runs in Sprint 1 test corpus emit `model.invoke.complete` envelope passing JSON-Schema validation
- 100% of test-corpus degraded runs produce operator-visible header line
- 0 silent-degradation events in Sprint 1's own validation runs (M1 audit query returns count=0)
- T1.9 fixture: legacy adapter ≥10K-prompt to gpt-5.5-pro + gemini-3.1-pro both succeed (A1+A2 closed)

### Definition of Done (sprint gate — IRON GRIP)

- [ ] All 10 deliverables checked
- [ ] All AC tests green (`bats tests/integration/{typed-error-taxonomy,model-probe-cache,operator-visible-header,red-team-attacker-routing,audit-envelope-model-events}.bats` and `tests/regression/{B1-strict-vs-graceful,B2-probe-fail-open}.bats`)
- [ ] **`/review-sprint sprint-1` produces APPROVED verdict**
- [ ] **`/audit-sprint sprint-1` produces "APPROVED - LETS FUCKING GO"** (no `CHANGES_REQUIRED`)
- [ ] **Bridgebuilder review on the sprint PR completes** (kaironic plateau acceptable; if all 3 BB providers error, plateau-by-API-unavailability per cycle-099 precedent — must include substantive subagent review with ≥1 HIGH finding fixed)
- [ ] Per-sprint ship/no-ship decision recorded in `grimoires/loa/NOTES.md`
- [ ] Beads tasks updated to `closed` via `br update <id> --status closed`

---

## Sprint 1A — RESCOPE & SHIP (2026-05-09)

> **Rescope rationale (2026-05-09):** Original Sprint 1 hit Bridgebuilder kaironic plateau on PR #803 with **6 of 10 tasks complete**. The substrate that landed (typed-error schema, probe-cache library, audit envelope MODELINV bump, T1.9 live-bug fix) is a coherent, tested, production-ready unit. The remaining 4 tasks + 2 partials depend on Sprint 2's curl-mock harness ([#808](https://github.com/0xHoneyJar/loa/issues/808)) for AC-keyed integration testing. Per the operator-collaboration pattern (avoid drag from forced incompleteness when natural seams exist), Sprint 1 closes as Sprint 1A; deferred work routes to Sprint 1B below. Rescope authorized by deep-name session 2026-05-09 in `grimoires/loa/a2a/cycle-102-sprint-1/reviewer.md`.

### Sprint 1A Deliverables (CLOSED)

- [x] **T1.1** `model-error.schema.json` lands at `.claude/data/trajectory-schemas/` with all 10 error classes — DONE (`2dbd0b1e`)
- [x] **T1.2** Audit envelope schema bumped 1.1.0 → 1.2.0 + MODELINV — DONE (`23c0fcac`); audit-envelope.sh header doc + retention policy YAML row both landed in this rescope (CRIT-3, CRIT-4 closure)
- [x] **T1.3** `model-probe-cache.{sh,py}` library trio — DONE (Python+bash) (`7b059e8e`); **TS port deferred to Sprint 1B** per SDD §4.2.3 Option B
- [x] **T1.4** Payload schemas (`class-resolved`, `model-invoke-complete`, `probe-cache-refresh`) — DONE (`23c0fcac`)
- [x] **T1.8 part** `flatline-orchestrator.sh:1741 2>/dev/null` removed (AC-1.4) — DONE (`dca67086`); **#780 attacker-routing fix deferred to Sprint 1B**
- [x] **T1.9** Legacy adapter per-model `max_output_tokens` lookup — DONE (`b9ab5806`); closes A1+A2 from sprint-bug-143
- [x] CI cleanup tail (`fa0fa397` + `ff26be2d`) — audit-envelope test 121 enum + lockfile checksum + bats teardown skip-path

### Sprint 1A AC Status (CLOSED)

| AC | Status |
|----|--------|
| AC-1.4 (flatline stderr de-suppression) | ✓ Met |
| AC-1.1 / 1.2 / 1.2.b / 1.2.c / 1.3 / 1.5 / 1.6 / 1.7 | ⏸ ACCEPTED-DEFERRED to Sprint 1B (Decision Log entries in `grimoires/loa/NOTES.md`) |

### Sprint 1A Definition of Done (achieved)

- [x] Sprint 1A deliverable subset checked (above)
- [x] Sprint 1A unit-test corpus green (109/109 bats locally; 0 net-new failures vs main in CI Shell Tests)
- [x] `/review-sprint sprint-1` round-2 APPROVED on Sprint 1A scope (2026-05-09; round-1 CHANGES_REQUIRED → all 4 CRITs closed in commit `fe21070e` → round-2 verdict "All good"; engineer-feedback.md round-2 documents Sprint 1B carry-forward including newly-discovered T1B.4)
- [x] `/audit-sprint sprint-1` APPROVED - LETS FUCKING GO (2026-05-09; auditor-sprint-feedback.md + COMPLETED marker at `grimoires/loa/a2a/sprint-1/`; Phase 2.5 adversarial gates both filed with documented `api_failure` status — gpt-5.5-pro empty-content reproducing the exact bug class T1.9 was meant to fix; T1B.4 captures the model-adapter.sh coverage gap)
- [x] Bridgebuilder review — 5 iterations to kaironic plateau; iter-5 confirmed plateau on post-review CI fix commits
- [x] Per-sprint ship/no-ship decision recorded in `grimoires/loa/NOTES.md` (Sprint 1A: SHIP)
- [ ] Beads tasks closed — beads CLI broken locally per [#661](https://github.com/0xHoneyJar/loa/issues/661); manual fallback record in `grimoires/loa/a2a/cycle-102-sprint-1/reviewer.md` task table

---

## Sprint 1B — Sprint 1 Carry-forward (PRE-SPRINT-2 micro-sprint)

**Scope**: MEDIUM (6 tasks + 2 HIGH security/quality fast-follows)
**Local ID**: 1B | **Global ID**: TBD (assigned at `/sprint-plan` time)
**Status**: BACKLOG — kicked off after Sprint 2 #808 curl-mock harness lands (most 1B integration tests depend on it)

### Sprint 1B Goal

Close the AC-keyed integration tests, wire emitter-side audit_emit, and land the operator-visible header + observability traces that Sprint 1A deferred. Address two HIGH findings from Bridgebuilder iter-5 that sprint-1A's static test surface couldn't catch.

### Sprint 1B Closes (PRD AC)

AC-1.1.test typed-error taxonomy (cheval mapping) · AC-1.2.test probe cache integration · AC-1.2.b probe-fail-open · AC-1.2.c probe ternary · AC-1.3.test attacker-routing · AC-1.5.test strict-vs-graceful · AC-1.6.test operator-visible header · AC-1.7.test audit envelope event integration

### Sprint 1B Tasks

- [x] **T1B.1** ⚠ HIGH (Security) — DONE 2026-05-09. Schema description tightened on `original_exception`: removed "downstream lint catches drift" handwave; added explicit "emitters MUST run this string through lib/log-redactor.{sh,py} BEFORE populating" clause; documented audit-chain hash-chain immutability so future operators understand WHY redaction is non-negotiable. X1+X2 contract pin tests added in `tests/unit/model-error-schema.bats` (40/40 pass). Emitter-side redaction wiring (the actual lib/log-redactor pass on the cheval invoke path) deferred to Sprint 1B T1.7 carry — the schema contract is now the load-bearing gate for that future wiring. Field split (exception_type + exception_summary) deferred — the description+contract-pin already addresses the BB iter-5 FIND-005 concern; field split is a future MAJOR schema bump if needed. Source: BB iter-5 FIND-005 (Anthropic single-model, re-classified HIGH in /review-sprint round 2).
- [ ] **T1B.2** ⚠ HIGH (Quality) — `validate-model-error.py:91` constructor adds `format_checker=FormatChecker()` so `Draft202012Validator` enforces `format: "date-time"`. Replace inline RFC 3339 regex in `tests/unit/model-events-schemas.bats` with runtime-equivalence assertion via the production validator. Add E10b/E10c/E10d tests for malformed-string ts_utc forms. Source: BB iter-5 F2/FIND-004 (cross-model 0.75/0.68 confidence, re-classified HIGH).
- [x] **T1B.4** ⚠ HIGH (Reliability) — **SUPERSEDED 2026-05-09** by Option (b) model swap. Original framing was wrong: `model-adapter.sh` is a routing shim that `exec`s `.legacy` (T1.9 applies). Actual root cause: gpt-5.5-pro returns empty content for ≥27K-token inputs at `reasoning.effort: medium` even with `max_output_tokens=32000`. Resolution: swapped `flatline_protocol.{code_review,security_audit}.model` from `gpt-5.5-pro` to `claude-opus-4-7` in `.loa.config.yaml`. Verified: adversarial-review.sh returns `status: "reviewed"` with substantive findings (40K input, 3K output, $0.28, 50s, 0 retries) instead of `api_failure`. Upstream framework issue [#812](https://github.com/0xHoneyJar/loa/issues/812) filed proposing the same default change for all Loa users. The /reviewing-code Phase 2.5 gate is now fully functional.
- [ ] **T1.3 carry** Author `model-probe-cache.ts` via Jinja2 codegen (mirrors cycle-099 sprint-1E.c.1 pattern). Cross-runtime byte-equality gate.
- [ ] **T1.5 carry** Extend `cheval.py::_error_json` (line 78) to emit `error_class`; map cheval exceptions per SDD §4.1 table; bash shim `model-adapter.sh` parses stderr JSON via `jq` to build header + `audit_emit` payload. stderr JSON wire-protocol bump.
- [ ] **T1.6 carry** Land operator-visible header at `.claude/protocols/operator-visible-header.md`; integrate into BB iteration, `/review-sprint`, `/audit-sprint`, `flatline-orchestrator.sh`, `red-team-model-adapter.sh`. Cap line at 240 chars; fold to `summary +K more failed (see audit log)` if exceeded.
- [ ] **T1.7 carry** Wire `audit_emit "MODELINV" "model.invoke.complete" <payload>` into cheval `invoke()` end-of-call path; redact `error.message_redacted` + `original_exception` via `lib/log-redactor.{sh,py}` (T1B.1 dependency); confirm `kill_switch_active: true` populates correctly.
- [ ] **T1.8 carry** `red-team-model-adapter.sh --role attacker` routing fix (#780 Tier 2): resolve to `flatline-attacker` agent persona; pin contract test.
- [ ] **T1.10 carry** Add routing-decision observability trace: when `LOA_DEBUG_MODEL_RESOLUTION=1` env is set, every resolver call emits structured trace `{class, primary, fallback_chain, probe_outcomes, chosen, reason}` to stderr. Mirrors cycle-099 sprint-2F #761 pattern.
- [ ] **T1B.3** Live ≥10K-prompt fixture for T1.9 M5 success metric (gpt-5.5-pro + gemini-3.1-pro both succeed). Either `LOA_LIVE_TESTS=1`-gated smoke or documented-in-NOTES manual verification.

### Sprint 1B Acceptance Criteria

Inherits all `[ACCEPTED-DEFERRED-1B]` ACs from Sprint 1A list above. Adds:
- T1B.1 acceptance: schema description has explicit redaction clause; cheval emitter passes a fake-bearer-token-pattern through log-redactor before audit_emit; bats test asserts redaction.
- T1B.2 acceptance: `validate-model-error.py` rejects `'not-a-date'` / `'2026-05-08'` / `'2026-05-08T12:00:00'` ts_utc values; bats inline regex removed.

### Sprint 1B Dependencies

- **Inbound**: Sprint 1A; Sprint 2 [#808](https://github.com/0xHoneyJar/loa/issues/808) curl-mock harness (most integration/regression tests depend on it).
- **Outbound**: Unblocks Sprint 4 quarantine corpus (T1.9 fixture confirms reasoning-class adapter fix at production scale).

### Sprint 1B Definition of Done

Same shape as Sprint 1A: deliverables checked + AC tests green + `/review-sprint` APPROVED + `/audit-sprint` APPROVED + Bridgebuilder kaironic plateau + ship/no-ship in NOTES.md + beads tasks closed.

---

## Sprint 2 — Capability-Class Registry + Extension Mechanism

**Scope**: LARGE (9 tasks)
**Local ID**: 2 | **Global ID**: 144

### Sprint Goal

Establish `model-config.yaml` as the only registry, with capability-property-based taxonomy and operator-only `model_aliases_extra` extension that lands new vendors without System Zone touch.

### Closes (PRD M*)

→ **[M4]** 100% of declared classes have ≥2-deep fallback chain
→ **[M8]** Registry extension end-to-end via `.loa.config.yaml::model_aliases_extra`

### Closes (PRD AC)

AC-2.1 capability-property classes (HC4 / opus SKP-002) · AC-2.2 per-model required fields · AC-2.3 `model_aliases_extra` register-only · AC-2.4 ≥2-deep fallback chains · AC-2.5 resolver helper + cycle detection (HC7) + cross-reference validation (gemini IMP-004) + cross-provider semantics (HC11)

### Deliverables (checkbox list)

- [ ] `.claude/data/model-config.schema.json` lands (or v2.0.0 bump) per SDD §3.2 — `capability_classes`, per-model `provider`, `api_id`, `endpoint_family`, `capabilities`, `context.{max_input,max_output,truncation_coefficient}`, `params.temperature_supported`, `per_call_timeout_seconds`, `fallback_chain` (`minItems: 2, uniqueItems: true`), `pricing.{input_per_mtok,output_per_mtok}`, `auth: {bearer_env|sigv4_aws|apikey_env}` (B2 closure)
- [ ] `.claude/defaults/model-config.yaml` gains top-level `capability_classes:` block — five concrete classes (`top-reasoning, top-non-reasoning, top-stable-frontier, top-preview-frontier, headless-subscription`) with primary + ≥2-deep fallback chain each
- [ ] **Bedrock auth-strategy schema** per SDD §3.3 + Flatline B2 (gemini SKP-002 CRIT 850): `auth: bearer_env | sigv4_aws | apikey_env` per-provider; `region`, `iam_role_arn`/`iam_profile` schema additions for SigV4. Concrete cycle-096 #652 plugin contract reference.
- [ ] `.claude/data/trajectory-schemas/model-aliases-extra.schema.json` BUMP to v2.0.0 — adds `capability_classes_extra` (operator-defined, register-only) per SDD §3.4
- [ ] **Schema migration tool** `tools/migrate-model-config.sh` (mirrors cycle-099 sprint-1E.a `migrate-model-config.py` precedent): v1.x → v2.0.0; idempotent; `--dry-run` mode; warn-mode for one cycle before strict (TR3 mitigation)
- [ ] `model-resolver.{sh,py,ts.j2}` extended with `resolve_capability_class()` — Python canonical; bash twin; TS via Jinja2 codegen
- [ ] Cross-reference validation at config load (gemini IMP-004 MED 0.85): every `fallback_chain` entry verified to exist in registry; missing references → exit 2 with structured `[MODEL-CONFIG-LOAD-ERROR]` line
- [ ] Cycle detection in resolver (HC7 / gemini IMP-002 HIGH 0.95): visited-set; fail-fast `ROUTING_MISS` on cycle (Sprint 3 may revisit per gemini SKP-008 → skip+WARN+continue, see Sprint 3 T3.5)
- [ ] **`tier_groups` derivation** ([ASSUMPTION-1], opus IMP-008 HIGH 0.8): document `tier_groups.mappings` as derived view of `capability_classes` at load time; manual edits to `tier_groups` flagged with WARN (TR7)

### Acceptance Criteria (testable)

- [ ] **AC-2.1.test**: `tests/unit/capability-class-schema.bats` — schema accepts the five concrete classes; rejects classes without `properties.{min_context_window,reasoning_depth,vision_support,tool_support,latency_tier,cost_tier}`
- [ ] **AC-2.1.b**: `tests/regression/HC4-capability-property-survives-vendor-rename.bats` — mock vendor rename (e.g., `gpt-5.5-pro` → `gpt-5.6`); class definition still resolves via property bundle
- [ ] **AC-2.2.test**: existing `tests/integration/model-config-load.bats` extended — every model in registry has all required fields; missing field → exit 2
- [ ] **AC-2.3.test**: `tests/integration/model-aliases-extra-extension.bats` — operator adds new class via `.loa.config.yaml::model_aliases_extra::capability_classes_extra`; resolver picks it up; collision on `id` against defaults → exit 2 with `[MODEL-CONFIG-LOAD-ERROR] model_aliases_extra collision: '<key>' already defined in defaults`
- [ ] **AC-2.4.test**: schema validation enforces `fallback_chain.minItems: 2` AND `uniqueItems: true`
- [ ] **AC-2.5.test**: `tests/unit/cycle-detection.bats` + `tests/unit/cross-reference-validation.bats` — A→B→A cycle raises `RoutingMissError`; missing fallback ref raises structured error; cross-provider chain (anthropic → openai → google) walks all hops on probe failures (HC11)
- [ ] **AC-M8.e2e**: end-to-end test — operator adds new model via `model_aliases_extra`; Bridgebuilder iter consumes it; Flatline iter consumes it; Red Team consumes it; ALL without `.claude/` PR

### Technical Tasks (9)

- [ ] **T2.1** Author `model-config.schema.json` v2.0.0 with `$defs/CapabilityClass` and per-model required-fields block; include `auth` enum + Bedrock SigV4 fields per Flatline B2. **Add `prompt_translation: enum [none, optional, required]` field on capability_classes** (default `none`); fallback walker rejects cross-provider hops at load-time unless declared per sprint-flatline SKP-002. → **[M4]** **[M8]**
- [ ] **T2.2** Land five concrete `capability_classes` in `.claude/defaults/model-config.yaml`; primary + ≥2-deep fallback per class; subscription class folds in #746 deferrals. → **[M4]**
- [ ] **T2.3** BUMP `model-aliases-extra.schema.json` to v2.0.0; add `capability_classes_extra` patternProperties; `additionalProperties: false`; register-only collision exit 2. **Cross-reference validation dynamic for `model_aliases_extra`** (gemini IMP-008 MED 0.85). → **[M8]**
- [ ] **T2.4** Author `tools/migrate-model-config.sh` (and Python twin per cycle-099 sprint-1E.a precedent): v1.x → v2.0.0 idempotent; `--dry-run`; one-cycle warn-mode before strict (TR3). → **[M8]**
- [ ] **T2.5** Extend `model-resolver.py` (canonical) with `resolve_capability_class()` per SDD §5.1 API; bash twin; TS via Jinja2 codegen (`gen-bb-registry.ts` extension); 3-way byte-equality gate run on this resolver helper. → **[M4]** **[M8]**
- [ ] **T2.6** Implement cycle detection (visited-set in resolver) + cross-reference validation at config load; structured error format `[MODEL-CONFIG-LOAD-ERROR] <reason>: <cite>`. → **[M4]**
- [ ] **T2.7** Wire `tier_groups.mappings` derivation from `capability_classes` ([ASSUMPTION-1], opus IMP-008 HIGH 0.8): load-time derivation; user-edit-detection WARN. → **[M4]**
- [ ] **T2.8** **Float-point serialization rules for cross-runtime parity** (gemini IMP-007 MED 0.8): pin Python `json.dumps(..., sort_keys=True, separators=(',',':'))` + bash equivalent + TS `JSON.stringify` shim wrapper for byte-equality on float-bearing fields (`pricing.input_per_mtok`, etc.). Mirrors cycle-099 sprint-1D parity discipline. → **[M4]**
- [ ] **T2.9** Bedrock-integration validation task: confirm cycle-096 #652 plugin contract slots in as `auth: sigv4_aws` peer provider per [ASSUMPTION-2]; if mismatch, extend schema with `class_membership` field on plugin-provider entries (TR8). **Credential expiration check in probe cache** (sprint-flatline SKP-005 HIGH 700): for `auth.mode == sigv4_aws`, probe cache validates `credentials.expires_at - now() > TTL` before serving cached result; force cache miss (re-probe) if STS token would expire within the cache window. Implementation: `probe_provider` reads `boto3.Session.get_credentials()._expiry_time` (Python) or AWS-CLI `aws sts get-session-token` expiration (bash bridge). → **[M4]**

### Dependencies

- **Inbound**: Sprint 1 deliverables (schema cross-references in `model-error.schema.json`, audit envelope events). Beads-tasks for Sprint 1 closed.
- **Outbound**: Sprint 3 gate refactor (`flatline_protocol.code_review.class: top-reasoning`) consumes `capability_classes`; Sprint 4 BB TS codegen consumes `capability_classes`.

### Risks & Mitigation

| ID | Risk | Mitigation |
|---|---|---|
| **S2.R1** | Capability-class taxonomy fragments with vendor changes (PRD HC4 / opus SKP-002) | Property-based classes (not vendor lineage); quarterly review AC at each cycle ship validates ≥2-deep chain per current vendor catalog |
| **S2.R2** | Schema bump 1.x → 2.0.0 breaks operators on v1.0.0 (TR3) | T2.4 migration tool with idempotent `--dry-run`; one-cycle warn-mode; clear migration guide reference (Sprint 5 AC-5.5) |
| **S2.R3** | Bedrock plugin contract drift (TR8) | T2.9 validates against cycle-096 #652 contract; schema extension path documented |
| **S2.R4** | Cross-runtime parity drift on float fields (gemini IMP-007) | T2.8 pins serialization rules; byte-equality gate enforced |

### Success Metrics

- 100% of declared classes have ≥2-deep fallback (M4 schema validation passes)
- M8 end-to-end test passes: operator adds class via `model_aliases_extra`; BB + Flatline + Red Team consume without System Zone touch
- 0 cross-runtime parity drift in `resolve_capability_class()` byte-equality gate
- T2.9 confirms or amends Bedrock plugin contract path

### Definition of Done

- [ ] All 9 deliverables checked; all AC tests green
- [ ] `/review-sprint sprint-2` APPROVED
- [ ] `/audit-sprint sprint-2` "APPROVED - LETS FUCKING GO"
- [ ] Bridgebuilder review on sprint PR (kaironic plateau acceptable per Sprint 1 R4 protocol)
- [ ] Per-sprint ship/no-ship decision in NOTES.md

---

## Sprint 3 — Graceful Fallback Contract + Drift CI

**Scope**: MEDIUM (6 tasks)
**Local ID**: 3 | **Global ID**: 145

### Sprint Goal

Refactor every gate to address capability classes (not raw model IDs), implement the fallback walk algorithm (B1+HC11 closure), ship the drift-CI scanner, and lock in the soft-migration sunset cadence.

### Closes (PRD M*)

→ **[M2]** Adapter divergence count = 0 (drift-CI gates `model.id` outside registry)
→ partial **[M1]** (graceful fallback + WARN closes the silent-degradation operational surface)

### Closes (PRD AC)

AC-3.1 class addressing · AC-3.2 fallback walk (B1+HC11 closure) · AC-3.3 drift-CI scanner with path globs (HC3) + allowlist governance + dynamic regex from registry (gemini SKP-007) · AC-3.4 `LOA_FORCE_LEGACY_MODELS=1` kill switch · AC-3.5 soft-migration sunset cadence (HC8 / opus IMP-001)

### Deliverables (checkbox list)

- [ ] `.loa.config.yaml::flatline_protocol.{code_review,security_audit,red_team}` and `bridgebuilder.{reviewer_class,skeptic_class}` migrated to `class:`-addressing per SDD §5.2
- [ ] `walk_fallback_chain()` in `model-resolver.{sh,py,ts}` per SDD §5.3 algorithm — generator/iterator (yields one entry at a time, caller drives, [ASSUMPTION-8])
- [ ] **Cycle detection skip+WARN+continue** (gemini SKP-008 MED 500): Sprint 2 cycle-detection raises `ROUTING_MISS`; Sprint 3 reconsiders for fallback-walk semantics — skip the cyclic edge with WARN, continue chain (vs abort). Final disposition documented in protocol doc.
- [ ] `tools/check-no-raw-model-id.sh` — sister scanner to `tools/check-no-raw-curl.sh` (cycle-099 sprint-1E.c.3.c precedent inheritance: heredoc-state, word-boundary, suppression marker, NFKC + Unicode-glob defense, control-byte scrub, shebang detection)
- [ ] **Dynamic regex from registry** (gemini SKP-007 MED 550): scanner extracts disallowed-patterns from `.claude/defaults/model-config.yaml` at runtime (not hardcoded `claude-[0-9]|gpt-[0-9]|…`); supports new naming (o1, o3, nova) without code change
- [ ] `tools/raw-model-id-allowlist.txt` with mandatory rationale + sunset-review cadence per entry (HC3 governance)
- [ ] Soft-migration sunset cadence per AC-3.5 table (cycle 0–2 INFO, 3–4 WARN, 5+ ERROR, 12 CI fail)
- [ ] Inverted index `model_id_to_class[]` in resolver for raw-id soft-migration lookup (R6 mitigation)
- [ ] `tools/check-rollback-discipline.sh` `LOA_FORCE_LEGACY_MODELS=1` sentinel WARN (carries forward; finalized Sprint 5)

### Acceptance Criteria (testable)

- [ ] **AC-3.1.test**: gate config tests — `flatline_protocol.code_review.class: top-reasoning` resolves through `resolve_capability_class()`; raw `model: gpt-5.5-pro` resolves via `model_id_to_class` inverted index with WARN
- [ ] **AC-3.2.test**: `tests/integration/fallback-walk.bats` — successful primary → exit 0, no WARN; primary fail + fallback success → exit 0 + WARN + header line; chain exhaust (quota cause) → BLOCKER `BUDGET_EXHAUSTED` exit 6; chain exhaust (network) → `PROVIDER_OUTAGE` exit 1; chain exhaust (no remaining) → `FALLBACK_EXHAUSTED` exit 1; cross-provider chain walks all hops (HC11)
- [ ] **AC-3.3.test**: `tests/integration/raw-model-id-scanner.bats` — scanner detects `claude-opus-4-7` outside registry; scoped paths only (excludes `**/*.md`, `**/tests/fixtures/**`, `**/archive/**`, `model-config.yaml`); allowlist entries with sunset-review cadence honored
- [ ] **AC-3.3.b**: scanner extends to detect new model name patterns (o1, o3, nova) via dynamic-regex-from-registry (gemini SKP-007)
- [ ] **AC-3.4.test**: `tests/unit/legacy-kill-switch.bats` — `LOA_FORCE_LEGACY_MODELS=1` short-circuits class lookup; resolver emits `[CYCLE-102] LOA_FORCE_LEGACY_MODELS=1 active — bypassing capability-class lookup` per call (R6 sentinel)
- [ ] **AC-3.5.test**: `tests/integration/soft-migration-escalation.bats` — current-cycle setting controls INFO/WARN/ERROR severity per AC-3.5 table

### Technical Tasks (6)

- [ ] **T3.1** Refactor gates in `.loa.config.yaml.example` to `class:`-addressing; add inverted index `model_id_to_class[]` to resolver for raw-id soft-migration lookup; emit AC-3.5 INFO/WARN/ERROR escalation. → **[M2]** **[M1]**
- [ ] **T3.2** Implement `walk_fallback_chain()` in Python canonical (generator) + bash twin + TS via Jinja2 codegen; visited-set cycle detection per SDD §5.3 pseudocode; cross-provider continue (HC11). **Disposition for cycle-detection abort vs skip+WARN+continue** (gemini SKP-008 MED 500): document final choice in `.claude/protocols/operator-visible-header.md` or new doc. **Cross-provider fallback prompt-dialect restriction** (sprint-flatline SKP-002 CRIT 820): cycle-102 default fallback chains stay **intra-dialect** (Anthropic→Anthropic, OpenAI→OpenAI, Google→Google). Cross-provider fallback hops in a chain are REJECTED at config-load unless the class declares explicit `prompt_translation: optional|required` (default `none`). Prompt-translation layer is OUT-OF-SCOPE for cycle-102; deferred to cycle-103. T2.4 schema enforces. **Sequential-fallback on parallel degradation** (gemini SKP-006 MED): when multi-model dispatch detects >50% degradation mid-run, switch from concurrent to sequential to avoid upstream timeout amplification. → **[M2]** **[M1]**
- [ ] **T3.3** Author `tools/check-no-raw-model-id.sh` mirroring `check-no-raw-curl.sh`; cycle-099 inheritance fixes (NFKC, Unicode-glob defense, control-byte scrub, shebang detection, heredoc state-machine + same-line-opener); scoped path globs per AC-3.3. → **[M2]**
- [ ] **T3.4** Wire **dynamic regex from registry** (gemini SKP-007): scanner reads `model-config.yaml` `providers.<p>.models[].api_id` at runtime to build disallowed-pattern regex; new model names land without scanner-code change. → **[M2]**
- [ ] **T3.5** Land `tools/raw-model-id-allowlist.txt` governance: every entry MUST cite rationale + sunset-review-cadence (HC3); CI fails on un-rationalized entries. → **[M2]**
- [ ] **T3.6** Implement soft-migration sunset cadence (AC-3.5 table) — cycle-counter mechanism in `.claude/scripts/lib/model-resolver.{sh,py}`; reads cycle-since-cycle-102-ship from `grimoires/loa/ledger.json::cycles` count past cycle-102; emits INFO/WARN/ERROR per table; `LOA_FORCE_LEGACY_MODELS=1` operators see CI WARN every cycle (R6). → **[M2]**

### Dependencies

- **Inbound**: Sprint 2 `capability_classes` registry + `resolve_capability_class()` resolver helper.
- **Outbound**: Sprint 4 adapter retirement depends on raw-id scanner being green; Sprint 5 rollback sentinel composes with this sprint's `LOA_FORCE_LEGACY_MODELS=1` sentinel.

### Risks & Mitigation

| ID | Risk | Mitigation |
|---|---|---|
| **S3.R1** | Gate refactor breaks downstream operators on day 1 (R2) | Soft-migration: raw-id resolves with INFO for cycles 0–2; clear migration deadline (cycle 12); `LOA_FORCE_LEGACY_MODELS=1` kill switch as escape hatch |
| **S3.R2** | Drift-CI scanner false positives on legitimate model-id mentions in docs (HC3 PRD risk) | Scoped path globs (`**/*.md` excluded by default); allowlist with mandatory rationale + sunset cadence |
| **S3.R3** | Cycle-detection abort-vs-skip semantics unclear at integration time (gemini SKP-008) | T3.2 documents final disposition before merge; Sprint 4 retest in concurrent dispatch context |

### Success Metrics

- M2: 0 hardcoded model IDs detected by `tools/check-no-raw-model-id.sh` outside scoped paths + allowlist
- 100% of multi-model gate configs use `class:`-addressing; raw-id soft-migration emits INFO line in PR comment
- T3.4 dynamic regex from registry: adding `o1` to `model-config.yaml` causes scanner to detect raw `o1` in code without scanner edit

### Definition of Done

- [ ] All 6 deliverables checked; all AC tests green
- [ ] `/review-sprint sprint-3` APPROVED
- [ ] `/audit-sprint sprint-3` "APPROVED - LETS FUCKING GO"
- [ ] Bridgebuilder review on sprint PR
- [ ] Per-sprint ship/no-ship decision in NOTES.md

---

## Sprint 4 — Adapter Unification + Retirement

**Scope**: LARGE (10 tasks)
**Local ID**: 4 | **Global ID**: 146

### Sprint Goal

Make cheval Python the canonical adapter, quarantine `model-adapter.sh.legacy` (delete deferred to cycle-103 ship-prep), ship BB TS codegen-from-SoT, and close the rollback-substrate adapter bugs (#757 codex stdin, #746 shadow-pricing + flag-injection, #774 cheval long-prompt, A1+A2+A3+A6).

### Closes (PRD M*)

→ partial **[M1]** (closes the four adapter-bug surfaces that produce silent failure)
→ partial **[M3]** (Sprint 5 finalizes; Sprint 4 demonstrates the rollback-discipline pattern in `.claude/protocols/rollback-discipline.md` falsification test, AC-4.5b)
→ **[TR6]** quarantine sentinel via `tools/check-no-raw-model-id.sh` `model-adapter.sh.legacy` import-pattern detection

### Closes (PRD AC)

AC-4.1 divergence audit doc · AC-4.2 quarantine (revised per HC2) · AC-4.3 BB TS codegen · AC-4.4 red-team consolidation · AC-4.4a kill-switch shim coverage corpus (precondition for cycle-103 deletion) · AC-4.5 #757 codex-headless · AC-4.5b reframe falsification (MC8 / opus IMP-010) · AC-4.5c parallel-dispatch concurrency (A6) · AC-4.5d max_output_tokens (A1+A2 cheval-canonical leg) · AC-4.5e cheval long-prompt (#774, A3) · AC-4.6 #746 shadow-pricing · AC-4.7 #746 flag-injection

### Deliverables (checkbox list)

- [ ] `grimoires/loa/cycles/cycle-102-model-stability/adapter-divergence.md` (AC-4.1) — surfaces every difference across (cheval Python, legacy bash, BB TS, red-team-model-adapter)
- [ ] `model-adapter.sh.legacy` moved to `.claude/archive/legacy-bash-adapter/model-adapter.sh.v1018.bak` per SDD §8.2 sequence; `hounfour.flatline_routing` defaults to `true`
- [ ] `tests/cycle-102/legacy-shim-coverage.bats` corpus (AC-4.4a, HC13 / opus IMP-006 HIGH 0.85): every legacy code path exercised via `LOA_FORCE_LEGACY_MODELS=1`; bit-equivalent behavior asserted vs pre-cycle-102
- [ ] `gen-bb-registry.ts` extended (AC-4.3, L13) — emits `class-config.generated.ts` (TS map class → fallback chain); BB drift-CI gate byte-equal-diff
- [ ] `red-team-model-adapter.sh` consolidated into cheval-callthrough or thin wrapper (AC-4.4); single resolver path
- [ ] **Adapter parallel-dispatch concurrency fix** (AC-4.5c, A6): per-provider connection-pool tuning + sequential-fallback strategy when parallelism degrades >50%; `tests/integration/parallel-dispatch-concurrency.bats` — 3 reviewer + 3 skeptic against 12–30K prompt → ≥5/6 succeed
- [ ] Cheval long-prompt PROVIDER_DISCONNECT characterization (AC-4.5e, #774, A3): fixture-replay 5K/10K/20K/30K/50K to OpenAI; failure threshold characterized; deliver upstream PR or cheval-side mitigation (chunking / streaming / httpx pool tuning)
- [ ] #757 codex-headless long-prompt stdin diagnosis + fix (AC-4.5): ≥50KB prompt fixture; subprocess invocation handles graceful failure or success
- [ ] #746 shadow-pricing on subscription providers (AC-4.6): `shadow_pricing.{input_per_mtok,output_per_mtok}` per subscription model; L2 `cost_check_budget` reads nonzero quota signal
- [ ] #746 flag-injection mitigation (AC-4.7): `--` separator pre-pended OR adapter rejects prompts starting with `-`; fixture `-rf /etc` exercised
- [ ] **Reframe falsification test** (AC-4.5b, MC8 / opus IMP-010): `.claude/protocols/rollback-discipline.md` ships with corpus of historical sprint bugs (143 + earlier) — first-hypothesis vs empirical-root-cause table; patch author signs

### Acceptance Criteria (testable)

- [ ] **AC-4.1**: `adapter-divergence.md` enumerates every divergence; every row has source-file + line-ref grounding
- [ ] **AC-4.2.test**: `model-adapter.sh.legacy` exists at `.claude/archive/legacy-bash-adapter/`; original location returns "file not found"; `tools/check-no-raw-model-id.sh` includes legacy-import-pattern detection (TR6)
- [ ] **AC-4.4a.test**: `tests/cycle-102/legacy-shim-coverage.bats` — every legacy code path tested via `LOA_FORCE_LEGACY_MODELS=1`; bit-equivalent behavior asserted; coverage report ≥95%
- [ ] **AC-4.5.test**: `tests/integration/codex-headless-long-prompt.bats` — ≥50KB prompt; subprocess returns 0 OR types `PROVIDER_DISCONNECT` (NOT silent-empty)
- [ ] **AC-4.5c.test**: `tests/integration/parallel-dispatch-concurrency.bats` — 3 reviewer + 3 skeptic concurrent on 12–30K prompt → ≥5/6 succeed; documented baseline for regression
- [ ] **AC-4.5d.test**: `tests/cycle-102/legacy-shim-coverage.bats` extended — ≥10K prompt to gpt-5.5-pro and gemini reasoning models succeed under cheval-canonical (Sprint 1 leg validates legacy; Sprint 4 leg validates cheval)
- [ ] **AC-4.5e.test**: `tests/integration/cheval-long-prompt-disconnect.bats` — stratified 5K/10K/20K/30K/50K fixture; failure threshold characterized; mitigation present (chunking OR streaming OR pool tuning)
- [ ] **AC-4.6.test**: `tests/integration/shadow-pricing.bats` — subscription model emits `shadow_cost_micro_usd` (separate from real `cost_micro_usd` per HC1 / gemini SKP-003); L2 budget gate reads nonzero quota signal; budget gate uses real cost only (HC1 closure)
- [ ] **AC-4.7.test**: existing security-tests extended — prompt `-rf /etc` does NOT inject as flag; either `--` separator works OR adapter rejects with structured error
- [ ] **AC-4.5b.test**: `.claude/protocols/rollback-discipline.md` includes ≥3 historical sprint-bug entries with first-hypothesis-vs-empirical-root-cause tables; patch-author-signature line present

### Technical Tasks (10)

- [ ] **T4.1** Author `adapter-divergence.md` (AC-4.1): table comparing cheval Python, legacy bash, BB TS, red-team-model-adapter on (model-resolution path, error-classification, retry semantics, max_output_tokens handling, auth strategy, structured-error format). → **[M2]**
- [ ] **T4.2** Move `model-adapter.sh.legacy` → `.claude/archive/legacy-bash-adapter/model-adapter.sh.v1018.bak`; update `model-adapter.sh` to be thin shim → cheval per SDD §8.1; ensure `hounfour.flatline_routing: true` is the default. → **[M1]**
- [ ] **T4.3** Author `tests/cycle-102/legacy-shim-coverage.bats` corpus per AC-4.4a / HC13: enumerate every legacy code path; one test per path under `LOA_FORCE_LEGACY_MODELS=1`; assert bit-equivalent behavior to pre-cycle-102 baseline. → **[M1]**
- [ ] **T4.4** Extend `gen-bb-registry.ts` (AC-4.3): read `capability_classes` block; emit `class-config.generated.ts`; CI workflow `codegen-drift-check.yml` byte-equal-diff. → **[M2]**
- [ ] **T4.5** Consolidate `red-team-model-adapter.sh` into thin cheval wrapper (AC-4.4); single resolver path; persist `--role attacker` routing fix from Sprint 1 T1.8. → **[M1]**
- [ ] **T4.6** Diagnose + fix A6 parallel-dispatch concurrency: 3 reviewer + 3 skeptic against 12–30K prompt currently fails 3/6. Per-provider connection-pool tuning + httpx limits + sequential-fallback when parallelism-degrade >50%. **Concrete pass/fail thresholds** (opus IMP-004 HIGH 0.85): success criterion = "6/6 calls succeed under 6×concurrent dispatch ≥ 95% of runs over N=20 trials" with 90% confidence interval, NOT a single ≥5/6 sample. Test corpus `tests/integration/parallel-dispatch-concurrency.bats` runs the trial loop and captures p99/p50 latency + success-rate confidence interval. → **[M1]**
- [ ] **T4.7** #774 cheval long-prompt PROVIDER_DISCONNECT characterization (AC-4.5e, A3): fixture-replay matrix 5K/10K/20K/30K/50K → OpenAI `/v1/responses`; identify upstream httpx connection-pool, request streaming, or chunking fix. Deliver upstream PR OR characterize as vendor-side bug with deterministic mitigation in cheval. → **[M1]**
- [ ] **T4.8** #757 codex-headless long-prompt stdin (AC-4.5): diagnose via subprocess strace + httpx-debug; fix or characterize; ≥50KB prompt fixture; graceful-failure-or-success contract. → **[M1]**
- [ ] **T4.9** #746 shadow-pricing (AC-4.6) + flag-injection (AC-4.7): subscription-billed providers declare `shadow_pricing.{input_per_mtok,output_per_mtok}`; L2 cost gate reads. Separately: `--` separator pre-pended in headless adapters OR adapter rejects prompts starting with `-`. **Shadow pricing accumulation in audit** (gemini IMP-010 LOW 0.75): `shadow_cost_micro_usd` field in `model.invoke.complete.payload.schema.json` (Sprint 4 schema delta) — keeps real budget separate (HC1 closure). → **[M1]**
- [ ] **T4.10** Author `.claude/protocols/rollback-discipline.md` (with AC-4.5b reframe falsification test): historical sprint-bug corpus (143 + earlier); first-hypothesis-vs-empirical-root-cause table; patch-author-signature requirement. **Legacy quarantine false rollback-safety sense** (gemini SKP-010 LOW 350): protocol doc explicitly notes that quarantine is NOT a rollback path until AC-4.4a corpus passes. → **[M3]**

### Dependencies

- **Inbound**: Sprint 1 typed errors + audit envelope; Sprint 2 `capability_classes` registry + Bedrock auth schema; Sprint 3 `LOA_FORCE_LEGACY_MODELS=1` kill switch + raw-id scanner.
- **Outbound**: Sprint 5 rollback-discipline-sentinel CI check tests against the protocol doc shipped here; cycle-103 ship-prep deletes the quarantined legacy adapter once AC-4.4a corpus has held for ≥1 cycle.

### Risks & Mitigation

| ID | Risk | Mitigation |
|---|---|---|
| **S4.R1** | Quarantining legacy before kill-switch shim has full coverage breaks rollback path (HC2 / opus SKP-006) | AC-4.4a corpus is **gating** — if any code path fails, deletion is deferred to cycle-104+; quarantine PR cannot merge without 100% corpus pass |
| **S4.R2** | A6 concurrency fix is brittle (vendor connection-pool tuning is empirical) | T4.6 includes regression-baseline test; if degrades >50% post-merge, sequential-fallback fires; smoke-fleet (Sprint 5) catches drift |
| **S4.R3** | #774 cheval long-prompt fix requires upstream change (vendor-side bug) | T4.7 acceptable disposition: characterize + cheval-side deterministic mitigation (chunking, streaming, retry) is sufficient; upstream PR is bonus |
| **S4.R4** | Shadow pricing leaks into real budget calculations (HC1 / gemini SKP-003) | T4.9 separates `shadow_cost_micro_usd` from `cost_micro_usd` at schema level; L2 budget gate uses real cost only (per SDD §3.3 + §9.4) |
| **S4.R5** | TR6 sentinel misses legacy-adapter accidental re-import | `tools/check-no-raw-model-id.sh` extended in this sprint to detect `model-adapter.sh.legacy` import patterns |

### Success Metrics

- AC-4.4a corpus passes 100% (`bats tests/cycle-102/legacy-shim-coverage.bats` exits 0); coverage report ≥95%
- T4.6 baseline: 3+3 concurrent dispatch on 12–30K prompt → ≥5/6 succeed
- T4.7 #774: failure threshold characterized; deterministic mitigation present; ≤30K prompts to OpenAI succeed via cheval
- T4.8 #757: ≥50KB prompt to codex-headless returns 0 OR typed PROVIDER_DISCONNECT
- M2 stays green: drift-CI scanner finds 0 raw IDs outside scoped paths

### Definition of Done

- [ ] All 10 deliverables checked; all AC tests green
- [ ] `/review-sprint sprint-4` APPROVED
- [ ] `/audit-sprint sprint-4` "APPROVED - LETS FUCKING GO"
- [ ] Bridgebuilder review on sprint PR
- [ ] Per-sprint ship/no-ship decision in NOTES.md
- [ ] Quarantine sentinel (TR6) operational: `tools/check-no-raw-model-id.sh` rejects re-imports of legacy adapter

---

## Sprint 5 — Rollback Discipline + Smoke Fleet + E2E Goal Validation

**Scope**: MEDIUM (6 tasks)
**Local ID**: 5 | **Global ID**: 147

### Sprint Goal

Lock in the rollback-comment hygiene CI sentinel, ship the hourly smoke fleet with active alerting + budget caps + scoped keys + size-capped audit retention, and run the cycle-102 end-to-end goal validation against M1–M8.

### Closes (PRD M*)

→ **[M3]** Rollback-comment age = 0 comments older than 7 days without tracking issue
→ **[M5]** Smoke-fleet detection latency < 24h (hourly cron + auto-issue + webhook)
→ **post-cycle [M1]** measured via 30-day audit-query window starting at cycle-102 ship

### Closes (PRD AC)

AC-5.1 rollback-discipline protocol · AC-5.2 rollback CI sentinel · AC-5.3 smoke-fleet workflow (hourly per HC4 / gemini SKP-006, active alerting per HC6, budget+abort per MC5, scoped keys per HC12, secrets-masking per HC9) · AC-5.4 vendor-regression detection (M5 24h SLA + R4 false-alarm dampener) · AC-5.5 migration guide

### Deliverables (checkbox list)

- [ ] `.claude/protocols/rollback-discipline.md` (Sprint 4 author; Sprint 5 finalize) — codifies (tracking-issue, fix-forward-gate, deadline_iso) format
- [ ] `tools/check-rollback-discipline.sh` per SDD §7.2 pseudocode — scans `.loa.config.yaml` + `.loa.config.yaml.example` for `# Restore … after #` patterns; fails on >7d age or missing tracking-issue OR closed-issue ref
- [ ] `.github/workflows/model-smoke-fleet.yml` — **hourly cron `13 * * * *`** (HC4 / gemini SKP-006); 15-min timeout (NFR-Perf-3); `actions/checkout@v4` + `setup-python@v5` per SDD §9.1
- [ ] `.claude/scripts/smoke-fleet/{run-smoke-fleet,detect-regressions,file-issue,webhook-alert,append-notes-tail}.sh`
- [ ] **GH Actions secret masking** (HC9 / gemini IMP-009) — `::add-mask::` step per provider key
- [ ] **Smoke-fleet-scoped keys** (HC12 / opus IMP-002): `secrets.SMOKE_FLEET_OPENAI_KEY` etc., separate from production keys; rotate quarterly; documented in `.claude/protocols/rollback-discipline.md` review cadence
- [ ] **Per-run cost cap** (MC5 / opus IMP-007) `LOA_SMOKE_FLEET_BUDGET_USD=0.50` default, configurable; 429 N=3 → abort
- [ ] **Size-capped audit retention** (gemini SKP-009 MED 450): `audit-retention-policy.yaml::model_invoke` adds `max_size_mb: 100`; rotation when capped
- [ ] **Auto-issue on regression** + optional webhook (M5 24h SLA enforcement, HC6); regression detected via 2-consecutive-failure threshold (R4) or latency >100% over 2-week median
- [ ] `grimoires/loa/a2a/smoke-fleet/{date}.jsonl` shape per SDD §9.2 — flock-guarded writes (MC2)
- [ ] NOTES.md tail-summary append (one-line per run)
- [ ] `docs/migration/cycle-102-model-stability.md` (AC-5.5) — operator migration guide; mirrors v1.130 release pattern
- [ ] `.loa.config.yaml.example` migrated: every raw model-id replaced with `class:`-addressing
- [ ] **Cross-CI-runner probe-cache behavior** (opus IMP-009 MED 0.75): document cache invalidation across CI runners; smoke-fleet workers don't share cache so each runner probes fresh once per hour

### Acceptance Criteria (testable)

- [ ] **AC-5.1**: protocol doc exists; format pinned with example entries
- [ ] **AC-5.2.test**: `tests/integration/rollback-discipline-sentinel.bats` — sentinel fails on rollback comment without tracking-issue ref; fails on tracking-issue closed; fails on comment age >7d (mock git log); passes on compliant comment
- [ ] **AC-5.3.test**: `tests/integration/smoke-fleet-regression.bats` (synthetic JSONL fixtures) — 4-week vector `[AVAILABLE, AVAILABLE, DEGRADED, DEGRADED]` triggers regression; `[AVAILABLE, AVAILABLE, AVAILABLE, DEGRADED]` does NOT (R4 dampener)
- [ ] **AC-5.3.b**: `tests/integration/smoke-fleet-budget-abort.bats` — synthetic 429×3 → abort + structured error; cost-cap exceeded → abort + structured error; budget gate calls `cost_check_budget` per (provider, model) per HC1 closure
- [ ] **AC-5.3.c**: `gh secret list` workflow inspection confirms `SMOKE_FLEET_OPENAI_KEY` etc. exist as separate-from-production keys (manual operator verify; documented)
- [ ] **AC-5.4.verify**: manual injection test in cycle-ship review — vendor regression simulated; auto-issue fires within ≤2 consecutive runs (≤2h since hourly cadence)
- [ ] **AC-5.5.verify**: migration guide present at `docs/migration/cycle-102-model-stability.md`; mirrors v1.130 structure; covers `LOA_FORCE_LEGACY_MODELS=1` opt-out; sunset-deadline cycle 12

### Technical Tasks (6 — including the E2E task)

- [ ] **T5.1** Author `tools/check-rollback-discipline.sh` per SDD §7.2 pseudocode; `gh issue view` calls for tracking-issue freshness; bats test corpus. → **[M3]**
- [ ] **T5.2** Author `.github/workflows/model-smoke-fleet.yml` per SDD §9.1 — hourly cron, 15-min timeout, scoped keys, secret masking, budget cap, abort policy. → **[M5]**
- [ ] **T5.3** Author `.claude/scripts/smoke-fleet/*.sh` (5 scripts per SDD §9 listing); flock-guarded JSONL writes (MC2); `cost_check_budget` per probe; `gh issue create --label "severity:smoke-fleet-regression"`. **Regression-detection beyond two-consecutive-failure** (opus IMP-007 MED 0.8): future-tech-hint comment in `detect-regressions.sh` for trend-analysis follow-up cycle. → **[M5]**
- [ ] **T5.4** Author `docs/migration/cycle-102-model-stability.md` (AC-5.5); migrate `.loa.config.yaml.example` to `class:`-addressing; cross-link from `CHANGELOG.md`. **Migration script tooling vs guide** (MC10 / opus IMP-008): doc + cross-link to T2.4 migration tool from Sprint 2. → **[M3]**
- [ ] **T5.5** Add `max_size_mb: 100` cap to `audit-retention-policy.yaml::model_invoke` (gemini SKP-009 MED 450); rotation logic in `audit_emit` retention sweep. → **[M1]**
- [ ] **T5.E2E** End-to-End Goal Validation against PRD M1–M8. **PRIORITY P0 (Must Complete)**. Validation steps below; NOT a checkbox-shrug — each step writes a structured artifact to `grimoires/loa/cycles/cycle-102-model-stability/e2e-validation.md`. → **[M1]** **[M2]** **[M3]** **[M4]** **[M5]** **[M6]** **[M7]** **[M8]**

#### T5.E2E — End-to-End Goal Validation (Task N.E2E)

**Priority**: P0 (Must Complete)
**Output**: `grimoires/loa/cycles/cycle-102-model-stability/e2e-validation.md` with one verification block per goal.

| Goal | Validation Step | Method | Pass condition |
|---|---|---|---|
| **M1** | 30-day silent-degradation audit query (post-ship window starts at cycle-ship) | `.claude/scripts/lib/audit-query.sh --event-type "model.invoke.complete" --since "$(date -u -d '30 days ago' +%FT%TZ)" --filter '.payload.models_failed != null and .payload.operator_visible_warn != true' --output count` | Count = 0 (or trip → file hotfix-cycle, NOT block cycle-102 ship) |
| **M2** | Drift-CI scanner full-repo sweep | `bash tools/check-no-raw-model-id.sh` | Exit 0; 0 findings outside allowlist |
| **M3** | Rollback-discipline sentinel | `bash tools/check-rollback-discipline.sh` | Exit 0; 0 stale comments |
| **M4** | Schema validation on `model-config.yaml` | `bash .claude/scripts/validate-model-config.sh` | All declared classes have `fallback_chain.minItems: 2`; cross-references valid |
| **M5** | Smoke-fleet detection latency manual injection | inject synthetic regression in test JSONL; observe auto-issue fire within ≤2h | Auto-issue created with `severity:smoke-fleet-regression` label |
| **M6** | Probe-gate latency benchmark | `bats tests/integration/model-probe-cache.bats --filter latency` | p99 < 500ms; per-provider <2s |
| **M7** | Operator-visible header on degraded multi-model run | manual: rig flatline run with one provider down; check PR comment | Header line present; format matches protocol |
| **M8** | Registry extension end-to-end | manual: add new class via `.loa.config.yaml::model_aliases_extra::capability_classes_extra`; run BB iter, Flatline iter, Red Team iter | All three consume new class without `.claude/` PR; auto-issue if any subsystem failed to consume |

**E2E artifact contents**: pass/fail per goal + supporting evidence (audit-query output, scanner exit code, smoke-fleet issue URL, etc.). If any goal fails, `/audit-sprint sprint-5` will block cycle-102 ship; remediation lands as Sprint 5 follow-up bugfix sprint.

⚠️ **WARNING — none active**: every PRD goal M1–M8 has at least one contributing task across Sprints 1–5; verified in Appendix C.

### Dependencies

- **Inbound**: Sprint 1 audit envelope + `model.invoke.complete` event (M1 query); Sprint 2 schema validation (M4); Sprint 3 drift-CI scanner (M2); Sprint 4 protocol doc (M3) + AC-4.4a corpus.
- **Outbound** (cycle-103): legacy-adapter deletion in ship-prep PR; M1 30-day window starts ticking.

### Risks & Mitigation

| ID | Risk | Mitigation |
|---|---|---|
| **S5.R1** | Hourly smoke-fleet exhausts API budget (24× weekly = 168× per week) | Per-run cost cap `LOA_SMOKE_FLEET_BUDGET_USD=0.50` (worst case $84/wk; tiny prompts ~50 tokens × 9 models × 24/day actual cost ≈ $0.10–0.30/day); 429×3 abort policy; quarterly cost-ceiling review |
| **S5.R2** | Smoke-fleet false alarms (R4 PRD risk) | 2-consecutive-failure threshold per AC-5.4; latency regression requires >100% over 2-week median |
| **S5.R3** | Scoped smoke-fleet keys leak via misconfigured GH secrets (TR5) | `::add-mask::` step (HC9); separate keys from production; rotate quarterly per AC-5.3 review cadence |
| **S5.R4** | M1 trips on day 28 of 30-day post-ship window (HC1 / opus SKP-004) | M1 is post-ship invariant; trip → file hotfix-cycle, NOT block cycle-102 ship; PRD §2.2 explicit on this |
| **S5.R5** | E2E manual-injection tests (M5, M7, M8) flake on first run | Document deterministic injection fixtures; record retest steps; if flake persists, file Sprint 5 follow-up |

### Success Metrics

- M3 sentinel: 0 stale rollback comments; CI green
- M5 manual injection: auto-issue fires within 2 hourly runs (≤2h latency)
- M1 baseline at cycle ship: count=0 (post-ship window starts ticking)
- All 8 E2E goals pass in `e2e-validation.md`; 0 outstanding blockers

### Definition of Done

- [ ] All 6 deliverables (incl. T5.E2E) checked
- [ ] All AC tests green
- [ ] **T5.E2E artifact** (`e2e-validation.md`) covers all 8 goals with evidence
- [ ] `/review-sprint sprint-5` APPROVED
- [ ] `/audit-sprint sprint-5` "APPROVED - LETS FUCKING GO"
- [ ] Bridgebuilder review on sprint PR
- [ ] Per-sprint ship/no-ship decision in NOTES.md
- [ ] Cycle-102 ship handoff via `handoff_write` to operator (composes with L6 per PRD §5.6)

---

## Risk Register (Cycle-Wide)

PRD §7.1 R1–R8 stand. Sprint-specific S{N}.R{M} are listed per sprint. Cross-cutting cycle-wide risks:

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| **R1** | Vendor API regression mid-cycle | M | H | Capture-and-replay fixtures (sprint-bug-143 pattern, codified Sprint 4); smoke fleet detects (Sprint 5) | maintainer |
| **R2** | Sprint 4 retirement breaks downstream operator flows | M | M | `LOA_FORCE_LEGACY_MODELS=1` kill switch (Sprint 3); soft-migration period; migration guide AC-5.5 | maintainer |
| **R3** | Probe-gate adds latency to small operations | L | M | 60s cache + `<2s` budget (Sprint 1 NFR-Perf-1) | maintainer |
| **R4** | Smoke-fleet false alarms | H | L | 2-consecutive-failure threshold AC-5.4 | maintainer |
| **R5** | Capability-class registry schema changes mid-cycle | L | M | Schema-version field (T2.1); migration tool (T2.4) | maintainer |
| **R6** | `LOA_FORCE_LEGACY_MODELS=1` operators stay forever | M | L | Sentinel CI WARN every cycle (T3.6); sunset trigger ~6 months post-ship | maintainer |
| **R7** | Probe-gate masks transient flakes | M | M | Retry budget within probe (T1.3) | maintainer |
| **R8** | Reframe Principle violation on next sprint bug | M | M | Capture-fixture-first pattern in `.claude/protocols/rollback-discipline.md` (T4.10); falsification test AC-4.5b | maintainer |
| **TR1** | Cross-runtime parity drift (Python ↔ bash ↔ TS) | M | H | Byte-equal CI gate per cross-runtime helper (Sprints 1–3 each have parity test) | maintainer |
| **TR2** | `audit_emit` schema bump conflicts | L | H | Sprint 1 ships additive bump only (1.1.0 → 1.2.0); cross-runtime release coordinated | maintainer |
| **TR3** | `model_aliases_extra` v2.0.0 schema bump breaks v1.0.0 operators | M | M | Migration tool T2.4; warn-mode for one cycle | maintainer |
| **TR4** | Probe gate amplifies vendor rate-limit pressure | M | M | 60s cache TTL; per-runtime cache file (no cross-runtime lock contention); fail-open at probe layer | maintainer |
| **TR5** | Smoke-fleet API keys leak via GH Actions misconfiguration | L | H | Scoped read-only keys (HC12); rotate quarterly; `::add-mask::` step | maintainer |
| **TR6** | Quarantined legacy adapter accidentally re-imported | L | M | `tools/check-no-raw-model-id.sh` includes legacy-import-pattern detection (T3.3 + T4.5) | maintainer |
| **TR7** | `tier_groups.mappings` and `capability_classes` get out of sync | M | M | T2.7 derives `tier_groups` from `capability_classes` at load time; manual edits flagged | maintainer |
| **TR8** | Bedrock plugin (#652) requires schema extension SDD didn't anticipate | M | M | T2.9 validates against #652 plugin contract; extends `class_membership` field if needed | maintainer |
| **CR1** | Beads-DB stays MIGRATION_NEEDED through cycle (#661) | H | L | Phase 0 P0-1 fix; alternate path: 24h opt-out + manual NOTES.md tracking | maintainer |
| **CR2** | Adapter bugs A1–A7 reproduce inside cycle-102's own Flatline/BB iterations | H | L | Self-hosting risk acknowledged. Sprint 1 BB review may need manual dogfood (PRD §9 / SDD §11 Iter-2 disposition); plateau-by-API-unavailability acceptable per cycle-099 precedent |

## Success Metrics & Validation Approach (Cycle-Level)

PRD §2.1 invariants M1–M8. Cycle-102 ships when **M2, M3, M4, M5, M6, M7, M8 are green at sprint-5 ship** AND **M1 baseline starts ticking** (M1 is the post-ship 30-day-window invariant per PRD §2.2). M1 trip during the post-ship window does NOT roll back cycle-102; it triggers a hotfix cycle (clear separation of cycle-ship gates vs post-ship invariants).

**Per-sprint validation gates**:
1. All AC tests green
2. `/review-sprint sprint-N` returns APPROVED
3. `/audit-sprint sprint-N` returns "APPROVED - LETS FUCKING GO"
4. Bridgebuilder review on sprint PR (kaironic plateau acceptable)
5. Per-sprint ship/no-ship decision documented in NOTES.md

**Cycle-level validation gates** (Sprint 5 T5.E2E):
- All 8 PRD goals validated in `e2e-validation.md`
- Cycle handoff via L6 `handoff_write` to operator

---

## Appendix A — Task Dependency Graph

```mermaid
flowchart TD
    P0[Phase 0 Prereqs<br/>P0-1 beads HEALTHY<br/>P0-2 beads register<br/>P0-3 file A7<br/>P0-4 toolchain]

    subgraph S1[Sprint 1 — Anti-silent-degradation]
        T11[T1.1 model-error.schema]
        T12[T1.2 audit envelope bump<br/>1.1.0 → 1.2.0]
        T13[T1.3 model-probe-cache trio]
        T14[T1.4 payload schemas]
        T15[T1.5 cheval _error_json + shim]
        T16[T1.6 operator-visible header]
        T17[T1.7 audit_emit wiring]
        T18[T1.8 red-team routing + stderr]
        T19[T1.9 legacy max_output_tokens]
        T1A[T1.10 routing observability]
    end

    subgraph S2[Sprint 2 — Capability classes]
        T21[T2.1 model-config.schema v2]
        T22[T2.2 5 concrete classes]
        T23[T2.3 model_aliases_extra v2]
        T24[T2.4 migration tool]
        T25[T2.5 resolve_capability_class]
        T26[T2.6 cycle + xref validation]
        T27[T2.7 tier_groups derivation]
        T28[T2.8 float serialization]
        T29[T2.9 Bedrock validation]
    end

    subgraph S3[Sprint 3 — Fallback contract + drift CI]
        T31[T3.1 gate refactor + inverted index]
        T32[T3.2 walk_fallback_chain]
        T33[T3.3 check-no-raw-model-id.sh]
        T34[T3.4 dynamic regex from registry]
        T35[T3.5 allowlist governance]
        T36[T3.6 sunset cadence + sentinel]
    end

    subgraph S4[Sprint 4 — Adapter unification]
        T41[T4.1 adapter-divergence.md]
        T42[T4.2 quarantine legacy]
        T43[T4.3 AC-4.4a coverage corpus]
        T44[T4.4 BB TS codegen]
        T45[T4.5 red-team cheval consolidation]
        T46[T4.6 A6 parallel concurrency]
        T47[T4.7 #774 long-prompt]
        T48[T4.8 #757 codex stdin]
        T49[T4.9 #746 shadow + flag-injection]
        T4A[T4.10 rollback-discipline.md]
    end

    subgraph S5[Sprint 5 — Discipline + smoke fleet + E2E]
        T51[T5.1 rollback CI sentinel]
        T52[T5.2 smoke-fleet workflow]
        T53[T5.3 smoke-fleet scripts]
        T54[T5.4 migration guide]
        T55[T5.5 audit retention size cap]
        T5E[T5.E2E E2E validation P0]
    end

    P0 --> S1
    T11 --> T13
    T11 --> T14
    T12 --> T17
    T13 --> T17
    T14 --> T17
    T15 --> T16
    T15 --> T17
    T16 --> T17

    S1 --> S2
    T21 --> T22
    T21 --> T23
    T21 --> T25
    T22 --> T25
    T25 --> T26
    T25 --> T27
    T21 --> T29

    S2 --> S3
    T25 --> T31
    T25 --> T32
    T22 --> T34
    T33 --> T34
    T33 --> T35

    S3 --> S4
    T42 -. precondition .-> T43
    T43 -. gates .-> T42
    T44 --> T22
    T46 --> T13
    T47 --> T15
    T49 --> T22

    S4 --> S5
    T4A --> T51
    T52 --> T53
    T55 --> T17
    T5E --> T11
    T5E --> T33
    T5E --> T51
    T5E --> T22
    T5E --> T52
    T5E --> T13
    T5E --> T16
    T5E --> T23
```

> **Preview**: render via `https://mermaid.live/edit` paste, or run
> `bash .claude/scripts/visual-communication/preview.sh` if available.
> Theme: read from `.loa.config.yaml::visual_communication.theme`.

## Appendix B — AC ↔ Sprint ↔ Task Cross-Reference

(Inverse of SDD §15. Use this when triaging an AC failure.)

| PRD AC | Sprint | Tasks |
|---|---|---|
| AC-1.1 | 1 | T1.1, T1.5 |
| AC-1.2 | 1 | T1.3 |
| AC-1.3 | 1 | T1.8 |
| AC-1.4 | 1 | T1.8 |
| AC-1.5 | 1 | T1.5, T1.7 |
| AC-1.6 | 1 | T1.6 |
| AC-1.7 | 1 | T1.2, T1.4, T1.7 |
| AC-2.1 | 2 | T2.1, T2.2 |
| AC-2.2 | 2 | T2.1, T2.9 |
| AC-2.3 | 2 | T2.3 |
| AC-2.4 | 2 | T2.1, T2.2 |
| AC-2.5 | 2 | T2.5, T2.6 |
| AC-3.1 | 3 | T3.1 |
| AC-3.2 | 3 | T3.2 |
| AC-3.3 | 3 | T3.3, T3.4, T3.5 |
| AC-3.4 | 3 | T3.6 |
| AC-3.5 | 3 | T3.6 |
| AC-4.1 | 4 | T4.1 |
| AC-4.2 | 4 | T4.2 |
| AC-4.3 | 4 | T4.4 |
| AC-4.4 | 4 | T4.5 |
| AC-4.4a | 4 | T4.3 |
| AC-4.5 | 4 | T4.8 |
| AC-4.5b | 4 | T4.10 |
| AC-4.5c | 4 | T4.6 |
| AC-4.5d | 1 + 4 | T1.9 (legacy leg), T4.3 (cheval-canonical leg) |
| AC-4.5e | 4 | T4.7 |
| AC-4.6 | 4 | T4.9 |
| AC-4.7 | 4 | T4.9 |
| AC-5.1 | 4 + 5 | T4.10 (author), T5.1 (sentinel pairs with doc) |
| AC-5.2 | 5 | T5.1 |
| AC-5.3 | 5 | T5.2, T5.3 |
| AC-5.4 | 5 | T5.3, T5.E2E (M5 manual injection) |
| AC-5.5 | 5 | T5.4 |

## Appendix C — Goal Traceability (PRD M1–M8 → Sprint → Tasks)

> **Per planning-sprints skill goal-trace requirement**: every PRD goal MUST
> have ≥1 contributing task; final sprint MUST include E2E validation task.
> Goals auto-extracted from PRD §2.1 (no IDs in PRD; assigned M1–M8 1:1 from
> the table). T5.E2E covers all 8 goals (P0 priority).

| Goal | PRD Source | Verification | Contributing Sprints | Contributing Tasks |
|---|---|---|---|---|
| **M1** | Multi-model runs that silently degrade = 0 in 30-day window | Audit envelope query (PRD §2.3) | 1, 3, 4, 5 | T1.1, T1.2, T1.4, T1.5, T1.6, T1.7, T1.9, T3.1, T3.2, T4.2, T4.3, T4.6, T4.7, T4.8, T4.9, T5.5, T5.E2E |
| **M2** | Adapter divergence count = 0 by Sprint 4 ship | Drift-CI scanner | 2, 3, 4, 5 | T2.1, T2.5, T3.3, T3.4, T3.5, T3.6, T4.1, T4.4, T5.E2E |
| **M3** | Rollback-comment age = 0 stale comments without tracking issue | `tools/check-rollback-discipline.sh` | 4, 5 | T4.10, T5.1, T5.4, T5.E2E |
| **M4** | Capability-class fallback chain coverage 100% with ≥2-deep | Schema validation | 2, 5 | T2.1, T2.2, T2.5, T2.6, T2.7, T2.8, T2.9, T5.E2E |
| **M5** | Smoke-fleet detection latency < 24h between vendor breakage and operator surfacing | Manual injection in cycle-ship review | 5 | T5.2, T5.3, T5.E2E |
| **M6** | Probe-gate per-call overhead < 500ms / < 2s per provider | Sprint 1 benchmark in AC-1.2 | 1, 5 | T1.3, T5.E2E |
| **M7** | Operator-visible degradation indication on 100% of degraded multi-model runs | BB pipeline integration test | 1, 5 | T1.1, T1.4, T1.5, T1.6, T1.7, T1.8, T1.10, T5.E2E |
| **M8** | Registry extension end-to-end via `model_aliases_extra` without System Zone touch | Sprint 2 AC end-to-end test + cycle-ship E2E | 2, 5 | T2.1, T2.3, T2.5, T5.E2E |

⚠️ **WARNING audit**: 0 goals lack contributing tasks; E2E validation task (T5.E2E) is in Sprint 5 (final sprint), priority P0.

---

## Appendix D — Flatline Findings Absorption Index

For sprint-plan auditors: every PRD-MEDIUM and SDD-HIGH/MED finding is
either folded into a sprint task above or explicitly held for follow-up.

### PRD MEDIUM (`flatline-prd-review-v1.md` MC1–MC10)

| ID | Disposition |
|---|---|
| MC1 cross-reference validation for fallback chains | Sprint 2 → T2.6 |
| MC2 file locking for smoke-fleet/audit log appends | Sprint 5 → T5.3 (flock-guarded JSONL writes) |
| MC3 local-network-failure differentiation | Sprint 1 → T1.3 (`detect_local_network` API + `LOCAL_NETWORK_FAILURE` error class) |
| MC4 `model_aliases_extra` collision/precedence beyond `id` | Sprint 2 → T2.3 (`additionalProperties: false` + register-only collision) |
| MC5 smoke-fleet budget/abort policy | Sprint 5 → T5.2 + T5.3 |
| MC6 migration path for in-flight runs at Sprint 4 deletion | Sprint 4 → T4.2 (quarantine, not delete; HC2 closure) |
| MC7 attacker schema pinning | Sprint 1 → T1.8 (contract test `tests/integration/red-team-attacker-routing.bats`) |
| MC8 Reframe Principle falsification test | Sprint 4 → T4.10 (AC-4.5b) |
| MC9 BB TS codegen build-pipeline coupling | Sprint 4 → T4.4 |
| MC10 migration script tooling vs guide | Sprint 2 → T2.4 (script) + Sprint 5 → T5.4 (guide cross-link) |

### SDD HIGH/MED (`flatline-sdd-review-v1.md`)

All HC1–HC14 listed as PRD-amended OR SDD-amended OR sprint-task-absorbed:

| HC/MC | Disposition |
|---|---|
| HC1 shadow pricing exhausts real budget | Sprint 4 → T4.9 (`shadow_cost_micro_usd` separate from `cost_micro_usd`) |
| HC2 fail-open + local network down → thread starvation | Sprint 1 → T1.3 (fail-fast on `LOCAL_NETWORK_FAILURE`) |
| HC3 thundering herd on TTL expiry | Sprint 1 → T1.3 (stale-while-revalidate) |
| HC4 weekly smoke-fleet too infrequent | Sprint 5 → T5.2 (hourly cron `13 * * * *`) |
| HC5 DEGRADED probe outcome ternary | Sprint 1 → T1.3 (OK / DEGRADED / FAIL) |
| HC6 Bedrock auth in `probe_provider` | Sprint 2 → T2.1 (`auth: sigv4_aws` schema) + T2.9 (validation) |
| HC7 lock acquisition timeouts + stale recovery | Sprint 1 → T1.3 (`flock -w 5` + `STALE_LOCK_RECOVERED` WARN) |
| HC8 audit emission during `LOA_FORCE_LEGACY_MODELS=1` | Sprint 1 → T1.4 + T1.7 (`kill_switch_active: true` field) |
| HC9 GH Actions secret masking | Sprint 5 → T5.2 (`::add-mask::` step) |
| HC10 [ASSUMPTION-3] resolved | Sprint 1 → T1.2 (`MODELINV` primitive_id; schema bump) |
| HC11 schema migration mechanics concrete | Sprint 2 → T2.4 (`tools/migrate-model-config.sh`) |
| HC12 smoke-fleet secrets-management + key-isolation | Sprint 5 → T5.2 (`SMOKE_FLEET_*_KEY` scoped keys) |
| HC13 contract test corpus AC-4.4a enumerate paths | Sprint 4 → T4.3 |
| HC14 `tier_groups → capability_classes` derivation | Sprint 2 → T2.7 |
| MC1 drift regex brittle for o1/o3/nova | Sprint 3 → T3.4 (dynamic regex from registry) |
| MC2 cycle detection abort vs skip+WARN+continue | Sprint 3 → T3.2 (final disposition) |
| MC3 unbounded audit log growth | Sprint 5 → T5.5 (`max_size_mb: 100`) |
| MC4 operator-visible header truncation/format | Sprint 1 → T1.6 (240-char cap + fold) |
| MC5 regression-detection beyond two-failure | Sprint 5 → T5.3 (future-tech-hint comment) |
| MC6 probe-cache cross-CI-runner | Sprint 5 → T5.2 (documented; per-runner fresh probe) |
| MC7 routing-decision observability | Sprint 1 → T1.10 (`LOA_DEBUG_MODEL_RESOLUTION=1` trace) |
| MC8 parallel cache-check/probing for fallback chain | Sprint 1 → T1.3 (per-runtime cache files) |
| MC9 split `total_latency_ms` into probe + invocation | Sprint 1 → T1.4 |
| MC10 float serialization for cross-runtime parity | Sprint 2 → T2.8 |
| MC11 cross-reference validation dynamic for `model_aliases_extra` | Sprint 2 → T2.3 |
| LC1 shadow pricing accumulation in audit | Sprint 4 → T4.9 |
| LC2 legacy quarantine false rollback-safety | Sprint 4 → T4.10 (protocol doc disclaimer) |

---

## Sprint-plan Self-Review Checklist (planning-sprints skill)

- [x] All MVP features from PRD are accounted for (PRD §4.1–§4.5 → Sprints 1–5)
- [x] Sprints build logically on each other (linear dependency chain documented in §1.2 + Appendix A)
- [x] Each sprint is feasible as a single iteration (LARGE = 9-10 tasks, MEDIUM = 6 tasks; hard-ceiling 2 weeks per sprint)
- [x] All deliverables have checkboxes for tracking
- [x] Acceptance criteria are clear and testable (every AC has a `tests/…` path or manual-verify protocol)
- [x] Technical approach aligns with SDD (Appendix B SDD §15 cross-reference is symmetric)
- [x] Risks identified with mitigation strategies (per-sprint S{N}.R + cycle-wide table)
- [x] Dependencies explicitly called out (per-sprint Inbound/Outbound)
- [x] Plan provides clear guidance for engineers (every task has source-doc + line-ref grounding)
- [x] All PRD goals mapped to tasks (Appendix C — 0 goals without contributing tasks)
- [x] All tasks annotated with goal contributions (`→ **[M*]**` annotations on each T*.*)
- [x] E2E validation task included in final sprint (T5.E2E, P0)
- [x] Iron-grip directive honored (every sprint Definition-of-Done lists `/review-sprint` + `/audit-sprint` + Bridgebuilder)

---

*Sprint plan generated 2026-05-09 from `prd.md` + `sdd.md` (cycle-102, schema_version 1.0).
Skill: `planning-sprints`. Flatline auto-trigger on this sprint plan per
`.loa.config.yaml::flatline_protocol.phases.sprint: true`. If iter-1
silently degrades (which is now expected based on three consecutive
demonstrations this session), dogfood manually per established pattern.
Next: `/build` (which will dispatch via `/run sprint-plan`).*

---

## 13. Flatline Iter-1 Disposition (manual synthesis 2026-05-09)

> Fourth dogfood of vision-019 axiom 3 this session. 2-voice manual run (cost
> discipline). Full synthesis: `flatline-sprint-review-v1.md`.

**Coverage**:
- ✅ opus-review (10 improvements: 4 HIGH + 5 MED + 1 LOW)
- ✅ gemini-skeptic (6+ concerns: 2 CRIT + 4 HIGH + 1+ MED — JSON truncated mid-SKP-006)

**Critical sprint-plan amendments applied inline**:

| Finding | Severity | Sprint amendment |
|---|---|---|
| SKP-001 (CRIT 850) — flock contention re-litigated | CRIT | T1.3 — clarification: stale-while-revalidate IS the high-concurrency mitigation; not vanilla blocking-flock |
| SKP-002 (CRIT 820) — Cross-provider fallback prompt-dialect | CRIT | T2.1 + T3.2 — `prompt_translation` field; default intra-dialect only; cross-provider OPT-IN |
| SKP-005 (HIGH 700) — SigV4 credential expiration vs probe TTL | HIGH | T2.9 — credential expiration check in probe cache for `auth: sigv4_aws` |
| IMP-003 (HIGH 0.8) — Schema bump 1.1.0 → 1.2.0 rollback procedure | HIGH | T1.2 — additive-only bump; rollback path; mid-flight reader compatibility |
| IMP-004 (HIGH 0.85) — Parallel-dispatch concurrency baseline thresholds | HIGH | T4.6 — concrete: 6/6 ≥95% of N=20 trials with 90% CI |
| SKP-006 (MED) — Sequential-fallback on parallel degradation upstream timeouts | MED | T3.2 — switch concurrent → sequential when parallelism-degrade >50% |

**HIGH_NON_AMENDED**:
- SKP-003 (HIGH 750) Float serialization byte-equality brittle — cycle-099 precedent; document fallback to semantic-equivalence if cycles break
- SKP-004 (HIGH 720) Sprint linear dependency vs 12-week ceiling — Sprint 5 mock-adapter prep can begin in parallel; (defer to operational phase)
- IMP-001 (HIGH 0.85) Per-task owner names — defer to /implement-time beads task creation

**MEDIUM/LOW**: 7 items deferred to task-level (per `flatline-sprint-review-v1.md`).

**Iter-2 NOT gated** (consistent with PRD/SDD iter-1 rationale; pattern durably documented).

**Cumulative Flatline cost across cycle-102 kickoff**: ~$5-8 across PRD + SDD + sprint-plan iter-1 manual dogfoods. **Caught**: 5 BLOCKER design defects + 30+ HIGH improvements + 7 adapter bugs (A1-A7). **Without iron-grip dogfood, all of these would have shipped silently.**
