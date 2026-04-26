# Sprint Plan — Cycle-093: Loa Stabilization & Model-Currency Architecture

**Version:** 1.1 (post-Flatline sprint integration — 3→3A/3B split, bypass governance, parser defenses)
**Date:** 2026-04-24
**Author:** Sprint Planner Agent
**PRD Reference:** `grimoires/loa/cycles/cycle-093-stabilization/prd.md`
**SDD Reference:** `grimoires/loa/cycles/cycle-093-stabilization/sdd.md`
**Flatline Provenance:** `flatline-prd-integration.md`, `flatline-sdd-integration.md`, `flatline-sprint-integration.md`
**Cycle:** `cycle-093-stabilization`
**Ledger Entry:** `grimoires/loa/ledger.json` — global sprint IDs 114–118 (5 sprints after Flatline-driven 3→3A/3B split)

> **Output-path isolation**: This sprint plan is deliberately written to `grimoires/loa/cycles/cycle-093-stabilization/sprint.md`, NOT to `grimoires/loa/sprint.md` (which is cycle-092's live artifact in PR #603 READY_FOR_HITL). Same isolation pattern as PRD+SDD for this cycle.
>
> **Meta-sprint authorization**: All writes under `.claude/` (System Zone) are authorized by the cycle-093 PRD §6 per `.claude/rules/zone-system.md`. This is a meta-sprint on the Loa framework itself.

---

## Executive Summary

This is a **5-sprint** stabilization cycle (v1.0 plan was 4 sprints; Flatline sprint-review SKP-001 CRITICAL drove a 3→3A/3B split for schedule realism) delivering:

1. **Three Tier-1 silent-failure fixes** (#605, #607, #618) — harness adversarial wiring, bridgebuilder submodule dist, dissenter `{{DOCUMENT_CONTENT}}` hallucination filter.
2. **Keystone architectural change** — a provider-side health-probe pattern that converts model-availability from hand-maintained to probed invariant. Delivered in **two milestones** (3A: core probe + cache; 3B: resilience + CI + integration + runbook) per Flatline SKP-001 split.
3. **Model-registry currency** — re-add Gemini 3.1 Pro Preview + add GPT-5.5/5.5-Pro latent entries, all routed through the new probe.

**Inter-sprint coordination** (Flatline SKP-003 HIGH): Sprints 1, 2, 3A are independent; 3B depends on 3A; Sprint 4 depends on 3A (and nice-to-have on 3B). Canonical merge order: 1 → 2 → 3A → 3B → 4 with 6h rebase slack per dependent sprint (sprints 1/2/3A touch overlapping files so serialization reduces conflict risk).

| # | Total Sprints | Scope | Est. Wall-Clock |
|---|---|---|---|
| 1 | Harness adversarial wiring (T1.1) | MEDIUM (6 tasks) | ~1 day |
| 2 | Bridgebuilder dist + dissenter filter (T1.2 + T1.3) | MEDIUM (8 tasks split S+S) | ~1 day |
| 3A | Provider health-probe — core probe + cache (T2.2 part 1) | MEDIUM (5 tasks + 3 from Flatline) | ~1.5 days |
| 3B | Provider health-probe — resilience + CI + integration + runbook (T2.2 part 2) | MEDIUM-LARGE (8 tasks + 6 from Flatline) | ~2 days |
| 4 | Model registry currency (T2.1 + T2.3 + T3.1) + E2E | MEDIUM (7 tasks + E2E gate) | ~1 day |

**Total:** 42 tasks across 5 sprints (34 original + 8 Flatline additions: canary probe, contract-version check, rollback flag, bypass governance, bypass audit alerts, secret scanner, centralized scrubber, concurrency stress, platform matrix, rollback doc). All PRD goals G1–G6 mapped (G-6 re-scoped to "infrastructure ready" per Flatline SKP-002); all Flatline sprint-review BLOCKERS (SKP-001..005) mitigated.

---

## Sprint Overview

| Sprint | Theme | Global ID | Key Deliverables | Depends on | Serialized merge position |
|--------|-------|-----------|------------------|------------|--------------------------|
| 1 | Harness Adversarial Wiring (T1.1) | 114 | `_gate_review` + `_gate_audit` emit adversarial artifacts; `adversarial-review-gate.sh` hook enforces presence | — | 1st |
| 2 | Bridgebuilder Dist + Dissenter Filter (T1.2 + T1.3) | 115 | `dist/core/multi-model-pipeline.js` shipped; submodule smoke CI; `_precheck_dissenter_hallucination` + bats tests | — | 2nd |
| 3A | Health-Probe Core (T2.2 part 1) | 116 | `model-health-probe.sh` skeleton + 3 provider adapters (Anthropic 4xx fix) + atomic-write cache + PID sentinel + state machine + **canary validation** + **contract-version check** + **rollback flag** | — | 3rd |
| 3B | Health-Probe Resilience + CI + Integration + Runbook (T2.2 part 2) | 117 | Resilience layer (**dual-approval label, 24h bypass TTL, mandatory audit alerts**) + 2 CI workflows (PR + daily cron) + contract-test fixtures + **centralized secret scrubber** + **post-job secret scanner** + **concurrency stress tests** + **platform matrix** + runtime integration + runbook with **rollback + key rotation** sections | 3A | 4th |
| 4 | Model Registry Currency (T2.1 + T2.3 + T3.1) + E2E Gate | 118 | Gemini 3.1 Pro Preview via generator; GPT-5.5/5.5-Pro latent via `probe_required: true`; gpt-5.2 audit; **G-6 re-scoped to "infrastructure ready"** | 3A (required); 3B (nice-to-have) | 5th |

**Canonical merge order** (Flatline SKP-003 mitigation — sprints touch overlapping files so serialize): sprint-1 → sprint-2 → sprint-3A → sprint-3B → sprint-4. Budget 6h rebase slack per dependent sprint.

**Parallelism** (where safe): sprint-1 and sprint-2 touch different sets of scripts (`spiral-harness.sh` vs `bridgebuilder-review/` + `adversarial-review.sh`) — can develop in parallel branches but merge in the order above. Sprint 3A is independent of 1 and 2 as written but shares `model-adapter.sh` touchpoints at integration time — defer integration work in 3A until after 1+2 land if branches diverge.

---

## Sprint 1: Harness Adversarial Wiring (T1.1 — Close #605)

**Scope:** MEDIUM (6 tasks)
**Global Sprint ID:** 114
**Duration:** 1 day
**Tier:** 1 (silent-failure fix)

### Sprint Goal

Wire `spiral-harness.sh::_gate_review` and `_gate_audit` so that `flatline_protocol.code_review.enabled: true` and `security_audit.enabled: true` produce `adversarial-review.json` / `adversarial-audit.json` in the evidence directory, satisfying the existing `adversarial-review-gate.sh` PostToolUse hook (v1.94.0).

### Deliverables

- [ ] `_gate_review` emits `adversarial-review.json` to `.run/cycles/$CYCLE_NAME/evidence/` when `flatline_protocol.code_review.enabled: true`
- [ ] `_gate_audit` emits `adversarial-audit.json` to same directory when `flatline_protocol.security_audit.enabled: true`
- [ ] `_invoke_claude` accepts `--skill <name>` + `--evidence-dir <path>` per SDD §6.6 contract (if preferred path chosen), OR the fallback `adversarial-review.sh` wrap landed (per SDD §1.4 C6)
- [ ] `adversarial-review-gate.sh` PostToolUse hook compatibility confirmed on the chosen path
- [ ] Live validation: `/spiraling` harness-dispatched cycle with both flags on produces both artifacts; operator does NOT see silent skip

### Acceptance Criteria

- [ ] **G1 satisfied**: harness-dispatched cycle with `flatline_protocol.code_review.enabled: true` produces `adversarial-review.json` in evidence dir, verified on a live test cycle *(PRD §3 G1)*
- [ ] Integration test `harness-gate-adversarial-artifact.bats` (SDD §7.2 T1.1) green on both `review` and `audit` gate invocations
- [ ] Unit test `spiral-harness-gate-review-wiring.bats` green; asserts skill/fallback dispatch path activates when config flag true
- [ ] Flag-off path regression: config flags `false` → no adversarial artifact emitted AND existing flow still passes (no regression)
- [ ] `adversarial-review-gate.sh` hook correctly BLOCKS gate PASS when flag-on run is missing artifact (structural enforcement verified)
- [ ] Evidence directory structure matches SDD §6.6 path convention (`.run/cycles/$CYCLE_NAME/evidence/`)

### Technical Tasks

- [ ] **Task 1.1**: Investigate feasibility of `--skill` dispatch through `_invoke_claude` per SDD §6.6 (Q1 open question); decide preferred vs fallback path, document decision in NOTES.md → **[G-1]**
- [ ] **Task 1.2**: Extend `_invoke_claude` signature to accept `--skill <skill-name>` and `--evidence-dir <path>` per SDD §6.6 contract (stdout schema + exit-code semantics, IMP-001 resolution) — OR skip if fallback chosen → **[G-1]**
- [ ] **Task 1.3**: Rewrite `_gate_review` in `.claude/scripts/spiral-harness.sh:550` — preferred path invokes `reviewing-code` skill with `--evidence-dir`, fallback path wraps existing `_invoke_claude` with post-hoc `adversarial-review.sh` call gated on `flatline_protocol.code_review.enabled` (SDD §6.6) → **[G-1]**
- [ ] **Task 1.4**: Rewrite `_gate_audit` in `.claude/scripts/spiral-harness.sh:568` — same dual-path approach using `auditing-security` skill / `adversarial-review.sh --mode audit` → **[G-1]**
- [ ] **Task 1.5**: Verify `adversarial-review-gate.sh` PostToolUse hook (v1.94.0) correctly observes artifacts on chosen path — no hook change expected; if skill-dispatch timing differs from script-dispatch timing, adjust hook glob or add explicit artifact-path hint → **[G-1]**
- [ ] **Task 1.6**: Add bats tests per SDD §7.2 T1.1: unit `spiral-harness-gate-review-wiring.bats`, integration `harness-gate-adversarial-artifact.bats`. Live test: run `/spiraling` with a small synthetic task, capture evidence dir contents, assert both JSONs present → **[G-1]**

### Dependencies

- **None for work to begin.**
- **Coordinated merge**: PR #603 (cycle-092) touches `spiral-harness.sh` observability. If #603 merges before Sprint 1 lands, rebase expected to be mechanical (distinct scope: cycle-092 = observability seams, cycle-093 = gate wiring) — SDD §9 R12.

### Security Considerations

- **Trust boundaries**: `_invoke_claude` stdout is redacted through `_redact_secrets` (§1.9 regex) before gate sees it. Preferred-path skill invocation inherits same redaction.
- **External dependencies**: None new. Uses existing `claude -p` CLI + existing `adversarial-review.sh`.
- **Sensitive data**: API keys flow through `curl --config` pattern in `adversarial-review.sh` (unchanged). No new secret-handling surface.

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| `--skill` dispatch through `_invoke_claude` ergonomically awkward (Q1, SDD §9 R3) | Medium | Low | Fallback path specified at SDD §1.4 C6 and §6.6 — wrap existing `_invoke_claude` with post-hoc `adversarial-review.sh`, producing same artifact names |
| `adversarial-review-gate.sh` hook timing incompatible with skill-invoked path (SDD §9 R14) | Medium | Low | Sprint task 1.5 verifies explicitly; adjust hook glob or add artifact-path hint if needed |
| Cycle-092 PR #603 rebase conflict on `spiral-harness.sh` | Medium | Low | Branch from fresh `main` after #603 merges; distinct scope |
| `adversarial-review.sh` fixed output path (Q3) blocks fallback path | Low | Low | Sprint task 1.2 verifies; add `--output PATH` arg to `adversarial-review.sh` if needed (minor patch) |

### Success Metrics

- `adversarial-review.json` present in `.run/cycles/*/evidence/` on 100% of harness-dispatched cycles with `flatline_protocol.code_review.enabled: true`
- 0 silent-skip observations across 5 live test cycles
- `harness-gate-adversarial-artifact.bats` green in CI

---

## Sprint 2: Bridgebuilder Dist + Dissenter Filter (T1.2 + T1.3 — Close #607, #618)

**Scope:** MEDIUM (8 tasks total — split as S (3 tasks T1.2) + S (5 tasks T1.3))
**Global Sprint ID:** 115
**Duration:** 1 day
**Tier:** 1 (silent-failure fixes)

### Sprint Goal

(1) Restore `dist/core/multi-model-pipeline.js` to the shipped `bridgebuilder-review` bundle so submodule consumers can invoke the skill end-to-end. (2) Add a deterministic bidirectional pre-check filter to `adversarial-review.sh` that downgrades dissenter findings containing `{{DOCUMENT_CONTENT}}`-family tokens absent from the diff.

### Deliverables

- [ ] `dist/core/multi-model-pipeline.js` present in the bridgebuilder bundle (alongside the other 11 `dist/core/*.js` files)
- [ ] CI workflow `.github/workflows/bridgebuilder-submodule-smoke.yml` emits `{ reviewed, skipped, errors }` JSON summary via submodule-consumer fixture
- [ ] Fixture repo at `.claude/tests/fixtures/submodule-consumer/` that reproduces the consumer path
- [ ] `_precheck_dissenter_hallucination` function in `adversarial-review.sh` with `_normalize_tokens` + `_contains_doc_content_token` helpers (per SDD §3.7)
- [ ] 10 bats test cases passing per SDD §7.2 T1.3 (TC1–TC10)
- [ ] G3 metric proven: 20 synthetic adversarial runs with `&&`, `&`, `2>&1` diff contexts produce 0 BLOCKING hallucinations

### Acceptance Criteria

- [ ] **G2 satisfied**: `bridgebuilder-review` skill runs end-to-end from submodule consumer; `.loa/.claude/skills/bridgebuilder-review/resources/entry.sh --dry-run` exits 0 and emits `{ reviewed, skipped, errors }` JSON *(PRD §3 G2)*
- [ ] **G3 satisfied**: zero BLOCKING hallucinations on synthetic diff containing `&&`, `&`, `2>&1` across 20 adversarial review runs — pre-check filter verified *(PRD §3 G3)*
- [ ] `bridgebuilder-submodule-smoke.yml` green on both same-repo and fork PR paths (fork uses submodule-allow protocol flag)
- [ ] All 10 bats test cases pass (TC1 canonical, TC2 lowercase, TC3 spaced, TC4 escaped, TC5 bare, TC6 mixed, TC7 legitimate diff-present, TC8 comment-only diff-present, TC9 no false-positive, TC10 20-run G3 verification)
- [ ] Downgraded findings retain evidence trail: `severity: ADVISORY`, `category: MODEL_ARTEFACT_SUSPECTED`, description prefix `[downgraded: ...]`
- [ ] No false-positive on legitimate `{{DOCUMENT_CONTENT}}` tokens in templates/docs (TC7)

### Technical Tasks

**Track T1.2 — Bridgebuilder dist (3 tasks):**

- [ ] **Task 2.1**: Root-cause investigation: inspect `.claude/skills/bridgebuilder-review/resources/tsconfig.json` `exclude` globs AND `.claude/skills/bridgebuilder-review/package.json` `files`/`prepack` filter to identify which is culling `dist/core/multi-model-pipeline.js`. Document root cause in NOTES.md → **[G-2]**
- [ ] **Task 2.2**: Apply fix to the identified filter (typically one-line change to `exclude` glob or `files` array). Add smoke assertion `node dist/main.js --help` exits 0 to existing CI pathway → **[G-2]**
- [ ] **Task 2.3**: Create `.claude/tests/fixtures/submodule-consumer/` (gitmodules template, `entry.sh` invocation script, `expected-output.json`) AND `.github/workflows/bridgebuilder-submodule-smoke.yml` per SDD §5.3.3. Workflow: init consumer repo in `/tmp`, add this repo as submodule (use `protocol.file.allow=always` for local test), invoke `.loa/.claude/skills/bridgebuilder-review/resources/entry.sh --dry-run`, assert exit 0 AND `jq -e '.reviewed != null and .skipped != null and .errors != null'` → **[G-2]**

**Track T1.3 — Dissenter filter (5 tasks):**

- [ ] **Task 2.4**: Implement `_normalize_tokens` helper in `.claude/scripts/adversarial-review.sh` per SDD §3.7 sed pipeline. Handles: escaped (`\{\{...\}\}`), spaced (single + multi), lowercase, TitleCase, bare. Regex: `\{\{[[:space:]]*([Dd][Oo][Cc][Uu][Mm][Ee][Nn][Tt]_[Cc][Oo][Nn][Tt][Ee][Nn][Tt])[[:space:]]*\}\}` → canonicalized form → **[G-3]**
- [ ] **Task 2.5**: Implement `_contains_doc_content_token` helper — pipes through `_normalize_tokens` then `grep -qE '\{\{DOCUMENT_CONTENT\}\}|\bDOCUMENT_CONTENT\b'` → **[G-3]**
- [ ] **Task 2.6**: Implement `_precheck_dissenter_hallucination` per SDD §5.4 pseudocode. Input: diff text + findings JSON. Bidirectional 4-quadrant matching table (PRD §5 T1.3 / SDD §5.4): (diff-has-token, finding-has-token) → {no-op, downgrade, no-op, no-op}. Downgrade sets `severity: ADVISORY`, `category: MODEL_ARTEFACT_SUSPECTED`, prefixes description with `[downgraded: dissenter-output contained {{DOCUMENT_CONTENT}} token that is absent from the diff]` → **[G-3]**
- [ ] **Task 2.7**: Call `_precheck_dissenter_hallucination` from `adversarial-review.sh` after finding parse and before finding emission (integration point per SDD §1.4 C7) → **[G-3]**
- [ ] **Task 2.8**: Write 10 bats test cases per SDD §7.2 T1.3 table in `.claude/tests/unit/adversarial-review-dissenter-filter.bats`. TC10 is the G3 metric verification: 20-run harness against synthetic `&&` / `&` / `2>&1` diff → 0 BLOCKING → **[G-3]**

### Dependencies

- **None.** T1.2 and T1.3 are independent single-file changes that can run in parallel within the sprint.

### Security Considerations

- **Trust boundaries (T1.2)**: Submodule fixture executes in CI's isolated `/tmp` dir. Submodule protocol `protocol.file.allow=always` scoped to test job only — not global git config change.
- **Trust boundaries (T1.3)**: Dissenter output is untrusted model text. Filter treats it as data, not executable. `jq --arg` + `jq --argjson` per `MEMORY.md` DX patterns — no shell-injection surface.
- **External dependencies**: None new.
- **Sensitive data**: None — T1.3 operates on review findings post-redaction; T1.2 fixture does not touch API keys.

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Bridgebuilder build pipeline has multiple filter layers (tsconfig + package.json + build script) — fix in wrong one re-breaks | Medium | Low | Task 2.1 documents root cause in NOTES.md; Task 2.2 verifies via `ls dist/core/*.js \| wc -l` count match to `src/core/*.ts` count |
| Fork PR fixture can't add local submodule (requires `protocol.file.allow=always`) | Low | Low | Workflow scopes the git-config flag to the test job only (not CI-wide) |
| Dissenter filter normalization regex mis-handles a variant not in the table (Flatline IMP-003) | Low-Med | Medium | Bidirectional + 6-variant normalization per SDD §3.7; TC10 20-run validation is the safety net |
| `gpt-5.3-codex` exhibits same `{{DOCUMENT_CONTENT}}` hallucination pattern as `gpt-5.2` | Low-Med | Medium | T1.3 pre-check is model-agnostic safety net; T3.1 (Sprint 4) adds operator advisory for migrators |
| Filter downgrades a legitimate concern (false-positive) | Low | Medium | TC7 (diff contains token → no-op) + TC8 (comment-only → no-op) gate against this; `ADVISORY` severity preserves visibility |

### Success Metrics

- `dist/core/*.js` count matches `src/core/*.ts` count (structural invariant)
- `bridgebuilder-submodule-smoke.yml` green on 5 consecutive same-repo PRs
- 0 BLOCKING hallucinations across 20 synthetic adversarial runs (TC10 verifies G3)
- Bats tests green for all 10 TCs

---

## Sprint 3A: Health-Probe Core (T2.2 part 1)

**Scope:** MEDIUM (5 original tasks + 3 from Flatline sprint review = 8 total)
**Global Sprint ID:** 116
**Duration:** 1.5 days (1 day + 30–50% slack per Flatline SKP-001 CRITICAL recommendation)
**Tier:** 2 (architectural spike — core)

### Sprint Goal

Ship the probe foundation: `.claude/scripts/model-health-probe.sh` with CLI contract, three per-provider probe adapters (OpenAI/Google/Anthropic with SKP-001 ambiguous-4xx fix), atomic-write cache, PID sentinel, state machine, and three Flatline-sprint-review-driven additions for parser robustness (canary validation, contract-version check, `LOA_PROBE_LEGACY_BEHAVIOR=1` emergency fallback — SKP-002 CRITICAL mitigation).

3A ships a probe that correctly classifies models but is not yet wired into CI or runtime — that's 3B's job. Exit criteria: probe script can be invoked manually and produces correct `ProbeResult`s for all three providers against live APIs.

### Deliverables (3A)

- [ ] `.claude/scripts/model-health-probe.sh` — new orchestrator script with full CLI contract per SDD §5.2
- [ ] `.run/model-health-cache.json` schema v1.0 with `schema_version`, `generated_at`, `entries{}`, `provider_circuit_state{}` per SDD §3.1
- [ ] Three per-provider probe adapters: `openai_probe` (pagination), `google_probe` (listing + generateContent), `anthropic_probe` (**rejects ambiguous 4xx** — SKP-001 core fix)
- [ ] State machine: `AVAILABLE | UNAVAILABLE | UNKNOWN` per SDD §3.2 with transitions matching HTTP signal taxonomy
- [ ] Atomic-write cache (temp + fsync + `mv`) under flock per SDD §3.6 Pattern 1; reader retry-on-parse-failure Pattern 2
- [ ] PID sentinel for background-probe dedup per SDD §3.6 Pattern 3
- [ ] **Canary validation (Flatline sprint-review SKP-002)** — non-blocking smoke probe against live providers before 3B's strict CI gate engages; runs as optional `--canary` flag on script
- [ ] **Contract-version check (Flatline sprint-review SKP-002)** — response-schema version check on each provider response; unknown shape → UNKNOWN bias (safety default)
- [ ] **`LOA_PROBE_LEGACY_BEHAVIOR=1` emergency fallback (Flatline sprint-review SKP-002)** — env var flips probe to "all AVAILABLE" (pre-cycle-093 hand-allowlist behavior) for operator unblock if probe infra fundamentally breaks

### Acceptance Criteria (3A)

- [ ] **SKP-001 closed**: Anthropic probe rejects ambiguous 4xx (400 without `model`-field reference → UNKNOWN, not AVAILABLE); regression bats test `model-health-probe-anthropic.bats` with mock "400 without model-field" → UNKNOWN
- [ ] **Flatline sprint-review SKP-002 CRITICAL closed**: `--canary` flag emits non-blocking smoke probe result (does NOT fail gate); contract-version check causes unknown response shape to bias UNKNOWN; `LOA_PROBE_LEGACY_BEHAVIOR=1` reverts probe to AVAILABLE-by-default
- [ ] State-machine unit tests pass: every `(current_state, signal) → next_state` transition from SDD §3.2 covered
- [ ] Atomic write + reader retry + PID sentinel patterns verified with bats tests (full concurrency stress in 3B)
- [ ] Probe budgets enforced **as HARD stops** (Flatline sprint-review IMP-006): 120s total invocation → exit 5; 30s per-call → retry-then-UNKNOWN; max 10 probes/run → exit 5; ≤$0.05 cost cap → exit 5. All emit telemetry before exit.
- [ ] Error taxonomy distinguishes 429/5xx (UNKNOWN) from hard-404 (UNAVAILABLE) per SDD §3.2
- [ ] Script runs manually against live providers with valid API keys and returns correct classifications for at least 3 known-AVAILABLE models, 1 known-UNAVAILABLE (synthetic `gpt-nonexistent-99`), 1 transient-simulated (rate-limit timeout)

### Technical Tasks (3A)

- [ ] **Task 3A.1**: Create `.claude/scripts/model-health-probe.sh` skeleton with CLI parser implementing SDD §5.2 contract (`--once`, `--dry-run`, `--invalidate`, `--provider`, `--model`, `--cache-path`, `--output`, `--fail-on`, `--quiet`, `--help`, `--version`) + **new `--canary` flag**. Exit codes per SDD §6.1 (0/1/2/3/5/64). **Probe budgets enforced as HARD stops** (Flatline IMP-006) — exit 5 on budget/timeout exceeded with telemetry → **[G-5]**
- [ ] **Task 3A.2**: Implement three per-provider probe adapters per SDD §3.3 with SKP-004 schema-tolerant parsing. **OpenAI**: `GET /v1/models`, pagination, auth 401/403 → UNKNOWN. **Google**: `GET /v1beta/models` + `generateContent` fallback, NOT_FOUND regex `^models/[^ ]+ is not found for API version`. **Anthropic**: `POST /v1/messages` with `max_tokens:1`; **reject ambiguous 4xx** (core SKP-001 fix per SDD §3.3 pseudocode). **Contract-version check (Flatline sprint-review SKP-002)** — verify response schema fields; unknown shape → UNKNOWN bias with `schema_mismatch` trajectory event → **[G-5]**
- [ ] **Task 3A.3**: Implement cache schema v1.0 per SDD §3.1; write `_cache_atomic_write` (SDD §3.6 Pattern 1 — temp-file + fsync + `mv` under flock); write `_cache_read` (Pattern 2 — lock-free with retry-on-parse-failure, 1 retry, 50ms backoff); `_require_flock` shim with macOS guidance → **[G-5]**
- [ ] **Task 3A.4**: Implement PID sentinel `_spawn_bg_probe_if_none_running` per SDD §3.6 Pattern 3 — `.run/model-health-probe.<provider>.pid`, `kill -0 $pid` check, trap-based cleanup on exit → **[G-5]**
- [ ] **Task 3A.5**: Implement state machine + error taxonomy per SDD §3.2 + §3.3. Explicit UNKNOWN state; all transitions covered by unit tests (`model-health-probe-state-machine.bats`); schema-tolerant parser biases to UNKNOWN on unexpected shape (SKP-004 defense) → **[G-5]**
- [ ] **Task 3A.canary** *(new, Flatline sprint-review SKP-002 CRITICAL)*: Implement `--canary` mode that probes live providers in non-blocking mode; emits telemetry but does NOT fail CI or return non-zero exit. Used as smoke test before 3B's strict gates turn on. Runs opportunistically as dev-sanity check. Test: `--canary` returns exit 0 even with 1 model UNAVAILABLE → **[G-5]**
- [ ] **Task 3A.rollback_flag** *(new, Flatline sprint-review SKP-002 CRITICAL)*: Implement `LOA_PROBE_LEGACY_BEHAVIOR=1` env-var emergency fallback — probe short-circuits to `state: AVAILABLE, confidence: legacy_bypass, reason: "LOA_PROBE_BYPASS_LEGACY_BEHAVIOR env var set"`. Audit-log entry mandatory. Bats test verifies flag forces AVAILABLE classification regardless of provider response → **[G-5]**
- [ ] **Task 3A.hardstop_tests** *(new, Flatline sprint-review IMP-006)*: Bats test suite for hard-stop budget semantics — exceed max_probes_per_run → exit 5; exceed cost cap → exit 5; exceed invocation timeout → exit 5. Each case emits telemetry entry to `.run/trajectory/<date>.jsonl` before exit → **[G-5]**

### Dependencies (3A)

- **None to begin.** This is the keystone architectural spike; independent of sprints 1 & 2 at code-level.
- **Blocks sprint 3B** — resilience and CI work requires a probe that correctly classifies.
- **Blocks sprint 4** — registry validation requires probe operational.

### Security Considerations (3A)

- **Trust boundaries**: Provider API responses are untrusted; schema-tolerant parser biases to UNKNOWN on unexpected shape (SKP-004). Contract-version check as additional guard (Flatline SKP-002).
- **External dependencies**: OpenAI `/v1/models`, Google `/v1beta/models`, Anthropic `/v1/messages`. No new SDKs; pure `curl` per SDD §2.2.
- **Sensitive data**: Three API keys (`OPENAI_API_KEY`, `GOOGLE_API_KEY`, `ANTHROPIC_API_KEY`). `curl --config` tempfile (`chmod 600`, `mktemp`) pattern. Full secret-scanning regression test is 3B (Task 3B.centralized_scrubber).
- **Legacy-behavior flag safety**: `LOA_PROBE_LEGACY_BEHAVIOR=1` is a security-relevant opt-out. Audit-log entry MANDATORY. CI step warns on commits that set this in env files.

### Risks & Mitigation (3A)

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **R1 (SKP-001)**: Probe correctness false pos/neg across providers | Medium | **CRITICAL** | State machine explicit UNKNOWN; provider rules per §3.3; Anthropic rejects ambiguous 4xx; contract-version check biases to UNKNOWN on shape mismatch |
| **Flatline SKP-002 CRITICAL**: Parser brittleness → false AVAILABLE/UNAVAILABLE | Low-Med | **CRITICAL** | Canary validation task 3A.canary; contract-version check task 3A.2; `LOA_PROBE_LEGACY_BEHAVIOR=1` emergency fallback task 3A.rollback_flag |
| **R9**: Cache concurrent-write corruption / torn reads | Medium | **CRITICAL** | Atomic write + flock; reader retry; schema versioning with auto-rebuild |
| **R18**: Background probe proliferation under concurrent harness | Medium | High | PID sentinel dedup per-provider; `kill -0 $pid` check before spawn |
| **R20**: Provider API schema drift | Low-Med | Medium | Contract-version check + schema-tolerant parser bias to UNKNOWN |
| **R16**: `flock` unavailable on macOS dev | Low | Low | `_require_flock()` shim with `brew install util-linux` guidance |
| **R24 (new)**: Parser rollback flag becomes operator crutch | Low | Medium | Audit-log mandatory; CI warning on commits that set `LOA_PROBE_LEGACY_BEHAVIOR`; runbook section explicit about emergency-only use |

### Success Metrics (3A)

- Script runs manually end-to-end against live providers (any operator with valid keys) and produces correct 3-state classification for 5+ test models
- State-machine unit test coverage: 100% of transitions
- Atomic-write / reader-retry / PID-sentinel bats tests green
- `--canary` flag returns exit 0 even with UNAVAILABLE findings (non-blocking)
- `LOA_PROBE_LEGACY_BEHAVIOR=1` forces AVAILABLE classification regardless of provider response (bats test + audit-log entry verified)

---

## Sprint 3B: Health-Probe Resilience + CI + Integration + Runbook (T2.2 part 2)

**Scope:** MEDIUM-LARGE (8 original tasks + 6 from Flatline sprint review = 14 total)
**Global Sprint ID:** 117
**Duration:** 2 days (1.5 days + 30–50% slack per Flatline SKP-001 CRITICAL recommendation)
**Tier:** 2 (architectural spike — resilience + integration)

### Sprint Goal

Ship the probe's production surface: resilience layer with governed bypass mechanisms (Flatline SKP-003 CRITICAL mitigation — dual-approval, 24h TTL, audit alerts), two CI workflows (PR-scoped + daily cron), contract-test fixtures, secrets discipline with centralized scrubber + post-job secret scanner (Flatline SKP-005 HIGH mitigation), concurrency stress tests with macOS/Linux platform matrix (Flatline SKP-004 HIGH mitigation), runtime integration in `model-adapter.sh`, and incident runbook (IMP-007 + Flatline IMP-001 rollback section). Close all remaining Flatline SKP BLOCKERS from PRD/SDD/sprint review.

### Deliverables (3B)

- [ ] Resilience layer: feature flag `model_health_probe.enabled`, `degraded_ok`, circuit breaker (5 failures → provider-wide UNKNOWN), `max_stale_hours: 72` fail-closed cutoff (SKP-003)
- [ ] **Governed bypass mechanisms (Flatline sprint-review SKP-003 CRITICAL)**:
  - `override-probe-outage` PR label with **dual-approval CI check** (requires CODEOWNER + framework maintainer)
  - `LOA_PROBE_BYPASS=1` env var with **24h TTL** (expires automatically) + **mandatory reason string**
  - **Mandatory audit alerts** to `.run/audit.jsonl` + optional webhook on every bypass/override
- [ ] `.github/workflows/model-health-probe.yml` — PR-scoped with path+dependency-graph triggers, fork-safe listing-only mode, label dual-approval gate
- [ ] `.github/workflows/model-health-drift-daily.yml` — cron on main, opens auto-issue with `model-health-drift` label on UNAVAILABLE
- [ ] Contract-test fixtures at `.claude/tests/fixtures/provider-responses/{openai,google,anthropic}/{available,unavailable,transient}.json` (SKP-004 drift defense)
- [ ] Runtime integration in `.claude/scripts/model-adapter.sh` — cache-hit 0ms path, background re-probe via PID sentinel dedup (from 3A), synchronous recheck on provider error
- [ ] Incident runbook `.claude/docs/runbooks/model-health-probe-incident.md` per SDD §D (IMP-007) with **new rollback section (Flatline IMP-001)** + **key rotation playbook (Flatline SKP-005)**
- [ ] **Centralized `_redact_secrets` function (Flatline sprint-review SKP-005)** — single source for redaction, all log paths route through it
- [ ] **Post-job secret scanner (Flatline sprint-review SKP-005)** — `gitleaks` or equivalent CI step; fails build if secret detected in job output
- [ ] **Concurrency stress tests (Flatline sprint-review SKP-004)** — `.claude/tests/integration/concurrency/` with N=10 parallel reads+writes + stale-PID cleanup verification + lock timeout handling
- [ ] **Platform matrix (Flatline sprint-review SKP-004)** — CI runs concurrency tests on macOS + Linux runners
- [ ] SKP-005 regression test: `.claude/tests/unit/model-health-probe-secrets.bats` — asserts no secrets match `sk-|AIza|ghp_|-----BEGIN` in probe stdout/stderr

### Acceptance Criteria (3B)

- [ ] **G5 satisfied**: CI gate fails with actionable message when any configured model returns NOT_FOUND from its provider; newly-available models added to `.loa.config.yaml` auto-probe on config-load with 24h TTL *(PRD §3 G5)*
- [ ] **SKP-003 closed**: `max_stale_hours: 72` fail-closes serving-stale beyond cutoff; `alert_on_stale_hours: 24` emits operator alert to `.run/audit.jsonl`; scheduled daily probe on main opens drift issue
- [ ] **SKP-004 closed**: feature flag `model_health_probe.enabled: false` disables probe entirely; `degraded_ok: true` + cache corrupt proceeds with warn; circuit breaker opens after 5 consecutive failures per provider with 300s reset
- [ ] **SKP-005 closed**: `curl --config <tempfile>` + `chmod 600` + `mktemp` pattern; `set +x` around secret ops; **centralized** `_redact_secrets` with regex `sk-|AIza|ghp_|-----BEGIN` applied to all logged output; secret-scanning bats test green; **post-job secret scanner** green; NO `upload-artifact` of probe payloads
- [ ] **Flatline sprint-review SKP-003 CRITICAL closed (bypass governance)**: `override-probe-outage` label enforced via CI check requiring CODEOWNER + framework-maintainer approval; `LOA_PROBE_BYPASS` expires at 24h with automatic probe re-engagement; every bypass emits mandatory audit entry with reason
- [ ] **Flatline sprint-review SKP-004 HIGH closed (concurrency fragility)**: N=10 parallel stress tests green on both macOS and Linux runners; stale-PID (>10min) auto-cleanup verified; 5s lock timeout + graceful fallback verified
- [ ] **Flatline sprint-review SKP-005 HIGH closed (layered defense)**: centralized scrubber refactor complete; post-job secret scanner green on test-case with known-embedded secret; key rotation playbook present in runbook
- [ ] Fork PR listing-only mode: missing secrets → UNKNOWN warn (do NOT fail); `override-probe-outage` label bypasses gate only with dual-approval met
- [ ] Runbook table-top exercise completed during Sprint 3B review (mocked outage walked through against fixture) **including new rollback + key rotation sections**

### Technical Tasks (3B)

- [ ] **Task 3B.1**: Implement resilience layer per SDD §4.1 — feature flag check; `degraded_ok` behavior; circuit breaker (5 consecutive failures → provider-wide UNKNOWN, 300s reset, stored in cache's `provider_circuit_state`) → **[G-5]**
- [ ] **Task 3B.2**: Implement staleness cutoff per SDD §3.5 — `max_stale_hours: 72` fail-closed cutoff; `alert_on_stale_hours: 24` alert to `.run/audit.jsonl`; retry/backoff with jitter (1s, 2s, 4s, 8s, 16s; 3 attempts max) per SDD §6.4 → **[G-5]**
- [ ] **Task 3B.bypass_governance** *(new, Flatline sprint-review SKP-003 CRITICAL)*: Implement `LOA_PROBE_BYPASS` with 24h TTL (track set-time in audit log; re-engage probe after TTL); mandatory `LOA_PROBE_BYPASS_REASON` env var (non-empty check on use); `override-probe-outage` PR label requires CI check validating TWO approvers (CODEOWNER + framework maintainer) via `gh api /repos/.../pulls/<pr>/reviews`. Bats + integration tests verify TTL expiry and dual-approval gate → **[G-5]**
- [ ] **Task 3B.bypass_audit** *(new, Flatline sprint-review SKP-003 CRITICAL)*: Every bypass/override emits structured audit entry to `.run/audit.jsonl` with fields `{timestamp, event_type, actor, pr_number, reason, expires_at}`. Optional webhook post configured via `.loa.config.yaml` `model_health_probe.alert_webhook_url`. Bats tests verify audit entry shape and webhook invocation (mocked) → **[G-5]**
- [ ] **Task 3B.3**: Create `.github/workflows/model-health-probe.yml` — PR-scoped with path filters per SDD §5.3.1; fork-vs-same-repo mode detection; `override-probe-outage` label handling with audit-log + dual-approval check; post findings as PR comment (redacted, no raw payloads); NO `upload-artifact` of probe responses → **[G-5]**
- [ ] **Task 3B.4**: Create `.github/workflows/model-health-drift-daily.yml` — cron `0 14 * * *` on main; opens auto-issue with `model-health-drift` label on `UNAVAILABLE` finding; SHA-pinned actions per `MEMORY.md` security patterns → **[G-5]**
- [ ] **Task 3B.5**: Create contract-test fixtures `.claude/tests/fixtures/provider-responses/{openai,google,anthropic}/{available,unavailable,transient}.json` (minimum 3 per provider per SDD §3.3 SKP-004). Bats tests in `model-health-probe-{openai,google,anthropic}.bats` assert parser behavior against each fixture → **[G-5]**
- [ ] **Task 3B.centralized_scrubber** *(new, Flatline sprint-review SKP-005)*: Refactor secret redaction to single `_redact_secrets` function sourced from `.claude/scripts/lib/secret-redaction.sh` (or add to existing compat-lib.sh per `MEMORY.md`). All probe log paths route through it. Structured-logging allowlist: only pre-approved fields (model_id, state, latency_ms, http_status) are emitted; arbitrary payloads never logged → **[G-5]**
- [ ] **Task 3B.secret_scanner** *(new, Flatline sprint-review SKP-005)*: Post-job CI step runs `gitleaks` (SHA-pinned) or equivalent over job output; fails build if secret pattern detected. Runs on both `model-health-probe.yml` and `model-health-drift-daily.yml` workflows. Test case: PR deliberately logs a mock-but-real-shaped key pattern → scanner catches it → build fails. (Remove test case before merge.) → **[G-5]**
- [ ] **Task 3B.6 (subsumes SDD §1.9 secrets)**: Implement secrets discipline per SDD §1.9 using centralized scrubber from 3B.centralized_scrubber — `curl --config <tempfile>` with `mktemp` + `chmod 600`; `set +x` around curl invocations; fail-path redaction on 401 before logging. Regression test `.claude/tests/unit/model-health-probe-secrets.bats` (SKP-005) → **[G-5]**
- [ ] **Task 3B.concurrency_stress** *(new, Flatline sprint-review SKP-004 HIGH)*: Create `.claude/tests/integration/concurrency/model-health-probe-stress.bats` — N=10 parallel script invocations; assert no cache corruption (readers observe either old or new state, never torn JSON); no probe-storm (only 1 background probe per provider at any time via PID sentinel); lock timeout triggers graceful fallback (log warn, skip cache update). Stale-PID cleanup: PID sentinel older than 10min auto-deleted on next probe invocation → **[G-5]**
- [ ] **Task 3B.platform_matrix** *(new, Flatline sprint-review SKP-004 HIGH)*: CI matrix runs concurrency stress tests on `ubuntu-latest` + `macos-latest` runners. macOS runner installs `util-linux` via `brew install util-linux` for flock. Matrix failure on either platform fails merge → **[G-5]**
- [ ] **Task 3B.7**: Runtime integration in `.claude/scripts/model-adapter.sh` per SDD §5.1 row 4–5 — cache read (lock-free w/ retry, Pattern 2); background re-probe spawn on stale (Pattern 3); synchronous recheck on first provider error; fail-fast with actionable message on UNAVAILABLE citing cache `reason` + invalidate hint (per SDD §6.2) → **[G-5]**
- [ ] **Task 3B.runbook** *(expanded, IMP-007 + Flatline IMP-001 + SKP-005)*: Create incident runbook `.claude/docs/runbooks/model-health-probe-incident.md` per SDD §D — diagnosis steps, short-term unblock (label + env var), cache operations, audit-log query, post-incident review requirement (24h root-cause follow-up), provider-specific escalation paths. **New sections**: (a) **Rollback path** (Flatline IMP-001) — trigger criteria + verification steps for rolling probe back to pre-cycle-093 behavior; (b) **Key rotation playbook** (Flatline SKP-005) — steps for revoking + reissuing keys if leak detected; (c) **Bypass governance** — canonical decision tree for when to use label vs env var vs degraded_ok. Table-top exercise during Sprint 3B review → **[G-5]**

### Dependencies (3B)

- **Requires Sprint 3A complete** (probe script + cache + state machine operational).
- **Blocks Sprint 4 (nice-to-have)** — Sprint 4's E2E validation can proceed with just 3A's probe, but 3B's resilience layer makes the E2E validation more robust.

### Security Considerations (3B)

- **Sensitive data**: Centralized `_redact_secrets` function is the single source for redaction; all logging paths MUST route through it. Structured logging with allowlist fields prevents accidental payload logging. Post-job secret scanner is the final fuse.
- **Bypass governance**: `override-probe-outage` label + `LOA_PROBE_BYPASS` are the highest-authority bypass mechanisms. Dual-approval for label, 24h TTL for env var, mandatory audit alerts on both.
- **GitHub Actions pinning**: All actions SHA-pinned per `MEMORY.md` security patterns.

### Risks & Mitigation (3B)

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **R2 (SKP-004)**: Probe infra creates new SPOF | Low-Med | **CRITICAL** | Feature flag; `degraded_ok`; circuit breaker; `LOA_PROBE_BYPASS=1` with 24h TTL + audit; `override-probe-outage` dual-approval label; no artifact upload |
| **R4 (SKP-002 #1)**: Stale cache window masks new unavailability | Medium | Medium | Split TTL (from 3A); sync recheck on first provider error |
| **R5 (SKP-002 #2)**: Provider outage blocks unrelated PRs | Medium | Medium | 429/5xx → UNKNOWN; last-known-good fallback; override label |
| **R6 (SKP-003)**: CI trigger misses drift via indirect paths | Medium | Medium | Dependency-graph scope expansion; daily cron on main |
| **R7 (SKP-005)**: Secret leak via probe output | Low | **CRITICAL** | Centralized scrubber; `set +x`; post-job secret scanner; no artifact upload |
| **R19**: Stale-cache indefinite-serve under degraded_ok | Medium | High | `max_stale_hours: 72` fail-closed; `alert_on_stale_hours: 24` audit alert |
| **R23 (new)**: Bypass governance too strict → operator friction | Low-Med | Low | Dual-approval ONLY for label (highest-authority); `LOA_PROBE_BYPASS` is solo-operator with audit trail (lower friction); documented in runbook |
| **R25 (new)**: macOS concurrency divergence from Linux | Low-Med | Medium | Platform matrix in CI; `_require_flock` shim + `brew install util-linux` guidance |
| **R26 (new)**: Secret scanner false positives block builds | Low | Low | Documented allowlist for test fixtures; dev runbook section on triaging false positives |
| **R17**: `(( var++ ))` under `set -e` with var=0 | Low | Low | Use `var=$((var + 1))` per `MEMORY.md` PR #213 lessons |

### Success Metrics (3B)

- Config-load overhead on cache hit ≤ 50 ms (SDD §1.8) — verified after runtime integration
- Full probe run ≤ 120 s total; per-call ≤ 30 s
- Probe cost per run ≤ $0.05
- Zero secret patterns in stdout/stderr across 100 randomized probe runs (SKP-005 regression) AND post-job scanner green
- `model-health-probe.yml` CI green on 10 consecutive same-repo PRs; listing-only mode verified on a fork PR
- Daily cron fires at least once in the 72h window after merge; opens `model-health-drift` issue if any model UNAVAILABLE on main
- Runbook table-top exercise completed with all diagnosis + unblock + rollback + key-rotation steps verified
- N=10 parallel stress tests green on both macOS and Linux runners
- Bypass governance: `LOA_PROBE_BYPASS` TTL expiry verified; `override-probe-outage` dual-approval gate rejects single-approval PRs

---

## Sprint 4 (Final): Model Registry Currency + E2E Validation (T2.1 + T2.3 + T3.1)

**Scope:** MEDIUM (7 tasks + E2E gate)
**Global Sprint ID:** 118
**Duration:** 1 day
**Tier:** 2 + 3 (model currency + dissenter audit)

### Sprint Goal

Re-add Gemini 3.1 Pro Preview as a first-class supported model via the SSOT generator (NOT hand-edit); add GPT-5.5 + GPT-5.5-Pro latent entries with `probe_required: true`; complete the gpt-5.2 hard-default audit; validate end-to-end that the probe gate (from Sprint 3) correctly detects AVAILABLE/UNAVAILABLE transitions on all registered models. **This is the final sprint; includes Task 4.E2E End-to-End Goal Validation covering all PRD goals G1–G6.**

### Deliverables

- [ ] `gemini-3.1-pro-preview` added to `.claude/defaults/model-config.yaml` `providers.google.models` with `capabilities: [chat, thinking_traces]`, `context_window: 1048576`, `extra.thinking_level: high`
- [ ] Alias `deep-thinker: google:gemini-3.1-pro-preview` restored
- [ ] `.claude/scripts/gen-adapter-maps.sh` regenerated → `.claude/scripts/generated-model-maps.sh` contains `gemini-3.1-pro` and `gemini-3.1-pro-preview` mappings
- [ ] Generator extended to also derive `VALID_FLATLINE_MODELS` allowlist for `flatline-orchestrator.sh` (T4.2; SSOT coverage extension per SDD §1.4 C4)
- [ ] GPT-5.5 + GPT-5.5-Pro added to `.claude/defaults/model-config.yaml` `providers.openai.models` with `probe_required: true`
- [ ] CI invariant test `.claude/tests/integration/model-registry-sync.bats` — diffs canonical model IDs across `model-adapter.sh`, `flatline-orchestrator.sh`, `red-team-model-adapter.sh`, `model-config.yaml`; fails on mismatch (SKP-002 drift fuse per SDD §1.4 C4)
- [ ] gpt-5.2 hard-default audit: `grep -rn 'gpt-5.2' .claude/` reveals all residual pins; operator-advisory comment added to `.loa.config.yaml.example` per PRD §T3.1
- [ ] **Task 4.E2E**: End-to-End Goal Validation covering G1–G6 — documented evidence for each goal

### Acceptance Criteria

- [ ] **G4 satisfied**: `.claude/scripts/model-adapter.sh --model gemini-3.1-pro --mode review ...` returns 200; `flatline_tertiary_model: gemini-3.1-pro-preview` validates at config-load; red-team adapter resolves `provider:model-id` *(PRD §3 G4)*
- [ ] **G6 satisfied (re-scoped per Flatline sprint-review SKP-002 HIGH)**: **Infrastructure ready for GPT-5.5**, NOT "GPT-5.5 operational". Acceptance: GPT-5.5 registry entry exists behind `probe_required: true`; probe auto-enables when OpenAI `/v1/models` returns `gpt-5.5` (proven via contract-test fixture-swap: `.claude/tests/fixtures/provider-responses/openai/gpt-5.5-listed.json` simulates API-ship moment; CI validates probe correctly transitions UNAVAILABLE → AVAILABLE on fixture swap). **Live validation deferred to follow-up cycle** when `gpt-5.5` actually appears in OpenAI `/v1/models` — R27 tracks this.
- [ ] `.claude/scripts/gen-adapter-maps.sh` run is deterministic — generator output diff is 1:1 with YAML change; committed YAML + generated.sh together (per SDD §4.3 Flow 1)
- [ ] `model-registry-sync.bats` green on every CI build (cheap text-diff invariant; catches regenerations operators forgot to run)
- [ ] `flatline-orchestrator.sh:302` `VALID_FLATLINE_MODELS` derived from generator (not hand-edited); hand-edit detection via bats test rejects drift
- [ ] `red-team-model-adapter.sh:55` `MODEL_TO_PROVIDER_ID` sourced from `generated-model-maps.sh`
- [ ] Python `google_adapter.py:476` unchanged (confirmed no Python work needed per PRD §T2.1)
- [ ] Probe integration (from Sprint 3) correctly returns AVAILABLE for `gemini-3.1-pro-preview` when Google `v1beta/models` lists it
- [ ] Probe integration correctly keeps GPT-5.5 as UNKNOWN/latent until OpenAI listing confirms; integration test with mocked listing addition proves transition to AVAILABLE
- [ ] `gpt-5.2` audit: all hard defaults cataloged in NOTES.md; no blocker findings (advisory follow-ups filed as separate issues if any)
- [ ] Operator advisory in `.loa.config.yaml.example` literal substring: *"If you have `gpt-5.2` pinned in your `.loa.config.yaml`, consider migrating to `gpt-5.3-codex`..."* (per PRD §T3.1)

### Technical Tasks

- [ ] **Task 4.1**: Add `gemini-3.1-pro-preview` entry to `.claude/defaults/model-config.yaml` `providers.google.models`: `id: gemini-3.1-pro-preview`, `capabilities: [chat, thinking_traces]`, `context_window: 1048576`, pricing per Google published rates, `extra.thinking_level: high`. Add alias `deep-thinker: google:gemini-3.1-pro-preview`. **DO NOT hand-edit bash maps** (SKP-002 mandate per SDD §4.3 Flow 1) → **[G-4]**
- [ ] **Task 4.2**: Extend `.claude/scripts/gen-adapter-maps.sh` to also regenerate `VALID_FLATLINE_MODELS` allowlist in `.claude/scripts/flatline-orchestrator.sh` (SSOT coverage extension per SDD §1.4 C4). Today the generator covers `MODEL_TO_PROVIDER_ID` across `model-adapter.sh` + `red-team-model-adapter.sh` — add third surface `VALID_FLATLINE_MODELS` derivation → **[G-4]**
- [ ] **Task 4.3**: Run `gen-adapter-maps.sh`; commit regenerated `.claude/scripts/generated-model-maps.sh` alongside `model-config.yaml` YAML change. Verify diff is deterministic and 1:1 with YAML addition → **[G-4]**
- [ ] **Task 4.4**: Create `.claude/tests/integration/model-registry-sync.bats` — text-diff invariant asserting canonical model IDs agree across `model-adapter.sh`, `flatline-orchestrator.sh`, `red-team-model-adapter.sh`, `model-config.yaml`. Runs on every CI build (cheap; no network). SKP-002 belt-and-suspenders per SDD §1.4 C4 → **[G-4, G-6]**
- [ ] **Task 4.5**: Add GPT-5.5 + GPT-5.5-Pro to `.claude/defaults/model-config.yaml` `providers.openai.models`: `id: gpt-5.5` / `gpt-5.5-pro`, `context_window: 400000` (pending), pricing `$5/$30` input/output (Pro `$30/$180`), `capabilities: [chat, tools, function_calling, code]`, **`probe_required: true`** — keeps entries latent until OpenAI `/v1/models` confirms per PRD §T2.3. Re-run generator → **[G-6]**
- [ ] **Task 4.6**: Dissenter currency audit (T3.1): `grep -rn 'gpt-5.2' .claude/ --include='*.sh' --include='*.md' --include='*.yaml'` — catalog all hard defaults in NOTES.md; file follow-up bug issues for any blocking findings. Add operator-advisory comment to `.loa.config.yaml.example` per PRD §T3.1 literal text → **[G-3, G-4]**
- [ ] **Task 4.7 (Integration)**: Verify probe gate (from Sprint 3) correctly handles both new models. Live-probe test: `gemini-3.1-pro-preview` → AVAILABLE (Google listing hit). Mocked-probe test: GPT-5.5 with mocked `/v1/models` NOT containing it → UNAVAILABLE (cached 1h); flip mock to contain it → probe auto-enables on next config-load → **[G-4, G-6]**

### Task 4.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete — final sprint gate)
**Goal Contribution:** All goals (G-1, G-2, G-3, G-4, G-5, G-6)

**Description:**

Validate that all PRD goals are achieved through the complete cycle-093 implementation. This is the final gate before cycle archive.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | Close #605 (harness adversarial wiring) | Run `/spiraling` harness cycle with `flatline_protocol.code_review.enabled: true` on a synthetic task; inspect `.run/cycles/<cycle>/evidence/` | `adversarial-review.json` present; `adversarial-review-gate.sh` hook passes |
| G-2 | Close #607 (bridgebuilder dist) | Trigger `bridgebuilder-submodule-smoke.yml` CI workflow on a PR touching `.claude/skills/bridgebuilder-review/**` | Workflow green; JSON summary `{ reviewed, skipped, errors }` emitted |
| G-3 | Close #618 (dissenter filter) | Run 20 adversarial reviews against synthetic diff containing `&&`, `&`, `2>&1` | 0 BLOCKING findings; all `{{DOCUMENT_CONTENT}}`-family downgraded to `MODEL_ARTEFACT_SUSPECTED` |
| G-4 | Gemini 3.1 Pro Preview routable | `model-adapter.sh --model gemini-3.1-pro --mode review ...` + `flatline_tertiary_model: gemini-3.1-pro-preview` validation + red-team adapter resolve | 200 OK; config validates; red-team adapter resolves `google:gemini-3.1-pro-preview` |
| G-5 | Health-probe invariant | Add a synthetic model ID `gpt-nonexistent-99` to `model-config.yaml`; open PR | `model-health-probe.yml` CI fails with actionable message citing provider NOT_FOUND; 24h TTL on newly-available models verified via unit test |
| G-6 | **GPT-5.5 infrastructure readiness** (re-scoped per Flatline SKP-002 HIGH — NOT live validation) | Contract-test fixture `.claude/tests/fixtures/provider-responses/openai/gpt-5.5-listed.json` simulates API-ship; CI swaps fixture; probe transitions UNAVAILABLE → AVAILABLE on next config-load | Fixture-swap integration test green; live validation deferred to follow-up cycle (R27) |

**Acceptance Criteria:**

- [ ] Each of G-1..G-6 validated with documented evidence (paste command output into NOTES.md)
- [ ] Integration points verified end-to-end: config → probe → cache → runtime adapter → provider
- [ ] All 5 Flatline SKP BLOCKERs (SKP-001…005) closed with regression tests green
- [ ] All 7 Flatline IMP findings (IMP-001, IMP-002, IMP-003, IMP-005, IMP-006, IMP-007, IMP-009) addressed in code and tests
- [ ] No goal marked as "not achieved" without explicit justification in NOTES.md
- [ ] `model-registry-sync.bats` + `model-health-probe-secrets.bats` + all sprint-1..3 test suites green on final PR
- [ ] Runbook `.claude/docs/runbooks/model-health-probe-incident.md` table-top exercise passed

### Dependencies

- **Sprint 3 COMPLETE** — registry currency work cannot validate end-to-end without the probe operational. T4.7 integration validation explicitly exercises the probe against both new models.
- **No external blockers** — probe feature flag `model_health_probe.enabled: true` is default after Sprint 3 merge.

### Security Considerations

- **Trust boundaries**: Model registry is operator-edited; changes flow through generator (no direct bash-map edits). CI invariant test prevents drift. Operator advisory discourages hand-edits.
- **External dependencies**: GPT-5.5 ship date is an [ASSUMPTION]; `probe_required: true` keeps entry latent until provider confirms. Single-line config update if final IDs differ.
- **Sensitive data**: None in this sprint (all secret handling is Sprint 3's probe script). Config additions are public model IDs + published pricing.

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **R21 (SKP-002)**: Operator forgets to re-run `gen-adapter-maps.sh` after YAML change | Medium | **CRITICAL** | `model-registry-sync.bats` invariant test (Task 4.4) catches drift at CI; operator advisory in Flow 1 (SDD §4.3) forbids hand-edits |
| **R10**: Gemini 3.1 Pro Preview v1beta instability (rate-limits, intermittent NOT_FOUND) | Medium | Medium | Health-probe (Sprint 3) handles this class via UNKNOWN-vs-UNAVAILABLE taxonomy; error taxonomy distinguishes transient from hard |
| **R13 [ASSUMPTION]**: GPT-5.5 API ships with announced model IDs in cycle window | High | Low | `probe_required: true` keeps entries latent; single-line update if IDs differ at ship; integration test with mocked listing doesn't require live GPT-5.5 |
| **R15 [ASSUMPTION]**: Google v1beta `ListModels` surfaces `gemini-3.1-pro-preview` by exact ID | Low | Medium | Probe parser handles paginated + aliased results; `generateContent` fallback signal (SDD §3.3) |
| Generator bug introduces bash-map syntax error | Low | High | Generator is deterministic per SDD §1.4 C4; Task 4.3 verifies 1:1 diff; `model-registry-sync.bats` catches semantic drift |
| gpt-5.2 audit reveals more hard defaults than expected, scope creep | Low-Med | Low | Task 4.6 scopes audit to `.claude/` grep; follow-up bugs filed as separate issues (do not land in this sprint) |
| Task 4.2 generator extension (wiring `VALID_FLATLINE_MODELS` derivation) breaks existing generator output | Low | Medium | Generator change is additive (new emit function); regression via `model-registry-sync.bats` + explicit verification in Task 4.4 |

### Success Metrics

- `gemini-3.1-pro-preview` routable end-to-end: `/spiraling` with tertiary model set to Gemini 3.1 Pro Preview completes review successfully
- GPT-5.5 integration test (mocked listing add) transitions UNKNOWN → AVAILABLE in one config-load cycle
- `model-registry-sync.bats` green on all 4 sprint-093 PRs (114, 115, 116, 117) — catches any regression during cycle
- 0 hand-edits to `.claude/scripts/{model-adapter,flatline-orchestrator,red-team-model-adapter}.sh` for model-map content during cycle-093 (all via generator)
- gpt-5.2 audit delivers a catalog (count + file:line) in NOTES.md; operator advisory string literal-present in `.loa.config.yaml.example`

---

## Risk Register

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R1 (SKP-001) | Probe correctness false pos/neg across providers | 3 | Medium | **CRITICAL** | State machine (§3.2); provider rules (§3.3); Anthropic rejects ambiguous 4xx; contract-test fixtures | Sprint 3 impl |
| R2 (SKP-004) | Probe infra creates new SPOF | 3 | Low-Med | **CRITICAL** | Feature flag; `degraded_ok`; circuit breaker; `LOA_PROBE_BYPASS`; override label; no artifact upload | Sprint 3 impl |
| R3 | Skill invocation ergonomics block T1.1 preferred path | 1 | Medium | Low | Fallback path in SDD §1.4 C6 / §6.6 wraps `_invoke_claude` with post-hoc `adversarial-review.sh` | Sprint 1 impl |
| R4 (SKP-002 #1) | Stale cache window masks new unavailability | 3 | Medium | Medium | Split TTL (24h/1h/0); sync recheck on first provider error | Sprint 3 impl |
| R5 (SKP-002 #2) | Provider outage blocks unrelated PRs | 3 | Medium | Medium | 429/5xx → UNKNOWN; last-known-good; override label | Sprint 3 impl |
| R6 (SKP-003) | CI trigger misses drift via indirect paths | 3 | Medium | Medium | Dependency-graph scope expansion; daily cron on main | Sprint 3 impl |
| R7 (SKP-005) | Secret leak via probe output | 3 | Low | **CRITICAL** | `curl --config` + `set +x` + redaction regex + bats regression + no artifact upload | Sprint 3 impl |
| R9 | Cache concurrent-write corruption / torn reads | 3 | Medium | **CRITICAL** | Atomic write + flock; reader retry; schema versioning | Sprint 3 impl |
| R10 | Gemini 3.1 Pro Preview v1beta instability | 4 | Medium | Medium | Health-probe UNKNOWN handling; error taxonomy | Sprint 4 impl |
| R11 | `gpt-5.3-codex` exhibits same hallucination pattern | 2, 4 | Low-Med | Medium | T1.3 pre-check is safety net; T3.1 advisory | Sprint 2, 4 impl |
| R12 | PR #603 (cycle-092) conflicts with T1.1 | 1 | Medium | Low | Branch from fresh main after merge; distinct scope | Sprint 1 impl |
| R16 | `flock` unavailable on macOS dev | 3 | Low | Low | `_require_flock` shim with `brew install util-linux` | Sprint 3 impl |
| R17 | `(( var++ ))` under `set -e` with var=0 | 3 | Low | Low | Use `var=$((var + 1))` per `MEMORY.md` | Sprint 3 impl |
| R18 | Background probe proliferation under concurrent harness | 3 | Medium | High | PID sentinel dedup per-provider | Sprint 3 impl |
| R19 | Stale-cache indefinite-serve under `degraded_ok` | 3 | Medium | High | `max_stale_hours: 72` fail-closed; `alert_on_stale_hours: 24` | Sprint 3 impl |
| R20 | Provider API schema drift flipping availability logic | 3A | Low-Med | Medium | Contract-test fixtures; schema-tolerant parser → UNKNOWN; version-pinned calls; **contract-version check Task 3A.2 (Flatline SKP-002)** | Sprint 3A impl |
| R21 (SKP-002) | Model-registry 4-file hand-sync regression | 4 | Medium | **CRITICAL** | SSOT via `gen-adapter-maps.sh`; `model-registry-sync.bats` fuse; Flow 1 forbids hand-edits | Sprint 4 impl |
| R22 (Flatline sprint) | Sprint 3 split creates integration lag between 3A and 3B | 3A/3B | Low | Medium | 3A exit criteria includes bats tests green before 3B starts; 3B immediately integrates against 3A at merge | Sprint 3A/3B impl |
| R23 (Flatline sprint) | Bypass governance too strict → operator friction | 3B | Low-Med | Low | Dual-approval ONLY for `override-probe-outage` label; `LOA_PROBE_BYPASS` is solo-operator with audit; runbook documents decision tree | Sprint 3B impl |
| R24 (Flatline sprint) | Parser rollback flag becomes operator crutch | 3A | Low | Medium | `LOA_PROBE_LEGACY_BEHAVIOR=1` audit-log mandatory; CI warns on env-file commits setting it; runbook marks emergency-only | Sprint 3A impl |
| R25 (Flatline sprint) | macOS concurrency divergence from Linux | 3B | Low-Med | Medium | Platform matrix in CI; `_require_flock` shim + `brew install util-linux` docs | Sprint 3B impl |
| R26 (Flatline sprint) | Secret scanner false positives block builds | 3B | Low | Low | Documented allowlist; dev runbook section on triaging | Sprint 3B impl |
| R27 (Flatline sprint) | GPT-5.5 never ships in cycle window | 4 | Medium | Low | G-6 re-scoped to "infrastructure ready"; fixture-swap test does not require live model; live validation deferred to follow-up cycle | Sprint 4 impl |

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| Harness-emitted adversarial artifacts (G-1) | 100% of flag-on cycles | `ls .run/cycles/*/evidence/adversarial-*.json \| wc -l` over 5 live cycles | 1 |
| Bridgebuilder submodule smoke (G-2) | 5 consecutive green PRs | `bridgebuilder-submodule-smoke.yml` CI log | 2 |
| Dissenter hallucination BLOCKING count (G-3) | 0 across 20 synthetic runs | TC10 bats test + live harness runs | 2 |
| Gemini 3.1 Pro Preview routable (G-4) | 200 OK on probe + config + red-team | Live integration test | 4 |
| Health-probe CI gate fires on NOT_FOUND (G-5) | Actionable error on synthetic unavailable model | CI workflow log | 3, 4 (E2E) |
| GPT-5.5 auto-enable on listing (G-6) | UNKNOWN → AVAILABLE on one config-load | Integration test with mocked listing flip | 4 |
| Config-load overhead cache-hit | ≤ 50 ms | Runtime benchmark | 3 |
| Full probe run | ≤ 120 s | CI workflow duration | 3 |
| Probe cost per run | ≤ $0.05 | Cost ledger audit (if Q5 resolves to yes) | 3 |
| Secret-scanning regression | 0 matches on `sk-\|AIza\|ghp_\|-----BEGIN` | `model-health-probe-secrets.bats` | 3 |
| Registry sync invariant | Green on every CI build post-Sprint-4 | `model-registry-sync.bats` | 4 |

---

## Dependencies Map (post-Flatline sprint-integration)

```
Sprint 1 (T1.1) ────────┐
                        │
Sprint 2 (T1.2+T1.3) ───┤
                        │
Sprint 3A (T2.2 core) ──┴─┐
                          │
Sprint 3B (T2.2 prod) ────┴─┐
                            │
Sprint 4 (T2.1+T2.3+T3.1) ──┴──▶ Task 4.E2E (Final Gate — all goals)
```

**Parallelism / merge order** (Flatline sprint-review SKP-003 HIGH mitigation — sprints touch overlapping files so serialization reduces conflict risk):

| Order | Sprint | Global ID | Rationale |
|-------|--------|-----------|-----------|
| 1st | sprint-1 (T1.1) | 114 | Independent. Touches `spiral-harness.sh` + `_invoke_claude`. |
| 2nd | sprint-2 (T1.2+T1.3) | 115 | Independent. Touches `bridgebuilder-review/` + `adversarial-review.sh`. |
| 3rd | sprint-3A (T2.2 core) | 116 | Core probe foundation. Touches `model-health-probe.sh` (new) + cache. |
| 4th | sprint-3B (T2.2 prod) | 117 | Depends on 3A. Integrates with `model-adapter.sh` — overlap with sprint-1's `spiral-harness.sh` touchpoints is minimal but budget 6h rebase slack. |
| 5th | sprint-4 (registry) | 118 | Depends on 3A (probe operational). Nice-to-have 3B (for full E2E validation). |

**Rebase slack budget**: 6h per dependent sprint (Flatline SKP-003 HIGH mitigation).

---

## Inter-Sprint Coordination (new, Flatline sprint-review SKP-003 + IMP-003 mitigation)

### Shared file surfaces

| File | Sprints touching | Conflict risk |
|------|------------------|---------------|
| `.claude/scripts/spiral-harness.sh` | 1 | None (other sprints don't touch) |
| `.claude/scripts/adversarial-review.sh` | 2 | None |
| `.claude/skills/bridgebuilder-review/` | 2 | None |
| `.claude/scripts/model-health-probe.sh` | 3A, 3B | 3B builds on 3A — serialize |
| `.run/model-health-cache.json` schema | 3A, 3B | 3B reads 3A's writes — schema locked in 3A |
| `.claude/scripts/model-adapter.sh` | 3B (integration) | No cross-sprint conflict; single touchpoint in 3B |
| `.claude/defaults/model-config.yaml` | 4 | No cross-sprint conflict |
| `.claude/scripts/generated-model-maps.sh` | 4 (via generator) | No cross-sprint conflict |

### Inter-sprint defect decision tree (Flatline sprint-review IMP-003)

When a defect in Sprint N is discovered during Sprint M (M > N):

| Situation | Action |
|-----------|--------|
| Sprint N PR still open (not merged) | **Fix forward** — add commit to Sprint N's PR; request re-review |
| Sprint N PR merged, defect is CRITICAL | **Block Sprint M** — file follow-up bug issue; Sprint M waits for bugfix PR to land before proceeding |
| Sprint N PR merged, defect is HIGH | **File follow-up bug issue**; Sprint M proceeds but notes dependency in its PR description |
| Sprint N PR merged, defect is ADVISORY | **File follow-up bug issue**; no Sprint M blocking |

Post-cycle retrospective must catalog all inter-sprint defects discovered for pattern analysis.

### Rebase discipline

- Each dependent sprint starts from `main` AFTER upstream sprint's PR has merged.
- If `main` moves during sprint development, rebase before opening PR.
- Budget 6h per dependent sprint for rebase work.
- Conflict on shared files resolves with: sprint that landed first wins line-level conflicts; later sprint manually re-applies its logic on top.

---

## Appendix

### A. PRD T-Req Mapping

| PRD T-Req | Sprint | Task(s) | Status |
|-----------|--------|---------|--------|
| T1.1 — Harness adversarial wiring | 1 | 1.1, 1.2, 1.3, 1.4, 1.5, 1.6 | Planned |
| T1.2 — Bridgebuilder dist completeness | 2 | 2.1, 2.2, 2.3 | Planned |
| T1.3 — Dissenter hallucination filter | 2 | 2.4, 2.5, 2.6, 2.7, 2.8 | Planned |
| T2.1 — Gemini 3.1 Pro Preview re-add | 4 | 4.1, 4.2, 4.3, 4.4 | Planned |
| T2.2 — Provider health-probe core (KEYSTONE part 1) | 3A | 3A.1–3A.5 + 3A.canary + 3A.rollback_flag + 3A.hardstop_tests | Planned |
| T2.2 — Provider health-probe resilience+CI+integration (KEYSTONE part 2) | 3B | 3B.1–3B.7 + 3B.bypass_governance + 3B.bypass_audit + 3B.centralized_scrubber + 3B.secret_scanner + 3B.concurrency_stress + 3B.platform_matrix + 3B.runbook | Planned |
| T2.3 — GPT-5.5 latent registry entry | 4 | 4.5, 4.4, 4.7 | Planned |
| T3.1 — Dissenter default audit | 4 | 4.6 | Planned |

### B. SDD Component Mapping

| SDD Component | Sprint | Task(s) | Status |
|---------------|--------|---------|--------|
| C1. `model-health-probe.sh` (new script) | 3 | 3.1, 3.2 | Planned |
| C2. Per-provider probe adapters | 3 | 3.2, 3.10 | Planned |
| C3. Cache layer `.run/model-health-cache.json` | 3 | 3.3, 3.4 | Planned |
| C4. Runtime adapters (SSOT via generator) | 4 | 4.1, 4.2, 4.3, 4.4, 4.5 | Planned |
| C5a. `model-health-probe.yml` (PR-scoped) | 3B | 3B.3 | Planned |
| C5b. `model-health-drift-daily.yml` (cron) | 3B | 3B.4 | Planned |
| C5c. `bridgebuilder-submodule-smoke.yml` | 2 | 2.3 | Planned |
| C6. `spiral-harness.sh` gate refactor | 1 | 1.3, 1.4 | Planned |
| C7. Dissenter hallucination pre-check | 2 | 2.4, 2.5, 2.6, 2.7 | Planned |
| C8. Bridgebuilder dist pipeline | 2 | 2.1, 2.2 | Planned |
| D. Incident runbook (expanded per Flatline sprint) | 3B | 3B.runbook | Planned |

### C. PRD Goal Mapping

| Goal ID | Goal Description (from PRD §3) | Contributing Tasks | Validation Task |
|---------|-------------------------------|-------------------|-----------------|
| G-1 | Close #605 — `/spiraling` harness with `flatline_protocol.code_review.enabled: true` produces `adversarial-review.json` | Sprint 1: Tasks 1.1, 1.2, 1.3, 1.4, 1.5, 1.6 | Sprint 4: Task 4.E2E |
| G-2 | Close #607 — `bridgebuilder-review` runs end-to-end from submodule consumer | Sprint 2: Tasks 2.1, 2.2, 2.3 | Sprint 4: Task 4.E2E |
| G-3 | Close #618 — Zero BLOCKING hallucinations on synthetic diff containing `&&`, `&`, `2>&1` across 20 runs | Sprint 2: Tasks 2.4, 2.5, 2.6, 2.7, 2.8; Sprint 4: Task 4.6 (advisory) | Sprint 4: Task 4.E2E |
| G-4 | Gemini 3.1 Pro Preview routable via `model-adapter.sh`, Flatline, red-team | Sprint 4: Tasks 4.1, 4.2, 4.3, 4.4, 4.6, 4.7 | Sprint 4: Task 4.E2E |
| G-5 | Health-probe invariant — CI gate fails with actionable message when configured model returns NOT_FOUND | Sprint 3: Tasks 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10, 3.11, 3.12, 3.13 | Sprint 4: Task 4.E2E |
| G-6 | GPT-5.5 readiness — registry entry behind `probe_required: true`; auto-enables on `/v1/models` listing | Sprint 4: Tasks 4.4, 4.5, 4.7 | Sprint 4: Task 4.E2E |

**Goal Coverage Check:**

- [x] All PRD goals (G-1..G-6) have at least one contributing task
- [x] All goals have a validation task in final sprint (Task 4.E2E)
- [x] No orphan tasks — every task traces to G-1..G-6

**Per-Sprint Goal Contribution:**

- Sprint 1: G-1 (complete)
- Sprint 2: G-2 (complete), G-3 (partial — core filter; advisory in Sprint 4)
- Sprint 3: G-5 (complete — keystone infrastructure enabling G-4 and G-6 verification)
- Sprint 4: G-3 (complete — advisory), G-4 (complete), G-6 (complete), Task 4.E2E (all G-1..G-6)

### D. Flatline Finding Mapping

**Three Flatline runs total across this cycle.** All findings from PRD review (6 BLOCKERs + 7 HIGH), SDD review (5 BLOCKERs + 7 HIGH), and sprint-plan review (8 BLOCKERs + 3 HIGH + 1 DISPUTED) are integrated. Provenance docs: `flatline-prd-integration.md`, `flatline-sdd-integration.md`, `flatline-sprint-integration.md`.

| Flatline Finding | Origin | Severity | Sprint / Task | Verification |
|------------------|--------|----------|---------------|--------------|
| PRD SKP-001 — Probe correctness across providers | PRD | BLOCKER | 3A Task 3A.2, 3A.5; 3B Task 3B.5 | `model-health-probe-anthropic.bats` (mock 400 without model-field → UNKNOWN) |
| PRD SKP-002 #1 — 24h cache TTL stale window | PRD | BLOCKER | 3A Task 3A.3; 3B Task 3B.2, 3B.7 | Unit test: split TTL 24h/1h/0; sync recheck |
| PRD SKP-002 #2 — Provider outage blocks unrelated PRs | PRD | BLOCKER | 3A Task 3A.5; 3B Task 3B.3 | Error taxonomy unit tests; override label integration |
| PRD SKP-003 — CI trigger scope too narrow | PRD | BLOCKER | 3B Task 3B.2, 3B.3, 3B.4 | Path filter + dependency-graph + daily cron |
| PRD SKP-004 — Probe failure creates SPOF | PRD | BLOCKER | 3B Task 3B.1 | Feature flag + `degraded_ok` + circuit breaker + `LOA_PROBE_BYPASS` |
| PRD SKP-005 — Secrets handling incomplete | PRD | BLOCKER | 3B Task 3B.centralized_scrubber, 3B.secret_scanner, 3B.6 | `model-health-probe-secrets.bats` + post-job scanner |
| SDD SKP-001 #1 — Background probe proliferation | SDD | HIGH | 3A Task 3A.4 | PID sentinel + `kill -0 $pid` stress test |
| SDD SKP-001 #2 — Cache atomic-write gap | SDD | CRITICAL | 3A Task 3A.3 | Atomic write Pattern 1 + reader retry Pattern 2 |
| SDD SKP-002 — 4-file hand-sync regression | SDD | CRITICAL | 4 Task 4.2, 4.4 | `model-registry-sync.bats` invariant + generator extension |
| SDD SKP-003 — `degraded_ok` masks failures | SDD | HIGH | 3B Task 3B.2 | `max_stale_hours: 72` fail-closed + `alert_on_stale_hours: 24` |
| SDD SKP-004 — API schema drift | SDD | HIGH | 3A Task 3A.2 (contract-version check); 3B Task 3B.5 (fixtures) | Schema-tolerant parser + fixture tests |
| **Sprint SKP-001 — Sprint 3 oversized (CRITICAL)** | Sprint | **CRITICAL** | **3→3A/3B split** (structural) | 5 sprints with 30–50% slack; 3A + 3B exit criteria explicit |
| **Sprint SKP-002 CRITICAL — Parser brittleness** | Sprint | **CRITICAL** | 3A Task 3A.canary, 3A.2 (contract-version check), 3A.rollback_flag | Canary runs non-blocking; contract-version check biases UNKNOWN; `LOA_PROBE_LEGACY_BEHAVIOR=1` emergency fallback |
| **Sprint SKP-003 CRITICAL — Bypass governance** | Sprint | **CRITICAL** | 3B Task 3B.bypass_governance, 3B.bypass_audit | Dual-approval CI check; 24h TTL; mandatory audit alerts to `.run/audit.jsonl` |
| Sprint SKP-003 HIGH — Inter-sprint file conflicts | Sprint | HIGH | Dependencies Map + §Inter-Sprint Coordination (doc) | Canonical merge order 1→2→3A→3B→4 with 6h rebase slack |
| Sprint SKP-004 — Concurrency cross-platform fragility | Sprint | HIGH | 3B Task 3B.concurrency_stress, 3B.platform_matrix | N=10 parallel stress; macOS + Linux CI matrix |
| Sprint SKP-005 — Redaction regex insufficient | Sprint | HIGH | 3B Task 3B.centralized_scrubber, 3B.secret_scanner | Centralized `_redact_secrets` + post-job `gitleaks`; key rotation playbook in runbook |
| Sprint SKP-002 HIGH — GPT-5.5 E2E depends on unshipped model | Sprint | HIGH | 4 Task 4.7 + §Acceptance Criteria G-6 re-scope | Fixture-swap test (not live); live validation deferred to follow-up cycle |
| IMP-001 (PRD) — Probe cost/throttling budgets | PRD | HIGH | 3A Task 3A.1, 3A.hardstop_tests | Hard-stop budget tests — exit 5 on violation |
| IMP-001 (Sprint) — Probe rollback documentation | Sprint | HIGH | 3B Task 3B.runbook | Runbook rollback section + table-top exercise |
| IMP-002 (PRD) — Probe failure vs unavailability distinction | PRD | HIGH | 3A Task 3A.5 | State machine UNKNOWN explicit |
| IMP-002 (SDD) — Cold-start + offline behavior | SDD | HIGH | 3A Task 3A.5; 3B Task 3B.1 | Cold-start unit tests + offline degraded_ok path |
| IMP-003 (PRD) — T1.3 filter robustness | PRD | HIGH | 2 Task 2.4, 2.5 | Bidirectional + 6-variant normalization |
| IMP-003 (SDD) — Background probe dedup lifecycle | SDD | HIGH | 3A Task 3A.4; 3B Task 3B.concurrency_stress | PID sentinel Pattern 3 + stress test |
| IMP-003 (Sprint) — Inter-sprint defect decision tree | Sprint | HIGH | §Inter-Sprint Coordination (doc) | Post-cycle retrospective catalogs defects |
| IMP-004 (SDD) — Cache persistence / git-tracking policy | SDD | HIGH | 3A Task 3A.3 (spec) | Cache table row in SDD §3.5 — `.run/` gitignored |
| **IMP-004 (Sprint) DISPUTED — Coverage thresholds** | Sprint | **DISPUTED** | §Testing Strategy — critical-path framing | Replace "80% line coverage" with "100% critical paths + BLOCKER regression tests" |
| IMP-005 — Cache file concurrency | PRD | HIGH | 3A Task 3A.3; 3B Task 3B.concurrency_stress | Atomic write + flock + schema versioning + stress |
| IMP-006 (PRD) — Endpoint overrides / unknown provider | PRD | HIGH | 3A Task 3A.1, 3A.5 | Config + env var overrides; unknown provider passthrough |
| IMP-006 (SDD) — Unknown provider handling | SDD | HIGH | 3A Task 3A.5 | Unknown provider → UNKNOWN passthrough |
| IMP-006 (Sprint) — Cost cap enforcement semantics | Sprint | HIGH | 3A Task 3A.1 Acceptance | Hard stops; exit 5 with telemetry |
| IMP-007 — Fixture-submodule CI test / Incident runbook | PRD+SDD | HIGH | 2 Task 2.3 + 3B Task 3B.runbook | `bridgebuilder-submodule-smoke.yml` + runbook table-top exercise |
| IMP-008 (SDD) — Atomic write + reader retry | SDD | HIGH | 3A Task 3A.3 | Pattern 1 + Pattern 2 per SDD §3.6 |
| IMP-009 — Fork PR listing-only mode | PRD | HIGH | 3B Task 3B.3 | Fork mode detection + missing-secrets UNKNOWN |

**Meta-observation**: Across 3 Flatline runs, **19 blockers total were sourced exclusively from the tertiary skeptic (Gemini 2.5 Pro)**. 100% sourced from the tertiary leg across PRD+SDD+Sprint reviews. This is the single strongest empirical case for both the 3-model Flatline protocol and the Gemini-tertiary upgrade in T2.1 of this cycle.

### E. Sprint Ledger Entry (post-Flatline sprint integration — 5 sprints)

Registered in `grimoires/loa/ledger.json`:

```json
{
  "id": "cycle-093-stabilization",
  "label": "Loa Stabilization & Model-Currency Architecture",
  "status": "active",
  "active_cycle": true,
  "sprints": [
    {"local_id": 1,  "global_id": 114, "label": "Harness Adversarial Wiring (T1.1)", "status": "planned"},
    {"local_id": 2,  "global_id": 115, "label": "Bridgebuilder Dist + Dissenter Filter (T1.2 + T1.3)", "status": "planned"},
    {"local_id": "3A","global_id": 116, "label": "Health-Probe Core — KEYSTONE part 1 (T2.2)", "status": "planned"},
    {"local_id": "3B","global_id": 117, "label": "Health-Probe Resilience+CI+Integration+Runbook — KEYSTONE part 2 (T2.2)", "status": "planned"},
    {"local_id": 4,  "global_id": 118, "label": "Model Registry Currency (T2.1 + T2.3 + T3.1) + E2E Gate", "status": "planned"}
  ]
}
```

**Ledger update note**: `global_sprint_counter` bumped from 117 → 118 to accommodate the 3→3A/3B split driven by Flatline sprint-review SKP-001 CRITICAL finding.

### F. Beads Integration (if `br` available)

When `br` (beads_rust) is available, create sprint epics + tasks with unique `external_ref` per MEMORY.md DX lesson from PR #218 (no duplicate refs):

```bash
# Sprint 1 epic + 6 tasks
EPIC_1=$(.claude/scripts/beads/create-sprint-epic.sh "Sprint 1: Harness Adversarial Wiring (T1.1)" 1)
.claude/scripts/beads/create-sprint-task.sh "$EPIC_1" "cycle-093-sprint-1-task-1.1" "Investigate --skill dispatch feasibility" 2 task
.claude/scripts/beads/create-sprint-task.sh "$EPIC_1" "cycle-093-sprint-1-task-1.2" "Extend _invoke_claude with --skill + --evidence-dir" 2 task
.claude/scripts/beads/create-sprint-task.sh "$EPIC_1" "cycle-093-sprint-1-task-1.3" "Rewrite _gate_review" 2 task
.claude/scripts/beads/create-sprint-task.sh "$EPIC_1" "cycle-093-sprint-1-task-1.4" "Rewrite _gate_audit" 2 task
.claude/scripts/beads/create-sprint-task.sh "$EPIC_1" "cycle-093-sprint-1-task-1.5" "Verify adversarial-review-gate.sh hook" 2 task
.claude/scripts/beads/create-sprint-task.sh "$EPIC_1" "cycle-093-sprint-1-task-1.6" "Add bats tests + live /spiraling validation" 2 task

# Sprint 2 — 8 tasks (2.1–2.8)
# Sprint 3 — 13 tasks (3.1–3.13)
# Sprint 4 — 7 tasks (4.1–4.7) + Task 4.E2E

# Blocking dependencies:
# Sprint 4 tasks block on Sprint 3 epic
```

**Note**: Beads JSONL stale check (`br sync --import-only`) recommended before creating tasks. External-ref format `cycle-093-sprint-N-task-N.N` ensures uniqueness across cycle (lesson from PR #218).

---

## Planning Decisions Log

1. **Parallelism over linear sequence**: Sprints 1, 2, 3 declared parallel-eligible because their scopes are fully independent (harness gates vs bridgebuilder dist vs new probe script). Sprint 4 is the only dependent sprint — blocks on probe availability for T4.7 integration validation. This matches cycle-092's shipping cadence (4 sprints in a single cycle) and halves wall-clock vs sequential.
2. **Sprint 2 split S+S (T1.2 + T1.3) rather than separate sprints**: Both are small single-file surgical changes. Combining keeps the PR count at 4 (one per sprint) which aligns with cycle-092's proven flow. Within Sprint 2, tasks T1.2 (2.1–2.3) and T1.3 (2.4–2.8) can be implemented in parallel or sequentially — no intra-sprint dependency.
3. **Sprint 3 sized LARGE with 13 tasks**: At the PRD/SDD upper bound (LARGE = 7–10 per CLAUDE.loa.md; sprint 3 exceeds this). Kept 13 because Flatline review produced 5 BLOCKERS + 7 IMPs all in T2.2 — splitting across sprints would fragment the keystone. Budget: 2–3 wall-clock days, not 1 (calibrated higher than other sprints).
4. **Task 4.E2E as dedicated final-sprint gate**: Per sprint-template, the final sprint includes E2E Goal Validation covering all PRD goals. Task 4.E2E is P0 (must-complete) and is the cycle-archive gate.
5. **SSOT via generator (SKP-002 mandate)**: Sprint 4 Task 4.2 extends `gen-adapter-maps.sh` to cover `VALID_FLATLINE_MODELS` (not just `MODEL_TO_PROVIDER_ID`). Operator advisory in Flow 1 forbids hand-edits. `model-registry-sync.bats` is the drift fuse. This is the single most load-bearing architectural decision of the cycle.
6. **No scope creep on T3.1 audit**: Sprint 4 Task 4.6 catalogs gpt-5.2 findings in NOTES.md; files follow-up bug issues for any blockers. Does NOT expand this cycle to address them — respects PRD §7 out-of-scope discipline.
7. **Traceability-first**: Every task annotated with `→ **[G-N]**` goal contribution. All 6 PRD goals mapped. All 5 Flatline BLOCKERS traced to specific sprint/task. Appendix D explicitly cross-references SKP/IMP findings to implementation touchpoints.

---

## Post-Sprint-Plan Step

Per user's workflow pattern (PRD → SDD → Flatline → sprint-plan → Flatline → `/run sprint-plan`):

1. **Next**: Run Flatline Protocol on this sprint plan. If HIGH_CONSENSUS findings emerge, integrate before execution.
2. **After Flatline**: `/run sprint-plan` executes the cycle (sprint-1 ∥ sprint-2 ∥ sprint-3 → sprint-4).
3. **Cycle archive**: After Task 4.E2E passes, `/archive-cycle` moves cycle-093 artifacts to dated archive.

---

*Generated by Sprint Planner Agent — `.claude/skills/planning-sprints/SKILL.md`*
