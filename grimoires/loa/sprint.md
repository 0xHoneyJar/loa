# Sprint Plan: Flatline Red Team — Evolution Phase

> Source: Bridgebuilder Review of PR [#317](https://github.com/0xHoneyJar/loa/pull/317), SDD cycle-012
> Cycle: cycle-012 (continued)
> Previous Sprints: 1-3 (global 79-81) — Foundation phase complete
> New Sprints: 4-6 (global 82-84) — Evolution phase
> Bridge Review Insights: 3 Bridgebuilder deep-dive comments with forward-looking observations

## Evolution Context

The foundation phase (sprints 1-3) shipped the red team pipeline skeleton: templates, schema, sanitizer, scoring engine, report generator, retention, and skill registration. The bridge loop (4 iterations, 19 findings fixed, flatline achieved) validated the mechanical correctness.

The Bridgebuilder review identified the gap between the current v1 (placeholder model invocations, hardcoded thresholds, 10-entry golden set) and a production-ready system that can operate with real multi-model adversarial diversity. These sprints close that gap.

### Key Improvement Areas (from Bridgebuilder Review)

1. **Documentation drift** — SKILL.md consensus criteria table doesn't match scoring engine behavior
2. **Golden set THEORETICAL gap** — Self-test can't reach the THEORETICAL category (most important for multi-model)
3. **Golden set scaling** — 10 entries insufficient for heterogeneous model calibration
4. **Budget enforcement** — `rt_token_budget` is dead code, never wired to pipeline
5. **Attack surface generality** — Registry is Loa-specific, no graceful degradation for other projects
6. **Inter-model sanitization** — Phase 1 output fed raw to Phase 2 creates confused deputy surface
7. **Hounfour integration prep** — Model adapter hooks needed for cheval.py integration
8. **Scoring engine configurability** — Thresholds hardcoded, config override deferred

---

## Sprint 4: Documentation Alignment + Golden Set Maturity

**Goal**: Fix documentation drift, extend golden set to cover THEORETICAL path, add compositional vulnerability entries, and make scoring engine thresholds configurable.

### Task 4.1: Fix SKILL.md Consensus Criteria Documentation Drift

**File**: `.claude/skills/red-teaming/SKILL.md`

The consensus criteria table (lines 57-58) still says:
- THEORETICAL: "One model >700, other <400"
- CREATIVE_ONLY: "Both <400 but novel"

The actual scoring engine behavior (and the schema, fixed in bridge iter-1):
- THEORETICAL: "One model >700, other ≤700" (i.e., any case where models disagree significantly)
- CREATIVE_ONLY: "Neither model >700" (i.e., no model finds it convincing)

The distinction matters: an attack where GPT scores 650 and Opus scores 750 is currently THEORETICAL (one is >700), but the SKILL.md documentation would suggest it's neither THEORETICAL (<400 threshold) nor CONFIRMED (both >700).

**Acceptance Criteria**:
- SKILL.md consensus table matches scoring engine `classify_attack()` logic
- All 4 categories described with precise threshold boundaries
- Example score pairs for each category included for clarity

### Task 4.2: Add THEORETICAL Path Entries to Golden Set

**File**: `.claude/data/red-team-golden-set.json`

The current self-test uses `severity_score` as both GPT and Opus scores, meaning both models always agree. This makes THEORETICAL (model disagreement) unreachable.

Add 3-5 new entries with separate `expected_gpt_score` and `expected_opus_score` fields:
- ATK-911: An ambiguous scenario where sophisticated reasoning finds a real threat (one model scores 800, other scores 400)
- ATK-912: A domain-specific attack that requires Web3 knowledge (model with more Web3 training scores higher)
- ATK-913: A subtle confused deputy scenario where the threat is real but non-obvious (split opinion)

These entries must also include `expected_consensus: "THEORETICAL"` for self-test verification.

**Acceptance Criteria**:
- Golden set has 13-15 entries (5 confirmed, 5 implausible, 3-5 theoretical)
- Self-test updated to accept per-model score fields
- `--self-test` now verifies all 3 reachable consensus categories
- New entries focus on ambiguity by design, not arbitrary score assignment

### Task 4.3: Add Compositional Vulnerability Entries to Golden Set

**File**: `.claude/data/red-team-golden-set.json`

The Bridgebuilder identified compositional vulnerabilities (attacks that emerge from the interaction of independently-correct subsystems) as the most important category the system should amplify. ATK-905 (flash loan) is the only current example.

Add 3-4 more compositional entries:
- Scenarios where two subsystems are correct in isolation but create vulnerabilities at their boundary
- Inspired by real-world composites: DAO reentrancy, Compound governance, OAuth redirect chain
- Mark these with `"compositional": true` field for future filtering

**Acceptance Criteria**:
- 3-4 new compositional entries with `compositional: true` flag
- Each entry identifies the specific subsystem interaction that creates the vulnerability
- `assumption_challenged` field explicitly names the composition assumption
- Entries are realistic (severity 650-900) and would generate actionable counter-designs

### Task 4.4: Make Scoring Engine Thresholds Configurable

**File**: `.claude/scripts/scoring-engine.sh`

Currently hardcodes thresholds:
```bash
local HIGH_CONSENSUS=700
local DISPUTE_DELTA=300
local LOW_VALUE=400
local BLOCKER=700
```

Read from config with fallback to hardcoded defaults:

```bash
local HIGH_CONSENSUS=$(yq '.red_team.thresholds.confirmed_attack // 700' "$CONFIG" 2>/dev/null || echo 700)
```

**Acceptance Criteria**:
- All 4 thresholds read from `.loa.config.yaml` with defaults
- `--self-test` still passes with default thresholds
- `--self-test` respects custom thresholds if configured
- Config path uses existing `CONFIG_FILE` variable pattern from other scripts

---

## Sprint 5: Budget Enforcement + Inter-Model Safety

**Goal**: Wire budget enforcement into the pipeline, add inter-model sanitization to prevent confused deputy within the evaluation pipeline, and make attack surfaces gracefully degrade for non-Loa projects.

### Task 5.1: Wire Budget Enforcement into Pipeline

**Files**: `.claude/scripts/red-team-pipeline.sh`, `.claude/scripts/red-team-report.sh`

The `rt_token_budget` variable is computed per execution mode but never checked during execution. When real model invocations happen (Hounfour), this is a $50 surprise waiting to happen.

Wire the budget:
- Pipeline accepts `--budget` and passes to each phase
- Each phase returns tokens consumed in its output JSON
- Pipeline accumulates `tokens_used` and checks against `budget` before each phase
- If budget exceeded, pipeline completes current phase but skips remaining phases
- Final result JSON includes `budget_exceeded: true` and `budget_consumed` vs `budget_limit`
- Report shows budget status in metrics section

**Acceptance Criteria**:
- Pipeline tracks cumulative tokens consumed across phases
- Budget check runs before each phase (not mid-phase)
- Exceeding budget produces a complete result (not an error) with truncation warning
- `budget_exceeded` field in output JSON when limit hit
- Metrics section in report shows consumed vs limit

### Task 5.2: Add Inter-Model Sanitization

**File**: `.claude/scripts/red-team-pipeline.sh`

When Phase 1 generates attack scenarios, those scenarios are prompts fed to Phase 2 for evaluation. A sufficiently adversarial attack scenario could contain instructions that influence the evaluating model's judgment — the confused deputy problem *within the pipeline itself*.

Add sanitization between phases:
- Phase 1 output → sanitize (strip instruction patterns, validate JSON structure) → Phase 2 input
- Reuse existing `red-team-sanitizer.sh` with a new `--inter-model` flag
- Inter-model mode: lighter than full sanitization (skip UTF-8 and secret scanning, focus on injection patterns and JSON structure validation)
- Log any inter-model sanitization triggers (these indicate the attack generator produced instruction-like content)

**Acceptance Criteria**:
- Phase 1 output passes through sanitizer before Phase 2 consumption
- `--inter-model` flag on sanitizer skips expensive checks but catches injection patterns
- Sanitization triggers are logged with source phase and attack ID
- Pipeline continues after inter-model sanitization (log, don't block)
- Self-test validates inter-model path doesn't corrupt valid attack JSON

### Task 5.3: Attack Surface Graceful Degradation

**File**: `.claude/scripts/red-team-pipeline.sh`

The attack surfaces registry contains Loa-specific surfaces (agent-identity, token-gated-access, etc.). When someone runs `/red-team` against a non-Loa document, the surface context is irrelevant noise.

Add graceful degradation:
- If `--focus` categories don't match any surfaces in registry, log warning and proceed without surface context
- If no surfaces registry exists, proceed with generic attack generation (no surface filtering)
- Template rendering handles empty surface context gracefully (already does via `/dev/null` fallback, but add explicit log message)
- Consider: when surface context is empty, add a template note instructing the model to infer surfaces from the document content

**Acceptance Criteria**:
- `/red-team doc.md --focus "nonexistent"` logs warning, runs successfully with empty surface context
- Missing surfaces registry file doesn't cause pipeline error
- Template includes fallback instruction when no surfaces loaded
- Existing surface-based invocations unchanged

### Task 5.4: Pipeline Phase Timing Metrics

**File**: `.claude/scripts/red-team-pipeline.sh`

Add per-phase timing to the output JSON for performance profiling:

```json
"metrics": {
  "phase0_sanitize_ms": 120,
  "phase1_attacks_ms": 5400,
  "phase2_validation_ms": 3200,
  "phase3_consensus_ms": 80,
  "phase4_counter_design_ms": 2100,
  "total_latency_ms": 10900
}
```

This is essential for Hounfour cost optimization — knowing which phase dominates latency informs tiered routing decisions.

**Acceptance Criteria**:
- Each phase reports its duration in milliseconds
- Metrics object in final result JSON includes all phase timings
- Report generator displays phase timing breakdown
- Zero-cost when phases are placeholders (just shows near-zero times)

---

## Sprint 6: Hounfour Integration Prep + Golden Set Scaling

**Goal**: Create the model adapter interface that the Hounfour will implement, scale the golden set for multi-model calibration, and add end-to-end integration tests with mock model responses.

### Task 6.1: Create Model Adapter Interface

**File**: `.claude/scripts/red-team-model-adapter.sh`

Create a thin adapter script that Phase 1 and Phase 2 call instead of direct model invocation. This is the seam where Hounfour's `cheval.py` will plug in.

Interface:
```bash
red-team-model-adapter.sh \
  --role attacker|defender|evaluator \
  --model opus|gpt|kimi|qwen \
  --prompt-file <path> \
  --output-file <path> \
  --budget <tokens> \
  --timeout <seconds>
```

Current implementation: return mock responses from fixtures (allowing pipeline to run end-to-end without real API calls). Future: delegate to `cheval.py` via Hounfour model routing.

**Acceptance Criteria**:
- Adapter script is callable with all required flags
- Returns valid JSON matching attack/counter-design schema
- Mock mode loads fixtures from `.claude/data/red-team-fixtures/`
- `--mock` flag (default for now) uses fixture data
- `--live` flag reserved for Hounfour integration (errors with "requires cheval.py" for now)
- Exit code 0 on success, 1 on timeout, 2 on budget exceeded

### Task 6.2: Create Model Response Fixtures

**Directory**: `.claude/data/red-team-fixtures/`

Create fixture files that the model adapter returns in mock mode:

- `attacker-response-01.json`: 5 realistic attack scenarios against agent identity
- `attacker-response-02.json`: 5 realistic attack scenarios against token-gated access
- `evaluator-response-01.json`: Cross-validation scores for attacker-response-01
- `evaluator-response-02.json`: Cross-validation scores for attacker-response-02
- `defender-response-01.json`: Counter-designs for confirmed attacks

Each fixture must be valid against the red team result schema.

**Acceptance Criteria**:
- All fixture files are valid JSON
- Attack fixtures produce a mix of consensus categories when scored
- At least 2 CONFIRMED_ATTACK, 2 THEORETICAL, 1 CREATIVE_ONLY across fixtures
- Evaluator fixtures contain per-attack scores that create realistic disagreement
- Fixtures are reusable by pipeline integration tests

### Task 6.3: Wire Pipeline Phases to Model Adapter

**File**: `.claude/scripts/red-team-pipeline.sh`

Replace placeholder phase implementations with calls to the model adapter:

- `run_phase1_attacks()`: Call adapter with `--role attacker` for each model, merge results
- `run_phase2_validation()`: Call adapter with `--role evaluator` for cross-validation
- `run_phase4_counter_design()`: Call adapter with `--role defender` for synthesis

The pipeline should work end-to-end with mock fixtures, producing a complete result JSON with realistic consensus classification.

**Acceptance Criteria**:
- Pipeline runs end-to-end with `--mock` model adapter
- Output JSON has populated attack arrays (not empty placeholders)
- Consensus classification produces at least 2 categories
- Budget tracking counts fixture response sizes
- Pipeline produces a readable report with actual attack scenarios

### Task 6.4: Scale Golden Set to 30+ Entries

**File**: `.claude/data/red-team-golden-set.json`

Scale the golden set for multi-model calibration:

| Category | Current | Target | Focus |
|----------|---------|--------|-------|
| CONFIRMED (realistic) | 5 | 12 | Add compositional, supply chain, automated |
| THEORETICAL (ambiguous) | 0→3-5 (from 4.2) | 8 | Domain-specific, model-bias-dependent |
| CREATIVE_ONLY (implausible) | 5 | 8 | Update with emerging tech (quantum, AI-on-AI) |
| DEFENDED (with counter) | 0 | 4 | Known-defended patterns |

New entries should cover:
- All 5 attacker profiles (external, insider, supply_chain, confused_deputy, automated)
- All 5 attack surfaces from registry
- Cross-surface compositional attacks
- Entries designed to expose model-specific calibration biases

**Acceptance Criteria**:
- Golden set has 30+ entries across all 4 consensus categories
- `--self-test` validates all entries with 100% accuracy
- Coverage: all attacker profiles and all attack surfaces represented
- At least 5 compositional entries (`compositional: true`)
- DEFENDED entries include explicit counter-design references

---

## Sequencing and Dependencies

```
Sprint 4 (Documentation + Golden Set Maturity)
  ├── Task 4.1: SKILL.md fix (independent)
  ├── Task 4.2: THEORETICAL entries (independent)
  ├── Task 4.3: Compositional entries (independent, can parallel with 4.2)
  └── Task 4.4: Config thresholds (independent)

Sprint 5 (Budget + Safety)
  ├── Task 5.1: Budget enforcement (depends on pipeline from sprint 2)
  ├── Task 5.2: Inter-model sanitization (depends on sanitizer from sprint 1)
  ├── Task 5.3: Surface degradation (depends on pipeline from sprint 2)
  └── Task 5.4: Phase timing (depends on pipeline from sprint 2)

Sprint 6 (Hounfour Prep + Scaling)
  ├── Task 6.1: Model adapter (independent)
  ├── Task 6.2: Fixtures (depends on 6.1 interface)
  ├── Task 6.3: Wire pipeline (depends on 6.1, 6.2, and sprint 5 budget enforcement)
  └── Task 6.4: Scale golden set (depends on 4.2, 4.3 patterns)
```

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Fixture data doesn't represent real model output diversity | Design fixtures with intentional disagreement patterns; update when Hounfour provides real samples |
| Golden set growth creates maintenance burden | Group entries by category, add `last_reviewed` field, automate schema validation |
| Budget enforcement breaks existing pipeline tests | Budget is only enforced when > 0; mock mode returns 0 tokens |
| Inter-model sanitization is too aggressive | Log-only mode first; blocking requires explicit opt-in via config |

## Success Metrics

| Metric | Target |
|--------|--------|
| Golden set coverage | 30+ entries, all 4 categories, all 5 profiles |
| Self-test accuracy | 100% across all golden set entries |
| Pipeline end-to-end | Runs with mock adapter, produces readable report |
| Budget enforcement | Pipeline stops cleanly when budget exceeded |
| Documentation alignment | SKILL.md matches scoring engine exactly |
| Phase timing | All 5 phases report latency in output JSON |
