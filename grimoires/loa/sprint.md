# Sprint Plan: Interview Depth Configuration — Planning Backpressure

> Cycle: cycle-031 | PRD: grimoires/loa/prd.md | SDD: grimoires/loa/sdd.md
> Sprints: 1 (MVP — discovering-requirements only) | Team: 1 developer (AI-assisted)

---

## Executive Summary

| Field | Value |
|-------|-------|
| **Total Sprints** | 1 (sprint-29) |
| **Scope** | Config schema + discovering-requirements SKILL.md backpressure |
| **Files Modified** | 2 (`.loa.config.yaml.example`, `discovering-requirements/SKILL.md`) |
| **Files Created** | 1 (`.claude/scripts/tests/test-interview-config.sh`) |
| **Success Metric** | `<interview_config>` block exists; phase transition gates exist; no hardcoded "2-3 per phase maximum"; smoke tests pass |

---

## Sprint 1: Config Schema + Discovering-Requirements Backpressure

**Scope**: FR-1 (config schema), FR-2 (interview_config block), FR-3 (question limits), FR-4 (phase gates), FR-5 (pre-gen gate), FR-6 (backpressure protocol), FR-7 (anti-inference), FR-8 (conditional logic)
**Scope size**: MEDIUM (8 tasks)

### Task 1.1: Add `interview:` config schema to `.loa.config.yaml.example`

**File**: `.loa.config.yaml.example`
**Anchor**: After line 88 (after `plan_and_analyze.codebase_grounding` section, before `autonomous_agent` section)

**Change**: Insert the `interview:` configuration section from SDD §2.1:
- Section header comment with version tag `(v1.41.0)`
- `mode: thorough` (default)
- `per_skill:` commented-out examples
- `input_style:` with `routing_gates: structured`, `discovery_questions: plain`, `confirmation: structured`
- `pacing: sequential`
- `phase_gates:` with `between_phases: true`, `before_generation: true`
- `backpressure:` with `no_infer: true`, `show_work: true`, `min_confirmation_questions: 1`
- Construct override comment referencing RFC #379

**Acceptance Criteria**:
- [x] `interview:` section exists between `plan_and_analyze` and `autonomous_agent`
- [x] `yq eval '.interview.mode' .loa.config.yaml.example` returns `thorough`
- [x] `yq eval '.interview.input_style.discovery_questions' .loa.config.yaml.example` returns `plain`
- [x] `per_skill:` examples are commented out (not active YAML)
- [x] Construct override comment references RFC #379

### Task 1.2: Add `<interview_config>` block to discovering-requirements/SKILL.md

**File**: `.claude/skills/discovering-requirements/SKILL.md`
**Anchor**: After line 94 (`</prompt_enhancement_prelude>`)

**Change**: Insert the `<interview_config>` XML-tagged section from SDD §2.2 containing 5 sub-sections:
1. **Config Reading** — bash/yq snippet reading all interview settings with `// "default"` fallback (SDD §2.2.1)
2. **Mode Behavior Table** — thorough vs minimal comparison table (SDD §2.2.2)
3. **Input Style Resolution** — structured vs plain for routing/discovery/confirmation (SDD §2.2.3)
4. **Question Pacing** — sequential vs batch behavior (SDD §2.2.4)
5. **Backpressure Protocol** — PROHIBITED/REQUIRED lists from PRD FR-6 (SDD §2.2.5)

Skill name in yq per_skill path: `discovering-requirements`

**Acceptance Criteria**:
- [x] `<interview_config>` block exists after `</prompt_enhancement_prelude>`
- [x] Config reading bash snippet uses `yq eval` with `// "default"` fallback
- [x] Mode behavior table has `thorough` and `minimal` rows
- [x] PROHIBITED list includes all 6 items from PRD FR-6
- [x] REQUIRED list includes all 4 items from PRD FR-6
- [x] `</interview_config>` closing tag present

### Task 1.3: Replace hardcoded question limit in `<kernel_framework>` (line 247)

**File**: `.claude/skills/discovering-requirements/SKILL.md`

**Before** (line 247):
```
- DO limit questions to 2-3 per phase maximum
```

**After** (SDD §2.3, row 2):
```
- DO limit questions to the configured range per phase (thorough: 3-6, minimal: 1-2)
- DO ask at least {min_confirm} confirmation question(s) per phase, even if context covers it
- DO NOT infer answers to questions you have not asked
- When pacing is "sequential": ask ONE question, wait for response, then ask the next
- When pacing is "batch": present questions as a numbered list
```

**Acceptance Criteria**:
- [x] No occurrence of "2-3 per phase maximum" in SKILL.md
- [x] "configured range" language present in `<kernel_framework>`
- [x] Sequential and batch pacing instructions present

### Task 1.4: Replace Phase 0.5 question limit (line 597)

**File**: `.claude/skills/discovering-requirements/SKILL.md`

**Before** (line 597):
```
3. Ask focused question (max 2-3 per phase)
```

**After** (SDD §2.3, row 3):
```
3. Ask focused questions (respect configured range and pacing)
```

**Acceptance Criteria**:
- [x] No occurrence of "max 2-3 per phase" in Phase 0.5 section
- [x] "configured range and pacing" language present

### Task 1.5: Replace conditional phase logic (lines 613-632)

**File**: `.claude/skills/discovering-requirements/SKILL.md`

**Before** (lines 613-632): Three-branch IF/ELSE with "max 2-3 questions"

**After** (SDD §2.6): Four-branch mode-aware logic:
1. Phase fully covered AND mode == "minimal" → summarize + 1 confirmation → next
2. Phase fully covered AND mode == "thorough" → summarize + min_confirm questions → DO NOT skip → wait
3. Phase partially covered → summarize known + ask about gaps (respect range/pacing)
4. Phase not covered → full discovery (respect range/pacing) → iterate until complete

**Acceptance Criteria**:
- [x] Four-branch conditional logic present
- [x] `mode == "thorough"` branch enforces minimum confirmation questions
- [x] `mode == "minimal"` branch allows gap-skipping
- [x] Both branches reference "configured range and pacing"
- [x] No "max 2-3 questions" remaining in this section

### Task 1.6: Add phase transition gates after Phases 1-7

**File**: `.claude/skills/discovering-requirements/SKILL.md`

**Change**: After each of the 7 phase headings (lines 634-682), insert the Phase Transition Gate template from SDD §2.4:
- When `gate_between` is true: summarize (3-5 bullets, cited), state carryforward, present transition (structured AskUserQuestion or plain text per `routing_style`), WAIT for response
- When `gate_between` is false: one-line transition

Gates inserted after:
- Phase 1: Problem & Vision (after line 637)
- Phase 2: Goals & Success Metrics (after line 642)
- Phase 3: User & Stakeholder Context (after line 647)
- Phase 4: Functional Requirements (after line 666 — after EARS section)
- Phase 5: Technical & Non-Functional (after line 671)
- Phase 6: Scope & Prioritization (after line 676)
- Phase 7: Risks & Dependencies (after line 682)

**Note**: Line numbers are approximate — apply insertions top-to-bottom. After each insertion, subsequent line numbers shift.

**Acceptance Criteria**:
- [x] 7 phase transition gate blocks exist (one per phase)
- [x] Each gate includes summary + carryforward + transition prompt + WAIT directive
- [x] Each gate has `gate_between` true/false conditional
- [x] Structured gates reference AskUserQuestion with Continue/Go back/Skip ahead
- [x] Plain gates use direct text "Continue, go back, or skip ahead?"

### Task 1.7: Add anti-inference directive to Phase 4

**File**: `.claude/skills/discovering-requirements/SKILL.md`
**Anchor**: Inside or immediately after Phase 4 (Functional Requirements) section, before the Phase 4 transition gate

**Change**: Insert PRD FR-7 directive (SDD §2.3, row 7):
```
When the user provides a feature list, DO NOT expand it with "you'll probably
also need..." additions. If you believe something is missing, ASK:
"I notice [X] isn't mentioned. Intentional, or should we add it?"
```

**Acceptance Criteria**:
- [x] Anti-inference directive present in Phase 4 section
- [x] Contains "you'll probably also need" as PROHIBITED example
- [x] Contains the "I notice [X] isn't mentioned" question template

### Task 1.8: Add pre-generation gate before Phase 8

**File**: `.claude/skills/discovering-requirements/SKILL.md`
**Anchor**: Before line 684 (`## Phase 8: PRD Generation`)

**Change**: Insert the Pre-Generation Gate from SDD §2.5:
- When `gate_before_gen` is true: present completeness summary (phases covered, questions asked, assumptions with `[ASSUMPTION]` tags and consequences), ask "Ready to generate PRD?" using `routing_style`, DO NOT generate until user confirms
- When `gate_before_gen` is false: proceed directly with one-line notice

**Acceptance Criteria**:
- [x] Pre-generation gate block exists before Phase 8
- [x] `gate_before_gen` true/false conditional present
- [x] Assumption enumeration with `[ASSUMPTION]` tags
- [x] "DO NOT generate until user explicitly confirms" directive present
- [x] Phases covered count and questions asked count mentioned

### Task 1.9: Create smoke test script

**File**: `.claude/scripts/tests/test-interview-config.sh` (new file)

**Change**: Create test script validating all structural changes from SDD §4.2:

| Assertion | What to Check |
|-----------|--------------|
| `<interview_config>` block exists | `grep -q '<interview_config>' SKILL.md` |
| Old question limit removed | `! grep -q '2-3 per phase maximum' SKILL.md` |
| Config-aware limit present | `grep -q 'configured range' SKILL.md` |
| Backpressure PROHIBITED block | `grep -q 'DO NOT answer your own questions' SKILL.md` |
| Phase transition gate exists | `grep -q 'Phase Transition' SKILL.md` |
| Pre-generation gate exists | `grep -q 'Pre-Generation Gate' SKILL.md` |
| Anti-inference directive | `grep -q "you.ll probably also need" SKILL.md` |
| Config example has interview | `grep -q 'interview:' .loa.config.yaml.example` |
| yq defaults resolve | `yq eval '.interview.mode // "thorough"' .loa.config.yaml` returns non-empty |

**Acceptance Criteria**:
- [x] Script exists at `.claude/scripts/tests/test-interview-config.sh`
- [x] Script is executable (`chmod +x`)
- [x] Uses `((errors+=1))` not `((errors++))` (set -e safety)
- [x] All 9 assertions pass after implementation
- [x] Existing `test-ux-phase2.sh` still passes (no regressions)

---

## Task Dependency Graph

```
Task 1.1 (config schema)         ← independent, separate file
Task 1.2 (interview_config)      ← independent, line 94
Task 1.3 (kernel_framework)      ← independent, line 247
Task 1.4 (Phase 0.5 limit)       ← independent, line 597
Task 1.5 (conditional logic)     ← after 1.2 (same region), lines 613-632
Task 1.6 (phase gates)           ← after 1.5 (line numbers shift), lines 634-682
Task 1.7 (anti-inference)        ← after 1.6 (inside Phase 4 gate area)
Task 1.8 (pre-gen gate)          ← after 1.7 (line numbers shift), before line 684
Task 1.9 (smoke test)            ← after all above (validates everything)
```

**Implementation order**: 1.1, 1.2, 1.3, 1.4 (parallel-safe) → 1.5 → 1.6 → 1.7 → 1.8 → 1.9

---

## Appendix C: Goal Traceability

| Goal | Sprint Coverage | Status |
|------|----------------|--------|
| G-1: Structural friction | Tasks 1.6, 1.8 (phase gates, pre-gen gate) | COVERED |
| G-2: Question count scales | Tasks 1.3, 1.4, 1.5 (config-aware limits + mode logic) | COVERED |
| G-3: No inference without asking | Tasks 1.2, 1.7 (backpressure protocol + anti-inference) | COVERED |
| G-4: Configurable input style | Tasks 1.1, 1.2 (config schema + input style resolution) | COVERED |
| G-5: Sequential pacing default | Tasks 1.1, 1.2 (config schema + pacing rules) | COVERED |
| G-6: Forward-compatible | Task 1.1 (construct override comment) | COVERED (schema only) |

---

## Risk Register

| Risk | Mitigation |
|------|-----------|
| Line numbers shift after each insertion | Apply modifications top-to-bottom per SDD §2.3 note |
| Prose directives ignored by Claude | Accepted as best-effort. Iterate on language if needed. (PRD §8) |
| Large SKILL.md becomes harder to maintain | All insertions are XML-tagged sections. No refactoring of existing content. |
| Existing smoke tests regress | Task 1.9 includes running `test-ux-phase2.sh` as regression check |
