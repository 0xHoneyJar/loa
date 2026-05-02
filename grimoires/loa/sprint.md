# Sprint Plan — Cycle-096: AWS Bedrock Provider + Provider-Plugin Hardening

**Version:** 1.2 (live-probe ground-truth integrated)
**Date:** 2026-05-02
**Author:** Sprint Planner Agent (deep-name + Claude Opus 4.7 1M)

> **v1.1 → v1.2 changes** (live probes against real Bedrock 2026-05-02; matches PRD v1.3 + SDD v1.2 wave):
> - **Task 1.2 (YAML)**: model IDs — `us.anthropic.claude-opus-4-7` (no `-v1:0`); `us.anthropic.claude-sonnet-4-6` (no suffix); Haiku 4.5 keeps `us.anthropic.claude-haiku-4-5-20251001-v1:0`. Bare `anthropic.*` IDs return HTTP 400 — inference profile IDs REQUIRED
> - **Task 1.A (regex)**: `ABSKY...{32,}` → `ABSK[A-Za-z0-9+/=]{36,}` (probe-confirmed)
> - **Task 1.4 (thinking)**: Bedrock requires `thinking.type: "adaptive"` + `output_config.effort` (not direct-Anthropic `enabled` + `budget_tokens`); adapter translates
> - **Task 1.3 (response shape)**: usage is camelCase with prompt-cache + serverToolUsage fields; normalize to cheval Usage
> - **Error taxonomy**: 7 → 9 categories (added `OnDemandNotSupported` + `ModelEndOfLife`)
> - **Sprint 0 G-S0-2 outcome**: PASS-WITH-CONSTRAINTS (3 corrections applied to PRD/SDD/sprint v1.x docs). Sprint 1 entry unblocked once remaining gates close (G-S0-1 survey override + G-S0-{4,5,CONTRACT,TOKEN-LIFECYCLE,BACKUP})
> Source: probe captures at `tests/fixtures/bedrock/probes/`. No re-Flatline (factual ground-truth, not opinion).
**PRD Reference:** `grimoires/loa/prd.md` (v1.2 — Flatline-double-pass cleared)
**SDD Reference:** `grimoires/loa/sdd.md` (v1.1 — Flatline pass cleared, kaironic stop)
**Source issue:** [#652](https://github.com/0xHoneyJar/loa/issues/652) — "[FEATURE] add amazon bedrock to loa"
**Cycle (active in ledger):** `cycle-096-aws-bedrock` (cycle-095 archived 2026-05-02)

> **v1.0 → v1.1 changes** (Flatline pass at `grimoires/loa/a2a/flatline/sprint-cycle-096-review.json` — 100% agreement, 7 BLOCKERS + 6 HIGH-CONSENSUS, 0 DISPUTED, all integrated, Kaironic stop after one pass):
> - **Sprint 0 hardened**: Added Task 0.7 (backup test account / break-glass path, closes SKP-001 SPOF), expanded G-S0-1 evidence requirements (SKP-002), explicit PASS/PASS-WITH-CONSTRAINTS/FAIL matrix per gate (SKP-003 + IMP-002), multi-region/account/partition coverage in G-S0-2 (SKP-004), live-data scrub process for spike-report capture (IMP-004)
> - **Sprint 1 reshaped**: Task 1.1 expanded to incremental-with-compatibility-shim rollout strategy (SKP-008 + IMP-003), Task 1.A (NEW) for adversarial redaction tests (SKP-005), Task 1.B (NEW) for streaming non-support assertion (IMP-007)
> - **Sprint 2 augmented**: Added fixture evolution policy section (IMP-006); CI smoke workflow tasks already cover the bulk per SDD §5.5
> - **Cycle-wide**: Timeline buffer added (SKP-007 — 17 days → 21 days with 4-day buffer); explicit must-have vs. stretch task split; predefined de-scope candidates list
> - Unrendered template placeholders cleaned (IMP-001) — searched and resolved any remaining `${...}` / `{{...}}` markers

---

## Executive Summary

Cycle-096 adds AWS Bedrock as a fourth Loa provider with API-Key (Bearer-token) auth, ships three Day-1 Anthropic-on-Bedrock models with region-prefixed inference-profile IDs, codifies the six-edit-site provider-plugin contract as a maintainer-facing guide, and hardens the contract long-term via a recurring CI smoke workflow that fixture-diffs against committed shape captures. SigV4/IAM auth is **designed-not-built** (v2). All existing provider behavior is preserved (NFR-Compat1) — Bedrock is opt-in via explicit `bedrock:` prefix.

The cycle is **gated by a Sprint 0 Contract Verification Spike** (a v1.1 PRD response to Flatline BLOCKERs SKP-001/-002). Sprint 1 cannot start until five Sprint 0 gates (G-S0-1 through G-S0-5) PASS or PASS-WITH-CONSTRAINTS, plus a versioned `bedrock-contract-v1.json` fixture is committed to tree. The architectural ordering inside Sprint 1 lands the **centralized parser** (`lib-provider-parse.sh` + `loa_cheval.types.parse_provider_model_id`) FIRST so every other commit can use it — closing Flatline v1.1 SKP-006.

**Total Sprints:** 3 (Sprint 0, Sprint 1, Sprint 2)
**Sprint Sizing:** Sprint 0 = MEDIUM (6 tasks); Sprint 1 = LARGE (10 tasks); Sprint 2 = MEDIUM (6 tasks + E2E validation)
**Total Tasks:** 22 + 1 E2E
**Estimated Completion:** Sprint 0 close T+5d → Sprint 1 close T+12d → Sprint 2 close T+17d (per PRD §Timeline; sizing is /sprint-plan's call per SDD §8 note)

### Phase-gated rollout

Sprint 0 is **BLOCKING**. No Sprint 1 task touches code paths affected by an unresolved Sprint 0 gate. Sprint 0 outputs (spike report + `bedrock-contract-v1.json`) become Sprint 1 fixtures. Sprint 1 is the merge gate for "Bedrock works end-to-end" (G-1). Sprint 2 lands the maintainer-experience layer (G-2 plugin guide) plus the long-term drift-detection layer (recurring CI smoke per SDD §5.5) — independently mergeable from Sprint 1 once Sprint 1 is in tree.

---

## Sprint Overview

| Sprint | Theme | Scope | Key Deliverables | Dependencies |
|--------|-------|-------|------------------|--------------|
| 0 | Contract Verification Spike (BLOCKING gate) | MEDIUM (6 tasks) | Spike report + `bedrock-contract-v1.json` fixture + token-lifecycle metadata + 5 PASS-or-PWC gate decisions | None — runs against maintainer's live Bedrock account |
| 1 | Bedrock v1 Functional + Centralized Parser | LARGE (10 tasks) | Parser refactor; FR-1/2/3/5/6/7/11/12/13; compliance-aware fallback; 2-layer secret redaction; NFR-Sec11 token age sentinel; live integration test green | Sprint 0 PASS (all five gates) + fixture committed |
| 2 | Plugin Guide + IR Runbook + Health Probe + Recurring Smoke | MEDIUM (6 tasks + E2E) | FR-4 design-only schema; FR-8 health probe; FR-9 plugin guide + IR runbook (NFR-Sec9); FR-10 completion; recurring CI smoke workflow with required-status signal; **E2E goal validation across G-1..G-4** | Sprint 1 merged to base |

> **Independently mergeable:** Sprint 1 is the cycle-097-promotion gate (cycle-096 ships when Sprint 1 lands; Sprint 2 lands on top). Sprint 2 is independently mergeable after Sprint 1.

### Cycle Timeline Strategy (NEW v1.1 per Flatline BLOCKER SKP-007)

The original v1.0 plan compressed 22 tasks + E2E into 17 calendar days, which Flatline correctly identified as aggressive given parser refactor + new provider integration + security controls + CI automation all in cycle scope. v1.1 timeline:

**Estimated cadence (revised):**
- Sprint 0: T+0 to T+5 (5 days, unchanged)
- Sprint 1: T+5 to T+14 (9 days, +2 days for canary windows in Task 1.1 phased rollout)
- Sprint 2: T+14 to T+21 (7 days, +2 days for plugin-guide review and recurring-smoke baseline)
- **Total**: 21 calendar days (was 17), with 4 calendar days of buffer distributed across Sprints 1–2

**Must-have vs. stretch task split (REQUIRED ordering):**

| Sprint | Must-have | Stretch (de-scope first if time pressured) |
|---|---|---|
| Sprint 0 | Tasks 0.1–0.6 (5 gates + token-lifecycle); Task 0.8 (scrub) | Task 0.7 (backup account) — can ship as Sprint 1 follow-up if backup user not identified by T+3 |
| Sprint 1 | Task 1.1 Phases A–C (parser landed via incremental rollout); Tasks 1.2/1.3/1.4 (YAML + adapter + auth); Task 1.5 (compliance fallback); Task 1.A (adversarial redaction); Task 1.6 (live integration test) | Task 1.1 Phase D (canary cleanup) — can defer to Sprint 2; Task 1.B (streaming assertion) — quick task, low risk to keep |
| Sprint 2 | Task 2.E2E (final cycle gate); Task 2.1 (FR-8 health probe); Task 2.2 (FR-9 plugin guide skeleton); Task 2.4 (recurring CI smoke workflow) | Task 2.3 (FR-4 SigV4 design-only schema) — can defer if survey shows no IAM users; Task 2.5/2.6 (fixture evolution policy doc) — defer to cycle-097 if Sprint 2 oversprung |

**De-scope candidates that do NOT compromise security or compatibility gates:**
1. **Task 0.7 (backup account)** — operational resilience; SKP-001 mitigation; can land as a Sprint 1 follow-up
2. **Task 1.1 Phase D (canary cleanup)** — code hygiene; canary flag is harmless if left in tree
3. **Task 2.3 (FR-4 SigV4 schema)** — gated on G-S0-1 outcome; if all users are Bearer-only, deferring schema costs nothing
4. **FR-13 thinking-trace per-capability override** — if probe #4 shows full parity, the per-capability `api_format` override path is unused; can defer the test fixture
5. **Cross-region inference profile error path test** — FR-12 requires the error path code; the test fixture can defer to cycle-097 if Sprint 1 oversprung

**De-scope candidates that DO compromise gates (DO NOT cut these):**
- ❌ Task 1.A (adversarial redaction) — closes SKP-005; security baseline
- ❌ Task 1.5 (compliance fallback) — closes BLOCKER NFR-R1
- ❌ NFR-Sec11 token age sentinel — closes BLOCKER SKP-002
- ❌ Cycle-094 G-7 invariant test extension — backward compatibility gate
- ❌ Live integration test — closes G-1 launch criterion
- ❌ Task 1.1 Phases A–C (parser landed) — foundation; cutting strands every other Sprint 1 task

**Schedule slip protocol:** If Sprint 0 closes > T+5, Sprint 1 entry slips proportionally; the 4-day buffer absorbs up to 3 days of upstream slip. If buffer is exceeded, Sprint 2 stretch tasks are de-scoped first; if still exceeded, escalate via `/feedback` and reconsider FR-13 / Task 0.7 / Task 1.1 Phase D as descope candidates per the must-have/stretch split above.

### Fixture Evolution Policy (NEW v1.1 per Flatline IMP-006)

`bedrock-contract-v1.json` (committed in Sprint 0) is a snapshot of Bedrock's API surface at cycle start. AWS will evolve the contract; the policy below governs how Loa keeps the fixture current without losing drift-detection signal.

**Versioning:**
- Current: `tests/fixtures/bedrock/contract/v1.json`
- Bumped to `v2.json` when AWS introduces a behavior delta (new field, removed field, semantic change in existing field, retired model ID, etc.) that makes the v1 fixture no longer assertable as ground-truth
- v1 fixture stays in tree for one cycle as a regression backstop (assert that recurring smoke from a v1-frozen-token still works against current API in restricted-feature mode)

**Triggers for a version bump (any of):**
1. Recurring CI smoke fixture-diff fails for a structural-key change (not just value change)
2. Maintainer observes a Bedrock release announcement affecting Day-1 model surface
3. Quarterly review (every 90 days, paired with key-rotation cadence per NFR-Sec6) — re-probe and decide if v(N+1) is needed
4. Cycle-097+ adds a new Bedrock model (v(N+1) captures the new model ID)

**Bump procedure:**
1. Re-run G-S0-2 probes against current Bedrock state, including any new probes for the changed surface
2. Generate `vN+1.json` from new captures
3. Diff vN.json vs vN+1.json; document deltas in `tests/fixtures/bedrock/contract/CHANGELOG.md`
4. Update Sprint 1 `bedrock_adapter.py` import to vN+1 fixture; vN tests retire OR move to a "legacy-shape regression" suite if vN behavior is still backward-compatible
5. Recurring CI smoke workflow updates to vN+1 baseline; the comparator handles the migration window (vN AND vN+1 both pass for a 1-week overlap)

**Documented in FR-9 plugin guide** as part of the "Adding a Provider" walkthrough — the fixture-evolution pattern generalizes beyond Bedrock to any future provider.

---

## Sprint 0: Contract Verification Spike (BLOCKING)

**Scope:** MEDIUM (6 tasks)
**Duration:** 5 calendar days (T+0 to T+5; survey runs in parallel with probe authoring per PRD §Sprint-0-timeline)
**Dates:** 2026-05-02 → 2026-05-07

### Sprint Goal

Retire the assumption risk on auth modality, API contract shape, compliance posture, error taxonomy, and cross-region inference profiles **before any Sprint 1 code is written**, by surveying users + probing live Bedrock + capturing a versioned contract fixture.

### Deliverables

- [ ] `grimoires/loa/spikes/cycle-096-sprint-0-bedrock-contract.md` — five gate sections (G-S0-1 through G-S0-5) each with PASS/FAIL judgment and citations
- [ ] `tests/fixtures/bedrock/contract/v1.json` — versioned contract fixture (`endpoint_url_pattern`, `request_body_shape`, `response_body_shape`, `error_response_shape`, `model_ids[]`, `tool_schema_wrapping`, `thinking_trace_shape`) per SDD §8 G-S0-CONTRACT
- [ ] Token-lifecycle metadata (issue date, last-rotated date, expected expiry if surfaced, creation source) captured per SDD §8 G-S0-TOKEN-LIFECYCLE — feeds NFR-Sec11 design
- [ ] Three Day-1 model IDs from `ListFoundationModels` confirmed (closes OQ-1)
- [ ] `compliance_profile` 4-step defaulting rule locked with concrete test cases (feeds SDD §5.6)

### Acceptance Criteria

- [ ] All five gates PASS or PASS-WITH-CONSTRAINTS (no FAILs); FAIL on any gate triggers PRD reframing per PRD §Sprint-0
- [ ] G-S0-1 sample size ≥ 3 respondents AND ≥ 70% Bearer-token (or operator override documented in spike report per PRD §G-S0-1 4-way decision tree)
- [ ] G-S0-2 captures full request/response for all 6 probes (redacted) — including `ListFoundationModels`, three Converse calls, tool-schema probe, thinking-trace probe, empty-content edge case probe, cross-region prefix probe
- [ ] `bedrock-contract-v1.json` committed and importable by Sprint 1 unit tests (Sprint 1 Task 1.6 imports as fixture)
- [ ] PRD §A8 + §A9 (URL-encoding requirement, tool-schema wrapping requirement) confirmed empirically against live API
- [ ] DISPUTED IMP-009 (thinking-trace parity) resolved with one of three FR-13 outcomes documented (parity / different shape / not exposed)

### Technical Tasks

- [ ] **Task 0.1**: Author and send G-S0-1 user survey (3 questions: auth modality, single-vs-cross-account scope, compliance posture) — issue comment + Discord ping; 5-day window → **[G-1]** (gates auth scope)
- [ ] **Task 0.2**: Run G-S0-2 live API probes #1–#6 against maintainer's Bedrock account; capture redacted request/response payloads to spike report; populate `bedrock-contract-v1.json` from probe captures. **NEW v1.1 per Flatline BLOCKER SKP-004**: Probe set MUST include multi-region coverage (probes run against 2 regions: maintainer's primary region + one secondary region from `us.*` set) and document the explicit non-support boundary for AWS partitions outside commercial (GovCloud `us-gov-*`, China `cn-*`) — these are documented as out-of-scope for v1 with no probe attempted. Single-account validation is acknowledged as a known gap; G-S0-BACKUP (Task 0.7) provides a partial mitigation path → **[G-1]**
- [ ] **Task 0.3**: G-S0-3 — codify the 4-step `compliance_profile` defaulting rule per PRD §G-S0-3; write three behavior test cases (mocked outage → fail-closed, warned-fallback, silent-fallback) plus migration test (fresh user → `bedrock_only` + one-shot stderr notice) → **[G-3]** (compliance posture must not break existing users)
- [ ] **Task 0.4**: G-S0-4 — enumerate Bedrock error taxonomy (7 categories per PRD §G-S0-4) with documented retry/no-retry/circuit-break decisions per category; capture 200-OK-with-quota-body example for the FR-11 retry classifier → **[G-1]** (reliability gate for Sprint 1 code)
- [ ] **Task 0.5**: G-S0-5 — probe both `us.anthropic.*` and `eu.anthropic.*` (or whichever regional profiles cover Day-1 models) with Bearer auth; confirm region-prefix format works AND cross-account ARN format does not (or fails as expected); document Day-1 model ID list with region scope → **[G-1, G-4]** (Day-1 availability)
- [ ] **Task 0.6**: G-S0-TOKEN-LIFECYCLE — capture maintainer-token metadata for NFR-Sec11 design (age, rotation source, AWS-side expiry exposure if any); write findings into the spike report's "Token lifecycle observations" section → **[G-3]** (security baseline; no behavior change for existing users)
- [ ] **Task 0.7 (NEW v1.1 per Flatline BLOCKER SKP-001)**: G-S0-BACKUP — establish break-glass continuity for the maintainer-account SPOF risk:
  - Identify a backup test account owner from the Bedrock-using user pool (G-S0-1 respondents are the natural candidates) and document the contact path
  - Capture a backup token from the backup account (NEVER stored in tree — only the contact path + CI-secret slot reservation)
  - Create a "non-blocking validation mode" path: when `AWS_BEARER_TOKEN_BEDROCK` and `AWS_BEARER_TOKEN_BEDROCK_BACKUP` are both unset (e.g., maintainer offline + backup unreachable), CI workflow exits cleanly with an INCONCLUSIVE label rather than failing — explicitly distinct from the "skipped: no_ci_token" path so this state is visible to maintainers via dashboard
  - Document the break-glass procedure in the FR-9 plugin guide (Sprint 2 deliverable; SKP-001 closure cross-references)
  → **[G-1, G-3]** (resilience baseline)
- [ ] **Task 0.8 (NEW v1.1 per Flatline IMP-004)**: Live-data scrub procedure for spike report — Sprint 0 collects redacted-but-still-sensitive data (account IDs, regional endpoint shapes, response timing). Author and run a structured sanitization checklist BEFORE the spike report is committed:
  - Account IDs: replaced with `<account-id>` literal
  - Token values: never present (already redacted at probe-capture time)
  - Inference profile ARNs (which embed account IDs): redacted
  - Probe-response timing values: rounded to 100ms boundaries (precise timing can fingerprint specific accounts)
  - Run `lib-security.sh redact_secrets` over the final spike report; verify zero matches against the running token's last-4 hash
  → **[G-3]** (no credential or account leakage from public planning artifacts)

### Per-Gate PASS / PASS-WITH-CONSTRAINTS / FAIL Matrix (NEW v1.1 per Flatline SKP-003 + IMP-002)

The original v1.0 PRD §G-S0-N gates accepted "PASS-WITH-CONSTRAINTS" loosely. v1.1 sprint plan locks down what *each* PWC outcome means per gate, and what mitigation tasks are mandatory before Sprint 1 entry.

| Gate | PASS | PASS-WITH-CONSTRAINTS allowed | FAIL → mandatory action |
|---|---|---|---|
| G-S0-1 (auth survey) | ≥ 3 respondents AND ≥ 70% Bearer | Mixed Bearer/SigV4 (30–70% Bearer) → promote FR-4 SigV4 implementation INTO this cycle (Sprint 3 added) | < 30% Bearer → reframe Phase 1; SigV4 becomes v1, FR-3 deferred to v2 |
| G-S0-2 (live API contract) | All 6 probes succeed AND structural shapes match documentation | Probe #4 (thinking traces) reveals different-but-mappable shape → FR-13 ships with shape-mapper code; probe #5 (empty content) reveals pattern but recovery works → NFR-R4 retry covers it | Probe #1/#2/#3 (foundational) FAILs → block Sprint 1; reframe FR-1/FR-2 contracts; revisit PRD §A2/§A4 |
| G-S0-3 (compliance schema) | 4-step rule passes all 4 mocked scenarios + migration test | Defaulting rule passes for the 3 primary scenarios but migration test reveals minor edge case → ship with edge-case warning + Sprint 1 follow-up task | Defaulting rule produces non-deterministic output for any of the 4 paths → block; rewrite rule before Sprint 1 |
| G-S0-4 (error taxonomy) | All 7 categories enumerated, retry decisions documented, fixture captures for FR-11 ready | Daily-quota body pattern not reliably reproduced (vendor returns it inconsistently) → fixture is "best-effort", document open question for Sprint 1 to harden | Three or more categories cannot be enumerated against live API → block; FR-11 retry classifier cannot be designed without it |
| G-S0-5 (cross-region profiles) | All 3 Day-1 models confirmed in `us.*` profiles with Bearer auth | One Day-1 model is region-blocked from maintainer's region → FR-5 ships with 2 models, that one model added in cycle-097 | Cross-region inference profile feature is not GA at cycle-start (vendor change) → block; defer cycle until vendor stabilizes |
| G-S0-CONTRACT | `bedrock-contract-v1.json` committed; Sprint 1 unit tests import successfully | Fixture is committed but ≥1 capability reflects degraded vendor behavior (e.g., undocumented response key) → Sprint 1 acknowledges with explicit "fixture-known-fragile" comment; CI smoke watches for change | Fixture cannot be generated due to G-S0-2 FAIL → block (already covered by G-S0-2 cascade) |
| G-S0-TOKEN-LIFECYCLE | Maintainer token metadata captured (age, rotation source, AWS-side expiry surfacing if any) | AWS does not expose token-expiry via any API → NFR-Sec11 ships with age-only warning (no AWS-side expiry probe) | (No FAIL path — this is a documentation gate, not a behavioral one) |
| G-S0-BACKUP | Backup account contact path documented + non-blocking validation mode coded | Backup user identified but token unprovisioned at Sprint 0 close → Sprint 1 includes follow-up task to provision; ship with single-account risk note in `sprint.md` | No backup user identifiable from G-S0-1 pool → escalate; consider holding cycle until SPOF mitigated |

**Sprint 1 entry rule (HARD GATE)**: All 7 gates must be PASS or PASS-WITH-CONSTRAINTS. Any FAIL blocks Sprint 1 unconditionally. PASS-WITH-CONSTRAINTS gates trigger their named mitigation task as a Sprint 1 prerequisite (added to Sprint 1 task list before Sprint 1 starts).

### Dependencies

- Maintainer (`@janitooor`) has a Bedrock-enabled AWS account with `AWS_BEARER_TOKEN_BEDROCK` provisioned (PRD §A6 cycle-095 archival is **already complete** per ledger and recent commit `73431db`)
- AWS Bedrock service availability in maintainer's region (PRD D-1 — out of Loa's control)
- ≥ 3 survey respondents in 5 days OR documented operator override (PRD §G-S0-1 INCONCLUSIVE branch)

### Security Considerations

- **Trust boundaries**: Probe outputs are sanitized before commit — strip token values, sanitize account IDs, leave structural keys; redaction happens via `lib-security.sh redact_secrets` (sourced once even though full Layer 1+2 implementation lands in Sprint 1)
- **External dependencies**: None added — probes use existing `httpx` / `urllib`. No `boto3` introduced.
- **Sensitive data**: Maintainer's Bedrock API Key handled only via env var; sentinel-shape fingerprint (last-4 of SHA256, never raw) is the only value persisted; full token never written to spike report

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| < 3 survey respondents in 5 days (PRD A1 INCONCLUSIVE) | Medium | High | Operator override path documented in PRD §G-S0-1; ship Bearer v1 with explicit roadmap commitment to revisit at 30-day post-launch checkpoint |
| Probe #4 reveals thinking traces NOT exposed via Converse (PRD R-3 / OQ-3) | Medium | Medium | FR-13 Acceptance Criterion (b)/(c) handles non-parity outcomes; `api_format.thinking_traces: invoke` per-capability fallback codified; capability list in FR-1 amended to ground truth |
| `ABSKY*` regex prefix has evolved between PRD lock-down and Sprint 0 (OQ-5) | Medium | Medium | Probe #1 captures sample token shape (redacted to last-4); Sprint 1 NFR-Sec2 Layer 1 regex updated from probe finding before merge |
| Cross-region inference profiles not GA in maintainer's region for one of the three models (R-13) | Medium | Medium | FR-12 region-prefix mismatch error path; probe #6 confirms coverage; if a model is region-blocked, FR-5 defers that one model with an explicit note |

### Success Metrics

- 5/5 gates PASS or PASS-WITH-CONSTRAINTS within 5 calendar days
- Spike report and `bedrock-contract-v1.json` both committed to base; Sprint 1 entry gate (PRD §Sprint-0-timeline T+5d) clears
- Zero unresolved [ASSUMPTION] flags remain on Sprint 1 code paths

---

## Sprint 1: Bedrock v1 Functional + Centralized Parser

**Scope:** LARGE (10 tasks)
**Duration:** 7 calendar days (T+5 to T+12)
**Dates:** 2026-05-07 → 2026-05-14

### Sprint Goal

Ship Bedrock-via-API-Key as a fully-functional fourth Loa provider — three Anthropic-on-Bedrock models invocable end-to-end with region resolution, compliance-aware fallback, two-layer secret redaction, error taxonomy, token age sentinel, and centralized parser landed FIRST as the foundation for every subsequent commit.

### Deliverables

- [ ] `lib-provider-parse.sh` (bash) + `loa_cheval.types.parse_provider_model_id` (Python) shared parser landed; all 4 bash callsites + all Python callsites refactored to use it
- [ ] `bedrock_adapter.py` implementing `complete()` / `validate_config()` / `health_check()` / `_classify_error()` per FR-2 + FR-11
- [ ] `model-config.yaml` extended with `providers.bedrock` entry (per-capability `api_format`, `compliance_profile: bedrock_only` default, region-prefixed model IDs, three Day-1 models with live-fetched pricing)
- [ ] `model-permissions.yaml` extended with three `bedrock:us.anthropic.*` trust scope entries mirroring `anthropic:claude-opus-4-7` (`model-permissions.yaml:147-173`)
- [ ] `lib-security.sh` `_SECRET_PATTERNS` extended with **two-layer** redaction (value-based PRIMARY + `ABSK[A-Za-z0-9+/=]{36,}` regex SECONDARY + length-fallback regex) per SDD §6.4.1
- [ ] `compliance_profile` 4-step loader rule (SDD §5.6) + cross-provider fallback gating (SDD §6.2) + audit/ledger entries (NFR-Sec8 schema)
- [ ] NFR-Sec11 token-age sentinel (`.run/bedrock-token-age.json`) + 60/80/90-day stderr warnings + `auth_lifetime: short` reject path
- [ ] `§6.6` concurrency primitives — `threading.Event()` for `_daily_quota_exceeded`, `total_deadline_ms` retry semantics, streaming explicit out-of-scope error
- [ ] `§6.7` Bedrock feature flag — `hounfour.bedrock.enabled` config gate + `.run/bedrock-migration-acked.sentinel`
- [ ] Live integration test (key-gated) green on maintainer's Bedrock account; cycle-094 G-7 invariant green; `model-invoke --validate-bindings` byte-identical for non-Bedrock-overridden configs

### Acceptance Criteria

- [ ] **Parser landed FIRST** — Task 1.1 commit precedes every other Sprint 1 commit; 4 bash callsites (`gen-adapter-maps.sh`, `model-adapter.sh`, `red-team-model-adapter.sh`, `flatline-orchestrator.sh`) source the shared helper; all Python callsites import `loa_cheval.types.parse_provider_model_id`
- [ ] `tests/integration/parser-cross-language.bats` passes with the 9 input cases from SDD §5.4 table (multi-colon, empty-provider, empty-model, no-colon, multi:colon:value, etc.)
- [ ] `tests/integration/colon-bearing-model-ids.bats` (NEW) passes — covers (a) provider parsing, (b) generated-map key shape, (c) `validate_model_registry()` cross-map invariant, (d) `MODEL_TO_ALIAS` resolution in `model-adapter.sh`
- [ ] `bash .claude/scripts/gen-adapter-maps.sh --check` passes (no drift; bedrock entries in all four arrays — `MODEL_PROVIDERS`, `MODEL_IDS`, `COST_INPUT`, `COST_OUTPUT`)
- [ ] `bats tests/integration/model-registry-sync.bats` passes (cycle-094 G-7 invariant — closes R-6)
- [ ] `bedrock_adapter.py` unit-test coverage ≥ 85% (per FR-10) covering: success, 4xx structured error, 5xx, timeout, daily-quota body pattern, empty `content[]` retry, region-prefix mismatch error
- [ ] Live integration test (`tests/integration/test_bedrock_live.py`) passes against real Bedrock account; skips cleanly when `AWS_BEARER_TOKEN_BEDROCK` absent (cycle-094 G-E2E precedent — closes R-1)
- [ ] `model-invoke --validate-bindings` output byte-identical before/after for configs that don't override aliases to bedrock (NFR-Compat1 — gates the merge per PRD §Launch Criteria)
- [ ] Two-layer secret-redaction tests pass: value-based redacts a non-`ABSKY` token; regex redacts a known-prefix token even with no env-var match (defense in depth)
- [ ] NFR-Sec11 mock-clock test asserts 60/80/90-day warning thresholds fire correctly; `auth_lifetime: short` is rejected with the documented error
- [ ] Bedrock pricing values **live-fetched at sprint execution** (closes OQ-2) and committed with citation comment per PRD FR-5 AC and `model-config.yaml:171-180` Haiku 4.5 precedent
- [ ] No BLOCKER findings on the bedrock branch when `/flatline-review` is invoked (PRD §Launch Criteria)
- [ ] No `boto3` import in `bedrock_adapter.py` (test asserts via import scan — FR-3 AC)

### Technical Tasks

<!-- Each task annotated with contributing PRD goal(s); architectural ordering enforced — Task 1.1 lands FIRST -->

- [x] **Task 1.1 (REVISED v1.1 per Flatline BLOCKER SKP-008 + IMP-003)**: Land centralized parser (`lib-provider-parse.sh` + `loa_cheval.types.parse_provider_model_id`) per SDD §5.4 — but **NOT as a single atomic refactor**; the v1.0 plan's atomic-PR approach was correctly flagged as regressing all 4 existing providers if the parser semantics drift. **Revised rollout (SKP-008 mitigation):**
  - **Phase A (PR 1)**: Land the helper modules with full unit tests (no callsite changes). Keep the existing inline parser logic in callsites in place, untouched. Helper exists in tree but is only referenced by its own tests.
  - **Phase B (PR 2)**: Introduce a compatibility shim — each existing callsite keeps its inline parser AND adds a parallel call to the new helper, asserting equivalent output via a debug-mode comparison flag (`LOA_PARSER_CANARY=1`). Run for ≥ 24 hours of CI on every existing test suite + ad-hoc dev work; surface any divergence loudly.
  - **Phase C (PR 3)**: Replace each callsite's inline parser with the helper (one callsite per commit; 4 bash + N Python = 5+ commits). Each commit independently runs the cycle-094 G-7 invariant test + every provider's existing test suite. Any regression on any commit reverts only that commit, leaving prior commits stable.
  - **Phase D (PR 4)**: Remove the canary flag and inline-parser code paths once all callsites are validated.
  - **Tests gating each phase**: `tests/integration/parser-cross-language.bats` covers the 9-case property table per SDD §5.4. NEW v1.1: `tests/integration/parser-legacy-regression.bats` runs every existing provider's existing model-resolution path through both inline-old AND helper-new parsers in canary mode; assertion: identical output for ≥ 1000 known-good IDs from `generated-model-maps.sh`.
  - **Rollback procedure** (NEW v1.1 per IMP-003 — original "rollback = revert single PR" was too shallow): If divergence surfaces in Phase B canary, revert PR 2 only — Phase A's helper stays in tree (it's unused). If divergence surfaces in Phase C, revert the offending callsite commit; remaining callsites keep using the helper. If a *post-merge* regression surfaces in production (cycle-097+), the canary flag remains available as an emergency tool to detect divergence in any environment.
  → **[G-2]** (foundation for "≤1-day fifth provider"; closes Flatline v1.1 SKP-006 + v1.0 AR-1 + sprint-pass SKP-008/IMP-003)
- [x] **Task 1.A (NEW v1.1 per Flatline BLOCKER SKP-005)**: Adversarial secret-redaction test fixtures — exercise NFR-Sec2/Sec10 redaction layers against transformed token leakage paths that a naive regex misses:
  - Base64-encoded token in a JSON request body field (encoded by an upstream client)
  - URL-encoded token in a query parameter (e.g., debug logging that captures full URL)
  - Multi-line token split across lines (e.g., terminal output with line wrapping)
  - Token concatenated with surrounding text (e.g., `"Authorization: Bearer ABSKY...{rest}\n"` log line where the token isn't on its own line)
  - Token in a structured log field (e.g., `{"auth_header": "Bearer ABSKY..."}`)
  - Token in CI debug output / `set -x` shell traces
  - **Default-disable verbose HTTP logging**: `bedrock_adapter.py` initializes the underlying httpx logger to WARNING by default; debug-level requires explicit `LOA_BEDROCK_HTTP_DEBUG=1` env var with a documented warning that token redaction may not catch all paths in debug mode
  - Each adversarial fixture asserts the value-based PRIMARY redaction catches it (since regex only matches the bare prefix); failures are merge-blocking
  → **[G-3]** (defense-in-depth secret hygiene)
- [x] **Task 1.B (NEW v1.1 per Flatline IMP-007)**: Streaming non-support assertion — `bedrock_adapter.py` raises `NotImplementedError("Streaming not supported in v1; track at OQ-S1")` immediately when streaming is requested; unit test asserts the error type, message, and call-site (no silent fallback to non-streaming). Documentation in FR-9 plugin guide includes a one-line note. Closes IMP-007. → **[G-2]** (capability honesty)
- [x] **Task 1.2**: Add `providers.bedrock` entry to `.claude/defaults/model-config.yaml` per FR-1 — region-prefixed model IDs from Sprint 0 fixture, per-capability `api_format` (chat/tools/thinking_traces), `compliance_profile: bedrock_only` default, `auth_modes: [api_key, sigv4]` (sigv4 designed-not-built), live-fetched pricing with citation comment; regenerate `generated-model-maps.sh` via `gen-adapter-maps.sh` → **[G-1, G-3]**
- [x] **Task 1.3**: Implement `bedrock_adapter.py` per FR-2 — `complete()` with per-capability dispatch (Converse / InvokeModel per `api_format`), URL-encoding via `_build_converse_url()` helper (AR-9 single-edit-site discipline), tool-schema wrapping via `_wrap_tool_schemas()` helper (AR-10), region resolution chain (FR-6), Bearer auth via FR-3, `validate_config()` rejecting `sigv4`/empty token, `health_check()` against control-plane endpoint → **[G-1, G-4]**
- [x] **Task 1.4**: Implement FR-11 error taxonomy + retry classifier in `_classify_error()` covering all 7 G-S0-4 categories — Throttling/ServiceUnavailable retry, ValidationException/AccessDeniedException/ResourceNotFoundException no-retry, daily-quota body-pattern detection, empty-content single-retry-then-`EmptyResponseError`; daily-quota uses `threading.Event()` per SDD §6.6 (closes AR-12) → **[G-1]**
- [x] **Task 1.5**: Implement `compliance_profile` defaulting rule per SDD §5.6 (4-step loader logic) + SDD §6.2 cross-provider fallback gating with **versioned `fallback_to` mapping enforcement** (loader rejects `prefer_bedrock` when no exact mapping declared, closes Flatline SKP-003); emit one-shot stderr migration notice gated by sentinel file `~/.loa/seen-bedrock-default` (or `${LOA_CACHE_DIR}/seen-bedrock-default` per AR-8) → **[G-3]** (compliance posture preserved; no silent egress)
- [x] **Task 1.6**: Implement two-layer secret redaction per SDD §6.4.1 — Layer 1 value-based (PRIMARY) registers resolved env-var values for whole-string replacement; Layer 2 regex `ABSK[A-Za-z0-9+/=]{36,}` (SECONDARY) + length-fallback regex (TERTIARY); both layers fire on every `redact_secrets` call; `tests/unit/secret-redaction.bats` covers all three paths including non-`ABSKY` token via value-based; **import `bedrock-contract-v1.json` as fixture** for response-shape assertions on every test run → **[G-3]** (sensitive data protected; no token leaks)
- [x] **Task 1.7**: NFR-Sec11 token-age sentinel — write `.run/bedrock-token-age.json` on first call from a new token (detected via SHA256 last-4 token_hint per NFR-Sec8); 60-day silent / 60-80 day info / 80-90 warn-every-100 / 90+ warn-every-call thresholds; mock-clock unit test verifies all four bands; `auth_lifetime` schema field added to bedrock provider entry, `short` value rejected with documented error → **[G-3]** (security baseline; closes AR-11)
- [x] **Task 1.8**: NFR-Sec8 audit/ledger schema — extend `cost-ledger.jsonl` writes with `event_type` enum (completion / fallback_cross_provider / circuit_breaker_trip / token_rotation), `fallback` field, `token_hint` (last-4 SHA256, never raw); extend `.run/audit.jsonl` with `category: auth | compliance | circuit_breaker` + `subcategory` enum; surface 401/403, daily-quota trips, and compliance-fallback events to all three sinks (cost ledger + audit log + stderr) → **[G-3]**
- [ ] **Task 1.9**: SDD §6.7 Bedrock feature flag — `hounfour.bedrock.enabled` config gate (default `false` until first explicit op-in); `.run/bedrock-migration-acked.sentinel` one-shot ack file; loader rejects `bedrock:*` references with clear error if flag is `false` and sentinel is absent; FR-7 same-model dual-provider naming discipline regression test asserts `aliases:` block in default `model-config.yaml` is untouched → **[G-3]** (NFR-Compat1 — backward-compat alias discipline preserved)
- [ ] **Task 1.10**: Live integration test (`tests/integration/test_bedrock_live.py`) — invoke each of the three Day-1 models end-to-end (Converse + tool-schema + thinking-trace probe shapes from `bedrock-contract-v1.json`); fork-PR/no-keys skip-clean per cycle-094 G-E2E precedent; live test green on maintainer's Bedrock account → **[G-1, G-4]** (UC-1 + UC-2 acceptance gate)

### Dependencies

- **Sprint 0 PASS** on all five gates + `bedrock-contract-v1.json` committed to tree (HARD blocker — Sprint 1 cannot start otherwise per SDD §8 Phase 0 exit criterion)
- Cycle-094 G-7 invariant test infrastructure (`tests/integration/model-registry-sync.bats`) — present, used as merge gate
- Cycle-095 cost guardrails (`max_cost_per_session_micro_usd`) — present unmodified, applies to Bedrock requests (NFR-Sec5)
- Maintainer's Bedrock account remains active for the live integration test in Task 1.10

### Security Considerations

- **Trust boundaries**: Bedrock API responses are untrusted bytes; `_classify_error()` and shape assertions against `bedrock-contract-v1.json` enforce expected shape; URL-construction helper centralizes URL-encoding (AR-9 single-edit-site discipline)
- **External dependencies**: ZERO new heavyweight dependencies (NFR-Compat3); `httpx` already present; explicit assertion that `boto3` is NOT imported anywhere in `bedrock_adapter.py` (test scans imports per FR-3 AC)
- **Sensitive data**: Two-layer redaction (value-based PRIMARY + regex SECONDARY + length fallback); token never logged to stderr / trajectory / audit / cost ledger; only last-4 SHA256 prefix as `token_hint` per NFR-Sec8
- **Authorized System Zone edits**: `.claude/defaults/model-config.yaml`, `.claude/data/model-permissions.yaml`, `.claude/scripts/lib-security.sh`, `.claude/scripts/lib-provider-parse.sh` (NEW), `.claude/scripts/gen-adapter-maps.sh`, `.claude/scripts/model-adapter.sh`, `.claude/scripts/red-team-model-adapter.sh`, `.claude/scripts/flatline-orchestrator.sh`, `.claude/scripts/model-health-probe.sh`, `.claude/adapters/loa_cheval/**` — all authorized at cycle scope per PRD §Constraints "No System Zone edits without cycle authorization"

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| AR-1 — Centralized parser refactor breaks an existing callsite (regression in non-Bedrock providers) | Medium | High | Land Task 1.1 as **single atomic PR with tests-first**; cycle-094 G-7 invariant continues to assert cross-map integrity; cross-language property test mandatory acceptance gate; rollback = revert single PR |
| R-1 / R-3 — Bedrock Converse feature gaps vs direct Anthropic surface during integration | Medium | Medium | Per-capability `api_format` schema (FR-1) accommodates partial parity; `bedrock-contract-v1.json` fixture imported in unit tests catches drift; FR-13 explicit verification step ensures aspirational capabilities are not declared |
| AR-7 — Two-layer redaction adds runtime cost in high-throughput workflows (Bridgebuilder, Flatline) | Low | Low | Value-based redaction is O(n×m) where m is small (≤ 5 registered tokens); profile in Sprint 1 if numbers surprise; existing `lib-security.sh` benchmarks as baseline |
| R-12 / AR-10 — Tool-schema `{ json: <schema> }` wrapping missed at one of multiple Bedrock callsites in the future | Medium | High | Wrapping happens in **one** place (`_wrap_tool_schemas()` helper); unit test asserts the wrapping; recurring CI smoke probe #2 (Sprint 2) catches structural changes |
| R-5 / OQ-2 — Bedrock pricing values change between Sprint 0 and Sprint 1 commit | Low | Low | Live-fetch at Sprint 1 execution per FR-5 AC; YAML-frozen with citation comment per `model-config.yaml:171-180` Haiku 4.5 precedent; quarterly refresh reminder added to operator runbook in Sprint 2 |
| OQ-10 — `gen-adapter-maps.sh` doesn't handle new YAML fields (`region_default`, `auth_modes`, `compliance_profile`) | Medium | Medium | Verify Sprint 1 day 0 by running `gen-adapter-maps.sh --check` against a draft bedrock entry; if needed, extend generator within Task 1.2 scope |

### Success Metrics

- All 6 PRD launch criteria (PRD §1000-1009) met at Sprint 1 close
- 0 BLOCKERs on `/flatline-review` of the bedrock branch
- 100% pass rate on `tests/integration/parser-cross-language.bats`, `tests/integration/colon-bearing-model-ids.bats`, `tests/integration/model-registry-sync.bats` (cycle-094 G-7), `tests/unit/providers/test_bedrock_adapter.py`, `tests/unit/secret-redaction.bats`
- ≥ 85% unit-test coverage on `bedrock_adapter.py`
- Live integration test green on maintainer's Bedrock account
- `model-invoke --validate-bindings` byte-identical before/after for non-Bedrock-overridden configs

---

## Sprint 2: Plugin Guide + IR Runbook + Health Probe + Recurring Smoke + E2E Goal Validation (Final)

**Scope:** MEDIUM (6 tasks + Task 2.E2E)
**Duration:** 5 calendar days (T+12 to T+17)
**Dates:** 2026-05-14 → 2026-05-19

### Sprint Goal

Codify the six-edit-site provider-plugin contract as a maintainer-facing guide with the Bedrock implementation as the worked example (closes G-2), ship the long-term drift-detection layer (recurring CI smoke per SDD §5.5), wire the Bedrock-side health probe into existing pre-flight cache, lock in the FR-4 SigV4 v2 schema seed without building it, and validate all four PRD goals end-to-end.

### Deliverables

- [ ] FR-9: `grimoires/loa/proposals/adding-a-provider-guide.md` — six-step checklist with file:line anchors, Bedrock-implementation references at each step, decision table (Bearer vs SigV4), pricing-source guidance, cross-map invariant warning
- [ ] FR-9 IR runbook section per NFR-Sec9 — "If your Bedrock token is compromised" — detection signals, immediate revocation procedure (AWS console + env var clear + process restart), blast-radius assessment (cost-ledger query), cycle-095 cost-guardrails as damage-cap layer
- [ ] FR-4: `auth_modes` schema field present in `model-config.yaml`; loader rejects `sigv4` value with documented error pointing to v2 follow-up cycle issue
- [ ] FR-8: `model-health-probe.sh` extended for Bedrock — control-plane reachability probe, AVAILABLE/UNAVAILABLE/UNKNOWN cache states; `_probe_cache_check()` auto-handles bedrock provider
- [ ] FR-10 completion: health probe BATS tests; secret-redaction BATS test extension covering value-based path; daily-quota circuit-breaker test verifying recovery on process restart
- [ ] **Recurring CI smoke** per SDD §5.5: `.github/workflows/bedrock-contract-smoke.yml` — daily 06:00 UTC weekday cron + path-trigger + workflow_dispatch; weekly model rotation across [Haiku/Sonnet/Opus]; pre-flight cost estimate + post-flight ledger assertion (≤ $0.50/run, ≤ $15/month); **required-status signal** (`BEDROCK_SMOKE_REQUIRE_TOKEN`) fails loudly when scheduled run hits missing secret; fixture-diff against `tests/fixtures/bedrock/recurring/probe-{1,2}-{model}-response.json` (structural keys via `jq 'paths'`); fork-PR no-keys skip-clean
- [ ] Quarterly pricing-refresh reminder + ≤ 90-day token rotation cadence (NFR-Sec6) added to operator runbook section in plugin guide
- [x] **Task 2.E2E**: End-to-End Goal Validation — all four PRD goals validated with documented evidence

### Acceptance Criteria

- [ ] FR-9 plugin guide enumerates **all six edit sites** with current `file:line` anchors that resolve at commit time (CI check optional, may surface as future work)
- [ ] Bedrock implementation referenced at each step of the six-step checklist as the worked example (cited file paths from Sprint 1)
- [ ] Validation checklist runnable as documented (`gen-adapter-maps.sh --check && bats tests/integration/model-registry-sync.bats && pytest tests/unit/providers/`)
- [ ] FR-9 plugin guide reviewed by `/review-sprint` against actual Bedrock implementation for fidelity (PRD §Launch Criteria + AR-2)
- [ ] IR runbook covers all four NFR-Sec9 sections — detection signals, immediate revocation, blast-radius assessment via ledger query, damage-cap layer reference
- [ ] FR-4 loader test: `auth_modes: sigv4` raises ConfigError with the documented "not yet supported" message; `auth_modes: api_key` passes; no `boto3` import
- [ ] FR-8 health probe transitions a bedrock model from UNKNOWN → AVAILABLE on successful probe; UNKNOWN → UNAVAILABLE on 4xx; LOA_PROBE_BYPASS audit-log path covers bedrock without provider-specific code (NFR-S1)
- [ ] Recurring CI smoke runs successfully on first scheduled invocation with secret present (`workflow_dispatch` confirmation in Sprint 2 acceptance per AR-2)
- [ ] Fixture diff is empty on first scheduled invocation (drift = exit non-zero per SDD §5.5)
- [ ] `BEDROCK_SMOKE_REQUIRE_TOKEN=true` AND missing secret on scheduled run **fails loudly** with auto-opened issue tagged `bedrock-contract-smoke-misconfigured` (closes Flatline BLOCKER SKP-004)
- [ ] Daily-quota circuit-breaker BATS test verifies recovery on process restart (NFR-R4 + AR-6)
- [x] **Task 2.E2E** all four goal-validation rows PASS

### Technical Tasks

- [x] **Task 2.1**: Author FR-9 plugin guide at `grimoires/loa/proposals/adding-a-provider-guide.md` with six-step checklist + file:line anchors + Bedrock worked-example cross-references + decision table + cycle-094 G-7 invariant explanation; submit for `/review-sprint` against actual Bedrock implementation → **[G-2]** (the maintainer-experience goal)
- [x] **Task 2.2**: Author FR-9 IR runbook section per NFR-Sec9 — detection / revocation / blast-radius / damage-cap; reference NFR-Sec11 token-age sentinel as forensic data source; runbook owner = `@janitooor` per CODEOWNERS → **[G-3]** (security baseline; security operator handoff)
- [x] **Task 2.3**: FR-4 design-only — add `auth_modes: [api_key, sigv4]` schema field on bedrock provider entry; loader rejects `sigv4` with error message "SigV4/IAM auth designed not built in cycle-096 — track v2 status in `grimoires/loa/proposals/bedrock-sigv4-v2.md` (Sprint 2 stub) and the next-cycle planning"; no `boto3`, no `botocore`, no `aws_signing.py` introduced → **[G-2]** (architecture accommodates v2 without retrofit)
- [x] **Task 2.4**: FR-8 health probe — extend `.claude/scripts/model-health-probe.sh` for bedrock provider (control-plane probe to `https://bedrock.{region}.amazonaws.com/foundation-models` with Bearer auth — verify URL pattern from Sprint 0 G-S0-2 probe #1 result before committing per OQ-4); `model-adapter.sh _probe_cache_check()` auto-extends since keyed on `provider:model-id`; BATS tests verify state transitions → **[G-1]**
- [x] **Task 2.5**: FR-10 completion — secret-redaction BATS test extension covers value-based path on a non-`ABSKY` token; daily-quota circuit-breaker BATS test verifies trip + recovery-on-restart (process-scoped flag is by design per AR-6); health probe BATS test extension → **[G-3]** (test coverage; closes residual FR-10 ACs from Sprint 1)
- [x] **Task 2.6**: Author + commit `.github/workflows/bedrock-contract-smoke.yml` per SDD §5.5 — cron + path + workflow_dispatch triggers; **weekly model rotation** through `[Haiku 4.5, Sonnet 4.6, Opus 4.7]` (`week-of-year mod 3`); pre-flight cost estimate (rejects run > $0.50) + post-flight ledger assertion + monthly aggregate ≤ $15; **required-status signal** `BEDROCK_SMOKE_REQUIRE_TOKEN` fails loudly on scheduled-run-missing-secret with auto-opened issue; baseline fixtures at `tests/fixtures/bedrock/recurring/probe-{1,2}-{model}-response.json` (structural keys via `jq 'paths'`); `lib-security.sh redact_secrets` sourced and applied to all logged output; fork-PR skip-clean per cycle-094 G-E2E precedent → **[G-1, G-2]** (long-term drift detection; supports maintainer experience)

### Task 2.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1, G-2, G-3, G-4)

**Description:** Validate that all four PRD goals are achieved end-to-end through the cycle-096 implementation. This is the final cycle gate before `/audit-sprint` and merge.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | Loa works end-to-end against AWS Bedrock with API-Key auth | Run `model-invoke --agent flatline-reviewer --model bedrock:us.anthropic.claude-opus-4-7 --input <fixture file>` against maintainer's live Bedrock account | Returns usable completion; cost-ledger entry shows `provider: bedrock`, correct token usage, non-zero `cost_micro_usd` |
| G-2 | Adding a fifth provider takes ≤ 1 day for a contributor familiar with the codebase | Walk through the FR-9 plugin guide step-by-step on a stub provider (could be a feature-flagged scaffold or read-through review by `/review-sprint`); time-box check or reviewer attestation | Six-step checklist enumerates all edit sites with current `file:line` anchors; Bedrock worked example is cited at each step; validation commands runnable as documented |
| G-3 | Existing users see zero behavior change | Run `model-invoke --validate-bindings` before and after the cycle on a stock `.loa.config.yaml`; run full BATS + pytest suites | Output byte-identical for non-Bedrock-overridden configs; all existing test suites pass without modification (NFR-Compat1) |
| G-4 | Bedrock-routed Anthropic models are usable as drop-in replacements for direct Anthropic models | Override `hounfour.aliases.opus: bedrock:us.anthropic.claude-opus-4-7` in a fixture `.loa.config.yaml`; run a non-trivial Loa workflow (e.g., `/flatline-review` on a sample PR diff or a bridgebuilder review) | Workflow completes; cost ledger reflects bedrock pricing; output is shape-equivalent to direct-Anthropic completion (downstream parsers don't fork) |

**Acceptance Criteria:**

- [ ] Each goal validated with documented evidence linked from the cycle PR description
- [ ] Integration points verified end-to-end (data flows from `.loa.config.yaml` → loader → `bedrock_adapter` → live Bedrock → `CompletionResult` → cost ledger → audit log)
- [ ] No goal marked "not achieved" without explicit justification AND a follow-up issue filed
- [ ] Live integration test (Task 1.10) re-run against final tip-of-Sprint-2 commit; recurring CI smoke (Task 2.6) green on first scheduled invocation
- [ ] G-3 byte-identical-bindings check is the merge gate per PRD §Launch Criteria

### Dependencies

- Sprint 1 merged to base — all 10 tasks green in CI per Sprint 1 acceptance criteria
- Sprint 0 spike report and `bedrock-contract-v1.json` fixture remain in tree (used by Task 2.6 fixture-diff baseline)
- Maintainer's Bedrock account remains active for Task 2.E2E live validation and Task 2.6 first-scheduled-invocation confirmation
- Org secret `secrets.AWS_BEARER_TOKEN_BEDROCK_CI` provisioned ahead of Task 2.6 first cron run

### Security Considerations

- **Trust boundaries**: Recurring CI smoke runs in GitHub Actions org context; `BEDROCK_SMOKE_REQUIRE_TOKEN` enforces presence of secret on scheduled runs to prevent silent skip-on-rotation; fork-PR skip-clean preserves cycle-094 G-E2E precedent for untrusted forks
- **External dependencies**: GitHub Actions cron infrastructure; AWS Bedrock service availability; org secret rotation cadence (operator policy, NFR-Sec6 ≤ 90 days documented in runbook)
- **Sensitive data**: Smoke workflow sources `lib-security.sh redact_secrets`; sanitized fixtures (no token values, no token usage values, no IDs); structural-key diff only; auto-opened issues do not echo token content

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| AR-2 — Recurring CI smoke silently skipped (org secret absent) and drift goes undetected | Medium | Medium | `BEDROCK_SMOKE_REQUIRE_TOKEN=true` (default for scheduled) + auto-opened issue tagged `bedrock-contract-smoke-misconfigured` on missing secret per SDD §5.5; manual `workflow_dispatch` confirmation in Sprint 2 acceptance |
| AR-3 — Recurring CI smoke costs spiral (vendor pricing change, quota burst) | Low | Medium | Pre-flight cost estimate rejects run > $0.50; post-flight ledger assertion; monthly aggregate ≤ $15; weekday-only initially; weekly model rotation (single probe per week per model) |
| R-7 — Plugin guide bit-rots — Bedrock implementation drifts and guide gets stale | Medium | Low | Sprint 2 acceptance: guide reviewed against actual implementation by `/review-sprint`; CI check that asserts file:line anchors still resolve is captured as future-work follow-up (deferred per cycle scope) |
| OQ-4 — Bedrock control-plane endpoint URL pattern not as expected | Medium | Low | Sprint 0 G-S0-2 probe #1 captures the actual URL; FR-8 priority is P1 (slippage acceptable); Task 2.4 verifies pattern from Sprint 0 fixture before committing |
| AR-8 — Loa-as-submodule consumers break on `compliance_profile` defaulting one-shot stderr notice | Low | Low | Sentinel file (`${LOA_CACHE_DIR}/seen-bedrock-default`) gates the notice; downstream automation can pre-create sentinel to silence; Sprint 1 Task 1.5 already implements; Sprint 2 doc references the override path |

### Success Metrics

- FR-9 plugin guide passes `/review-sprint` fidelity check on first review iteration
- Recurring CI smoke green on first scheduled cron invocation (T+13d 06:00 UTC)
- Recurring CI smoke fixture-diff is empty on first run (no false-drift)
- All four Task 2.E2E goal validations PASS with documented evidence
- 0 BLOCKERs on cycle-PR `/flatline-review`
- Cycle-096 ships per PRD §Launch Criteria + 30-day post-launch checkpoint scheduled

---

## Risk Register (Cycle-Wide)

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R-1 | Bedrock API Keys feature still maturing; vendor edge cases surface during integration | 0, 1 | Medium | Medium | Live integration test (Task 1.10); maintainer canary (Task 0.2 probes); document known limitations at sprint close | Maintainer |
| R-2 | "Managed keys" intent turns out to be SigV4/IAM, not Bearer | 0 | Low | High | Sprint 0 G-S0-1 survey; PASS-WITH-CONSTRAINTS reframing path documented in PRD §G-S0-1 | Maintainer |
| R-3 | Bedrock Converse feature gaps vs direct Anthropic (thinking traces, tools) | 0, 1 | Medium | Medium | Per-capability `api_format` (FR-1); FR-13 explicit verification; `bedrock-contract-v1.json` fixture catches drift | Sprint 1 implementer |
| R-6 | Cross-map invariant misses an edge case from colon-bearing model IDs | 1 | Low | Medium | `tests/integration/colon-bearing-model-ids.bats` covers 4 facets; centralized parser + cross-language property test | Sprint 1 implementer |
| R-12 | Tool-schema `{ json: <schema> }` wrapping missed in future contributor edit | 1, 2 | Medium | High | `_wrap_tool_schemas()` single-edit-site discipline (AR-10); recurring CI smoke probe #2 catches structural changes | Sprint 1 implementer; long-term: recurring smoke (Task 2.6) |
| AR-1 | Centralized parser refactor breaks an existing callsite | 1 | Medium | High | Single atomic PR with tests-first; cycle-094 G-7 invariant; cross-language property test mandatory acceptance gate | Sprint 1 implementer |
| AR-2 | Recurring CI smoke silently skipped on scheduled runs | 2 | Medium | Medium | `BEDROCK_SMOKE_REQUIRE_TOKEN=true` + auto-opened issue + manual workflow_dispatch confirmation | Sprint 2 implementer |
| AR-3 | Recurring CI smoke costs spiral | 2 | Low | Medium | Pre/post-flight cost gates ≤ $0.50/run, ≤ $15/month; weekday-only; weekly rotation | Sprint 2 implementer |
| AR-9 | URL-encoding the model ID omitted at one of multiple Bedrock callsites in the future | 1 | Low | High | URL construction in **one** place (`_build_converse_url()`); unit test asserts `%3A` in encoded URL | Sprint 1 implementer |
| AR-11 | Bedrock token expires/rotates without operator awareness; silent auth failures | 1 | Medium | High | NFR-Sec11 — token age sentinel + 60/80/90-day stderr warnings + AWS-side expiry probe (best-effort) | Sprint 1 implementer |
| OQ-2 | Cycle-start Bedrock pricing for Day-1 models unknown until Sprint 1 day 1 | 1 | High (resolves via fetch) | Low | Live-fetch at Sprint 1 execution per FR-5 AC; YAML-frozen with citation comment | Sprint 1 implementer |
| OQ-5 | `ABSKY*` regex evolved between PRD lock-down and Sprint 0 | 0, 1 | Medium | Medium | Sprint 0 G-S0-2 probe #1 captures sample shape; Sprint 1 Task 1.6 updates regex from probe finding before merge | Sprint 0 + Sprint 1 implementer |

> Full Risk Register: PRD §Risks (R-1..R-13) + SDD §9 (AR-1..AR-12). Cycle-wide risks above are the ones with explicit sprint owners and active mitigations in this plan.

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| Provider count | 4 (+ bedrock) | `grep -c '^  [a-z]*:$' .claude/defaults/model-config.yaml` providers section | 1 |
| Bedrock-via-API-Key smoke test | Passes against live Bedrock account | `pytest tests/integration/test_bedrock_live.py -v` | 1 |
| Backward-compat regression | 0 deltas | `model-invoke --validate-bindings` byte-diff before/after | 1 |
| Loa workflows running on Bedrock-Anthropic | ≥ 1 verified end-to-end | Task 2.E2E G-4 validation (Flatline review with `opus`-aliased to bedrock) | 2 |
| Edit-sites per provider addition | 6 (documented + scaffold) | FR-9 plugin guide `/review-sprint` audit | 2 |
| `bedrock_adapter.py` unit-test coverage | ≥ 85% | `pytest --cov=bedrock_adapter` | 1 |
| Cycle-094 G-7 invariant | Green | `bats tests/integration/model-registry-sync.bats` | 1, 2 |
| Recurring CI smoke first invocation | Green | First scheduled cron run (T+13d 06:00 UTC) | 2 |
| Recurring CI smoke fixture-diff | Empty (no false drift) | `jq 'paths'` diff per SDD §5.5 | 2 |
| Flatline review on cycle PR | 0 BLOCKERs | `/flatline-review` invocation | 1, 2 |

---

## Dependencies Map

```
   Sprint 0 (Spike)               Sprint 1 (Functional)            Sprint 2 (Hardening + E2E)
   ─────────────────              ──────────────────────           ───────────────────────────
   • G-S0-1 user survey   ───┐    • Task 1.1 PARSER (lands  ───┐   • Task 2.1 plugin guide
   • G-S0-2 probes #1-#6      │     FIRST atomically)          │   • Task 2.2 IR runbook
   • G-S0-3 compliance        ├──▶ • Task 1.2 YAML entry       ├──▶• Task 2.3 FR-4 schema
   • G-S0-4 error taxonomy    │    • Task 1.3 bedrock_adapter   │   • Task 2.4 health probe
   • G-S0-5 region profiles   │    • Task 1.4 FR-11 errors      │   • Task 2.5 FR-10 completion
   • bedrock-contract-v1.json │    • Task 1.5 compliance        │   • Task 2.6 recurring smoke
                              │    • Task 1.6 redaction         │   • Task 2.E2E goal validation
   ↓ HARD GATE ↓              │    • Task 1.7 token age         │
   spike report PASS          │    • Task 1.8 audit/ledger      │
   + fixture committed        │    • Task 1.9 feature flag      │   ↑ HARD GATE ↑
   ──────────────────────────▶│    • Task 1.10 live test        │   Sprint 1 merged
                              │                                 │   + spike artifacts in tree
                              │    ↑ HARD GATE ↑                │   ─────────────────────────▶
                              │    All 10 tasks green           │
                              │    cycle-094 G-7 passes         │
                              │    /flatline-review 0 BLOCKERs  │
                              └─────────────────────────────────┘
```

---

## Appendix

### A. PRD Feature Mapping

| PRD Feature | Sprint | Status |
|-------------|--------|--------|
| Sprint 0 G-S0-1 (auth-modality survey) | Sprint 0 | Planned (Task 0.1) |
| Sprint 0 G-S0-2 (live API contract probes) | Sprint 0 | Planned (Task 0.2) |
| Sprint 0 G-S0-3 (compliance profile schema) | Sprint 0 | Planned (Task 0.3) |
| Sprint 0 G-S0-4 (error taxonomy enumeration) | Sprint 0 | Planned (Task 0.4) |
| Sprint 0 G-S0-5 (cross-region profiles) | Sprint 0 | Planned (Task 0.5) |
| FR-1 (provider registry entry) | Sprint 1 | Planned (Task 1.2) |
| FR-2 (Python adapter) | Sprint 1 | Planned (Task 1.3) |
| FR-3 (Bearer-token auth) | Sprint 1 | Planned (Task 1.3) |
| FR-4 (SigV4 designed-not-built) | Sprint 2 | Planned (Task 2.3) |
| FR-5 (three Day-1 models) | Sprint 1 | Planned (Task 1.2 + Task 1.10) |
| FR-6 (region configuration) | Sprint 1 | Planned (Task 1.3) |
| FR-7 (no default alias retargeting) | Sprint 1 | Planned (Task 1.9 regression test) |
| FR-8 (health probe extension) | Sprint 2 | Planned (Task 2.4) |
| FR-9 (plugin guide + IR runbook) | Sprint 2 | Planned (Task 2.1 + Task 2.2) |
| FR-10 (tests) | Sprint 1 + 2 | Planned (Task 1.10 + Task 2.5; partial in Sprint 1, completion in Sprint 2) |
| FR-11 (error taxonomy + retry classifier) | Sprint 1 | Planned (Task 1.4) |
| FR-12 (cross-region profiles Day-1) | Sprint 1 | Planned (Task 1.2 + Task 1.3) |
| FR-13 (thinking-trace parity verification) | Sprint 1 | Planned (Task 1.2 + Task 1.3, verifies vs Sprint 0 fixture) |
| NFR-R1 (compliance-aware fallback) | Sprint 1 | Planned (Task 1.5) |
| NFR-Sec2 + NFR-Sec10 (two-layer redaction) | Sprint 1 | Planned (Task 1.6) |
| NFR-Sec6 + NFR-Sec7 (key rotation + revocation) | Sprint 2 | Planned (Task 2.2 IR runbook + plugin guide) |
| NFR-Sec8 (audit/ledger event schema) | Sprint 1 | Planned (Task 1.8) |
| NFR-Sec9 (IR runbook ownership) | Sprint 2 | Planned (Task 2.2) |
| NFR-Sec11 (token lifecycle runtime controls) | Sprint 1 | Planned (Task 1.7) |
| Recurring CI smoke (SDD §5.5) | Sprint 2 | Planned (Task 2.6) |

### B. SDD Component Mapping

| SDD Component | Sprint | Status |
|---------------|--------|--------|
| §1.10 + §6.7 Bedrock feature flag | Sprint 1 | Planned (Task 1.9) |
| §3.1 + §6.2 versioned `fallback_to` mapping | Sprint 1 | Planned (Task 1.5) |
| §3 Provider registry schema (bedrock entry) | Sprint 1 | Planned (Task 1.2) |
| §5.1 Bedrock Converse API integration | Sprint 1 | Planned (Task 1.3) |
| §5.2 ListFoundationModels (health probe) | Sprint 2 | Planned (Task 2.4) |
| §5.3 cheval `complete()` contract | Sprint 1 | Planned (Task 1.3) |
| §5.4 Centralized parser contract | Sprint 1 | Planned (Task 1.1 — lands FIRST) |
| §5.5 Recurring CI smoke workflow | Sprint 2 | Planned (Task 2.6) |
| §5.6 Compliance profile defaulting (loader) | Sprint 1 | Planned (Task 1.5) |
| §6.1 Bedrock error taxonomy | Sprint 1 | Planned (Task 1.4) |
| §6.4 + §6.4.1 Two-layer secret redaction | Sprint 1 | Planned (Task 1.6) |
| §6.6 Concurrency + total-deadline + streaming-out-of-scope | Sprint 1 | Planned (Task 1.4 — `threading.Event()` + retry semantics) |
| §7 Testing strategy (unit + integration + invariant + cross-language) | Sprint 1 + 2 | Planned (Tasks 1.1, 1.10, 2.5, 2.6) |
| §9 NFR-Sec11 token lifecycle runtime controls | Sprint 1 | Planned (Task 1.7) |

### C. PRD Goal Mapping

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| G-1 | Loa works end-to-end against AWS Bedrock with API-Key auth | Sprint 0: Task 0.1 (gates auth scope), Task 0.2 (probes), Task 0.4 (error taxonomy), Task 0.5 (region profiles); Sprint 1: Task 1.2 (YAML), Task 1.3 (adapter), Task 1.4 (error classifier), Task 1.10 (live integration test); Sprint 2: Task 2.4 (health probe), Task 2.6 (recurring smoke) | Sprint 2: Task 2.E2E (G-1 row) |
| G-2 | Adding a fifth provider takes ≤ 1 day for a contributor familiar with the codebase | Sprint 1: Task 1.1 (centralized parser as foundation); Sprint 2: Task 2.1 (plugin guide), Task 2.3 (FR-4 schema seed), Task 2.6 (recurring smoke as long-term contract) | Sprint 2: Task 2.E2E (G-2 row) |
| G-3 | Existing users see zero behavior change | Sprint 0: Task 0.3 (compliance defaulting), Task 0.6 (token lifecycle); Sprint 1: Task 1.5 (compliance fallback gating), Task 1.6 (two-layer redaction), Task 1.7 (token age sentinel), Task 1.8 (audit/ledger schema), Task 1.9 (feature flag + alias-stability regression test); Sprint 2: Task 2.2 (IR runbook), Task 2.5 (residual FR-10 ACs) | Sprint 2: Task 2.E2E (G-3 row — `model-invoke --validate-bindings` byte-identical check) |
| G-4 | Bedrock-routed Anthropic models are usable as drop-in replacements for direct Anthropic models | Sprint 0: Task 0.2 (probes #2/#3/#4 confirm shape parity), Task 0.5 (region coverage); Sprint 1: Task 1.3 (adapter normalizes Bedrock response into `CompletionResult`), Task 1.10 (live test) | Sprint 2: Task 2.E2E (G-4 row — override `opus` alias and run a Loa workflow end-to-end) |

**Goal Coverage Check:**

- [x] All PRD goals have at least one contributing task (G-1: 10 tasks; G-2: 4 tasks; G-3: 9 tasks; G-4: 4 tasks)
- [x] All goals have a validation task in final sprint (Task 2.E2E covers G-1, G-2, G-3, G-4)
- [x] No orphan tasks — every Sprint 1 / Sprint 2 task is annotated with at least one goal contribution

**Per-Sprint Goal Contribution:**

- Sprint 0: G-1 (gates auth + region availability), G-3 (compliance posture + token lifecycle baseline), G-4 (probe shape parity)
- Sprint 1: G-1 (complete: end-to-end functional), G-2 (partial: parser foundation), G-3 (complete: zero-behavior-change discipline + redaction + audit + alias-stability), G-4 (complete: drop-in replacement working)
- Sprint 2: G-1 (long-term reliability via health probe + recurring smoke), G-2 (complete: plugin guide + FR-4 schema seed), G-3 (complete: residual tests + IR runbook), G-4 (E2E validation)
- Sprint 2.E2E: All four goals validated end-to-end

---

## Beads Workflow Notes

This sprint plan is intended to be **mirrored into beads** before Sprint 0 starts:

- **Epic per sprint** (3 epics): `cycle-096-sprint-0-spike`, `cycle-096-sprint-1-functional`, `cycle-096-sprint-2-hardening`
- **Tasks under each epic**: Task 0.1..0.6 (6 tasks), Task 1.1..1.10 (10 tasks), Task 2.1..2.6 + Task 2.E2E (7 tasks)
- **Blocking dependencies**:
  - Every Task 1.x is blocked by Task 0.2 + Task 0.4 + Task 0.5 + Task 0.6 (Sprint 0 hard gate per SDD §8 Phase 0 exit criterion)
  - Tasks 1.2..1.10 are blocked by Task 1.1 (parser lands FIRST)
  - Task 1.10 is blocked by Tasks 1.2..1.9 (live test runs at end of Sprint 1)
  - Every Task 2.x is blocked by Task 1.10 closure (Sprint 1 merge gate)
  - Task 2.E2E is blocked by Tasks 2.1..2.6 (final cycle gate)
- **Labels**: `sprint:0`, `sprint:1`, `sprint:2`; `epic:<epic-id>`; `cycle:cycle-096-aws-bedrock`

Run `.claude/scripts/beads-flatline-loop.sh --max-iterations 6 --threshold 5` after beads creation to refine task decomposition before `/run sprint-plan`.

---

*Generated by Sprint Planner Agent (deep-name + Claude Opus 4.7 1M) — cycle-096 — 2026-05-02*
