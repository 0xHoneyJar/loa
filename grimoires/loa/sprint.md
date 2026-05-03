# Sprint Plan — Cycle-098: Agent-Network Operation Primitives (L1-L7)

**Version:** 1.0
**Date:** 2026-05-03
**Author:** Sprint Planner Agent (deep-name + Claude Opus 4.7 1M)
**PRD Reference:** `grimoires/loa/prd.md` (v1.3 — 2 PRD-level Flatline passes + SDD pass-1 SKP-002 back-propagation)
**SDD Reference:** `grimoires/loa/sdd.md` (v1.5 — 4 SDD-level Flatline passes; pass-#4 partial integration; cheval HTTP/2 bug filed as #675)
**Cycle (proposed for ledger):** `cycle-098-agent-network`
**Source issues:** #653 (L1), #654 (L2), #655 (L3), #656 (L4), #657 (L5), #658 (L6), #659 (L7), plus #675 (cheval/HTTP-2 hardening — pre-sprint dependency)

---

## Executive Summary

Cycle-098 ships **seven framework-level primitives** (L1 through L7) that extend Loa from per-repo, per-session, per-operator operation to **operator-absent network operation** — multiple repos, multiple sessions, multiple agents, with explicit primitives for adjudication (L1), budget enforcement (L2), scheduled cycles (L3), graduated trust (L4), cross-repo status (L5), structured handoffs (L6), and descriptive identity (L7).

The plan structures the work as **7 sprints in L1→L7 ship order, with a 0.5-week buffer between Sprint 4 and Sprint 5** (Sprint 4.5, per SKP-001 CRITICAL mitigation), preceded by a single **pre-sprint bug-fix dependency** (`sprint-bug-131`, the #675 cheval/HTTP-2 hardening) that MUST ship before Sprint 1 starts so subsequent Flatline reviews can run on the new sprint docs.

Sprint 1 carries **shared cross-cutting infrastructure** used by all six subsequent sprints — the audit-envelope schema (versioned, hash-chained, Ed25519-signed, JCS-canonicalized), the `lib/audit-envelope.sh` + `audit_envelope.py` library, the `sanitize_for_session_start()` extension, the tier validator, the protected-class router, the operator-identity library, the lore directory, the `/loa status` integration pattern, the **release-signed root-of-trust pubkey**, **fd-based secret loading**, and the **JCS multi-language conformance CI gate** — alongside the L1 hitl-jury-panel skill itself. Sprint 2 un-defers the L2 reconciliation cron (per SKP-005). Sprint 7 ships the L7 SOUL.md primitive, the cycle-wide integration test suite across 5 supported tiers, **and** the §1.9.3.2 Layer 4 adversarial jailbreak corpus.

The cycle is **gated on `sprint-bug-131`** shipping first (#675 fix). All seven primitives ship `enabled: false` by default; downstream Loa-mounters inherit surfaces without behavioral change unless they configure them.

**Total Sprints:** 7 (Sprints 1–7) + 1 buffer (Sprint 4.5) + 1 pre-sprint bug-fix dependency (`sprint-bug-131`)
**Sprint Sizing:** Sprint 1 = LARGE (10 tasks); Sprint 2 = MEDIUM (6 tasks); Sprint 3 = MEDIUM (5 tasks); Sprint 4 = MEDIUM (6 tasks); Sprint 4.5 = BUFFER (4 consolidation tasks); Sprint 5 = SMALL (4 tasks); Sprint 6 = MEDIUM (5 tasks); Sprint 7 = LARGE (8 tasks incl. cycle-wide integration + jailbreak corpus + E2E)
**Estimated Completion:** Pre-sprint `sprint-bug-131` close ~T+2d (2026-05-05); Sprint 1 close ~T+12d (2026-05-13); Sprint 7 close ~T+62d (2026-07-01); cycle close ~T+64d (2026-07-03). 6–10 week range per PRD §Timeline.
**Global Sprint IDs (ledger):** `sprint-bug-131` (already assigned, global_id=131); cycle-098 sprints will be assigned global_id=132 through 138 by the ledger when each sprint registers.

### Pre-sprint dependency: `sprint-bug-131` (#675 fix) — BLOCKING

`sprint-bug-131` is a **release-blocking** bugfix sprint (cycle `cycle-bug-20260503-i675-ceb96f`, global_id=131) that hardens `cheval.py` + `model-adapter.sh.legacy` against HTTP/2 disconnects on 137KB+ Anthropic payloads. Without this fix, Flatline reviews on Sprint 1+ documents — which routinely exceed 137KB — will run at 2-of-3-model coverage (same failure mode as SDD passes #3 and #4). Sprint 1 cannot start until `sprint-bug-131` is merged, validated, and the workaround ("direct curl HTTP/1.1 with `max_tokens` ≤ 4096") is retired in favor of the production retry path. Triage and 3-failing-test plan already prepared in `grimoires/loa/a2a/bug-20260503-i675-ceb96f/`.

### Cycle constraints inherited from PRD/SDD

- **Beads workspace UNHEALTHY (#661):** ledger-only fallback per PRD R9 + cycle-098-bug-batch evidence. Cycle proceeds with `grimoires/loa/ledger.json` as the sole sprint-tracking source of truth. Beads-based task tracking is permanently deferred for this cycle.
- **R11 weekly Friday schedule-check ritual is ALREADY ACTIVE** (routine `trig_01E2ayirT9E93qCx3jcLqkLp`, first run 2026-05-08T16:00Z). Triggered immediately at Sprint 1 kickoff per SDD pass-#4 SOLO_OPUS recommendation, not at first slip.
- **Operator action prerequisites all approved 2026-05-03**: root key staged at `~/.config/loa/audit-keys/cycle098-root.priv` (mode 0600); fingerprint published in 3 channels (PR template + NOTES.md + Sprint 1 release notes); tier-enforcement decision filed (Option C: `warn`-then-`refuse` migration, `warn` ships in cycle-098, `refuse` flips in cycle-099); GitHub App now installed (enables routine push + PR comments).
- **Cycle counter advances 130 → 131 (sprint-bug-131, already done by `/bug`) → 132 (cycle-098 Sprint 1) → … → 138 (Sprint 7)**. Sprint 4.5 is a buffer week, not a numbered sprint, and consumes no global counter.
- **De-Scope Triggers active** per PRD §De-Scope Triggers: Sprint 1 >2 weeks late triggers re-baseline (split into cycle-098a + cycle-098b); any sprint >2× planned duration triggers HALT + de-scope review; envelope schema breaks 2x triggers schema mini-cycle; cross-primitive integration test failures >3 across sprints triggers Sprint 4.5 mandatory + integration-test pass gate.

---

## Sprint Overview

| Sprint | Theme | Scope | Global ID | Duration (target) | Key Deliverables | Dependencies |
|--------|-------|-------|-----------|-------------------|------------------|--------------|
| pre-sprint | `sprint-bug-131` — cheval/HTTP-2 hardening (#675) | bugfix | 131 | T..T+2d | `cheval.py` exception scoping fix; `model-adapter.sh.legacy` argv-limit fix via `--data-binary @file`; `--per-call-max-tokens` flag; 3 failing tests passing | None — runs against `main` |
| 1 | L1 hitl-jury-panel + Cross-Cutting Infrastructure | LARGE (10 tasks) | 132 | ~1.5 wk | `lib/audit-envelope.sh` + `audit_envelope.py`; `agent-network-envelope.schema.json`; `lib/jcs.sh` + JCS multi-language conformance CI gate; release-signed root pubkey; fd-based secret loading; `sanitize_for_session_start()`; tier validator; protected-class router; operator-identity lib; lore directory; `/loa status` integration; `AskUserQuestion` baseline instrumentation; L1 skill + 9 ACs | `sprint-bug-131` MERGED |
| 2 | L2 cost-budget-enforcer + Reconciliation Cron | MEDIUM (6 tasks) | 133 | ~1 wk | L2 skill; 10 ACs; UTC-windowed daily cap; per-provider counter; reconciliation cron (6h cadence default, un-deferred from FU-2 per SKP-005); state-transition table tests (5 uncertainty modes); audit-envelope verdict + reconcile event types; daily snapshot job for L1/L2 untracked logs (RPO 24h per SKP-001 §3.4.4↔§3.7) | Sprint 1 |
| 3 | L3 scheduled-cycle-template | MEDIUM (5 tasks) | 134 | ~1 wk | L3 skill; 8 ACs; 5-phase contract (reader/decider/dispatcher/awaiter/logger); cron registration via `/schedule`; idempotency on cycle_id; concurrency lock; mock-dispatcher integration tests | Sprints 1, 2 |
| 4 | L4 graduated-trust | MEDIUM (6 tasks) | 135 | ~1 wk | L4 skill; 8 ACs; hash-chained ledger; chain integrity walk + recovery (NFR-R7); auto-drop on override; cooldown enforcement; force-grant audit-logged exception; concurrent-write tests; reconstructable from git history | Sprints 1, 2 |
| **4.5** | **BUFFER WEEK** (per SKP-001 CRITICAL) | BUFFER (4 consolidation tasks) | — | 1 wk | Cross-primitive integration test consolidation (L1↔L2, L1↔L4, L3↔L2); audit-envelope schema-stability check; de-scope trigger evaluation; documentation pass on Sprints 1–4; weekly schedule-check review | Sprints 1–4 |
| 5 | L5 cross-repo-status-reader | SMALL (4 tasks) | 136 | ~1 wk | L5 skill; 7 ACs; parallel `gh api` p95 <30s for 10 repos; 429 backoff + secondary rate limit; TTL cache + stale fallback; BLOCKER extraction from NOTES.md tail; per-source error capture | Sprint 1 |
| 6 | L6 structured-handoff | MEDIUM (5 tasks) | 137 | ~1 wk | L6 skill; 8 ACs; schema validation (strict + warn); OPERATORS.md verification; atomic INDEX.md update; SessionStart-hook unread-surfacing using `sanitize_for_session_start`; content-addressable handoff_id; same-machine-only enforcement (FU-6 deferral) | Sprints 1, 4 |
| 7 | L7 soul-identity-doc + Cycle Integration Tests + Jailbreak Corpus | MEDIUM-LARGE (8 tasks incl. E2E) | 138 | ~1 wk | L7 skill; 7 ACs; SOUL.md schema + SessionStart surfacing; prescriptive-section rejection (NFR-Sec3); §1.9.3.2 **Layer 4 adversarial jailbreak corpus** (≥50 attack vectors at `tests/red-team/prompt-injection/`); cycle-wide integration test suite across 5 supported tiers; cross-primitive integration tests (L1↔L2, L1↔L4, L3↔L2); E2E goal validation; CHANGELOG; cycle archival | Sprints 1, 6 |

---

## Pre-Sprint: `sprint-bug-131` — cheval/HTTP-2 Hardening (#675)

**Scope:** Bugfix (already triaged 2026-05-03; ledger global_id=131; cycle `cycle-bug-20260503-i675-ceb96f` ACTIVE).
**Why blocking:** Flatline reviews on cycle-098 sprint docs routinely exceed 137KB; without this fix, Sprint 1 review/audit reverts to 2-of-3-model coverage (Gemini drops, Opus skeptic truncates). Workaround "direct curl HTTP/1.1 with `max_tokens` ≤ 4096" must be retired before Sprint 1 starts.
**Sprint plan:** `grimoires/loa/a2a/bug-20260503-i675-ceb96f/sprint.md` (121 lines, already authored).
**Triage:** `grimoires/loa/a2a/bug-20260503-i675-ceb96f/triage.md` (167 lines, eligibility 5/5 ACCEPT).
**State file:** `.run/bugs/20260503-i675-ceb96f/state.json` (state=TRIAGE; 4 sub-issues catalogued).

### Sub-issues (per triage)

1. **`cheval.py` UnboundLocalError hides RetriesExhaustedError** — line 389 local re-import shadows module-scope `BudgetExceededError`. Fix: delete line 389 (1 line).
2. **Anthropic 60s server-side timeout** — server-side, documentation + warning only.
3. **`model-adapter.sh.legacy` argv-limit on 137KB+ payloads** — 3 sites (lines 261, 324, 386); refactor to `--data-binary @file` using existing `--config` curl-config-file pattern at lines 311-320.
4. **`flatline-orchestrator.sh --per-call-max-tokens` knob** — net-new wiring; cheval.py line 337 already accepts `args.max_tokens`.

### Test-first plan (3 failing tests before code)

- `.claude/adapters/tests/test_cheval_exception_scoping.py` (NEW)
- `tests/integration/model-adapter-argv-safety.bats` (NEW)
- `tests/unit/flatline-orchestrator-max-tokens.bats` (NEW)

### Pre-sprint launch criteria

- [ ] All 3 failing tests written and committed BEFORE any production-code change
- [ ] All 3 tests turn green after fix
- [ ] PR #675-fix merged to `main`
- [ ] Manual Flatline cross-check at 152KB+ payload size (the size that broke pass #4) succeeds at 3-of-3-model coverage (Opus + GPT + Gemini) without the direct-curl workaround
- [ ] `/review-sprint sprint-bug-131` APPROVED
- [ ] `/audit-sprint sprint-bug-131` APPROVED
- [ ] NOTES.md updated with "cheval HTTP/2 hardening shipped"

### Handoff

Operator runs `/run sprint-bug-131` (recommended per CLAUDE.md "ALWAYS use /run for implementation") OR `/implement sprint-bug-131`. System Zone authorization is OK because cycle-098 PRD references this work via #675. **No cycle-098 sprint may begin until this PR is merged.**

---

## Sprint 1: L1 hitl-jury-panel + Cross-Cutting Infrastructure (LARGE)

**Global ID (ledger):** 132
**Duration:** ~1.5 weeks (per PRD §Timeline; LARGE per SDD §8 sprint-1 overload note + SOLO_OPUS R11 trigger)
**Dates (target):** 2026-05-06 → 2026-05-13 (after `sprint-bug-131` merges ~2026-05-05)

### Sprint Goal

Land the **shared cross-cutting infrastructure** used by all six subsequent sprints (audit-envelope library, JCS canonicalization, root-of-trust, fd-based secret loading, sanitization, tier validator, protected-class router, operator-identity, lore directory, `/loa status` pattern) **alongside** the L1 hitl-jury-panel skill (9 ACs) — so Sprints 2–7 can compose against a stable substrate from day one.

### Deliverables

**Cross-cutting (USED BY ALL SUBSEQUENT SPRINTS):**

- [ ] `agent-network-envelope.schema.json` at `.claude/data/trajectory-schemas/agent-network-envelope.schema.json` — versioned, hash-chained, Ed25519-signed, `additionalProperties: true` on payload
- [ ] `lib/audit-envelope.sh` + `loa/audit_envelope.py` — `audit_emit`, `audit_verify_chain`, `audit_recover_chain`, `audit_seal_chain` (per SDD §5.2)
- [ ] `lib/jcs.sh` (bash) + Python `rfc8785` adapter + Node `canonicalize` adapter — RFC 8785 JCS canonicalization for chain/signature inputs (NOT `jq -S -c`)
- [ ] **JCS multi-language conformance CI gate** at `tests/conformance/jcs/run.sh` — fails PR on byte-divergence between any two adapters; ≥20 nested-object test vectors covering RFC 8785 §3.2.2 + §3.2.3
- [ ] **Release-signed root pubkey** distributed via `git tag -v cycle-098-root-key-v1`; bootstrap script fetches from tagged release artifact (NOT working-tree); multi-channel fingerprint cross-check (PR description + NOTES.md + Sprint 1 release notes); `[ROOT-PUBKEY-DIVERGENCE]` BLOCKER on working-tree vs tagged-release mismatch
- [ ] **fd-based secret loading**: `audit-envelope.sh --password-fd N` OR `--password-file <path>` (mode 0600); `LOA_AUDIT_KEY_PASSWORD` env var deprecated with v1.5 warning, removed v2.0; CI redaction tests; process-inspection tests
- [ ] `lib/context-isolation-lib.sh` extension: `sanitize_for_session_start(source, content) -> sanitized_content` (delimited containment, length cap, code-fence escaping, tool-call pattern detection, no-execution semantics)
- [ ] `tier-validator.sh` (CC-10 startup check) — validates enabled-set against 5 supported tiers; mode `warn` (default per SKP-007 deferred decision) prints warning; mode `refuse` halts boot; `--allow-unsupported-tier` opt-out flag
- [ ] `.claude/data/protected-classes.yaml` + `protected-class-router.sh` — 10 default classes per PRD Appendix D; operator override procedure; versioned schema
- [ ] `operator-identity.sh` + `OPERATORS.md` schema (`grimoires/loa/operators.md`) — per-repo verifiable identity; optional `git_email` / `gpg_key_fingerprint` cross-check
- [ ] `.claude/data/lore/agent-network/` directory + 5 initial entries (`jury-panel`, `panelist`, `binding-view`, `fail-closed-cost`, `descriptive-identity`) — YAML format per Loa lore convention
- [ ] **`/loa status` integration pattern** (CC-5) — every primitive registers a status block; layout per SDD §4.4
- [ ] **Baseline `AskUserQuestion`-call instrumentation** for G-1 KPI — counts in `/run`, `/run-bridge`, `/spiral` flows; written to `.run/baseline-askuserquestion-counts.jsonl`
- [ ] **Audit-log retention compaction script template** at `.claude/scripts/audit-log-compaction.sh` — pattern from event-bus PR #215
- [ ] **Hash-chain recovery procedure** (NFR-R7) — `[CHAIN-RECOVERED]` marker on rebuild success; `[CHAIN-BROKEN]` marker + BLOCKER on rebuild failure
- [ ] **Daily snapshot job for L1/L2 untracked logs** (per SKP-001 §3.4.4↔§3.7 reconciliation) — 24h RPO (was 7d weekly); operator-runbook documents snapshot-archive restore path
- [ ] **`audit-envelope.sh` exits 78 (`EX_CONFIG`)** with structured stderr on missing key/trust-store in non-interactive contexts (no stdin fallback); `[BOOTSTRAP-PENDING]` and `[UNVERIFIED-WRITER]` markers documented in §6.1 error category table
- [ ] **`/loa audit-keys init`** emits trust-store PR template; runbook at `grimoires/loa/runbooks/audit-keys-bootstrap.md` documents secret-store → tmpfs → `LOA_AUDIT_KEY_PATH` flow for GitHub Actions, GitLab CI, CircleCI
- [ ] **Worst-case write-path latency benchmark** (SKP-004) at `tests/benchmarks/audit-envelope-worst-case.sh` — 1000 iterations, max event_size 64 KiB, full crypto + ajv schema validation, on Linux + macOS runners; result published to `grimoires/loa/a2a/benchmarks/sprint-1-write-path.json`; if measured p95 ≥50ms or p99 ≥200ms, SLO targets in §6.4 / §7.1 / IMP-005 are revised in Sprint 1 review (no silent slip)
- [ ] **Tier-enforcement default decision** logged at `grimoires/loa/cycles/cycle-098-agent-network/decisions/tier-enforcement-default.md` — Option C (`warn`-then-`refuse` migration) per operator decision 2026-05-03; cycle-098 ships `warn`; cycle-099 flips to `refuse`

**L1-specific:**

- [ ] `.claude/skills/hitl-jury-panel/SKILL.md` + `lib/jury-panel-lib.sh` + tests
- [ ] All 9 L1 ACs (FR-L1-1..FR-L1-9) implemented
- [ ] 3 default panelist persona files in `.claude/data/personas/`
- [ ] Caller-configurable embedding-fn adapter (default: no-op pass; OpenAI `text-embedding-3-small` available as opt-in adapter, NOT default-wired per Phase 5 modification)
- [ ] Selection-seed distribution audit script (FR-L1-8) — `.claude/scripts/jury-panel-distribution-audit.sh`
- [ ] Fallback matrix for 4 cases tested (timeout, API failure, tertiary unavailable, all-fail)

### Acceptance Criteria

**Cross-cutting:**

- [ ] CC-1: All 7 primitives ship `enabled: false` default in `.loa.config.yaml`
- [ ] CC-2: Every primitive writes to `.run/*.jsonl` audit log via shared envelope; envelope MUST include `schema_version` (semver), `prev_hash`, `primitive_id`, `event_type`, `ts_utc`, `payload`
- [ ] CC-3: `flock` concurrency via `_require_flock()` shim works on macOS + Linux for L1, L3, L4, L6
- [ ] CC-4: All new state in `grimoires/loa/` + `.run/`; new skills under `.claude/skills/<name>/`
- [ ] CC-5: `/loa status` surfaces L1 health/state; integration pattern documented for Sprints 2–7
- [ ] CC-6: CLAUDE.md "Process Compliance" updated with new constraint rows; lore entries written
- [ ] CC-7: New skills follow `.claude/rules/skill-invariants.md` (write-capable → not Plan/Explore agent type)
- [ ] CC-8: All audit-log writes append-only; retention defaults documented per primitive
- [ ] CC-9: All primitives degrade gracefully when disabled — no crash, no block
- [ ] CC-10: Tier validator startup check passes for Tier 0..Tier 4
- [ ] CC-11: Normative JSON Schema for envelope at `.claude/data/trajectory-schemas/agent-network-envelope.schema.json`, validated by `ajv` at write-time (with Python `jsonschema` fallback per R15)

**JCS conformance + root-of-trust + fd-based secrets (per SDD pass-#4 v1.5 ACs):**

- [ ] `lib/jcs.sh`, `rfc8785` (Python), `canonicalize` (Node) produce **byte-identical** output for the test vector corpus at `tests/conformance/jcs/test-vectors.json`; CI gate fails PR on divergence; ≥20 nested-object vectors covering RFC 8785 §3.2.2 (number canonicalization) + §3.2.3 (string escaping/Unicode)
- [ ] `audit-envelope.sh` write path uses `lib/jcs.sh`; negative test: substituting `jq -S -c` produces signature verification failure under conformance vector input
- [ ] Maintainer root pubkey distributed via release-signed git tag (`git tag -v cycle-098-root-key-v1` validates against maintainer's GitHub-registered GPG key)
- [ ] Bootstrap script fetches root pubkey from tagged release artifact, NOT directly from working-tree
- [ ] Multi-channel cross-check at install: pubkey fingerprint published in (a) cycle-098 PR description, (b) `grimoires/loa/NOTES.md` cycle-098 section, (c) Sprint 1 release notes; operator runbook instructs "verify all 3 channels match before accepting"
- [ ] Runtime trust-store verification fails closed if working-tree `.claude/data/maintainer-root-pubkey.txt` diverges from tagged-release pubkey (`[ROOT-PUBKEY-DIVERGENCE]` BLOCKER + halt)
- [ ] Threat model documented: repo compromise alone is insufficient to legitimize malicious signing keys
- [ ] `audit-envelope.sh` accepts password via `--password-fd N` OR `--password-file <path>` (mode 0600); `LOA_AUDIT_KEY_PASSWORD` deprecated v1.5, removed v2.0
- [ ] On password load, env-var memory page scrubbed (best-effort `unset` + `export -n`); fd-passed passwords stay in process memory only
- [ ] CI redaction check (`tests/security/no-env-var-leakage.bats`) greps build logs + CI artifacts for `LOA_AUDIT_KEY_PASSWORD=`; fails PR on any match
- [ ] Process inspection test: `ps aux | grep audit-envelope` does NOT show password content; `cat /proc/<pid>/environ` does NOT show env var after fd consumption
- [ ] Documentation in `grimoires/loa/runbooks/audit-keys-bootstrap.md` shows fd-passing examples for GitHub Actions, GitLab CI, CircleCI

**L1 hitl-jury-panel ACs:**

- [ ] FR-L1-1: Skill convenes ≥3 panelists in parallel
- [ ] FR-L1-2: Panelist views logged BEFORE selection (verifiable from log if skill crashes mid-cycle)
- [ ] FR-L1-3: Deterministic seed produces same binding choice for same `(decision_id, context_hash)`; `seed = sha256(decision_id || context_hash)`; `selected_index = seed % len(sorted(panelists, key=id))`
- [ ] FR-L1-4: Protected classes route to `QUEUED_PROTECTED` without panel invocation; default protected-class taxonomy from PRD Appendix D + operator-extensible via `protected_classes` config
- [ ] FR-L1-5: Fallback matrix tested for all 4 cases (timeout, API failure, tertiary unavailable, all-fail)
- [ ] FR-L1-6: Disagreement check uses caller-configurable embedding fn (default: no-op pass)
- [ ] FR-L1-7: All decisions written to `.run/panel-decisions.jsonl` with full panelist reasoning + selection seed + binding view + minority dissent
- [ ] FR-L1-8: Selection-seed distribution audit script ships (enforcement is post-ship telemetry)
- [ ] FR-L1-9: L1 cost-estimation integrates with L2 when L2 is enabled (compose-when-available stub)

**R11 + Sprint 1 overload (per SDD pass-#4 SOLO_OPUS):**

- [ ] R11 weekly Friday schedule-check ritual already active (routine `trig_01E2ayirT9E93qCx3jcLqkLp`); first run 2026-05-08T16:00Z; documented in §8 Development Phases
- [ ] Sprint 1 daily standup checklist includes AC backlog count + de-scope-trigger evaluation against PRD §De-Scope Triggers
- [ ] Sprint 1 PR template includes a "Sprint 1 AC progress" section (X of Y items complete)

### Technical Tasks

- [ ] **Task 1.1**: Author `agent-network-envelope.schema.json` (v1.0.0); Ed25519 signature field; `prev_hash` (SHA-256 of canonical-JSON of prior entry's content excluding signature); `payload: additionalProperties: true`. Land at `.claude/data/trajectory-schemas/agent-network-envelope.schema.json`. → **[G-2, G-4]**
- [ ] **Task 1.2**: Implement `lib/audit-envelope.sh` + `loa/audit_envelope.py` with `audit_emit`, `audit_verify_chain`, `audit_recover_chain`, `audit_seal_chain` per SDD §5.2; `audit_emit` exits 78 (`EX_CONFIG`) on missing key/trust-store. → **[G-2, G-4]**
- [ ] **Task 1.3**: Ship `lib/jcs.sh` (bash RFC 8785 JCS), wire Python `rfc8785` + Node `canonicalize`, build conformance corpus + CI gate at `tests/conformance/jcs/`. → **[G-2, G-4]**
- [ ] **Task 1.4**: Distribute maintainer root pubkey via release-signed git tag `cycle-098-root-key-v1`; bootstrap script reads from tag, not working tree; multi-channel fingerprint publication; `[ROOT-PUBKEY-DIVERGENCE]` runtime check. → **[G-2]**
- [ ] **Task 1.5**: Implement fd-based secret loading (`--password-fd N`, `--password-file <path>`); deprecate `LOA_AUDIT_KEY_PASSWORD`; CI redaction tests; process-inspection tests. → **[G-2]**
- [ ] **Task 1.6**: Extend `lib/context-isolation-lib.sh` with `sanitize_for_session_start()`; ship `tier-validator.sh` (CC-10); ship `protected-classes.yaml` + `protected-class-router.sh`; ship `operator-identity.sh` + `OPERATORS.md` schema. → **[G-2, G-3]**
- [ ] **Task 1.7**: Create `.claude/data/lore/agent-network/` with 5 initial YAML lore entries (`jury-panel`, `panelist`, `binding-view`, `fail-closed-cost`, `descriptive-identity`); update CLAUDE.md "Process Compliance" + new constraint rows. → **[G-3, G-4]**
- [ ] **Task 1.8**: Land `/loa status` integration pattern (CC-5); add baseline `AskUserQuestion` instrumentation in `/run`, `/run-bridge`, `/spiral`; ship `audit-envelope.sh` worst-case latency benchmark (Linux + macOS); compaction script template. → **[G-1, G-3, G-4]**
- [ ] **Task 1.9**: Implement L1 hitl-jury-panel skill at `.claude/skills/hitl-jury-panel/SKILL.md` + `lib/jury-panel-lib.sh` + 3 panelist persona files; selection seed (FR-L1-3); fallback matrix (FR-L1-5); JSONL audit log emission to `.run/panel-decisions.jsonl`. → **[G-1, G-2, G-4]**
- [ ] **Task 1.10**: BATS + pytest test suite covering all 9 L1 ACs + cross-cutting infrastructure (`audit-envelope.sh` chain walk, recovery, seal; tier-validator boundary cases; JCS conformance vectors; fd-based secret tests); macOS CI matrix passes. → **[G-2, G-3, G-4]**

### Dependencies

- **Pre-sprint:** `sprint-bug-131` (#675 fix) MERGED — without this, Flatline review of Sprint 1 doc reverts to 2-of-3-model coverage
- **Internal libs (existing, verified):** `lib/context-isolation-lib.sh`, `_require_flock()`, `lib/portable-realpath.sh`, `lib-security.sh::_SECRET_PATTERNS`, `prompt_isolation`
- **External:** `cryptography` Python pkg (Ed25519 signing/verification — pinned per R14), `ajv` Node pkg with Python `jsonschema` fallback (per R15), `rfc8785` Python pkg, `canonicalize` Node pkg
- **Operator prerequisites (already approved 2026-05-03):** root key staged at `~/.config/loa/audit-keys/cycle098-root.priv`; fingerprint `e76eec460b34eb610f6db1272d7ef364b994d51e49f13ad0886fa8b9e854c4d1` published in 3 channels; tier-enforcement decision filed (Option C)

### Security Considerations

- **Trust boundaries**: Panelist context (untrusted body input) wrapped in `prompt_isolation`; SessionStart-bound content wrapped in `<untrusted-content>` containment; all writes to audit log signed with per-writer Ed25519 key
- **External dependencies**: `cryptography` pinned in `requirements.txt`; `ajv`/`canonicalize` pinned in `package.json`; root pubkey fetched from release-signed git tag (NOT mutable working tree)
- **Sensitive data**: Audit-key passwords passed via fd or mode-0600 file (NEVER env var in v2.0+); JSONL logs run secret-scanning on write per `_SECRET_PATTERNS`; mode 0600 on all key files
- **Threat model**: Repo compromise alone insufficient — attacker would also need (a) maintainer's GPG key + GitHub registration, OR (b) all 3 fingerprint-publication channels; documented in `grimoires/loa/runbooks/audit-keys-bootstrap.md`

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Sprint 1 overload (12 cross-cutting items + L1 + 7 v1.4-added ACs in 1.5 weeks; SOLO_OPUS 780) | High | High | R11 weekly schedule-check **already active** (first run 2026-05-08); daily standup AC count + de-scope eval; PR template AC-progress section. **Re-baseline trigger: Sprint 1 >2 weeks late → split into cycle-098a (L1-L4 + CC) + cycle-098b (L5-L7).** |
| JCS multi-language conformance fails (bash vs Python vs Node byte-divergence) | Med | High | Conformance corpus is the gate; CI fails PR on divergence; canonical reference is `rfc8785` Python pkg behavior |
| Worst-case write-path latency exceeds SLO (p95 <50ms / p99 <200ms) | Med | Med | Sprint 1 review revises SLO based on measured numbers (no silent slip per SDD pass-#3 SKP-004 protocol) |
| Root-pubkey divergence between working-tree and tagged-release | Low | High | `[ROOT-PUBKEY-DIVERGENCE]` BLOCKER + halt at runtime; multi-channel fingerprint cross-check at install |
| `LOA_AUDIT_KEY_PASSWORD` env-var leakage in CI logs | Low | High | CI redaction grep test; `--password-fd` / `--password-file` mandatory by v2.0; deprecation warning v1.5 |
| Beads UNHEALTHY (#661) blocks task tracking | High (already realized) | Med | Ledger-only fallback per PRD R9; sprint progress tracked in `grimoires/loa/ledger.json` and Sprint 1 PR description |

### Success Metrics

- All 10 cross-cutting deliverables landed; all 6 L1-specific deliverables landed
- 9/9 L1 ACs PASS; 11/11 CC FRs satisfied
- JCS conformance CI gate green (bash + Python + Node byte-identical on ≥20 vectors)
- Worst-case write-path benchmark publishes p95/p99 numbers; SLO either confirmed or revised in Sprint 1 review
- Baseline `AskUserQuestion`-call counts captured for G-1 KPI baseline
- `/review-sprint sprint-1` APPROVED; `/audit-sprint sprint-1` APPROVED with COMPLETED marker
- macOS CI passes for all primitives using flock (NFR-Compat2)
- 0 regressions in existing skills (NFR-R1, NFR-Compat3)

---

## Sprint 2: L2 cost-budget-enforcer + Reconciliation Cron (MEDIUM)

**Global ID (ledger):** 133
**Duration:** ~1 week
**Dates (target):** 2026-05-13 → 2026-05-20

### Sprint Goal

Ship the L2 daily-budget enforcer with **fail-closed semantics** under all uncertainty modes, including the un-deferred reconciliation cron job (per SKP-005 CRITICAL: promoted from FU-2), tracking per-provider counters with UTC-windowed daily cap, and extending the audit-envelope schema with verdict + reconcile event types.

### Deliverables

- [ ] `.claude/skills/cost-budget-enforcer/SKILL.md` + `lib/cost-budget-enforcer-lib.sh` + tests
- [ ] All 10 ACs (FR-L2-1..FR-L2-10) implemented
- [ ] State machine: `allow` → `warn-90` → `halt-100` → `halt-uncertainty` covering 5 uncertainty modes (`billing_stale`, `counter_inconsistent`, `counter_drift`, `clock_drift`, `provider_lag`)
- [ ] UTC-windowed daily cap (`00:00:00Z` to `23:59:59Z`); clock validation on first paid call of UTC day (cross-check tolerance ±60s)
- [ ] Per-provider counter (Anthropic, OpenAI, Bedrock, etc.) + aggregate cap + optional per-provider sub-caps via `per_provider_caps`
- [ ] **Reconciliation cron** (un-deferred per SKP-005) — default 6h cadence, configurable via `reconciliation.interval_hours`; runs even when no cycle is active; compares internal counter to billing API; emits BLOCKER on drift >5%; counter NOT auto-corrected (operator decides via `force-reconcile`)
- [ ] BLOCKER on drift >5%; configurable threshold
- [ ] Audit-envelope extended with `budget.allow`, `budget.warn_90`, `budget.halt_100`, `budget.halt_uncertainty`, `budget.reconcile` event types
- [ ] **Daily snapshot job for L1/L2 untracked logs** (per SKP-001 §3.4.4↔§3.7 reconciliation, RPO 24h, was 7d) — operator runbook documents snapshot-archive restore path
- [ ] Lore entry: "fail-closed cost gate"
- [ ] Integration tests for billing API outage, counter drift, sudden cap change, clock drift, provider lag

### Acceptance Criteria

- [ ] FR-L2-1: `allow` returned when usage <90% AND data fresh (≤5min)
- [ ] FR-L2-2: `warn-90` returned when 90% ≤ usage <100% AND data fresh
- [ ] FR-L2-3: `halt-100` returned when usage ≥100% AND data fresh; cycle halts before next paid call
- [ ] FR-L2-4: `halt-uncertainty` returned when billing API stale + counter near cap (5 uncertainty modes covered)
- [ ] FR-L2-5: Reconciliation job detects drift >5% and emits BLOCKER (configurable threshold)
- [ ] FR-L2-6: Counter inconsistencies (negative, decreasing, backwards) trigger `halt-uncertainty: counter_inconsistent`
- [ ] FR-L2-7: Fail-closed semantics under all uncertainty modes — never `allow` under doubt
- [ ] FR-L2-8: Per-repo caps respected when configured
- [ ] FR-L2-9: All verdicts logged to `.run/cost-budget-events.jsonl`
- [ ] FR-L2-10: Integration tests cover billing API outage, counter drift, sudden cap change
- [ ] State-transition table tests cover all 5 transitions per SDD §6.3.2 + IMP-004
- [ ] Reconciliation cron registers via `/schedule`; deregisters cleanly on `enabled: false`
- [ ] CC-1..CC-11 satisfied for L2 specifically

### Technical Tasks

- [ ] **Task 2.1**: Implement L2 skill at `.claude/skills/cost-budget-enforcer/SKILL.md` + `lib/cost-budget-enforcer-lib.sh`; state machine with 5 uncertainty modes; UTC-window daily cap. → **[G-2]**
- [ ] **Task 2.2**: Wire L2 to `hounfour.metering` (existing `cost-report.sh`, `measure-token-budget.sh`) — extend per-call to daily aggregate; per-provider counter; aggregate cap. → **[G-2]**
- [ ] **Task 2.3**: Implement reconciliation cron job (default 6h cadence) registering via `/schedule`; idempotent re-runs; BLOCKER emission on drift >5%; `force-reconcile` operator action. → **[G-2]**
- [ ] **Task 2.4**: Extend `agent-network-envelope.schema.json` with `budget.*` event-type schemas (per-event-type schema registry pattern per IMP-001 v1.1); ajv validation on write. → **[G-2, G-4]**
- [ ] **Task 2.5**: Daily snapshot job for L1/L2 untracked logs (24h RPO); snapshot-archive restore path documented in `grimoires/loa/runbooks/audit-log-recovery.md`. → **[G-2, G-4]**
- [ ] **Task 2.6**: BATS + pytest integration tests for billing API outage, counter drift, sudden cap change, clock drift, provider lag; lore entry "fail-closed cost gate"; CLAUDE.md update. → **[G-2, G-4]**

### Dependencies

- **Sprint 1**: `audit-envelope.sh`, `agent-network-envelope.schema.json`, `lib/jcs.sh`, `tier-validator.sh`, `protected-class-router.sh` all available
- **Existing internal**: `hounfour.metering`, `/schedule` (Loa skill), `_require_flock()`
- **External (caller-supplied)**: provider billing API client (`UsageObserver` interface)

### Security Considerations

- **Trust boundaries**: `UsageObserver` is caller-supplied — must validate `usd_used` is non-negative numeric, `billing_ts` is parseable ISO-8601
- **External dependencies**: provider billing APIs over TLS; no new network listeners
- **Sensitive data**: cost data in audit log subject to `_SECRET_PATTERNS` redaction
- **Fail-closed**: never `allow` under uncertainty (NFR-Sec5) — CRITICAL invariant tested in every uncertainty mode

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Reconciliation cron deregistration leaves orphan cron entries | Low | Med | `/schedule deregister` integration; lifecycle test on disable |
| Provider billing API rate limits during reconciliation | Med | Low | 6h cadence default; configurable; reconciliation skips if billing API 429 (defers to next interval) |
| Counter and billing API agree on drift but counter is correct | Low | Med | Counter NOT auto-corrected — operator reviews via `force-reconcile`; force-reconcile audit-logged with reason |
| Clock drift across DST or NTP jumps | Low | Med | UTC-only window (no DST); ±60s tolerance; `clock_drift` halt-uncertainty mode |

### Success Metrics

- 10/10 L2 ACs PASS
- 0 budget overruns >100% in integration test suite
- Reconciliation cron drift detection: 100% accuracy (drift >5% emits BLOCKER) per G-2 KPI
- Lore entry "fail-closed cost gate" written
- `/review-sprint sprint-2` APPROVED; `/audit-sprint sprint-2` APPROVED

---

## Sprint 3: L3 scheduled-cycle-template (MEDIUM)

**Global ID (ledger):** 134
**Duration:** ~1 week
**Dates (target):** 2026-05-20 → 2026-05-27

### Sprint Goal

Ship the L3 generic skill template that, given a 5-phase contract (reader, decider, dispatcher, awaiter, logger), runs autonomous cycles via `/schedule` — composing with the existing autonomous-mode primitives (`/run`, `/run-bridge`, `/spiral`) and integrating L2 budget pre-checks when L2 is enabled.

### Deliverables

- [ ] `.claude/skills/scheduled-cycle-template/SKILL.md` + `lib/scheduled-cycle-lib.sh` + tests
- [ ] All 8 ACs (FR-L3-1..FR-L3-8) implemented
- [ ] 5-phase DispatchContract (reader, decider, dispatcher, awaiter, logger) — each phase invoked in order
- [ ] Cron registration via `/schedule` (existing Loa skill); deregistration on `enabled: false`
- [ ] Idempotency on `cycle_id` — same cycle_id no-ops if previous run completed
- [ ] Concurrency lock via `flock` on `.run/cycles/<schedule-id>.lock`
- [ ] L2 budget pre-check integration (compose-when-available) in pre-read phase
- [ ] Cycle records persist to JSONL log (`.run/cycles.jsonl`); replayable
- [ ] Mock-dispatcher integration tests covering happy path, timeout per phase, error per phase
- [ ] Lore entry: "scheduled cycle"

### Acceptance Criteria

- [ ] FR-L3-1: Skill registers cron via `/schedule` and fires on schedule
- [ ] FR-L3-2: Same `cycle_id` produces no-op if previous run completed (idempotent)
- [ ] FR-L3-3: All 5 contract phases (reader, decider, dispatcher, awaiter, logger) invoked in order
- [ ] FR-L3-4: Cycle errors captured in record without halting subsequent cycles
- [ ] FR-L3-5: Concurrency lock (`flock` on `.run/cycles/<schedule-id>.lock`) prevents overlapping invocations
- [ ] FR-L3-6: Budget check (when provided via L2 integration) runs before reader phase
- [ ] FR-L3-7: Records persist to `.run/cycles.jsonl`; replayable
- [ ] FR-L3-8: Integration tests with mock DispatchContracts cover happy path, timeout, error in each phase
- [ ] CC-1..CC-11 satisfied for L3 specifically

### Technical Tasks

- [ ] **Task 3.1**: Implement L3 skill at `.claude/skills/scheduled-cycle-template/SKILL.md` + `lib/scheduled-cycle-lib.sh`; 5-phase contract dispatch loop. → **[G-1, G-2]**
- [ ] **Task 3.2**: Wire `/schedule` registration + deregistration; idempotency check on `cycle_id`; flock-based concurrency. → **[G-1, G-2]**
- [ ] **Task 3.3**: Implement L2 budget pre-check integration in pre-read phase (compose-when-available; only active when L2 enabled per CC-9). → **[G-1, G-2]**
- [ ] **Task 3.4**: Extend audit-envelope schema with `cycle.start`, `cycle.phase`, `cycle.complete`, `cycle.error`, `cycle.lock_failed` event types. → **[G-2, G-4]**
- [ ] **Task 3.5**: BATS integration tests with mock DispatchContracts (happy path, timeout per phase, error per phase, concurrency conflict); lore entry "scheduled cycle"; CLAUDE.md update. → **[G-2, G-4]**

### Dependencies

- **Sprints 1, 2**: audit-envelope library, tier-validator, protected-class-router, L2 cost-budget-enforcer (compose-when-available)
- **Existing internal**: `/schedule` (existing Loa skill), `_require_flock()`

### Security Considerations

- **Trust boundaries**: DispatchContract phase functions are caller-supplied; phase outputs are untrusted by L3 logger (passed through `prompt_isolation` if surfaced to operator)
- **Concurrency**: `flock` on `.run/cycles/<schedule-id>.lock` prevents overlapping invocations; lock acquire fail logged as `cycle.lock_failed`
- **No secrets in cycle records**: redaction via `_SECRET_PATTERNS` on write

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Cron registration drift if `/schedule` is itself disabled | Low | Med | L3 boot validates `/schedule` availability; degrades gracefully (CC-9) |
| Cycle phase timeout cascades into next cycle invocation | Med | Med | Phase timeout captured + cycle marked failed; next cycle invocation runs fresh |
| Idempotency check spurious replay (cycle_id collision) | Low | Med | `cycle_id` includes `(schedule_id, ts_utc, content_hash)` — collision-resistant |

### Success Metrics

- 8/8 L3 ACs PASS
- All 5 phases invoked in order across happy path + 4 failure modes (timeout, error, lock conflict, budget halt)
- Lore entry "scheduled cycle" written
- `/review-sprint sprint-3` APPROVED; `/audit-sprint sprint-3` APPROVED

---

## Sprint 4: L4 graduated-trust (MEDIUM)

**Global ID (ledger):** 135
**Duration:** ~1 week
**Dates (target):** 2026-05-27 → 2026-06-03

### Sprint Goal

Ship the L4 per-(scope, capability, actor) trust ledger with operator-defined tier transitions, hash-chained for tamper detection, with auto-drop on operator override and configurable cooldown enforcement — providing the relational trust model that ratchets up by demonstrated alignment and ratchets down automatically on observed disagreement.

### Deliverables

- [ ] `.claude/skills/graduated-trust/SKILL.md` + `lib/graduated-trust-lib.sh` + tests
- [ ] All 8 ACs (FR-L4-1..FR-L4-8) implemented
- [ ] Hash-chained ledger at `.run/trust-ledger.jsonl` (TRACKED in git per SDD §3.7)
- [ ] Chain integrity walk + recovery procedure (NFR-R7) — `[CHAIN-RECOVERED]` on rebuild success, `[CHAIN-BROKEN]` + BLOCKER on rebuild failure
- [ ] Tier transitions per operator-defined `TransitionRule` array
- [ ] Auto-drop on `recordOverride(scope, capability, decision_id, reason)`; cooldown enforcement (default 7d)
- [ ] Force-grant audit-logged exception (`trust.force_grant` event type)
- [ ] Concurrent-write tests (runtime + cron + CLI per FR-L4-6)
- [ ] Reconstructable from git history (per FR-L4-7)
- [ ] Auto-raise stub: `auto-raise-eligibility-detector` ships as stub returning `eligibility_required` (FU-3 deferral per PRD)
- [ ] Lore entries: "graduated trust", "auto-drop", "cooldown"

### Acceptance Criteria

- [ ] FR-L4-1: First query for any `(scope, capability, actor)` returns `default_tier`
- [ ] FR-L4-2: Only configured transitions allowed; arbitrary jumps return error
- [ ] FR-L4-3: `recordOverride` produces auto-drop per rules; cooldown enforced
- [ ] FR-L4-4: Auto-raise-eligible entry produced when conditions met (eligibility detector is stub per FU-3); raise itself requires operator action
- [ ] FR-L4-5: Hash-chain integrity validates; tampering detectable
- [ ] FR-L4-6: Concurrency safe (flock); concurrent writes from runtime + cron + CLI tested
- [ ] FR-L4-7: Ledger reconstructable from git history if local file lost
- [ ] FR-L4-8: Force-grant in cooldown logged as exception with reason
- [ ] CC-1..CC-11 satisfied for L4 specifically; trust-ledger.jsonl is TRACKED per §3.7

### Technical Tasks

- [ ] **Task 4.1**: Implement L4 skill at `.claude/skills/graduated-trust/SKILL.md` + `lib/graduated-trust-lib.sh`; tier-transition rule engine; default tier resolution. → **[G-2]**
- [ ] **Task 4.2**: Implement hash-chained ledger writes via `audit-envelope.sh`; chain integrity walk on read; recovery from git history per NFR-R7. → **[G-2]**
- [ ] **Task 4.3**: Wire `recordOverride` for auto-drop + cooldown enforcement; `forceGrant` audit-logged exception with operator identity + reason. → **[G-2]**
- [ ] **Task 4.4**: Stub auto-raise-eligibility detector returning `eligibility_required` per FU-3; document FU-3 contract in skill README. → **[G-2]**
- [ ] **Task 4.5**: Concurrent-write tests (runtime + cron + CLI); flock-based serialization; reconstruction from git history. → **[G-2, G-4]**
- [ ] **Task 4.6**: Lore entries (graduated-trust, auto-drop, cooldown); CLAUDE.md update; integration tests with L1 protected-class router (compose-when-available). → **[G-2, G-4]**

### Dependencies

- **Sprints 1, 2**: audit-envelope library (hash-chained, signed), `protected-class-router.sh`, `operator-identity.sh` (per SDD §3.2.6 LedgerEntry references actor identity)
- **Existing internal**: `_require_flock()`

### Security Considerations

- **Trust boundaries**: tier transitions must reference `actor` identity from `OPERATORS.md`; verification via `operator-identity.sh`
- **Hash chain**: SHA-256 chain over canonical-JSON entries (RFC 8785 JCS via `lib/jcs.sh`); tampering detected on read; recovery via `git log -p` (since trust-ledger is TRACKED)
- **Force-grant abuse**: every force-grant audit-logged with operator identity + reason; auditor (P6) reviews via JSONL grep

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Hash-chain break via force-push or rebase on State Zone files | Med | Med | Operator runbook documents "no rebase on audit log files"; CI hook checks for force-push; `[CHAIN-BROKEN]` BLOCKER on unrecoverable break (R17) |
| Force-grant in cooldown abused | Low | High | Force-grant audit-logged with reason; auditor reviews; max duration default 86400s configurable (R20) |
| Concurrent writes from runtime + cron + CLI | Med | Med | flock-based serialization tested explicitly per FR-L4-6 |
| Auto-raise eligibility detector stub becomes production-quality without FU-3 work | Low | Med | Stub returns `eligibility_required`; integration tests assert stub behavior; FU-3 issue tracks production impl |

### Success Metrics

- 8/8 L4 ACs PASS
- 100% hash-chain integrity validation pass rate (G-2 KPI)
- Reconstruction from git history succeeds for ≥3 simulated chain breaks
- Lore entries written; CLAUDE.md updated
- `/review-sprint sprint-4` APPROVED; `/audit-sprint sprint-4` APPROVED

---

## Sprint 4.5: BUFFER WEEK (per SKP-001 CRITICAL)

**Global ID (ledger):** — (BUFFER, no global counter assignment)
**Duration:** ~1 week
**Dates (target):** 2026-06-03 → 2026-06-10

### Sprint Goal

Consolidate cross-primitive integration tests, validate audit-envelope schema stability across Sprints 1–4, evaluate de-scope triggers, and complete a documentation pass — providing a planned recovery point per SKP-001 CRITICAL mitigation rather than an emergency reaction.

### Deliverables

- [ ] **Cross-primitive integration test suite** at `tests/integration/cross-primitive/` covering: L1↔L2 budget pre-check, L1↔L4 protected-class trust check, L3↔L2 budget pre-read; 5 supported tier integration scenarios scaffolded (Tiers 0..4)
- [ ] **Audit-envelope schema-stability check**: schema version pinned; no breaking changes since Sprint 1 (regression test asserts `schema_version` of every stored event matches Sprint 1's v1.0.0; if breaking change is needed, semver-major bump documented + migration notes + `[SCHEMA-MIGRATION]` marker + dedicated mini-cycle proposal)
- [ ] **De-scope trigger evaluation**: review against PRD §De-Scope Triggers — any sprint >2× planned duration? schema breaks 2x? integration test failures >3? If any trigger hit, propose Sprint 5+ scope adjustment
- [ ] **Documentation pass on Sprints 1–4**: CLAUDE.md "Process Compliance" rows current; lore entries match shipped behavior; runbooks at `grimoires/loa/runbooks/` validated; baseline `AskUserQuestion`-call telemetry showing first 30d trend (G-1 KPI on track?)
- [ ] **Weekly schedule-check review**: 5 weekly check-ins (2026-05-08, 05-15, 05-22, 05-29, 06-05) collated; drift report; if drift >3 days, evaluate de-scope triggers immediately

### Acceptance Criteria

- [ ] All 3 documented cross-primitive integration scenarios PASS (L1↔L2, L1↔L4, L3↔L2)
- [ ] Schema-stability regression test passes (no breaking changes to envelope schema since Sprint 1)
- [ ] De-scope trigger evaluation memo at `grimoires/loa/cycles/cycle-098-agent-network/de-scope-eval-week5.md` — any trigger hit results in HALT + operator decision before Sprint 5 starts
- [ ] CLAUDE.md, lore entries, runbooks all match shipped behavior across Sprints 1–4
- [ ] Weekly schedule-check report at `grimoires/loa/cycles/cycle-098-agent-network/buffer-week-summary.md`
- [ ] Sprint 4.5 PR (consolidation/docs only, no new primitive code) merged to main

### Technical Tasks

- [ ] **Task 4.5.1**: Author cross-primitive integration test suite at `tests/integration/cross-primitive/` covering L1↔L2, L1↔L4, L3↔L2 (Tier 3 paths). → **[G-2, G-3, G-4]**
- [ ] **Task 4.5.2**: Audit-envelope schema-stability regression test — every Sprint 1–4 audit log entry validates against current `agent-network-envelope.schema.json`; document any necessary version bumps. → **[G-2, G-4]**
- [ ] **Task 4.5.3**: De-scope trigger evaluation; weekly-check collation; documentation pass on CLAUDE.md / lore / runbooks / `AskUserQuestion` baseline. → **[G-1, G-3, G-4]**
- [ ] **Task 4.5.4**: Sprint 4.5 PR + memo + runbook validations + R11 weekly schedule-check review. → **[G-3, G-4]**

### Dependencies

- Sprints 1, 2, 3, 4 all merged to main

### Security Considerations

- **No new code surface**: Sprint 4.5 is consolidation; security boundaries inherited from Sprints 1–4
- **Schema stability**: any breaking change to envelope schema requires explicit semver-major bump + migration documentation; bypass blocked by regression test

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| De-scope trigger hit (any sprint >2× planned) | Med | High | HALT before Sprint 5; operator decides between extending sprint vs dropping ACs flagged in deferral candidates |
| Cross-primitive integration test surfaces schema break | Med | High | If schema breaks 2x in cycle, promote schema design to dedicated mini-cycle (per PRD §De-Scope Triggers) |
| `AskUserQuestion` baseline shows G-1 KPI trend not on track | Low | Med | Document and recalibrate; G-1 is post-30d telemetry — buffer-week look is early signal only |

### Success Metrics

- All 3 cross-primitive integration scenarios PASS
- Schema-stability regression test PASS (no breaking change)
- De-scope evaluation memo published; no triggers hit OR triggers hit + operator decision logged
- Documentation pass complete (CLAUDE.md current; lore entries match; runbooks valid)
- Buffer-week summary at `grimoires/loa/cycles/cycle-098-agent-network/buffer-week-summary.md`

---

## Sprint 5: L5 cross-repo-status-reader (SMALL)

**Global ID (ledger):** 136
**Duration:** ~1 week
**Dates (target):** 2026-06-10 → 2026-06-17

### Sprint Goal

Ship the L5 skill that reads structured cross-repo state via `gh api` with TTL cache + stale fallback, achieving p95 <30s for 10 repos, with BLOCKER extraction from NOTES.md tail and per-source error capture — providing the operator-visibility primitive for Agent-Network Operator (P1).

### Deliverables

- [ ] `.claude/skills/cross-repo-status-reader/SKILL.md` + `lib/cross-repo-status-lib.sh` + tests
- [ ] All 7 ACs (FR-L5-1..FR-L5-7) implemented
- [ ] Parallel `gh api` for ≤10 repos with p95 <30s
- [ ] 429 backoff + secondary rate-limit handling
- [ ] BLOCKER extraction from NOTES.md tail per repo
- [ ] Per-source error capture (one repo's failure does not abort full read)
- [ ] TTL cache at `.run/cache/cross-repo-status/` + stale fallback up to `fallback_stale_max_seconds` (default 900s); BLOCKER raised beyond
- [ ] Lore entry: "cross-repo state"

### Acceptance Criteria

- [ ] FR-L5-1: Skill returns structured JSON for a list of repos in <30s for 10 repos (p95)
- [ ] FR-L5-2: gh API rate-limit handling: 429 backed off; secondary rate limit respected
- [ ] FR-L5-3: Stale fallback: if API unreachable, last good cache returned with `cache_age_seconds`
- [ ] FR-L5-4: BLOCKER markers extracted from NOTES.md tail
- [ ] FR-L5-5: Per-source fetch errors captured without aborting full read
- [ ] FR-L5-6: Idempotent: same call returns same shape (modulo timestamps + cache age)
- [ ] FR-L5-7: Integration tests cover: clean read, partial failure (one repo unreachable), full API outage with cache warm/cold, malformed NOTES.md
- [ ] CC-1..CC-11 satisfied for L5 specifically

### Technical Tasks

- [ ] **Task 5.1**: Implement L5 skill + `lib/cross-repo-status-lib.sh` with parallel `gh api` invocations; structured `CrossRepoState` JSON output per SDD §5.7. → **[G-3]**
- [ ] **Task 5.2**: TTL cache at `.run/cache/cross-repo-status/`; stale fallback up to `fallback_stale_max_seconds`; BLOCKER beyond; cache invalidation on disable (per SDD §1.4.2). → **[G-3]**
- [ ] **Task 5.3**: BLOCKER extraction from NOTES.md tail; per-source error capture; idempotency check on response shape. → **[G-3]**
- [ ] **Task 5.4**: BATS integration tests (clean read, partial failure, full API outage with cache warm/cold, malformed NOTES.md, 429 backoff, secondary rate limit); lore entry "cross-repo state"; CLAUDE.md update. → **[G-3, G-4]**

### Dependencies

- **Sprint 1**: audit-envelope library, lore directory, `/loa status` integration pattern
- **External**: `gh` CLI authenticated as a user with read access to listed repos (per PRD R5 + Phase 7 dependency)

### Security Considerations

- **Trust boundaries**: NOTES.md content from external repos is untrusted; BLOCKER extraction must not interpret NOTES.md content as instructions
- **External dependencies**: `gh` CLI version pinned in setup docs; API rate limits respected
- **Sensitive data**: cross-repo state may include private repo metadata — JSONL log redaction via `_SECRET_PATTERNS`; cache files mode 0600

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| `gh api` rate limit cascading across 10 parallel calls | Med | Low | Secondary rate limit + 429 backoff handled; partial-failure pattern preserves successful reads |
| NOTES.md tail malformed (non-UTF-8, truncated) | Low | Low | Per-source error capture; malformed NOTES.md returns `notes_md_parse_error` per SDD §6.3.4 |
| Cache poisoning via tampered repo state | Very Low | Med | Cache mode 0600; readlink-resolved before write; invalidated on disable |

### Success Metrics

- 7/7 L5 ACs PASS
- p95 <30s for 10-repo read in integration tests (G-3 KPI)
- 100% rejection of malformed NOTES.md inputs (NFR-Sec2 surface)
- Lore entry "cross-repo state" written
- `/review-sprint sprint-5` APPROVED; `/audit-sprint sprint-5` APPROVED

---

## Sprint 6: L6 structured-handoff (MEDIUM)

**Global ID (ledger):** 137
**Duration:** ~1 week
**Dates (target):** 2026-06-17 → 2026-06-24

### Sprint Goal

Ship the L6 skill that emits structured markdown+frontmatter handoff documents to State Zone, schema-validated, with atomic INDEX.md update and SessionStart-hook unread-surfacing using `sanitize_for_session_start` from Sprint 1 — providing the **same-machine-only** structured-context-transfer primitive between Loa sessions (multi-host deferred to FU-6 per SDD §1.7.1).

### Deliverables

- [ ] `.claude/skills/structured-handoff/SKILL.md` + `lib/structured-handoff-lib.sh` + tests
- [ ] All 8 ACs (FR-L6-1..FR-L6-8) implemented
- [ ] Schema validation (strict + warn modes) — required fields: `from`, `to`, `topic`, `body`
- [ ] OPERATORS.md verification (configurable via `verify_operators`); strict mode rejects handoff with `from`/`to` not in OPERATORS.md
- [ ] Atomic INDEX.md update via flock + temp + rename (no half-written rows per FR-L6-3)
- [ ] SessionStart hook integration for unread surfacing (uses `sanitize_for_session_start` from Sprint 1; delimited containment + length cap + no-execution semantics)
- [ ] Content-addressable `handoff_id` (SHA-256 of canonical-JSON of handoff content via `lib/jcs.sh`)
- [ ] **Same-machine-only enforcement**: machine fingerprint check on every L6 write per SDD §1.7.1 hard runtime guardrails; cross-host write attempt → `[CROSS-HOST-REFUSED]` error + BLOCKER
- [ ] Schema migration path documented
- [ ] Lore entry: "structured handoff"

### Acceptance Criteria

- [ ] FR-L6-1: Schema validation rejects malformed handoffs (missing required fields)
- [ ] FR-L6-2: File written to `handoffs_dir/{date}-{topic}.md` with correct frontmatter
- [ ] FR-L6-3: INDEX.md updated atomically (no half-written rows; flock + temp + rename)
- [ ] FR-L6-4: Same-day collision handled with numeric suffix
- [ ] FR-L6-5: SessionStart hook surfaces unread handoffs at session begin
- [ ] FR-L6-6: handoff_id is content-addressable + unique (collision detection on write)
- [ ] FR-L6-7: Reference fields preserved verbatim
- [ ] FR-L6-8: Tests cover: malformed input, collision, hook integration, schema migration
- [ ] Same-machine-only enforcement: cross-host write attempt produces `[CROSS-HOST-REFUSED]` BLOCKER (SDD §1.7.1)
- [ ] CC-1..CC-11 satisfied for L6 specifically

### Technical Tasks

- [ ] **Task 6.1**: Implement L6 skill + `lib/structured-handoff-lib.sh`; schema validation (strict + warn); content-addressable `handoff_id` via `lib/jcs.sh` + SHA-256. → **[G-3]**
- [ ] **Task 6.2**: Atomic INDEX.md update via flock + temp + rename; same-day collision handling; OPERATORS.md verification with `verify_operators` flag. → **[G-3]**
- [ ] **Task 6.3**: SessionStart hook integration — read INDEX.md, surface unread handoffs to operator using `sanitize_for_session_start` (delimited containment + length cap default 4000 chars + no-execution semantics + tool-call pattern detection). → **[G-3]**
- [ ] **Task 6.4**: Same-machine-only enforcement via machine fingerprint check (SDD §1.7.1); `[CROSS-HOST-REFUSED]` BLOCKER on mismatch; FU-6 deferral documented in skill README. → **[G-3]**
- [ ] **Task 6.5**: BATS integration tests (malformed input, collision, hook integration, schema migration, cross-host refusal); lore entry "structured handoff"; CLAUDE.md update; layered-defense Layer 3 policy rules per SDD §1.9.3.2. → **[G-3, G-4]**

### Dependencies

- **Sprint 1**: audit-envelope library, `sanitize_for_session_start`, `operator-identity.sh`, `OPERATORS.md` schema, `lib/jcs.sh`
- **Sprint 4**: graduated-trust (compose-when-available — handoff `from`/`to` reference L4 actor identity)
- **Existing internal**: SessionStart hook, `_require_flock()`

### Security Considerations

- **Trust boundaries**: handoff body is untrusted — `prompt_isolation` mandatory (NFR-Sec2); `sanitize_for_session_start` applied at SessionStart surfacing
- **External dependencies**: none new
- **Sensitive data**: handoff body subject to `_SECRET_PATTERNS` redaction on write; mode 0600 on handoff files
- **Multi-host violation**: hard refusal at runtime; cross-host write produces BLOCKER + audit-log entry

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| INDEX.md half-written under concurrent writes | Low | High | flock + temp + rename atomic update tested in stress test |
| OPERATORS.md PR-edit workflow doesn't match every team | Med | Low | `verify_operators: false` config-managed-elsewhere alternative (R16) |
| handoff_id collision (extremely rare; same content + ts + actor) | Very Low | Low | Collision detection on write; numeric suffix appended; full collision protocol per IMP-010 v1.1 |
| Operators violate same-machine assumption | Med | Med | Hard runtime guardrails (machine fingerprint); `[CROSS-HOST-REFUSED]` BLOCKER; FU-6 promotion path documented |

### Success Metrics

- 8/8 L6 ACs PASS
- 100% schema-validation rejection of malformed handoffs (G-3 KPI)
- Atomic INDEX.md update under 100-concurrent-write stress test
- Cross-host write attempt produces BLOCKER (no silent success)
- Lore entry "structured handoff" written
- `/review-sprint sprint-6` APPROVED; `/audit-sprint sprint-6` APPROVED

---

## Sprint 7: L7 soul-identity-doc + Cycle Integration Tests + Adversarial Jailbreak Corpus (LARGE)

**Global ID (ledger):** 138
**Duration:** ~1 week (LARGE — L7 + cycle-wide integration + jailbreak corpus + E2E goal validation + cycle close)
**Dates (target):** 2026-06-24 → 2026-07-01

### Sprint Goal

Ship the L7 SOUL.md primitive (descriptive identity doc complement to prescriptive CLAUDE.md), the cycle-wide integration test suite across all 5 supported tiers (Tier 0..Tier 4), the cross-primitive integration tests, **and** the §1.9.3.2 Layer 4 adversarial jailbreak corpus (≥50 attack vectors at `tests/red-team/prompt-injection/`) — closing the cycle with full safety + integration + E2E validation, and archiving cycle-098.

### Deliverables

**L7-specific:**

- [ ] `.claude/skills/soul-identity-doc/SKILL.md` + `lib/soul-identity-lib.sh` + tests
- [ ] All 7 ACs (FR-L7-1..FR-L7-7) implemented
- [ ] SOUL.md schema (frontmatter + required sections: `## What I am`, `## What I am not`, `## Voice`, `## Discipline`, `## Influences`; optional: `## Refusals`, `## Glossary`, `## Provenance`)
- [ ] SessionStart hook integration (uses `sanitize_for_session_start` from Sprint 1; default `surface_max_chars: 2000`)
- [ ] Schema validation (strict + warn modes); strict refuses load on missing required sections
- [ ] Surface truncation with `[truncated; full content at <path>]` marker
- [ ] Cache scoped to session (no re-validation per tool use)
- [ ] **Prescriptive-section rejection** (NFR-Sec3) — schema validation rejects sections that look like prescriptive rules (e.g., "Always do X", "Never do Y") with `[PRESCRIPTIVE-SECTION-REJECTED]` warning
- [ ] Lore entries: "SOUL", "descriptive identity"

**Adversarial jailbreak corpus (per SDD §1.9.3.2 Layer 4):**

- [ ] **`tests/red-team/prompt-injection/` corpus with ≥50 documented attack vectors** covering: (a) role-switch ("From now on you are..."), (b) tool-call exfiltration ("call read_file with..."), (c) credential leakage ("your API key is..."), (d) indirect prompt injection via Markdown links, (e) Unicode obfuscation, (f) encoded payloads (base64, hex), (g) multi-turn conditioning attacks (per SDD pass-#4 Opus 740 finding), (h) tool-call boundary bypass attempts (Layer 5 per SDD §1.9.3.2)
- [ ] **CI gate**: jailbreak suite runs on every PR touching `prompt_isolation`, L6, L7, or SessionStart hook (mandatory, not advisory)
- [ ] **Corpus README at `tests/red-team/prompt-injection/README.md`** documents each attack vector class, expected mitigation, and adversarial-test author attribution

**Cycle-wide:**

- [ ] **Cycle-wide integration test suite** at `tests/integration/cycle-098-tiers/` covering all 5 supported tiers (Tier 0 baseline regression-only, Tier 1 L4+L7, Tier 2 L2+L4+L6+L7, Tier 3 L1+L2+L3+L4+L6+L7, Tier 4 all 7)
- [ ] **Cross-primitive integration tests** (L1↔L2 budget pre-check, L1↔L4 protected-class trust check, L3↔L2 budget pre-read) consolidated from Sprint 4.5
- [ ] **Task 7.E2E**: End-to-end goal validation across G-1, G-2, G-3, G-4
- [ ] **CHANGELOG entry** generated via post-merge automation; `cycle-098-agent-network` PR label applied
- [ ] **Cycle archived** to `grimoires/loa/archive/2026-07-03-cycle-098-agent-network/` per Loa convention; ledger updated

### Acceptance Criteria

**L7:**

- [ ] FR-L7-1: Hook loads SOUL.md at session start
- [ ] FR-L7-2: Schema validation: missing required sections → warning (warn mode) or refused load (strict mode)
- [ ] FR-L7-3: Frontmatter validates against schema
- [ ] FR-L7-4: Surfaced content respects `surface_max_chars`; full content path always referenced
- [ ] FR-L7-5: No re-validation per tool use (cache scoped to session)
- [ ] FR-L7-6: Hook silent (no surface) when `enabled: false` or file missing
- [ ] FR-L7-7: Tests cover: valid SOUL.md, missing sections, malformed frontmatter, very long content (truncation)
- [ ] NFR-Sec3: Prescriptive sections rejected with `[PRESCRIPTIVE-SECTION-REJECTED]`

**Jailbreak corpus:**

- [ ] ≥50 attack vectors documented across 8 attack classes (role-switch, tool-call exfil, credential leak, MD link injection, Unicode obfuscation, encoded payloads, multi-turn conditioning, tool-call boundary bypass)
- [ ] CI gate runs on every PR touching `prompt_isolation`, L6, L7, SessionStart hook; PR fails on any new attack vector NOT mitigated
- [ ] Multi-turn conditioning attacks specifically tested (per SDD pass-#4 Opus 740: tool-call boundary policy with concrete `N` turn count specified — agreed `N=3` for tool-call boundary heuristic OR session-scoped provenance taint, decision logged)

**Cycle-wide:**

- [ ] All 5 supported tiers (Tier 0..Tier 4) pass integration tests
- [ ] L1↔L2, L1↔L4, L3↔L2 cross-primitive integration tests pass
- [ ] All 63 AC items + 11 CC FRs satisfied across the 7 primitives
- [ ] macOS CI passes for all primitives using flock (NFR-Compat2)
- [ ] Audit-log envelope schema stable across all 7 primitives (NFR-O1)
- [ ] `/loa status` surfaces all 7 primitives' state (NFR-O3, CC-5)

### Task 7.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1, G-2, G-3, G-4)

**Description:**
Validate that all 4 PRD goals are achieved through the complete cycle-098 implementation across all 7 primitives.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | Autonomous-pace progress without operator-presence requirement | Tier 3 integration test runs a sleep-window cycle invoking L1 jury panel for 10 routine decisions; `AskUserQuestion` baseline (Sprint 1) compared to current; protected-class queue reviewed | ≥80% of routine decisions auto-bound by jury panel; protected-class decisions queued without panel invocation; median time-to-decision <60s |
| G-2 | Fail-closed safety for cost, trust, protected-class | Integration tests run against L2 (5 uncertainty modes), L4 (hash-chain integrity + force-grant exception), L1 (protected-class router); audit log JSONL validated against envelope schema | 0 budget overruns >100%; 0 unauthorized tier escalations; 0 unaudited dispatches; 100% hash-chain integrity validation pass rate |
| G-3 | Cross-context continuity (repos, sessions, operators) | Tier 4 integration test runs L5 read on 10 mock repos; L6 handoff schema validation against malformed inputs; L7 SOUL.md surface latency measured | Cross-repo state read p95 <30s; handoff schema rejection rate 100% on malformed input; SOUL.md surface latency <500ms |
| G-4 | Audit completeness — every decision, dispatch, trust-change, handoff in JSONL | Audit log integrity check + grep-based completeness audit across all 7 primitives | 100% of in-scope events in `.run/*.jsonl`; consistent envelope schema; 0 unredacted secrets per `_SECRET_PATTERNS`; chain integrity validates |

**Acceptance Criteria:**

- [ ] Each of G-1, G-2, G-3, G-4 validated with documented evidence in `grimoires/loa/cycles/cycle-098-agent-network/e2e-validation.md`
- [ ] Integration points verified (data flows end-to-end through audit log)
- [ ] No goal marked as "not achieved" without explicit justification
- [ ] Adoption metric (G-* implicit, 90d): ≥1 downstream Loa-using project mounts at least 1 of the 7 primitives within 30 days post-cycle (telemetry baseline captured)

### Technical Tasks

- [ ] **Task 7.1**: Implement L7 skill + `lib/soul-identity-lib.sh`; SOUL.md schema (frontmatter + 5 required sections); SessionStart hook integration with `sanitize_for_session_start`. → **[G-3]**
- [ ] **Task 7.2**: Schema validation (strict + warn); prescriptive-section rejection (NFR-Sec3) with regex + structural detection; surface truncation with marker; session-scoped cache. → **[G-3]**
- [ ] **Task 7.3**: Author ≥50 adversarial jailbreak corpus entries at `tests/red-team/prompt-injection/` covering 8 attack classes; document each attack vector + expected mitigation in corpus README. → **[G-2]**
- [ ] **Task 7.4**: CI gate wiring — jailbreak suite runs on every PR touching `prompt_isolation`/L6/L7/SessionStart hook; specify `N=3` for tool-call boundary heuristic (or document session-scoped provenance taint alternative); decision logged in `cycles/cycle-098-agent-network/decisions/jailbreak-corpus-N.md`. → **[G-2]**
- [ ] **Task 7.5**: Cycle-wide integration test suite at `tests/integration/cycle-098-tiers/` covering Tier 0..Tier 4; consolidate cross-primitive tests from Sprint 4.5; macOS CI matrix. → **[G-2, G-3, G-4]**
- [ ] **Task 7.6**: Lore entries (SOUL, descriptive-identity); CLAUDE.md final update; runbooks finalized for all 7 primitives. → **[G-3, G-4]**
- [ ] **Task 7.7**: CHANGELOG generation via post-merge automation; cycle-098-agent-network PR label; cycle archive at `grimoires/loa/archive/2026-07-03-cycle-098-agent-network/`. → **[G-4]**
- [ ] **Task 7.E2E**: End-to-end goal validation (G-1, G-2, G-3, G-4) per validation table above; results published at `grimoires/loa/cycles/cycle-098-agent-network/e2e-validation.md`. → **[G-1, G-2, G-3, G-4]**

### Dependencies

- **Sprint 1**: audit-envelope library, `sanitize_for_session_start`, lore directory, JCS conformance, root-of-trust
- **Sprints 2, 3, 4, 5, 6**: L2, L3, L4, L5, L6 all merged and integration-tested
- **Existing internal**: SessionStart hook
- **Existing external**: post-merge automation pipeline (CHANGELOG generation per cycle-076 PR #536 patterns)

### Security Considerations

- **Trust boundaries**: SOUL.md content is untrusted — `sanitize_for_session_start` applied at surfacing; prescriptive-section rejection enforces descriptive-only invariant (NFR-Sec3)
- **External dependencies**: none new
- **Sensitive data**: SOUL.md content subject to `_SECRET_PATTERNS` redaction; mode 0600 on file
- **Adversarial coverage**: ≥50 attack vectors enforced via mandatory CI gate; new attacks added by Bridgebuilder reviews appended to corpus

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Sprint 7 overload (L7 + integration + jailbreak corpus + E2E + cycle close) | Med | Med | Sprint 4.5 buffer week consolidated cross-primitive tests; corpus authoring distributed across team via Bridgebuilder reviews |
| SOUL.md becomes prescriptive-rules dumping ground (defeats NFR-Sec3) | Med | Med | Strict schema validation + prescriptive-section rejection regex; documentation + bridgebuilder reviews catch drift (R6) |
| Jailbreak corpus produces flaky CI on multi-turn conditioning | Med | Med | Decision logged in `cycles/cycle-098-agent-network/decisions/jailbreak-corpus-N.md`: choose `N=3` deterministic OR session-scoped provenance taint; integration tests deterministic via mock conversation metadata |
| Cycle-wide integration test runtime exceeds CI budget | Low | Med | Tier-by-tier matrix runs in parallel; full cycle takes ~30min on macOS + Linux runners |
| Cycle archival breaks ledger schema | Low | Med | Archive uses ledger v1 schema (existing pattern); regression test runs ledger validation post-archive |

### Success Metrics

- 7/7 L7 ACs PASS; NFR-Sec3 enforced
- ≥50 jailbreak corpus entries committed; CI gate active on every PR touching prompt_isolation/L6/L7/SessionStart
- All 5 supported tiers (Tier 0..Tier 4) PASS integration tests
- All cross-primitive integration tests PASS (L1↔L2, L1↔L4, L3↔L2)
- E2E goal validation: 4/4 goals achieved with documented evidence
- macOS + Linux CI green across all 7 primitives
- CHANGELOG entry generated; cycle-098 archived; ledger updated
- `/review-sprint sprint-7` APPROVED; `/audit-sprint sprint-7` APPROVED with COMPLETED marker
- 0 critical bugs in any primitive at archival

---

## Risk Register

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R1 | Spec drift over 6-10 weeks | All | Med | Med | Each sprint locks SDD via `/architect` re-pass; post-lock changes become new work | Sprint Planner |
| R2 | Audit-log envelope schema needs to extend in later sprints | 1-7 | High | Low | `additionalProperties: true` on `payload`; bump version on breaking change; per-event-type schemas separate from envelope schema | Architecture |
| R3 | Cross-primitive integration edge cases (L1↔L2, L1↔L4, L3↔L2) | 4.5, 7 | Med | Med | Each sprint writes integration tests against earlier primitives' APIs; Sprint 4.5 consolidation; Sprint 7 cycle-wide suite | Architecture |
| R4 | macOS portability (flock, realpath, BSD utilities) | All | Low | Med | `_require_flock()` and `lib/portable-realpath.sh` from cycle-098. New tests must run on macOS CI | Implementation |
| R5 | Embedding model unavailable for L1 disagreement check | 1 | Low | Low | Caller-configurable design; default no-op. Operator's responsibility | Implementation |
| R6 | SOUL.md becomes prescriptive-rules dumping ground | 7 | Med | Med | Strict schema validation rejects prescriptive sections; documentation + bridgebuilder reviews catch drift | Architecture |
| R7 | L4 trust ledger gaming via force-grant in cooldown | 4 | Low | High | Force-grant logged as exception with reason; auditor (P6) reviews | Implementation |
| R8 | L1 decision-context hash collisions reduce panelist randomness | 1 | Very Low | Low | `decision_id` adds entropy; periodic distribution audit (FR-L1-8) | Implementation |
| R9 | Beads workspace migration broken (#661) — sprint task tracking degrades to ledger | All | High (realized) | Med | Sprint 1 verifies beads healthy or routes task lifecycle through `grimoires/loa/ledger.json` per Loa graceful-fallback. Already permanent in this cycle | Sprint Planner |
| R10 | 7 primitives is a lot; downstream Loa mounters may not enable any | All | Med | Low | Each spec ships `enabled: false` default. Document opt-in path in mount-time docs (CLAUDE.md.example). Adoption metric is post-cycle telemetry | Architecture |
| R11 | Cycle takes 6-10 weeks; review/audit iteration may stretch timeline (CRITICAL per SKP-001) | All | High | High | Sprint 4.5 buffer added; explicit de-scope triggers documented; **weekly schedule-check ritual ALREADY ACTIVE** (routine `trig_01E2ayirT9E93qCx3jcLqkLp`); first run 2026-05-08T16:00Z. Re-baseline trigger: Sprint 1 >2 weeks late | Operator |
| R12 | L1 panelist persona injection from untrusted body | 1 | Low | High | `prompt_isolation` mandatory for body input (NFR-Sec2) | Implementation |
| R13 | JSONL audit log unbounded growth | All | Med | Low | Retention policy per primitive (NFR-O4); compaction script per Loa convention (event-bus PR #215 pattern) | Implementation |
| R14 | Ed25519 signing adds dependency surface (`cryptography` Python pkg) | 1 | Low | Low | Already a transitive dep of existing Loa Python adapters; pin version in `requirements.txt` | Implementation |
| R15 | `ajv` (Node.js) required for write-time schema validation; not all Loa users have node | 1 | Low | Low | Sprint 1 also implements pure-Python schema validator fallback (`jsonschema` package); ajv preferred for performance but not mandatory | Implementation |
| R16 | OPERATORS.md PR-edit workflow may not match every team's process | 1, 6 | Med | Low | Schema validation runs at CI; alternative workflows (config-managed elsewhere) supported via `verify_operators: false` in L6 config | Architecture |
| R17 | Hash-chain recovery via git history fails on a hard rebase / force-push | 4 | Med | Med | Operator runbook documents that audit-log files MUST not be rebased; CI hook checks for force-push to State Zone files; `[CHAIN-BROKEN]` marker + BLOCKER on unrecoverable break | Implementation |
| R18 | SessionStart hook adds latency to every session start (L7 surfacing) | 7 | Low | Low | NFR-P2: <500ms latency; cache scoped to session; hook silent when disabled | Implementation |
| R19 | Tier validator may reject configs operators have working in production (1 of the 123 unsupported tiers) | 1 | Med | Low | `tier_enforcement_mode: warn` default — only prints warning, not block. `refuse` mode is operator-explicit opt-in (Option C: warn-then-refuse migration logged in cycle decisions) | Implementation |
| R20 | Time-bounded protected-class override mis-configured (duration too long) | 1 | Low | High | Audit-logged with operator identity + reason; auditor (P6) reviews; max duration default 86400s (1 day) configurable | Implementation |
| R21 | `sprint-bug-131` (#675 fix) does not ship before Sprint 1 | pre | Med | High | Triage already complete (5/5 ACCEPT); 3-failing-test plan ready; recommended `/run sprint-bug-131` immediately. Sprint 1 cannot start until merged. **HARD BLOCK** |
| R22 | Cheval HTTP/2 bug remains unfixed across cycle (Flatline reviews permanently 2-of-3 model coverage) | All | Low (after sprint-bug-131) | High | `sprint-bug-131` directly addresses root cause; if regression, escalate to dedicated mini-cycle |
| R23 | Multi-turn conditioning jailbreak attacks defeat first-N-turn boundary heuristic | 7 | Med | High | SDD pass-#4 Opus 740 finding addressed by Sprint 7 corpus task: choose `N=3` deterministic OR session-scoped provenance taint; decision logged in cycle decisions dir |
| R24 | Sprint 7 overload (L7 + cycle integration + jailbreak corpus + E2E + cycle close) | 7 | Med | Med | Sprint 4.5 buffer week consolidated cross-primitive tests in advance; jailbreak corpus authoring distributed across team via Bridgebuilder reviews |

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| L1 routine decisions in sleep window auto-bound by jury panel | ≥80% (G-1) | `.run/panel-decisions.jsonl` analysis after 30d post-L1 ship | 1, post-cycle telemetry |
| L1 median time-to-decision for routine adjudication | <60s when L1 active (G-1) | Audit log timestamp delta | 1 |
| L2 daily-cap overruns >100% | 0 (G-2) | `.run/cost-budget-events.jsonl` grep over 30d | 2, post-cycle telemetry |
| L2 reconciliation drift detection accuracy | 100% (drift >5% emits BLOCKER) (G-2) | Integration test + 30d telemetry | 2, post-cycle telemetry |
| L4 hash-chain integrity validation pass rate | 100% (G-2) | Continuous (chain walk on read) | 4, continuous |
| L5 cross-repo status read p95 latency for 10 repos | <30s (G-3) | Integration test + post-ship measurement | 5, post-cycle telemetry |
| L6 schema-validation rejection rate of malformed handoffs | 100% in strict mode (G-3) | Integration test | 6 |
| L7 SOUL.md surfacing latency at session start | <500ms (G-3) | Session-start hook telemetry | 7, continuous |
| Decisions/cycles/handoffs without audit JSONL entry | 0 (G-4) | Continuous grep audit | 1, continuous |
| Adoption: ≥1 downstream Loa-using project mounts each primitive | 7/7 within 90d | Manual operator survey + telemetry | post-cycle |
| Worst-case audit-envelope write-path p95 / p99 | <50ms p95 / <200ms p99 (or revised in Sprint 1 review) | `tests/benchmarks/audit-envelope-worst-case.sh` Linux + macOS | 1 |
| JCS multi-language conformance (bash + Python + Node byte-identical) | 100% on conformance corpus | `tests/conformance/jcs/run.sh` CI gate | 1 |
| Adversarial jailbreak corpus coverage | ≥50 attack vectors across 8 classes; 100% mitigated | `tests/red-team/prompt-injection/` CI gate | 7 |

---

## Dependencies Map

```
sprint-bug-131 (pre)
    │
    │ MERGED → Sprint 1 unblocked
    ▼
Sprint 1: L1 + Cross-Cutting Infra (LARGE)
    │
    ├──────────▶ Sprint 2: L2 + Reconciliation Cron
    │              │
    │              └──▶ Sprint 3: L3 (uses L2 budget pre-check)
    │                       │
    │                       └──▶ Sprint 4: L4 (uses Sprint 1 audit infra)
    │                                │
    │                                ▼
    │                       Sprint 4.5: BUFFER WEEK
    │                                │
    │                                ├──▶ Sprint 5: L5 (uses Sprint 1 audit infra)
    │                                │       │
    │                                │       └──▶ Sprint 6: L6 (uses Sprint 1 sanitize +
    │                                │                            Sprint 4 trust integration)
    │                                │              │
    │                                │              └──▶ Sprint 7: L7 + Cycle Integration +
    │                                │                              Jailbreak Corpus + E2E
    │                                │
    │                                └─────────────────────────▶ (parallel)
```

**Critical path**: `sprint-bug-131` → 1 → 2 → 3 → 4 → 4.5 → 5 → 6 → 7 (cycle close).
**Parallelism**: Sprints 5 and 6 may run in parallel after Sprint 4.5 IF beads were healthy; ledger-only tracking constrains to serial.
**Sprint 4.5 BUFFER**: planned recovery point; not a sprint with new primitive deliverables.

---

## Appendix

### A. PRD Feature Mapping

| PRD Feature (FR-X) | Sprint | Status |
|--------------------|--------|--------|
| CC-1..CC-11 (Cross-Cutting) | 1 (lands), 2-7 (extend) | Planned |
| FR-L1-1..FR-L1-9 | 1 | Planned |
| FR-L2-1..FR-L2-10 + reconciliation cron | 2 | Planned |
| FR-L3-1..FR-L3-8 | 3 | Planned |
| FR-L4-1..FR-L4-8 | 4 | Planned |
| FR-L5-1..FR-L5-7 | 5 | Planned |
| FR-L6-1..FR-L6-8 | 6 | Planned |
| FR-L7-1..FR-L7-7 | 7 | Planned |
| NFR-Sec1..NFR-Sec8 | 1 (lands), 2-7 (apply) | Planned |
| NFR-R1..NFR-R7 | 1, 4 (R7 chain recovery) | Planned |
| NFR-P1..NFR-P4 | 1 (benchmark), 5 (P1), 7 (P2) | Planned |
| NFR-O1..NFR-O4 | 1 (lands), 2-7 (apply) | Planned |
| Operator Identity Model | 1 | Planned |
| SessionStart Sanitization Model | 1 (lib), 6 (L6), 7 (L7) | Planned |
| Protected-Class Taxonomy (PRD Appendix D) | 1 | Planned |

### B. SDD Component Mapping

| SDD Component | Sprint | Status |
|---------------|--------|--------|
| §1.4.1 Shared Cross-Cutting Infrastructure (audit-envelope, sanitize, tier-validator, protected-class router, operator-identity) | 1 | Planned |
| §1.4.2 L1 hitl-jury-panel | 1 | Planned |
| §1.4.2 L2 cost-budget-enforcer | 2 | Planned |
| §1.4.2 L3 scheduled-cycle-template | 3 | Planned |
| §1.4.2 L4 graduated-trust | 4 | Planned |
| §1.4.2 L5 cross-repo-status-reader | 5 | Planned |
| §1.4.2 L6 structured-handoff | 6 | Planned |
| §1.4.2 L7 soul-identity-doc | 7 | Planned |
| §1.7.1 Multi-Host: Out of Scope (FU-6 deferral) | 1 (CC), 6 (L6 enforcement) | Planned |
| §1.9.3.1 Ed25519 Key Lifecycle (rotation, trust-store, revocation) | 1 | Planned |
| §1.9.3.2 Adversarial Prompt-Injection Defense (Layers 1-5) | 1 (Layers 1, 2, 5), 6 (Layer 3 L6), 7 (Layer 3 L7 + Layer 4 corpus) | Planned |
| §3.2.1 Shared Audit Envelope schema | 1 | Planned |
| §3.2.2 Per-Primitive Audit Log Layout | 1 (template), 2-7 (extend) | Planned |
| §3.2.3 Operator Identity Schema | 1 | Planned |
| §3.2.4 Protected-Class Registry Schema | 1 | Planned |
| §3.2.5 SOUL.md Schema | 7 | Planned |
| §3.2.6 L4 Trust Ledger Entry Schema | 4 | Planned |
| §3.4.4 Hash-Chain Recovery + §3.7 snapshot reconciliation | 1 (lands), 4 (L4 chain) | Planned |
| §4.4 `/loa status` Layout | 1 | Planned |
| §5.2 Audit Envelope API | 1 | Planned |
| §5.3-§5.13 Per-primitive APIs | 1-7 (per primitive) | Planned |
| §7.3 CI/CD Integration (jailbreak suite, JCS conformance, worst-case latency) | 1 (lands), 7 (final integration) | Planned |
| §8 Sprint 1 ACs (IMP-003 + SKP-004 + SKP-007 + IMP-001 + SKP-001 + SKP-002 + SOLO_OPUS) | 1 | Planned |

### C. PRD Goal Mapping

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| **G-1** | Autonomous-pace progress without operator-presence requirement | Sprint 1: Task 1.8 (baseline `AskUserQuestion` instrumentation), Task 1.9 (L1 skill); Sprint 3: Task 3.1, 3.2, 3.3 (scheduled cycle template) | Sprint 7: Task 7.E2E |
| **G-2** | Fail-closed safety for cost, trust, protected-class | Sprint 1: Tasks 1.1-1.10 (audit envelope, JCS, root-of-trust, fd-secrets, sanitize, protected-class router, L1 fail-closed); Sprint 2: Tasks 2.1-2.6 (L2 fail-closed); Sprint 4: Tasks 4.1-4.6 (L4 hash-chain + auto-drop + force-grant); Sprint 7: Task 7.3, 7.4 (jailbreak corpus + Layer 4 defense) | Sprint 7: Task 7.E2E |
| **G-3** | Cross-context continuity (repos, sessions, operators) | Sprint 1: Task 1.6 (sanitize, operator-identity), Task 1.7 (lore + CLAUDE.md), Task 1.8 (`/loa status`); Sprint 4.5: Task 4.5.3 (documentation pass); Sprint 5: Tasks 5.1-5.4 (L5 cross-repo); Sprint 6: Tasks 6.1-6.5 (L6 handoff); Sprint 7: Tasks 7.1, 7.2, 7.6 (L7 SOUL + lore) | Sprint 7: Task 7.E2E |
| **G-4** | Audit completeness — every decision, dispatch, trust-change, handoff in JSONL with consistent envelope | Sprint 1: Tasks 1.1, 1.2, 1.3, 1.7, 1.8, 1.10 (audit envelope, JCS, lore, baseline, tests); Sprint 2: Tasks 2.4, 2.5, 2.6 (envelope extension, snapshot job, integration tests); Sprint 3: Task 3.4, 3.5; Sprint 4: Tasks 4.5, 4.6; Sprint 4.5: Task 4.5.2 (schema-stability); Sprint 5: Task 5.4; Sprint 6: Task 6.5; Sprint 7: Tasks 7.5, 7.6, 7.7 (cycle integration + CHANGELOG + archive) | Sprint 7: Task 7.E2E |

**Goal Coverage Check:**

- [x] All 4 PRD goals (G-1, G-2, G-3, G-4) have ≥1 contributing task across multiple sprints
- [x] All goals have a validation task in final sprint (Sprint 7 Task 7.E2E)
- [x] No orphan tasks — every Sprint 1-7 task annotated with `→ **[G-N]**` (or multi-goal annotation)
- [x] E2E validation task included in final sprint (Task 7.E2E)
- [x] Adoption metric (G-* implicit, 90d post-cycle) tracked via post-cycle telemetry

**Per-Sprint Goal Contribution:**

- **Sprint 1**: G-1 (foundational instrumentation), G-2 (audit-envelope, root-of-trust, fd-secrets, protected-class router, L1 fail-closed), G-3 (sanitize, operator-identity, `/loa status`), G-4 (audit envelope schema, JCS conformance, lore)
- **Sprint 2**: G-2 (L2 fail-closed cost gate, reconciliation cron), G-4 (envelope extension, snapshot job)
- **Sprint 3**: G-1 (scheduled-cycle template enables autonomous cycles), G-2 (L2 budget pre-check integration)
- **Sprint 4**: G-2 (L4 graduated-trust, hash-chain integrity, force-grant audit)
- **Sprint 4.5**: G-1, G-2, G-3, G-4 (consolidation across all primitives; documentation pass; baseline AskUserQuestion telemetry review)
- **Sprint 5**: G-3 (cross-repo status read, BLOCKER extraction)
- **Sprint 6**: G-3 (structured handoff, INDEX atomic, SessionStart surfacing, OPERATORS verification)
- **Sprint 7**: All 4 goals via E2E validation; G-2 (jailbreak corpus + Layer 4 defense); G-3 (L7 SOUL); G-4 (cycle integration test suite + CHANGELOG + archive)

### D. Tier-to-Sprint Mapping (per PRD §Supported Configuration Tiers)

| Tier | Enabled primitives | Tested in Sprint | Integration test path |
|------|-------------------|------------------|------------------------|
| **Tier 0: Baseline** | None | 1, regression continuous | Regression-only (Loa behaves identically pre-cycle) |
| **Tier 1: Identity & Trust** | L4 + L7 | 4, 7 | Sprint 7 cycle-wide suite — L4 ↔ SessionStart hook, L7 ↔ SessionStart hook |
| **Tier 2: + Resource & Handoff** | L2 + L4 + L6 + L7 | 2, 4, 6, 7 | Sprint 7 cycle-wide suite — Tier 1 + L2 verdicts, L6 schema validation, L6 INDEX ↔ SessionStart |
| **Tier 3: + Adjudication & Orchestration** | L1 + L2 + L3 + L4 + L6 + L7 | 1, 2, 3, 4, 6, 7 | Sprint 4.5 cross-primitive consolidation + Sprint 7 cycle-wide suite — Tier 2 + L1 ↔ L2 budget pre-check, L1 ↔ L4 protected-class, L3 ↔ L2 budget pre-read |
| **Tier 4: Full Network** | All 7 (L1-L7) | All sprints | Sprint 7 cycle-wide suite — Tier 3 + L5 cross-repo state |

### E. Ledger Updates Required

When this sprint plan is approved, the following ledger updates are required:

1. **Add cycle-098-agent-network entry** to `grimoires/loa/ledger.json` `cycles` array:
   ```json
   {
     "id": "cycle-098-agent-network",
     "label": "Agent-Network Operation Primitives (L1-L7)",
     "status": "active",
     "created": "2026-05-03T...",
     "prd": "grimoires/loa/prd.md",
     "sdd": "grimoires/loa/sdd.md",
     "sprints": [
       {"local_id": 1, "global_id": 132, "label": "L1 hitl-jury-panel + Cross-Cutting Infrastructure", "status": "planned"},
       {"local_id": 2, "global_id": 133, "label": "L2 cost-budget-enforcer + Reconciliation Cron", "status": "planned"},
       {"local_id": 3, "global_id": 134, "label": "L3 scheduled-cycle-template", "status": "planned"},
       {"local_id": 4, "global_id": 135, "label": "L4 graduated-trust", "status": "planned"},
       {"local_id": 5, "global_id": 136, "label": "L5 cross-repo-status-reader", "status": "planned"},
       {"local_id": 6, "global_id": 137, "label": "L6 structured-handoff", "status": "planned"},
       {"local_id": 7, "global_id": 138, "label": "L7 soul-identity-doc + Cycle Integration + Jailbreak Corpus", "status": "planned"}
     ]
   }
   ```
2. **Set `active_cycle: "cycle-098-agent-network"`** in ledger root
3. **Advance `global_sprint_counter` from 131 to 138** (covers all 7 cycle-098 sprints)
4. **Sprint 4.5 is BUFFER, no global_id assigned** (consistent with PRD §Timeline + Loa convention)

### F. Beads Workspace Note

Beads workspace remains UNHEALTHY (#661 `dirty_issues.marked_at` migration bug); this cycle uses **ledger-only sprint tracking** as a permanent fallback (PRD R9 + cycle-098-bug-batch evidence). Per PRD §De-Scope Triggers row "Beads workspace remains broken throughout cycle (R9)": Sprint 1 documents permanent ledger-only fallback for this cycle; no per-sprint `br create` / `br update` calls are required. Future cycles inherit this pattern until #661 is resolved upstream.

---

*Generated by Sprint Planner Agent — 2026-05-03. Active cycle proposal: `cycle-098-agent-network` (ledger update required at approval). Pre-sprint dependency: `sprint-bug-131` (#675 fix) MUST merge before Sprint 1 starts. R11 weekly Friday schedule-check ritual already active (routine `trig_01E2ayirT9E93qCx3jcLqkLp`, first run 2026-05-08T16:00Z).*
