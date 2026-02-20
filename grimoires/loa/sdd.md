# SDD: Interview Depth Configuration — Planning Backpressure

> Cycle: cycle-031 | Author: soju + Claude
> Source PRD: `grimoires/loa/prd.md` (Interview Depth Configuration)
> Design Context: `grimoires/loa/context/interview-depth-config.md`

---

## 1. System Overview

This cycle modifies **instruction files** (SKILL.md prose + YAML config), not application code. There are no APIs, databases, or runtime services. The "architecture" is:

1. **Configuration layer** — YAML schema in `.loa.config.yaml.example` read via `yq eval`
2. **Behavioral directive layer** — Prose blocks in `discovering-requirements/SKILL.md` that shape Claude's interview behavior
3. **Structural gate layer** — Phase transition and pre-generation gates that enforce conversational pacing

```
┌─────────────────────────────────────────────┐
│            .loa.config.yaml                  │
│  interview:                                  │
│    mode: thorough | minimal                  │
│    input_style: { routing, discovery, confirm}│
│    pacing: sequential | batch                │
│    phase_gates: { between, before_gen }      │
│    backpressure: { no_infer, show_work, min }│
└──────────────┬──────────────────────────────┘
               │ yq eval (read at skill start)
               ▼
┌─────────────────────────────────────────────┐
│   discovering-requirements/SKILL.md          │
│                                              │
│   <interview_config>                         │
│     Config reading (bash/yq)                 │
│     Mode behavior table                      │
│     Input style resolution                   │
│     Backpressure protocol                    │
│   </interview_config>                        │
│                                              │
│   Phase 0.5: Targeted Interview (modified)   │
│   Phases 1-7: Conditional Discovery (modified)│
│     + Phase Transition Gates (new)           │
│   Phase 8: Pre-Generation Gate (new)         │
│     + PRD Generation                         │
└─────────────────────────────────────────────┘
```

---

## 2. Component Design

### 2.1 Configuration Schema (`.loa.config.yaml.example`)

**Location**: After line 88 (after `plan_and_analyze` section)
**Pattern**: Follows existing convention — commented YAML with section header and version tag

```yaml
# -----------------------------------------------------------------------------
# Interview Depth Configuration (v1.41.0)
# -----------------------------------------------------------------------------
# Controls question depth, input style, and pacing across planning skills.
# Default: thorough mode with sequential plain-text discovery questions.
#
# Construct override: Schema supports future construct manifest interview
# overrides gated by trust tier (RFC #379). Not wired yet.
interview:
  mode: thorough               # thorough | minimal

  # per_skill:                  # Optional per-skill overrides
  #   discovering-requirements: thorough
  #   designing-architecture: minimal
  #   planning-sprints: thorough

  input_style:
    routing_gates: structured   # structured | plain
    discovery_questions: plain  # structured | plain
    confirmation: structured    # structured | plain

  pacing: sequential            # sequential | batch

  phase_gates:
    between_phases: true
    before_generation: true

  backpressure:
    no_infer: true
    show_work: true
    min_confirmation_questions: 1
```

**Default resolution**: Every field uses `yq eval '.interview.X // "default"'` with fallback. Missing `interview:` section = thorough mode, sequential pacing, plain text discovery.

### 2.2 Interview Config Block (`<interview_config>`)

**Insertion point**: `discovering-requirements/SKILL.md` line 94, after `</prompt_enhancement_prelude>`
**Pattern**: XML-tagged section (matches existing `<kernel_framework>`, `<post_completion>`, etc.)

The block contains 5 sub-sections:

#### 2.2.1 Config Reading

```bash
interview_mode=$(yq eval '.interview.mode // "thorough"' .loa.config.yaml 2>/dev/null || echo "thorough")
skill_mode=$(yq eval '.interview.per_skill.discovering-requirements // ""' .loa.config.yaml 2>/dev/null || echo "")
[[ -n "$skill_mode" ]] && interview_mode="$skill_mode"

pacing=$(yq eval '.interview.pacing // "sequential"' .loa.config.yaml 2>/dev/null || echo "sequential")
discovery_style=$(yq eval '.interview.input_style.discovery_questions // "plain"' .loa.config.yaml 2>/dev/null || echo "plain")
routing_style=$(yq eval '.interview.input_style.routing_gates // "structured"' .loa.config.yaml 2>/dev/null || echo "structured")
confirmation_style=$(yq eval '.interview.input_style.confirmation // "structured"' .loa.config.yaml 2>/dev/null || echo "structured")
no_infer=$(yq eval '.interview.backpressure.no_infer // true' .loa.config.yaml 2>/dev/null || echo "true")
show_work=$(yq eval '.interview.backpressure.show_work // true' .loa.config.yaml 2>/dev/null || echo "true")
gate_between=$(yq eval '.interview.phase_gates.between_phases // true' .loa.config.yaml 2>/dev/null || echo "true")
gate_before_gen=$(yq eval '.interview.phase_gates.before_generation // true' .loa.config.yaml 2>/dev/null || echo "true")
min_confirm=$(yq eval '.interview.backpressure.min_confirmation_questions // 1' .loa.config.yaml 2>/dev/null || echo "1")
```

#### 2.2.2 Mode Behavior Table

| Mode | Questions/Phase | Pacing | Phase Gates | Gap Skipping |
|------|----------------|--------|-------------|--------------|
| `thorough` | 3-6 (scales down with context) | sequential | All ON | Suppressed: always ask `min_confirm` questions |
| `minimal` | 1-2 | batch | `before_generation` only | Active: skip covered phases |

#### 2.2.3 Input Style Resolution

| Interaction Type | `structured` | `plain` |
|-----------------|-------------|---------|
| Routing gates | AskUserQuestion with options | "Continue, go back, or skip ahead?" |
| Discovery questions | AskUserQuestion with suggested answers | Markdown question, user responds freely |
| Confirmations | AskUserQuestion (Yes/Correct/Adjust) | "Is this accurate? [yes/corrections]" |

#### 2.2.4 Question Pacing

| Pacing | Behavior |
|--------|----------|
| `sequential` | Ask ONE question per turn. Wait for response. Then ask the next. |
| `batch` | Present 3-6 numbered questions. User responds to all at once. |

#### 2.2.5 Backpressure Protocol

Verbatim PROHIBITED/REQUIRED lists from PRD FR-6. This is the core behavioral shaping for Opus 4.6.

### 2.3 Modification Map

All changes in `discovering-requirements/SKILL.md`:

| Location | Action | Description |
|----------|--------|-------------|
| After line 94 | **INSERT** | `<interview_config>` block (~80 lines) |
| Line 247 | **REPLACE** | Question limit constraint → config-aware language |
| Line 597 | **REPLACE** | Phase 0.5 question limit → "respect configured range and pacing" |
| Lines 613-632 | **REPLACE** | 3-branch IF/ELSE → 4-branch mode-aware logic |
| After line 637 (Phase 1) | **INSERT** | Phase transition gate block |
| After line 642 (Phase 2) | **INSERT** | Phase transition gate block |
| After line 647 (Phase 3) | **INSERT** | Phase transition gate block |
| After line 653 (Phase 4) | **INSERT** | Phase transition gate + anti-inference directive |
| After line 671 (Phase 5) | **INSERT** | Phase transition gate block |
| After line 676 (Phase 6) | **INSERT** | Phase transition gate block |
| After line 682 (Phase 7) | **INSERT** | Phase transition gate block |
| Before line 684 (Phase 8) | **INSERT** | Pre-generation gate block |

**Note**: Line numbers are approximate — after each insertion, subsequent line numbers shift. Modifications should be applied top-to-bottom.

### 2.4 Phase Transition Gate Template

Reusable block inserted after each Phase (1-7):

```markdown
#### Phase N Transition

When `gate_between` is true:
1. Summarize what was learned in this phase (3-5 bullets, cited)
2. State what carries forward to the next phase
3. Present transition:
   - If `routing_style` == "structured": Use AskUserQuestion:
     question: "Phase N complete. Ready for Phase N+1: {next_phase_name}?"
     header: "Phase N"
     options:
       - label: "Continue"
         description: "Move to {next_phase_name}"
       - label: "Go back"
         description: "Revisit this phase — I have corrections"
       - label: "Skip ahead"
         description: "Jump to PRD generation — enough context gathered"
   - If `routing_style` == "plain":
     "Phase N: {phase_name} complete. Moving to Phase N+1: {next_phase_name}. Continue, go back, or skip ahead?"
4. WAIT for response. DO NOT auto-continue.

When `gate_between` is false:
One-line transition: "Moving to Phase N+1: {next_phase_name}."
```

### 2.5 Pre-Generation Gate

Inserted before Phase 8:

```markdown
### Pre-Generation Gate

When `gate_before_gen` is true:

Present completeness summary:

Discovery Complete
---
Phases covered: {N}/7
Questions asked: {count}
Assumptions made: {count}

Top assumptions (review before I generate):
1. [ASSUMPTION] {description} — if wrong, {impact}
2. [ASSUMPTION] {description} — if wrong, {impact}
3. [ASSUMPTION] {description} — if wrong, {impact}

Ready to generate PRD?
---

Use `routing_style` for the "Ready to generate?" prompt.
DO NOT generate the PRD until the user explicitly confirms.

When `gate_before_gen` is false:
Proceed directly to generation with a one-line notice.
```

### 2.6 Conditional Phase Logic (Replacement)

Replaces lines 613-632:

```
IF phase fully covered AND interview_mode == "minimal":
  → Summarize with citations
  → Ask: "Is this accurate?" (1 confirmation, uses confirmation_style)
  → Move to next phase

ELSE IF phase fully covered AND interview_mode == "thorough":
  → Summarize with citations
  → Ask at least {min_confirm} questions: "Is this accurate?" +
    "What am I missing about [specific aspect]?"
  → DO NOT skip. Context coverage does not exempt from confirmation.
  → Wait for response. Respect pacing setting.

ELSE IF phase partially covered:
  → Summarize known (cited)
  → Ask about gaps (respect configured question range and pacing)

ELSE IF phase not covered:
  → Full discovery (respect configured question range and pacing)
  → Iterate until user confirms phase is complete
```

---

## 3. Construct Override Extension Point (Future)

**Not built in this cycle.** Schema shape documented for forward compatibility.

When RFC #379 lands, construct manifests will include:

```json
{
  "workflow": {
    "interview": {
      "mode": "minimal",
      "trust_tier": "BACKTESTED"
    }
  }
}
```

**Precedence chain** (highest to lowest):
1. Construct manifest `interview` (if trust tier >= BACKTESTED)
2. `.loa.config.yaml` `interview.per_skill.{name}`
3. `.loa.config.yaml` `interview.mode`
4. Built-in default (`thorough`)

**Integration point**: `construct-workflow-read.sh` adds `interview` as optional validated key. SKILL.md config reading adds construct override check before per-skill check.

---

## 4. Testing Strategy

### 4.1 Config Parsing Validation

```bash
# Verify yq defaults work with missing config
yq eval '.interview.mode // "thorough"' .loa.config.yaml
# Expected: "thorough" (when interview section missing)

# Verify yq reads explicit config
echo 'interview:\n  mode: minimal' >> /tmp/test-config.yaml
yq eval '.interview.mode // "thorough"' /tmp/test-config.yaml
# Expected: "minimal"
```

### 4.2 Smoke Test Assertions

Extend existing `test-ux-phase2.sh` or create `test-interview-config.sh`:

| Assertion | What to Check | File |
|-----------|--------------|------|
| interview_config block exists | `grep -q '<interview_config>' SKILL.md` | discovering-requirements/SKILL.md |
| Old question limit removed | `! grep -q '2-3 per phase maximum' SKILL.md` | discovering-requirements/SKILL.md |
| Config-aware limit present | `grep -q 'configured range' SKILL.md` | discovering-requirements/SKILL.md |
| Backpressure PROHIBITED block | `grep -q 'DO NOT answer your own questions' SKILL.md` | discovering-requirements/SKILL.md |
| Phase transition gate exists | `grep -q 'Phase Transition' SKILL.md` | discovering-requirements/SKILL.md |
| Pre-generation gate exists | `grep -q 'Pre-Generation Gate' SKILL.md` | discovering-requirements/SKILL.md |
| Anti-inference directive | `grep -q 'you.ll probably also need' SKILL.md` | discovering-requirements/SKILL.md |
| Config example has interview section | `grep -q 'interview:' .loa.config.yaml.example` | .loa.config.yaml.example |
| yq defaults resolve | `yq eval '.interview.mode // "thorough"' .loa.config.yaml` returns non-empty | .loa.config.yaml |

### 4.3 Behavioral Validation (Manual)

Run `/plan-and-analyze` on a test project and verify:
- Agent asks questions one at a time (sequential pacing)
- Agent uses plain text for discovery, AskUserQuestion for gates
- Agent does NOT skip phases even with rich context files
- Agent presents phase transition gates between phases
- Agent presents pre-generation summary before writing PRD
- No "Based on common patterns..." or "Typically..." in agent output

---

## 5. Development Phases (Sprint Plan Input)

### Sprint 5 (MVP): Config + Discovering-Requirements

| Task | File | Type |
|------|------|------|
| Add `interview:` config schema | `.loa.config.yaml.example` | INSERT |
| Add `<interview_config>` block | `discovering-requirements/SKILL.md` | INSERT |
| Replace hardcoded question limits (3 locations) | `discovering-requirements/SKILL.md` | REPLACE |
| Replace conditional phase logic | `discovering-requirements/SKILL.md` | REPLACE |
| Add phase transition gates (7 phases) | `discovering-requirements/SKILL.md` | INSERT |
| Add pre-generation gate | `discovering-requirements/SKILL.md` | INSERT |
| Add anti-inference directive (Phase 4) | `discovering-requirements/SKILL.md` | INSERT |
| Create smoke test | `.claude/scripts/tests/test-interview-config.sh` | NEW |

**Scope**: MEDIUM (8 tasks, 2 files modified + 1 new)

---

## 6. Risks & Mitigation

| Risk | Mitigation |
|------|-----------|
| Prose directives ignored by Claude | Accepted as best-effort. Iterate on language if needed. |
| Phase transition gates slow down power users | Question count scales with context. `mode: minimal` available. |
| Large SKILL.md becomes harder to maintain | All insertions are clearly XML-tagged sections. No refactoring of existing content. |
| Config typos cause silent fallback to defaults | `yq eval` with `//` fallback is safe — typos mean defaults, not errors. |

---

## 7. Open Questions

None. PRD is fully specified for MVP scope. Future questions (construct runtime override, propagation to other skills) deferred to Sprint 6+.
