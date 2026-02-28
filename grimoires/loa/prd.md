# PRD: Review Pipeline Hardening — Gemini Activation, Orchestrator Wiring, Red Team Post-Implementation

> Cycle-045 | Created: 2026-02-28
> Sources: User investigation, codebase research (3 parallel agents), .loa.config.yaml, simstim-orchestrator.sh, SKILL.md

## 1. Problem Statement

Three review pipeline components exist in specification but fail to execute in practice:

1. **Gemini in Flatline**: Fully configured (API, orchestrator, scoring) but a Phase 3 consensus bug silently dropped tertiary results until cycle-040 fix. Downstream repos (loa-finn, loa-hounfour, loa-freeside, loa-dixie) likely haven't pulled the fix. No verification mechanism exists to confirm 3-model operation.

2. **Red Team Phase 4.5 + Bridgebuilder Phase 3.5 in Simstim**: Both phases are fully specified in SKILL.md but neither appears in `simstim-orchestrator.sh` PHASES array (line 41) or `simstim-state.sh` state schema (lines 199-207). Even with config enabled, the orchestrator never reaches the phase check code.

3. **No post-implementation security design verification**: Audit-sprint checks for implementation security (OWASP, secrets, injection), but nothing verifies that the SDD's security design was actually implemented as specified. A new Red Team Code-vs-Design gate after audit would catch design-to-code divergence.

> Sources: simstim-orchestrator.sh:41-42, simstim-state.sh:199-207, .loa.config.yaml:169-210, SKILL.md:224-476, bug-flatline-3model triage

## 2. Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| Gemini participates in Flatline | 3 model results in consensus output | 100% of Flatline runs when `flatline_tertiary_model` is set |
| Phase 3.5 + 4.5 execute when enabled | State file shows `bridgebuilder_sdd: completed` and `red_team_sdd: completed` | First successful simstim run with both enabled |
| Red Team code-vs-design catches divergence | At least 1 CONFIRMED_DIVERGENCE in test SDD+code scenario | Demonstrated in eval |
| Zero regression in existing pipeline | All existing evals pass | framework eval: ALL PASS |

## 3. User & Stakeholder Context

**Primary user**: Loa framework operators running `/simstim` and `/run-bridge` workflows across the 5-repo ecosystem.

**Pain point**: "I have never noticed Gemini actually participate" and "never noticed evidence that the red team process has been actually being used" — invisible quality gates create false confidence.

**Stakeholder requirement**: Progressive rollout with config gates (default off). Existing workflows must not break.

## 4. Functional Requirements

### FR-1: Gemini Flatline Verification (P0)

**Objective**: Confirm 3-model Flatline operation and provide observable evidence.

| Requirement | Details |
|-------------|---------|
| FR-1.1 | Add `tertiary_model_used` field to Flatline output JSON showing which tertiary model ran |
| FR-1.2 | Add eval test that verifies 3-model consensus output when `flatline_tertiary_model` is configured. Test skips gracefully when `GOOGLE_API_KEY` is not set (integration test, not unit test). |
| FR-1.3 | Log a visible line during Flatline: "Tertiary model: gemini-2.5-pro (active)" or "Tertiary model: none (disabled)" |

**Acceptance criteria**: Running `/flatline-review` with gemini configured produces output JSON with `tertiary_model_used: "gemini-2.5-pro"` and 3-model cross-scores.

### FR-2: Simstim Orchestrator Wiring — Phase 3.5 + 4.5 (P0)

**Objective**: Wire Bridgebuilder Design Review (3.5) and Red Team SDD (4.5) into the simstim orchestrator and state schema.

| Requirement | Details |
|-------------|---------|
| FR-2.1 | Verify `bridgebuilder_sdd` and `red_team_sdd` use the **sub-phase pattern** (SKILL.md config gates) — do NOT add to `PHASES` array in `simstim-orchestrator.sh`. Consistent with Phase 6.5 (flatline_beads) pattern. |
| FR-2.2 | Add `bridgebuilder_sdd` and `red_team_sdd` to state schema in `simstim-state.sh` (lines 199-207) with default `"pending"` |
| FR-2.3 | Wire sub-phase execution: SKILL.md Phase 3 completion checks config gate → runs Phase 3.5 inline → proceeds to Phase 4. Similarly Phase 4 → 4.5 → Phase 5. |
| FR-2.4 | Handle `--from` flag: `--from bridgebuilder_sdd` and `--from red_team_sdd` must work for resume via jump table in SKILL.md |
| FR-2.5 | Both phases skip silently when their config gates are false (no warning, no delay) |
| FR-2.6 | State file tracks sub-phase status: `bridgebuilder_sdd` and `red_team_sdd` keys appear in phases object regardless of whether they execute (set to `"skipped"` when disabled) |

**Acceptance criteria**: Running `/simstim` with `bridgebuilder_design_review.enabled: true` and `red_team.simstim.auto_trigger: true` produces state file with both phase entries showing `completed`. The `PHASES` array in `simstim-orchestrator.sh` remains UNCHANGED.

### FR-3: Red Team Code-vs-Design Gate (P1)

**Objective**: Add optional Red Team verification after audit-sprint in the `/run` sprint loop that checks whether SDD security design was implemented.

| Requirement | Details |
|-------------|---------|
| FR-3.1 | New phase `RED_TEAM_CODE` in `/run` cycle loop, after audit-sprint passes |
| FR-3.2 | Only triggers when: SDD exists AND `red_team.code_vs_design.enabled: true` AND audit-sprint passed |
| FR-3.3 | Compares SDD security sections to actual code diff, producing findings categorized as: CONFIRMED_DIVERGENCE, PARTIAL_IMPLEMENTATION, FULLY_IMPLEMENTED |
| FR-3.4 | CONFIRMED_DIVERGENCE findings feed back into the implement cycle (same as review/audit findings) |
| FR-3.5 | Config section: `red_team.code_vs_design.enabled: false` (default off), `red_team.code_vs_design.skip_if_no_sdd: true` |
| FR-3.6 | Circuit breaker: max 2 red-team-code cycles before auto-skip (prevents infinite security loops) |

**Acceptance criteria**: Running `/run sprint-1` with code-vs-design enabled and an SDD that specifies "all API inputs validated via schema" while the code has unvalidated inputs produces a CONFIRMED_DIVERGENCE finding.

### FR-4: Observability Improvements (P2)

**Objective**: Make all review pipeline components visibly active or inactive.

| Requirement | Details |
|-------------|---------|
| FR-4.1 | `/loa` status command shows which review gates are active/inactive with config state |
| FR-4.2 | Simstim displays phase count including optional phases: "[0/10] PREFLIGHT" when 3.5 + 4.5 enabled, "[0/8] PREFLIGHT" when disabled |
| FR-4.3 | Bridge loop reports model count: "Flatline: 3-model (opus + gpt-5.3 + gemini-2.5-pro)" |

## 5. Technical & Non-Functional Requirements

| NFR | Target |
|-----|--------|
| NFR-1: Backward compatibility | All existing workflows produce identical output when new features are disabled (default) |
| NFR-2: Token budget | Red Team code-vs-design: max 150K tokens per invocation |
| NFR-3: Performance | Phase 3.5 + 4.5 add max 5 minutes to simstim wall-clock time when enabled |
| NFR-4: Config isolation | Each feature independently toggleable — enabling Red Team code-vs-design does not require enabling Phase 4.5 |
| NFR-5: State schema migration | Existing `.run/simstim-state.json` files without new phases must be handled gracefully (auto-upgrade) |

## 6. Scope & Prioritization

### In Scope (P0)

- FR-1: Gemini Flatline verification + observability
- FR-2: Orchestrator wiring for Phase 3.5 + 4.5

### In Scope (P1)

- FR-3: Red Team code-vs-design gate in sprint loop

### In Scope (P2)

- FR-4: Observability improvements

### Out of Scope

- Red Team in bridge loop (research concluded: redundant with Bridgebuilder + audit)
- Gemini as Flatline primary model (remains tertiary)
- Cross-repo Flatline fix propagation (downstream repos pull independently)
- New attack surface definitions for Red Team (uses existing `attack-surfaces.yaml`)

## 7. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Orchestrator wiring breaks existing phase transitions | Medium | High | Eval tests cover all existing phase sequences; conditional insertion only when config enabled |
| Red Team code-vs-design produces false positives | High | Medium | CONFIRMED_DIVERGENCE requires >700 severity from both models; human review gate for >800 |
| Gemini API rate limits during Flatline | Low | Medium | Existing retry logic in model-adapter.sh; fallback to 2-model if tertiary fails |
| State schema migration breaks resume | Medium | Medium | Auto-upgrade path: missing phases default to "skipped" status |

## 8. Architecture Hints

### Sub-Phase Pattern (Established)

The `PHASES` array in `simstim-orchestrator.sh` (line 41) is NOT modified. Phase 3.5, 4.5, and 6.5 all use the **sub-phase pattern**: execution is driven by SKILL.md config gates, not by array position. This avoids index-shift breakage and is consistent with how Phase 6.5 (flatline_beads) already works.

```
PHASES array (unchanged): preflight → discovery → flatline_prd → architecture → flatline_sdd → planning → flatline_sprint → implementation
Sub-phases (SKILL.md):    architecture → [3.5 bridgebuilder_sdd?] → flatline_sdd → [4.5 red_team_sdd?] → planning
```

State schema adds `bridgebuilder_sdd` and `red_team_sdd` keys (defaulting to `"pending"`, set to `"skipped"` when disabled).

### Red Team Code-vs-Design Integration

Extends the `/run` main loop:
```
while circuit_breaker.state == CLOSED:
  1. /implement → 2. commit → 3. /review-sprint
  4. if has_findings: continue
  5. /audit-sprint
  6. if has_findings: continue
  7. if red_team.code_vs_design.enabled AND sdd_exists:
       /red-team-code → if has_divergence: continue
  8. COMPLETE
```

> Sources: User answers (all three workstreams, sprint loop after audit), simstim-orchestrator.sh:41-42, run skill SKILL.md main loop
