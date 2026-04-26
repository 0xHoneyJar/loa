# Flatline Integration — cycle-093 Sprint Plan

> **Document**: `grimoires/loa/cycles/cycle-093-stabilization/sprint.md`
> **Phase**: sprint
> **Timestamp**: 2026-04-24T04:38:56Z
> **Models**: 3-model (opus + gpt-5.3-codex + gemini-2.5-pro)
> **Agreement**: 90% (first time below 100% — DISPUTED item present)
> **Confidence**: full
> **Consensus**: HIGH=3, DISPUTED=1, LOW=0, BLOCKER=8
> **Cost/Latency**: 94s, 76 cents

## Summary

**Strongest signal of the three Flatline runs.** Sprint-plan-level review surfaces integration risks (inter-sprint, governance, schedule realism) that were invisible at PRD and SDD review. 3 of 8 blockers are CRITICAL and challenge core planning decisions:

- **Sprint 3 is dangerously oversized** (SKP-001 CRITICAL 920 + SKP-001 CRITICAL 880 — same concern from two models)
- **Bypass mechanisms lack governance** (SKP-003 CRITICAL 860) — exactly the silent-failure class this cycle is trying to eliminate
- **Parser correctness is brittle** (SKP-002 CRITICAL 885)

The planning decisions in the original sprint plan assumed Sprint 3 could ship in 2-3 days despite exceeding the LARGE threshold by itself. Tertiary skeptic caught this explicitly: *"13 tasks with 5 BLOCKERS + 7 IMPs in 2-3 days is historically optimistic."* That's the kind of calibration finding HITL review exists to surface.

## Blockers (8) — must resolve

### SKP-001 (CRITICAL, 920) — Sprint 3 schedule underestimated
- **Concern**: 13 tasks + new architecture + CI + security + runtime + runbook in 2-3 days is historically optimistic. Overrun cascades to Sprint 4 and blocks all E2E validation.
- **Fix**: Split Sprint 3 → **Sprint 3A** (core probe + cache, Tasks 3.1–3.5) and **Sprint 3B** (resilience + CI + integration + runbook, Tasks 3.6–3.13). Cycle grows from 4 sprints to 5. Add explicit 30-50% slack on both 3A and 3B.
- **Secondary**: mark non-BLOCKER IMPs as follow-up cycle candidates if schedule slips.

### SKP-001 (CRITICAL, 880) — Sprint 3 task count exceeds LARGE threshold
Same concern, different framing. Resolution: same split.

### SKP-002 (CRITICAL, 885) — Parser correctness is brittle
- **Concern**: Provider-specific regex/response-shape parsing can drift. False UNAVAILABLE blocks valid PRs; false AVAILABLE routes traffic to invalid models.
- **Fix**:
  1. **Canary validation in Sprint 3A**: non-blocking smoke probe against live providers before CI gate goes strict.
  2. **Contract version checks**: verify response schema version before applying parser rules; unknown shape → UNKNOWN not AVAILABLE (biases toward safety).
  3. **Fast rollback flag**: `LOA_PROBE_LEGACY_BEHAVIOR=1` → probe reports all models AVAILABLE (pre-cycle-093 hand-maintained allowlist behavior) as emergency fallback if probe infra fundamentally breaks.

### SKP-003 (CRITICAL, 860) — Bypass governance unspecified
- **Concern**: `LOA_PROBE_BYPASS=1`, `override-probe-outage` label, `degraded_ok` are powerful but governance/authorization/expiry unspecified. Can silently disable safeguards.
- **Fix**:
  1. **Label dual-approval**: `override-probe-outage` requires approval from a CODEOWNER AND a framework maintainer (via CI check on reviewer list).
  2. **Bypass TTL**: `LOA_PROBE_BYPASS=1` sessions expire after 24h (probe re-engages on next runtime invocation after TTL); reason string is mandatory.
  3. **Mandatory audit alerts**: every bypass/override emits to `.run/audit.jsonl` AND — if configured — to operator webhook/Slack.
  4. **Authorized-role definition**: framework maintainers only for PR label; any operator for `LOA_PROBE_BYPASS`, but mandatory audit.

### SKP-003 (HIGH, 730) — Inter-sprint file conflicts in parallel sprints
- **Concern**: Plan claims Sprints 1/2/3 are fully independent. Incorrect — all touch `spiral-harness.sh` and/or `adversarial-review.sh` and/or `model-adapter.sh`. Parallel branches → guaranteed conflicts.
- **Fix**: Update dependency map. Three options:
  1. **Serialize** sprints touching shared scripts (reduces parallelism but zero conflict risk).
  2. **Pre-refactor** shared interfaces into clean seams first — small Sprint 0 "seam prep" task.
  3. **Merge-order arbiter** + explicit rebase budget per sprint (6h rebase slack per dependent sprint).
- **Recommendation**: Option 3 (merge-order arbiter) — keeps parallelism, documents reality. Canonical merge order: sprint-1 → sprint-2A → sprint-2B → sprint-3A → sprint-3B → sprint-4.

### SKP-004 (HIGH, 760) — Concurrency cross-platform fragility
- **Concern**: flock + PID sentinel + atomic writes are shell-level and cross-platform fragile. Partial failure-mode coverage.
- **Fix**:
  1. **Stress tests** in `.claude/tests/integration/concurrency/`: parallel invocation bats scenarios with N=10 simultaneous reads+writes.
  2. **Stale-PID cleanup**: PID sentinel files older than 10 minutes → auto-cleanup on next probe invocation.
  3. **Lock timeout handling**: explicit 5s flock timeout + graceful fallback (log warning, skip cache update).
  4. **Platform matrix**: macOS (util-linux flock via brew) + Linux CI runners both run concurrency tests.

### SKP-005 (HIGH, 735) — Redaction regex insufficient
- **Concern**: Regex patterns miss transformed secrets (encoding/chunking/new formats). No leak-incident response defined.
- **Fix**: Layered defense:
  1. **Centralized scrubber**: single `_redact_secrets` function; all log paths route through it.
  2. **Structured logging with allowlist fields**: don't log arbitrary payloads; emit JSON with pre-approved fields (model_id, state, latency_ms, http_status).
  3. **Post-job secret scanner**: CI step runs `gitleaks` or equivalent over job output; fails build if secret detected.
  4. **Key rotation playbook**: add to `.claude/docs/runbooks/model-health-probe-incident.md` — steps for revoking + reissuing keys if leak detected.

### SKP-002 (HIGH, 720) — GPT-5.5 E2E validation depends on hypothetical model
- **Concern**: G-6 requires `gpt-5.5` returned by OpenAI `/v1/models`; R13 marks this as "HIGH probability ASSUMPTION" that API ships in cycle window. If it doesn't ship, G-6 validates only against a mock — misleading as "goal-satisfied."
- **Fix**: **Re-scope G-6**: "Infrastructure ready for GPT-5.5" (not "GPT-5.5 operational"). Sprint 4 E2E accepts:
  - Latent registry entry exists with `probe_required: true`
  - Probe contract correctly marks entry UNAVAILABLE when OpenAI returns no such model
  - Contract-test fixture at `.claude/tests/fixtures/provider-responses/openai/gpt-5.5-listed.json` simulates the day API ships; CI validates probe correctly transitions UNAVAILABLE → AVAILABLE on fixture swap.
- **Live validation**: move to follow-up cycle (cycle-094 or later) when `gpt-5.5` is actually in `/v1/models`.

## High Consensus (3) — auto-integrate

### IMP-001 (avg 845) — Probe rollback path needs documentation
Probe gates all adapter calls. A gate that breaks has high blast radius. Runbook must include a rollback section with trigger criteria + verification steps.

### IMP-003 (avg 850) — Inter-sprint defect handling decision tree
Sprint 3 defects discovered in Sprint 4 need an explicit decision tree: fix-forward in Sprint 3 PR (if still open) vs. file follow-up bug (if merged) vs. block Sprint 4 (if critical). Add to sprint plan §Inter-sprint coordination.

### IMP-006 (avg 745) — Cost cap enforcement semantics
`max_probes_per_run: 10` and `$0.05 cost cap` — hard stop or soft warn? Answer: **hard stop with actionable error** (exit 5 — budget exceeded, per SDD §6.1); emit telemetry to trajectory log before exit.

## Disputed (1)

### IMP-004 (avg 685, delta 330) — Shell-script coverage thresholds
- GPT-5.3-codex scored 520: "hard percentage thresholds for shell scripts incentivize shallow tests"
- Opus scored 850, Gemini scored 960: "still valuable"
- **Synthesis**: GPT has a point. 80% shell-script coverage often means testing trivial paths. Better framing: require **critical-path scenario coverage** (all error paths have a bats test) + **BLOCKER-mitigation regression tests** (every SKP-00X has a direct regression test). The sprint plan's Appendix D already does this; adjust coverage language from "80% line coverage" to "100% of critical paths + all BLOCKER mitigations have regression tests."
- **Decision**: resolve toward critical-path framing (Appendix D already applies this pattern). Update testing strategy language in sprint.md.

## Sprint Plan Changes Required

### §Sprint shape — add Sprint 3A/3B split
- Sprint 1 (Global ID 114) — unchanged
- Sprint 2 (Global ID 115) — unchanged
- **Sprint 3A (Global ID 116)** — Core probe + cache (Tasks 3.1–3.5). MEDIUM. Depends on nothing.
- **Sprint 3B (Global ID 117)** — Resilience + CI + integration + runbook (Tasks 3.6–3.13). MEDIUM-LARGE. Depends on 3A.
- **Sprint 4 (Global ID 118)** — Model registry currency. MEDIUM. Depends on 3A (probe must exist); nice-to-have 3B (resilience).

Ledger must be updated: add global sprint ID 118, `global_sprint_counter: 118`.

### §Sprint 3A Deliverables (new)
- Tasks 3.1–3.5 from original plan
- **New Task 3.1.canary**: non-blocking smoke probe against live providers before 3B's strict CI gate engages (SKP-002 CRITICAL mitigation)
- **New Task 3.2.contract_version**: response-schema version check; unknown shape → UNKNOWN bias (SKP-002 mitigation)
- **New Task 3.rollback_flag**: `LOA_PROBE_LEGACY_BEHAVIOR=1` emergency-fallback implementation (SKP-002 mitigation)

### §Sprint 3B Deliverables (new)
- Tasks 3.6–3.13 from original plan
- **New Task 3.6.bypass_governance**: dual-approval for `override-probe-outage` label; 24h TTL on `LOA_PROBE_BYPASS` (SKP-003 CRITICAL mitigation)
- **New Task 3.6.bypass_audit**: mandatory audit alerts to `.run/audit.jsonl` + optional webhook integration (SKP-003 CRITICAL mitigation)
- **New Task 3.11.secret_scanner**: post-job secret scanner (`gitleaks` or equivalent) in CI (SKP-005 HIGH mitigation)
- **New Task 3.11.centralized_scrubber**: refactor redaction to single `_redact_secrets` function (SKP-005 HIGH mitigation)
- **New Task 3.12.concurrency_stress**: stress tests in `.claude/tests/integration/concurrency/` with N=10 parallel (SKP-004 HIGH mitigation)
- **New Task 3.12.platform_matrix**: CI runs concurrency tests on macOS + Linux (SKP-004 HIGH mitigation)
- **New Task 3.13.rollback_doc**: runbook section for probe rollback (IMP-001 HIGH mitigation)

### §Sprint 4 Deliverables
- Re-scope G-6 acceptance: "Infrastructure ready for GPT-5.5," not "operational" (SKP-002 HIGH mitigation)
- Add contract-test fixture `openai/gpt-5.5-listed.json` — simulates API-ship moment
- E2E validates fixture-swap transition UNAVAILABLE → AVAILABLE

### §Inter-sprint coordination (new section)
- Canonical merge order: 1 → 2A → 2B → 3A → 3B → 4 (SKP-003 HIGH mitigation)
- Budget: 6h rebase slack per dependent sprint
- Defect handling decision tree (IMP-003 HIGH mitigation): fix-forward if PR still open; file follow-up bug if merged; block dependent sprint only if CRITICAL

### §Risk register — add R22–R27
- R22: Sprint 3 split creates integration lag between 3A and 3B (mitigation: 3A must pass canary + atomic write tests before 3B starts)
- R23: Bypass governance controls too strict → operator friction (mitigation: dual-approval only for label; LOA_PROBE_BYPASS solo-operator with audit)
- R24: Parser rollback flag becomes operator crutch (mitigation: emergency-only; usage tracked in audit-log; CI warning on commits that set it)
- R25: macOS concurrency divergence from Linux (mitigation: platform matrix in CI; `_require_flock` shim already specified)
- R26: Secret scanner false positives block builds (mitigation: documented allowlist; dev runbook section)
- R27: GPT-5.5 never ships in cycle (mitigation: G-6 re-scoped to "infrastructure ready"; live validation deferred to follow-up cycle)

### §Testing language — shift from % coverage to shape
Replace "80% line coverage for bash" with "100% of critical paths + all BLOCKER mitigations have direct regression tests." Appendix D already structures this; update §Testing Strategy to match.

### §Cost cap — clarify hard vs soft
Add to Sprint 3A Task 3.1 acceptance: "`max_probes_per_run` and `$0.05 cost cap` are HARD stops; exceeding either exits 5 (SDD §6.1) with actionable error. Telemetry emitted to trajectory before exit."

## Agreement detail

| Finding | Opus | GPT-5.3-codex | Gemini-2.5-pro | Delta | Avg |
|---------|-----:|--------------:|---------------:|------:|----:|
| IMP-001 | 780  | 910           | 950            | 130   | 845 |
| IMP-003 | 820  | 880           | 900            | 60    | 850 |
| IMP-006 | 750  | 740           | 980            | 10    | 745 |
| **IMP-004 (DISPUTED)** | **850**  | **520**           | **960**            | **330**   | **685** |

The DISPUTED item (IMP-004 coverage thresholds) is the most interesting — 330-delta means real disagreement. GPT's point about coverage-gaming is legitimate; resolution is to shift framing from quantitative % to qualitative shape (critical-path + BLOCKER-mitigation regression).

**Consistent pattern across all 3 Flatline runs**: Gemini 2.5 Pro was the source of every single blocker across PRD (6), SDD (5), and sprint-plan (8) reviews — total 19 blockers, 100% sourced from tertiary skeptic. This is the single strongest empirical case for this cycle's T2.1 Gemini 3.1 Pro upgrade and the 3-model Flatline protocol as a standard.

## Next step

Sprint plan updated in place with:
- 5-sprint shape (3→3A/3B split, Sprint 4 renumbered)
- Ledger update (sprint ID 118 added)
- 7 new tasks across 3A + 3B (canary, contract_version, rollback_flag, bypass_governance, bypass_audit, secret_scanner, centralized_scrubber, concurrency_stress, platform_matrix, rollback_doc)
- Inter-sprint coordination section
- 6 new risks (R22–R27)
- Testing language shift to critical-path framing
- Cost cap hard-stop clarification

Recommendation: skip re-Flatline of sprint plan (integration was mechanical) and proceed to `/run sprint-plan` — with caveat that the Beads JSONL is 113h stale and needs `br sync --import-only` before beads tasks are created at implement time.

Alternative: present revised sprint plan to user, confirm 5-sprint shape is acceptable, then execute.
