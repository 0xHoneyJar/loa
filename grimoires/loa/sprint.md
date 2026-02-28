# Sprint Plan: Bridgebuilder Design Review — Pre-Implementation Architectural Intelligence

> **Cycle**: 044
> **Created**: 2026-02-28
> **PRD**: `grimoires/loa/prd.md`
> **SDD**: `grimoires/loa/sdd.md`
> **Target**: `.claude/` System Zone (skills, scripts, data) + `.loa.config.yaml`

---

## Sprint Overview

This cycle has **3 sprints** covering the full Phase 3.5 implementation. All sprints modify System Zone files (`.claude/`) and the config file.

| Sprint | Label | Focus | Dependency |
|--------|-------|-------|------------|
| 1 | Core Phase Integration | SKILL.md, parser, prompt template, config, constraints | None |
| 2 | HITL Interaction + Vision Capture | Severity-specific interaction, REFRAME transitions, vision capture | Sprint 1 |
| 3 | Hardening + Validation | Resume, graceful degradation, trajectory logging, bridge validation | Sprint 2 |

---

## Sprint 1: Core Phase Integration

**Goal**: Wire Phase 3.5 into the simstim workflow with generation, parsing, and configuration. The phase generates a review and parses findings but does NOT implement HITL interaction yet (that's Sprint 2).

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T1.1 | Add Phase 3.5 section to `.claude/skills/simstim-workflow/SKILL.md` (steps 1-7, 10-11 from SDD Section 2.1) | Section inserted between `</phase_3_architecture>` and `<phase_4_flatline_sdd>`. Steps: update state, load persona, load lore, read artifacts (SDD summarized if >5K tokens per Run Bridge truncation strategy), generate review, save review (`mkdir -p .run/bridge-reviews/` before write), parse findings, update checksum, complete phase. Include advisory timing note per SDD Section 5.3. Verify `bridgebuilder_sdd` is NOT added to `force_phase()` whitelist (SDD Section 2.5). |
| T1.2 | Update Phase 3 ending directive in SKILL.md | `Proceed to Phase 3.5 (if enabled) or Phase 4.` replaces `Proceed to Phase 4.` |
| T1.3 | Update resume jump table in SKILL.md | `bridgebuilder_sdd → Phase 3.5` added between `architecture` and `flatline_sdd` |
| T1.4 | Update constraint rule in `.claude/data/constraints.json` (C-PHASE-004) AND generated SKILL.md text | `text_variants.skill-md` updated to `0→1→2→3→3.5→4→4.5→5→6→6.5→7→8` in constraints.json (also fixes missing 4.5). Generated constraint text in SKILL.md also updated to match. |
| T1.5 | Add REFRAME to `.claude/scripts/bridge-findings-parser.sh` severity weight map (line 30-38) | `["REFRAME"]=0` added to `SEVERITY_WEIGHTS` associative array |
| T1.6 | Add REFRAME to `bridge-findings-parser.sh` jq weight mapping (lines 354-364) | `elif .severity == "REFRAME" then 0` added |
| T1.7 | Add REFRAME to `bridge-findings-parser.sh` by_severity output | `by_reframe` computation added (after `by_speculation`, ~line 378). `--argjson reframe "$by_reframe"` added to jq output construction. Empty-findings default includes `"reframe": 0`. |
| T1.8 | Update `.claude/scripts/bridge-vision-capture.sh` jq filters to include SPECULATION | All 3 `select(.severity == "VISION")` filters (lines 211, 270, 291) changed to `select(.severity == "VISION" or .severity == "SPECULATION")` |
| T1.9 | Create `.claude/data/design-review-prompt.md` | Template per SDD Section 4.2: 6 evaluation dimensions, dual-stream output format, severity guide, token budget (30K output) |
| T1.10 | Add `bridgebuilder_design_review` config section to `.loa.config.yaml` | Top-level section with: `enabled: false`, `persona_path`, `lore_enabled: true`, `vision_capture: true`, `token_budget` (5K/25K/30K). Placed after `run_bridge:`. |
| T1.11 | Add `bridgebuilder_design_review: false` under `simstim:` in `.loa.config.yaml` | Single line addition under existing `simstim:` section |
| T1.12 | Implement config gate validation with mismatch warning in Phase 3.5 trigger | If `bridgebuilder_design_review.enabled` and `simstim.bridgebuilder_design_review` disagree, emit warning with specific guidance. Phase skipped unless both are true. Prevents silent skip from Sprint 1 onward. |

**Exit Criteria**: Phase 3.5 section exists in SKILL.md. REFRAME appears in parser severity map. Config keys present with `false` defaults. Constraint rule updated. Design review prompt template created.

---

## Sprint 2: HITL Interaction + Vision Capture

**Goal**: Add the HITL interaction model for all severity levels and wire vision capture with synthetic bridge-id.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T2.1 | Add step 8 HITL interaction to Phase 3.5 SKILL.md — REFRAME findings | REFRAME findings presented with 4 options: Accept minor (modify SDD), Accept major (return to Phase 3), Reject (log rationale), Defer (capture as vision). Accept major includes circuit breaker (max 2 rework cycles tracked in `bridgebuilder_sdd.rework_count`). |
| T2.2 | Add step 8 HITL interaction — CRITICAL findings | CRITICAL findings presented with mandatory acknowledgment: Accept (modify SDD), Return to Architecture, Reject (with rationale). No Defer option — CRITICAL findings demand a decision, not deferral (intentional per SDD). |
| T2.3 | Add step 8 HITL interaction — HIGH/MEDIUM findings | Presented with Accept/Reject/Defer options. Accepted findings → agent modifies SDD. Deferred → vision capture. |
| T2.4 | Add step 8 HITL interaction — SPECULATION findings | Presented as "architectural alternatives": Accept (incorporate into SDD), Defer (capture as vision). No Reject option. |
| T2.5 | Add step 8 HITL interaction — LOW/PRAISE/VISION findings | LOW: display for awareness, no action. PRAISE: display to user. VISION: auto-capture to registry. |
| T2.6 | Add step 9 vision capture with synthetic bridge-id | `bridge-vision-capture.sh --findings ... --bridge-id "design-review-{simstim_id}" --iteration 1 --output-dir grimoires/loa/visions`. Triggered when VISION or SPECULATION findings exist AND `bridgebuilder_design_review.vision_capture: true`. |
| T2.7 | Implement REFRAME "accept major" state transition | On accept major: (1) set `bridgebuilder_sdd` to `incomplete`, (2) set `architecture` to `in_progress`, (3) preserve REFRAME context to `.run/bridge-reviews/reframe-context.md`, (4) increment `bridgebuilder_sdd.rework_count`, (5) return to Phase 3. |
| T2.8 | Implement SDD checksum update after modifications (step 10) | After any SDD modification via accepted findings, run `simstim-state.sh add-artifact sdd grimoires/loa/sdd.md` to refresh checksum. |

**Exit Criteria**: All severity levels have defined HITL interaction. REFRAME accept major correctly transitions state. Vision capture produces entries with `design-review-` provenance. SDD checksum updated after modifications.

---

## Sprint 3: Hardening + Validation

**Goal**: Ensure resume support, graceful degradation, observability, and validate the review quality.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T3.1 | Test resume from `bridgebuilder_sdd` phase | `--resume` with state `phase: bridgebuilder_sdd` correctly routes to Phase 3.5 via jump table. `update_phase bridgebuilder_sdd in_progress` creates state key dynamically. |
| T3.2 | Verify config gate mismatch warning works end-to-end | Test with: (a) both false → silent skip, (b) only one true → warning + skip, (c) both true → phase runs. Moved implementation to Sprint 1 (T1.12). |
| T3.3 | Implement graceful degradation on Phase 3.5 failure | If review generation fails: log error, mark phase as `skipped`, display warning to user, continue to Phase 4. No blocking on failure. |
| T3.4 | Add trajectory logging for vision capture events | After step 9, log to trajectory JSONL: event name, number of vision entries created, bridge-id, findings count by severity. |
| T3.5 | Add trajectory logging for lore loading | After step 3, log to trajectory JSONL: categories loaded, number of lore entries, fallback status (if lore files missing). |
| T3.6 | Validate review quality via bridge iteration | Run a bridge iteration with the design review enabled to verify: (a) findings JSON is parseable, (b) severity distribution is reasonable, (c) REFRAME/SPECULATION findings appear when warranted. Document results in NOTES.md. |

**Exit Criteria**: Resume works. Config mismatch produces warning. Failure gracefully degrades. Trajectory logging active. One successful end-to-end design review validated.

---

## Cross-Cutting Concerns

### File Safety

All modified files are in `.claude/` (System Zone) or `.loa.config.yaml`. Per Three-Zone Model, System Zone writes are made by the `/implement` skill. No application code is modified.

### Backward Compatibility

- Phase 3.5 is disabled by default (`false`). Existing workflows unaffected.
- `bridge-findings-parser.sh` REFRAME addition is additive — existing findings without REFRAME are unaffected.
- `bridge-vision-capture.sh` SPECULATION filter is additive — existing VISION-only captures still work.
- `constraints.json` update fixes existing drift (missing 4.5) while adding 3.5.

### Risk Registry

| Risk | Sprint | Mitigation |
|------|--------|------------|
| SKILL.md insertion at wrong location | 1 | Verify `</phase_3_architecture>` tag exists, insert after it |
| Parser REFRAME breaks existing tests | 1 | REFRAME is additive (weight 0), run existing parser tests |
| Vision capture silently drops SPECULATION | 1 | T1.8 updates jq filter before T2.6 wires capture |
| REFRAME accept-major infinite loop | 2 | Circuit breaker (T2.7, max 2 cycles) |
| Config mismatch confuses users | 3 | Warning message (T3.2) |

---

## Implementation Notes

### Where Code Lives

All code is modified in this repo (loa):
- Skills: `.claude/skills/simstim-workflow/SKILL.md`
- Scripts: `.claude/scripts/bridge-findings-parser.sh`, `.claude/scripts/bridge-vision-capture.sh`
- Data: `.claude/data/design-review-prompt.md`, `.claude/data/constraints.json`
- Config: `.loa.config.yaml`

### Files NOT Modified

- `.claude/scripts/simstim-orchestrator.sh` — zero changes (sub-phase pattern)
- `.claude/data/bridgebuilder-persona.md` — reused as-is
- `.claude/scripts/bridge-orchestrator.sh` — Run Bridge unchanged
- `.claude/scripts/flatline-orchestrator.sh` — Flatline unchanged
