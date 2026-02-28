# Sprint Plan: Review Pipeline Hardening

> **Cycle**: 045
> **Created**: 2026-02-28
> **PRD**: `grimoires/loa/prd.md`
> **SDD**: `grimoires/loa/sdd.md`
> **Target**: `.claude/` System Zone (scripts, skills, data) + `.loa.config.yaml`

---

## Sprint Overview

This cycle has **3 sprints** with clear dependency ordering.

| Sprint | Label | Focus | Dependency |
|--------|-------|-------|------------|
| 1 | Gemini Verification + State Schema | FR-1 (Flatline observability) + FR-2 (state schema) | None |
| 2 | Red Team Code-vs-Design | FR-3 (new gate in run loop) | Sprint 1 (config patterns) |
| 3 | Observability + Hardening | FR-4 (observability) + integration testing + backward compat | Sprint 2 |

---

## Sprint 1: Gemini Verification + State Schema

**Goal**: Make Gemini participation in Flatline observable, and wire sub-phase state tracking into simstim.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T1.1 | Add `tertiary` model key to `.loa.config.yaml` under `flatline_protocol.models` | `flatline_protocol.models.tertiary: gemini-2.5-pro` added. Placed after `secondary:` key. |
| T1.2 | Add tertiary model logging to `flatline-orchestrator.sh` | During Phase 1 setup, log line: `"Tertiary model: gemini-2.5-pro (active)"` or `"Tertiary model: none (disabled)"`. Read from `flatline_protocol.models.tertiary` config key. |
| T1.3 | Add `tertiary_model_used` field to Flatline output JSON in `flatline-orchestrator.sh` | After Phase 3 consensus, output JSON includes `"tertiary_model_used": "gemini-2.5-pro"` (or `null` when disabled) and `"tertiary_status": "active"` / `"disabled"`. |
| T1.4 | Add `bridgebuilder_sdd`, `red_team_sdd`, `flatline_beads` to state schema in `simstim-state.sh` | Lines 199-208 jq template extended inline with 3 new keys. Insert `bridgebuilder_sdd` after `architecture` line, `red_team_sdd` after `flatline_sdd` line, `flatline_beads` after `flatline_sprint` line. Skip logic: `bridgebuilder_sdd` uses same condition as `architecture`, `red_team_sdd` uses same condition as `flatline_sdd`, `flatline_beads` uses same condition as `flatline_sprint`. All default to `"pending"`. Validate with `jq '.' <<< "$output"` after generation. |
| T1.5 | Add `red_team.code_vs_design` config section to `.loa.config.yaml` | Section added with: `enabled: false`, `max_cycles: 2`, `skip_if_no_sdd: true`, `severity_threshold: 700`, `token_budget: 150000`. Placed under existing `red_team:` section. |

**Exit Criteria**: Config has tertiary model + code-vs-design section. Flatline orchestrator logs tertiary status. State schema includes all 3 sub-phases.

---

## Sprint 2: Red Team Code-vs-Design

**Goal**: Create the Red Team code-vs-design gate and wire it into the run mode sprint loop.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T2.1 | Create `.claude/scripts/red-team-code-vs-design.sh` | Script accepts `--sdd <path>`, `--diff <file>`, `--output <path>`, `--sprint <id>`, `--token-budget <n>`, and `--dry-run` flags. Token budget read from config `red_team.code_vs_design.token_budget` (default 150000) and passed to `model-adapter.sh --max-tokens`. Extracts SDD security sections via header regex. Generates comparison prompt. Invokes model-adapter.sh. Produces findings JSON with CONFIRMED_DIVERGENCE / PARTIAL_IMPLEMENTATION / FULLY_IMPLEMENTED categories. |
| T2.2 | SDD section extraction in `red-team-code-vs-design.sh` | Regex: `/^#{1,3}\s.*(Security\|Authentication\|Authorization\|Validation\|Error.Handling\|Access.Control\|Secrets\|Encryption)/i`. Extracts content under matched headers until next same-or-higher-level header. Truncates to 5K tokens if large. |
| T2.3 | Findings JSON output format | Output matches SDD §2.3.2: `{ findings: [{id, sdd_section, sdd_requirement, code_evidence, classification, severity, recommendation}], summary: {total, confirmed_divergence, partial_implementation, fully_implemented} }`. Written to `grimoires/loa/a2a/sprint-{N}/red-team-code-findings.json`. |
| T2.4 | Wire RED_TEAM_CODE phase into `.claude/skills/run/SKILL.md` main loop | After audit-sprint passes, if `red_team.code_vs_design.enabled: true` AND SDD exists: invoke `red-team-code-vs-design.sh`. If CONFIRMED_DIVERGENCE findings with severity > `severity_threshold`: record cycle, check circuit breaker, continue loop. State tracking: `red_team_code.cycles`, `red_team_code.max_cycles: 2`. |
| T2.5 | Circuit breaker for Red Team code-vs-design | Separate counter from main circuit breaker. After `max_cycles` (default 2) red-team-code iterations, auto-skip with warning: "Red Team code-vs-design max cycles reached, skipping." Log to `.run/state.json`. |
| T2.6 | `skip_if_no_sdd: true` handling | When SDD doesn't exist at `grimoires/loa/sdd.md` (or config-specified path) and `skip_if_no_sdd: true`: skip silently. When `false`: error and halt. |

**Exit Criteria**: `red-team-code-vs-design.sh` produces parseable findings JSON. Run loop invokes it after audit. Circuit breaker limits re-implementation cycles.

---

## Sprint 3: Observability + Hardening

**Goal**: Make pipeline status visible, add backward compatibility tests, and verify end-to-end.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T3.1 | Flatline model count reporting in `flatline-orchestrator.sh` | After consensus, log: `"Flatline: 3-model (opus + gpt-5.3-codex + gemini-2.5-pro)"` or `"Flatline: 2-model (opus + gpt-5.3-codex)"`. |
| T3.2 | Simstim phase count display in `SKILL.md` | At preflight, compute total phases: base 8 + enabled sub-phases (bridgebuilder_sdd, red_team_sdd, flatline_beads). Display: `[0/11] PREFLIGHT` or `[0/8] PREFLIGHT`. Store `total_phases` in simstim state. |
| T3.3 | Backward compat: 2-model Flatline when no tertiary | Verify that when `flatline_protocol.models.tertiary` is not set, output includes `"tertiary_model_used": null` and scoring uses 2-model path. No behavioral change from pre-cycle-045. |
| T3.4 | Backward compat: simstim without sub-phases | Verify that when bridgebuilder + red_team + beads config gates are all false, simstim runs 8-phase sequence with sub-phases marked `"skipped"` in state. No extra time or output. |
| T3.5 | Backward compat: run loop without code-vs-design | Verify that when `red_team.code_vs_design.enabled: false`, run loop goes implement → review → audit → COMPLETE with no RED_TEAM_CODE phase. |
| T3.6 | State file auto-upgrade test | Load a pre-cycle-045 simstim state file (missing sub-phase keys). Verify SKILL.md handles null/missing keys as `"pending"` without errors. |
| T3.7 | Create `flatline-3model.sh` eval test | Integration test that: (a) skips when GOOGLE_API_KEY not set, (b) runs flatline with tertiary configured, (c) verifies `models: 3` and `tertiary_model_used: "gemini-2.5-pro"` in output. |

**Exit Criteria**: All observability additions active. Backward compatibility verified for all 3 features. Eval test created.

---

## Cross-Cutting Concerns

### File Safety

All modified files are in `.claude/` (System Zone) or `.loa.config.yaml`. Per Three-Zone Model, System Zone writes are made by the `/implement` skill. No application code is modified.

### Backward Compatibility

- Gemini tertiary is additive — 2-model Flatline unchanged when tertiary not configured
- State schema additions are backward-compatible — missing keys treated as `"pending"`
- Red Team code-vs-design defaults to `false` — run loop unchanged when disabled
- PHASES array in `simstim-orchestrator.sh` is NOT modified

### Risk Registry

| Risk | Sprint | Mitigation |
|------|--------|------------|
| State schema jq template malformed | 1 | Insert keys inline in correct order; test with `jq '.'` validation |
| Flatline tertiary config breaks 2-model mode | 1 | T3.3 backward compat test |
| Red Team code-vs-design false positives | 2 | severity_threshold: 700 + max_cycles: 2 circuit breaker |
| SDD section extraction misses security content | 2 | Regex covers 8 common security header patterns |
| State file upgrade breaks resume | 3 | T3.6 auto-upgrade test |
