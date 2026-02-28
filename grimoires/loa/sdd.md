# SDD: Review Pipeline Hardening — Gemini Activation, Orchestrator Wiring, Red Team Post-Implementation

> **Cycle**: 045
> **Created**: 2026-02-28
> **PRD**: `grimoires/loa/prd.md`
> **Target**: `.claude/` System Zone (scripts, skills, data) + `.loa.config.yaml`

---

## 1. System Architecture

### 1.1 Component Map

```
┌─────────────────────────────────────────────────────────────┐
│                    Simstim Workflow                          │
│                                                             │
│  PHASES array (UNCHANGED):                                  │
│  preflight → discovery → flatline_prd → architecture →      │
│  flatline_sdd → planning → flatline_sprint → implementation │
│                                                             │
│  Sub-phases (SKILL.md driven):                              │
│  architecture → [3.5]? → flatline_sdd → [4.5]? → planning  │
│                  │                        │                  │
│                  ▼                        ▼                  │
│         bridgebuilder_sdd          red_team_sdd              │
│         (existing Phase 3.5)       (existing Phase 4.5)      │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                    Run Mode Loop                             │
│                                                             │
│  implement → review → audit → [RED_TEAM_CODE]? → COMPLETE   │
│                                    │                         │
│                                    ▼                         │
│                           Red Team Code-vs-Design            │
│                           (NEW — FR-3)                       │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                   Flatline Protocol                          │
│                                                             │
│  Phase 1: Parallel reviews (opus + gpt + [gemini]?)         │
│  Phase 2: Cross-scoring                                     │
│  Phase 3: Consensus (2-model or 3-model)                    │
│           ▲                                                  │
│           │                                                  │
│  tertiary_model_used: "gemini-2.5-pro" | null  (NEW — FR-1) │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Change Scope

| Component | Change Type | Files Modified |
|-----------|-------------|----------------|
| Flatline observability (FR-1) | Additive | `flatline-orchestrator.sh`, `scoring-engine.sh` |
| State schema (FR-2) | Additive | `simstim-state.sh` |
| Sub-phase wiring (FR-2) | Verification | `SKILL.md` (verify existing Phase 3.5/4.5) |
| Red Team code-vs-design (FR-3) | New | `SKILL.md` (run-mode), new script `red-team-code-vs-design.sh` |
| Config additions (FR-3) | Additive | `.loa.config.yaml` |
| Observability (FR-4) | Additive | `flatline-orchestrator.sh`, `SKILL.md` (simstim) |

---

## 2. Detailed Design

### 2.1 FR-1: Gemini Flatline Verification

#### 2.1.1 Tertiary Model Observability

**File**: `.claude/scripts/flatline-orchestrator.sh`

Add `tertiary_model_used` to output JSON at the consensus phase:

```bash
# After Phase 2 cross-scoring completes
tertiary_model=$(read_config '.flatline_protocol.models.tertiary' '')
if [[ -n "$tertiary_model" && "$has_tertiary" == "true" ]]; then
    tertiary_status="active"
else
    tertiary_status="disabled"
fi

# Add to output JSON
jq --arg model "$tertiary_model" --arg status "$tertiary_status" \
    '. + {tertiary_model_used: $model, tertiary_status: $status}' \
    "$output_file" > "$output_file.tmp" && mv "$output_file.tmp" "$output_file"
```

#### 2.1.2 Visible Logging

**File**: `.claude/scripts/flatline-orchestrator.sh`

Add log line during Phase 1 setup:

```bash
# Before parallel model invocations
if [[ -n "$tertiary_model" ]]; then
    log "Tertiary model: $tertiary_model (active)"
else
    log "Tertiary model: none (disabled)"
fi
```

#### 2.1.3 Eval Test

**File**: `.claude/evals/flatline-3model.sh` (new)

Integration test with API key guard:

```bash
# Skip if no Google API key
if [[ -z "${GOOGLE_API_KEY:-}" ]]; then
    echo "SKIP: GOOGLE_API_KEY not set (integration test)"
    exit 0
fi

# Run flatline with tertiary model configured
output=$(flatline-orchestrator.sh --doc "$TEST_DOC" --phase prd --json)

# Verify 3-model output
models=$(echo "$output" | jq -r '.models')
tertiary=$(echo "$output" | jq -r '.tertiary_model_used')

[[ "$models" -eq 3 ]] || fail "Expected 3 models, got $models"
[[ "$tertiary" == "gemini-2.5-pro" ]] || fail "Expected gemini-2.5-pro, got $tertiary"
```

#### 2.1.4 Config Addition

**File**: `.loa.config.yaml`

```yaml
flatline_protocol:
  models:
    primary: opus
    secondary: gpt-5.3-codex
    tertiary: gemini-2.5-pro    # NEW — enables 3-model Flatline
```

---

### 2.2 FR-2: Simstim State Schema Wiring

#### 2.2.1 State Schema Update

**File**: `.claude/scripts/simstim-state.sh` (lines 199-208)

Add sub-phase entries to the phases object. These appear between their parent phases:

```jq
phases: {
    preflight: ...,
    discovery: ...,
    flatline_prd: ...,
    architecture: ...,
    bridgebuilder_sdd: "pending",   // NEW — Phase 3.5
    flatline_sdd: ...,
    red_team_sdd: "pending",        // NEW — Phase 4.5
    planning: ...,
    flatline_sprint: ...,
    flatline_beads: "pending",      // NEW — Phase 6.5 (already exists in SKILL.md)
    implementation: "pending"
}
```

**Status logic**: Sub-phases default to `"pending"`. When their config gate is false, the SKILL.md sets them to `"skipped"` at execution time. When enabled and completed, they're set to `"completed"`.

**Backward compatibility**: Existing state files without these keys are handled gracefully — `jq` returns `null` for missing keys, which the SKILL.md treats as `"pending"`.

**Implementation note**: The `simstim-state.sh` jq template (lines 199-208) constructs the phases object inline as a string. New keys must be inserted at the correct position in the template, NOT via a separate `jq` merge, because jq object key order depends on insertion order in the template.

#### 2.2.2 Skip Logic for --from

**File**: `.claude/scripts/simstim-state.sh`

When `--from architect` is used (start_index=3), sub-phases before the start point should be marked `"skipped"`:

```jq
bridgebuilder_sdd: (
    if ($phase == "preflight" or $phase == "discovery" or $phase == "architecture")
    then "pending"
    else "skipped"
    end
),
red_team_sdd: (
    if ($phase == "preflight" or $phase == "discovery" or $phase == "architecture" or $phase == "flatline_sdd")
    then "pending"
    else "skipped"
    end
),
flatline_beads: (
    if ($phase != "implementation")
    then "pending"
    else "skipped"
    end
),
```

#### 2.2.3 Sub-Phase Verification (SKILL.md)

**File**: `.claude/skills/simstim-workflow/SKILL.md`

Verify existing Phase 3.5 (lines 224-404) and Phase 4.5 (lines 433-476) correctly:
1. Check config gates before execution
2. Update state via `simstim-state.sh` calls
3. Handle the `"pending"` → `"in_progress"` → `"completed"` | `"skipped"` transition

**No SKILL.md changes expected for FR-2** — the sub-phases are already implemented. The gap was only in the state schema and orchestrator awareness.

---

### 2.3 FR-3: Red Team Code-vs-Design Gate

#### 2.3.1 Architecture

The Red Team code-vs-design gate is a NEW phase in the `/run` sprint loop. It sits after audit-sprint and before PR creation.

```
implement → review (loop) → audit (loop) → [red_team_code] (loop) → COMPLETE → PR
                                                    │
                                                    ▼
                                            Compare SDD security
                                            design to actual code
                                            diff. Produce findings:
                                            CONFIRMED_DIVERGENCE,
                                            PARTIAL_IMPLEMENTATION,
                                            FULLY_IMPLEMENTED
```

#### 2.3.2 New Script: red-team-code-vs-design.sh

**File**: `.claude/scripts/red-team-code-vs-design.sh` (new)

**Input**:
- SDD path (from `.loa.config.yaml` or default `grimoires/loa/sdd.md`)
- Code diff (from `git diff main...HEAD`)
- Sprint target (for scoping)

**Process**:
1. Extract SDD security sections by scanning for headers matching `/^#{1,3}\s.*(Security|Authentication|Authorization|Validation|Error.Handling|Access.Control|Secrets|Encryption)/i` and extracting all content under those headers until the next same-level or higher-level header. Truncate to 5K tokens if SDD is large.
2. Extract code diff (limited to sprint-modified files via `git diff main...HEAD`)
3. Generate comparison prompt:
   - "Compare the security design specifications below to the actual code changes. For each security design requirement, classify as CONFIRMED_DIVERGENCE, PARTIAL_IMPLEMENTATION, or FULLY_IMPLEMENTED."
4. Invoke model-adapter.sh with the comparison prompt
5. Parse findings JSON

**Output**: `grimoires/loa/a2a/sprint-{N}/red-team-code-findings.json`

```json
{
  "findings": [
    {
      "id": "RTC-001",
      "sdd_section": "§5.2 Input Validation",
      "sdd_requirement": "All API inputs validated via JSON schema",
      "code_evidence": "src/api/handler.ts:45 — raw req.body used without validation",
      "classification": "CONFIRMED_DIVERGENCE",
      "severity": 750,
      "recommendation": "Add zod schema validation at API boundary"
    }
  ],
  "summary": {
    "total": 5,
    "confirmed_divergence": 1,
    "partial_implementation": 2,
    "fully_implemented": 2
  }
}
```

#### 2.3.3 Run Mode Integration

**File**: `.claude/skills/run/SKILL.md`

Insert after audit-sprint in the main loop:

```
  7. if red_team.code_vs_design.enabled AND sdd_exists AND audit_passed:
       run red-team-code-vs-design.sh
       if has_confirmed_divergence:
         record_cycle(findings)
         check_circuit_breaker()
         continue  # Loop back to implement
  8. COMPLETE
```

**Circuit breaker**: `red_team_code.max_cycles: 2` (separate from the main circuit breaker). After 2 red-team-code cycles, auto-skip with warning.

#### 2.3.4 State Tracking

**File**: `.run/state.json`

Add to phase tracking:

```json
{
  "phase": "RED_TEAM_CODE",
  "red_team_code": {
    "cycles": 0,
    "max_cycles": 2,
    "findings_total": 0,
    "divergences_found": 0,
    "last_findings_hash": null
  }
}
```

#### 2.3.5 Config Section

**File**: `.loa.config.yaml`

```yaml
red_team:
  code_vs_design:
    enabled: false                    # Default off
    max_cycles: 2                     # Circuit breaker
    skip_if_no_sdd: true             # Skip silently when no SDD exists
    severity_threshold: 700           # Only divergences >700 trigger re-implementation
    token_budget: 150000              # 150K token ceiling
```

---

### 2.4 FR-4: Observability

#### 2.4.1 Flatline Model Count Reporting

**File**: `.claude/scripts/flatline-orchestrator.sh`

After consensus phase, log:

```bash
model_count=$(jq '.models' "$output_file")
if [[ "$model_count" -eq 3 ]]; then
    log "Flatline: 3-model ($primary + $secondary + $tertiary_model)"
else
    log "Flatline: 2-model ($primary + $secondary)"
fi
```

#### 2.4.2 Simstim Phase Count Display

**File**: `.claude/skills/simstim-workflow/SKILL.md`

In the phase progress display, count enabled sub-phases:

```
# When bridgebuilder_sdd + red_team_sdd + flatline_beads all enabled:
[0/11] PREFLIGHT

# When only base phases:
[0/8] PREFLIGHT
```

Compute by reading config gates at preflight time and storing `total_phases` in simstim state.

---

## 3. Data Flow

### 3.1 Flatline 3-Model Flow

```
flatline-orchestrator.sh
  ├── Phase 1: model-adapter.sh --model opus --mode review
  ├── Phase 1: model-adapter.sh --model gpt-5.3-codex --mode review
  ├── Phase 1: model-adapter.sh --model gemini-2.5-pro --mode review  [NEW]
  ├── Phase 1: model-adapter.sh --model opus --mode skeptic
  ├── Phase 1: model-adapter.sh --model gpt-5.3-codex --mode skeptic
  └── Phase 1: model-adapter.sh --model gemini-2.5-pro --mode skeptic [NEW]
      │
      ▼
  Phase 2: scoring-engine.sh
    ├── --opus-scores <file>
    ├── --gpt-scores <file>
    ├── --tertiary-scores-opus <file>   [EXISTING - now populated]
    ├── --tertiary-scores-gpt <file>    [EXISTING - now populated]
    ├── --gpt-scores-tertiary <file>    [EXISTING - now populated]
    └── --opus-scores-tertiary <file>   [EXISTING - now populated]
      │
      ▼
  Phase 3: consensus output
    └── { models: 3, tertiary_model_used: "gemini-2.5-pro", ... }
```

### 3.2 Red Team Code-vs-Design Flow

```
/run sprint-N loop
  ├── implement → commit
  ├── review-sprint → (loop if findings)
  ├── audit-sprint → (loop if findings)
  └── red-team-code-vs-design.sh         [NEW]
        ├── Input: grimoires/loa/sdd.md (security sections)
        ├── Input: git diff main...HEAD (code changes)
        ├── Process: model-adapter.sh --mode dissent
        ├── Output: a2a/sprint-N/red-team-code-findings.json
        └── Decision: CONFIRMED_DIVERGENCE → loop back to implement
                      PARTIAL/FULLY → continue to COMPLETE
```

---

## 4. Security Considerations

### 4.1 API Key Isolation

Gemini API key (`GOOGLE_API_KEY`) is already handled by model-adapter.sh. No new key management needed.

### 4.2 Token Budget Enforcement

Red Team code-vs-design enforces `token_budget: 150000` via model-adapter.sh `--max-tokens` flag. SDD input is truncated to security sections only (not full SDD) to keep within budget.

### 4.3 Finding Integrity

Red Team code-vs-design findings are written to `a2a/sprint-N/` directory (State Zone) with the same permissions model as existing review/audit findings.

---

## 5. Testing Strategy

### 5.1 Unit Tests

| Test | Validates |
|------|-----------|
| State schema includes sub-phases | `simstim-state.sh` creates state with bridgebuilder_sdd, red_team_sdd, flatline_beads keys |
| --from skips sub-phases correctly | `--from sprint-plan` marks bridgebuilder_sdd and red_team_sdd as "skipped" |
| Config gate logic | Sub-phases skip when disabled, run when enabled |
| Tertiary model output field | Flatline output JSON includes `tertiary_model_used` |

### 5.2 Integration Tests

| Test | Validates | API Key Required |
|------|-----------|------------------|
| 3-model Flatline | gemini-2.5-pro participates in consensus | GOOGLE_API_KEY |
| Red Team code-vs-design | CONFIRMED_DIVERGENCE produced for known SDD/code mismatch | OPENAI_API_KEY or ANTHROPIC_API_KEY |
| Full simstim with sub-phases | State file shows bridgebuilder_sdd + red_team_sdd completed | All keys |

### 5.3 Backward Compatibility Tests

| Test | Validates |
|------|-----------|
| 2-model Flatline when no tertiary configured | Existing behavior unchanged, `tertiary_model_used: null` |
| Simstim without sub-phases enabled | PHASES array unchanged, sub-phases marked "skipped" |
| Run loop without code-vs-design | Audit passes directly to COMPLETE |
| Existing state file without sub-phase keys | Graceful handling (null → pending) |

---

## 6. Migration & Rollback

### 6.1 State File Auto-Upgrade

Existing `.run/simstim-state.json` files without sub-phase keys are handled by treating `null` (missing key) as `"pending"`. No explicit migration script needed.

### 6.2 Config Defaults

All new features default to `false`/disabled:
- `flatline_protocol.models.tertiary`: not set (2-model remains default)
- `red_team.code_vs_design.enabled: false`
- Sub-phases in SKILL.md already have config gates

### 6.3 Rollback

Each feature is independently toggleable via config. Disabling returns to exact previous behavior:
- Remove `tertiary` from flatline config → 2-model Flatline
- Set `red_team.code_vs_design.enabled: false` → no code-vs-design in run loop
- Sub-phase config gates already handle enable/disable

---

## 7. File Inventory

### Modified Files

| File | Change |
|------|--------|
| `.claude/scripts/flatline-orchestrator.sh` | Add tertiary model logging + output field |
| `.claude/scripts/simstim-state.sh` | Add bridgebuilder_sdd, red_team_sdd, flatline_beads to state schema |
| `.claude/skills/run/SKILL.md` | Add RED_TEAM_CODE phase after audit |
| `.claude/skills/simstim-workflow/SKILL.md` | Add phase count display, verify sub-phase state updates |
| `.loa.config.yaml` | Add tertiary model + red_team.code_vs_design section |

### New Files

| File | Purpose |
|------|---------|
| `.claude/scripts/red-team-code-vs-design.sh` | Code-vs-design comparison script |
| `.claude/evals/flatline-3model.sh` | Integration test for 3-model Flatline |

### Unchanged Files

| File | Reason |
|------|--------|
| `.claude/scripts/simstim-orchestrator.sh` | PHASES array NOT modified (sub-phase pattern) |
| `.claude/scripts/scoring-engine.sh` | 3-model scoring already works (cycle-040 fix) |
| `.claude/scripts/model-adapter.sh.legacy` | Gemini already supported |
| `.claude/scripts/bridge-findings-parser.sh` | No changes needed |
