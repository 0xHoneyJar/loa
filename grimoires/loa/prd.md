# PRD: Interview Depth Configuration — Planning Backpressure

> Cycle: cycle-031 | Author: soju + Claude
> Predecessor: cycle-030 (UX Redesign — Vercel-Grade Developer Experience)
> Related: [#379](https://github.com/0xHoneyJar/loa/issues/379) (construct trust), [#90](https://github.com/0xHoneyJar/loa/issues/90) (AskUserQuestion UX), [#343](https://github.com/0xHoneyJar/loa/issues/343) (progressive disclosure)
> Design Context: `grimoires/loa/context/interview-depth-config.md`, `grimoires/loa/context/ux-redesign-plan.md`
> Priority: P1 — directly impacts planning quality for all users

---

## 1. Problem Statement

Opus 4.6 rushes through Loa's planning phases. It infers answers instead of asking, skips phases when context "seems sufficient," and generates PRDs in the same conversation turn as the last question. The result: users get a document that looks complete but wasn't properly interrogated.

**The root causes:**

1. **No configuration surface.** Question limits ("2-3 per phase max") are hardcoded in SKILL.md prose. There is zero user-facing control for interview depth, input style, or pacing.

2. **Gap-skipping logic is too aggressive.** When context files cover a phase, the agent silently moves on with a one-line "Is this accurate?" — no friction, no confirmation gate, no summary of what was understood.

3. **No backpressure mechanism.** Nothing in the SKILL.md explicitly prohibits the agent from combining phases, inferring answers, or generating the output document in the same response as the last question. More capable models exploit this absence.

4. **AskUserQuestion UI isn't always wanted.** Some users prefer typing freely over selecting from 4 predefined options. The structured widget constrains users who think holistically.

> Sources: JNova Discord feedback (2026-02-19), cycle-030 retrospective, `ux-redesign-plan.md` Open Question #1 ("Should /plan offer a speed toggle?")

---

## 2. Vision

**Planning should feel like a senior PM interview, not a form submission.**

The agent walks every phase, shows its understanding, asks what it doesn't know, and waits for you to confirm before moving on. Rich context means fewer questions — not fewer phases. The friction is structural (every phase has a gate) not volumetric (always ask N questions regardless).

Users who want speed can opt into minimal mode. Constructs that earn trust (RFC #379) can eventually declare their own interview depth. But the default experience is thorough.

---

## 3. Goals & Success Criteria

| Goal | Success Criteria |
|------|-----------------|
| G-1: Structural friction at planning stage | Agent never skips a discovery phase, even with rich context. Every phase gets at minimum a summary + confirmation. |
| G-2: Question count scales with context | Rich context (LARGE assessment) produces fewer questions per phase. Empty context produces full discovery. Neither produces zero-question phases. |
| G-3: No inference without asking | Agent does not write "Based on common patterns..." or "Typically..." for requirements. Gaps are asked, not filled. |
| G-4: Configurable input style | Users can choose structured (AskUserQuestion) or plain text for discovery questions via `.loa.config.yaml`. |
| G-5: Sequential pacing by default | Agent asks one question per turn, waits for response. Users can switch to batch pacing. |
| G-6: Forward-compatible with constructs | Config schema shape supports future construct manifest `interview` overrides gated by trust tier. No runtime plumbing yet. |

---

## 4. User Personas

### Persona 1: New User (no context)
- Arrives with little or no context files
- Needs full 7-phase discovery interview
- Benefits from sequential pacing — one question at a time, conversational
- Default mode: `thorough`

### Persona 2: Power User (rich context)
- Provides extensive context files in `grimoires/loa/context/`
- Wants the agent to confirm understanding, not re-ask what's documented
- Still expects every phase to be walked — no silent skipping
- Question count scales down, but structural gates remain
- Default mode: `thorough` (friction comes from gates, not question count)

### Persona 3: Construct Operator (speed matters)
- Working within a construct's defined workflow (UI fixes, bug triage, domain-specific pipelines)
- Needs concise planning or to opt out of heavy phases entirely
- Uses `mode: minimal` in config, or construct manifest declares interview depth
- Future: BACKTESTED+ constructs can reduce friction automatically (RFC #379)
- Default mode: `minimal` (via config or construct override)

---

## 5. Functional Requirements

### FR-1: Interview Configuration Schema

Add `interview:` section to `.loa.config.yaml.example` with:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mode` | `thorough` \| `minimal` | `thorough` | Global interview depth |
| `per_skill` | map | (empty) | Per-skill mode overrides |
| `input_style.routing_gates` | `structured` \| `plain` | `structured` | Phase transitions use AskUserQuestion or plain text |
| `input_style.discovery_questions` | `structured` \| `plain` | `plain` | Discovery questions use AskUserQuestion or plain text |
| `input_style.confirmation` | `structured` \| `plain` | `structured` | Understanding confirmations use AskUserQuestion or plain text |
| `pacing` | `sequential` \| `batch` | `sequential` | One question per turn vs numbered batch |
| `phase_gates.between_phases` | boolean | `true` | Require confirmation between discovery phases |
| `phase_gates.before_generation` | boolean | `true` | Require confirmation before generating output doc |
| `backpressure.no_infer` | boolean | `true` | Prohibit inferring answers to unasked questions |
| `backpressure.show_work` | boolean | `true` | Cite known vs unknown before asking |
| `backpressure.min_confirmation_questions` | integer | `1` | Minimum questions per phase even when context covers it |

Config is read via `yq eval` with `// "default"` fallback pattern (same as existing `codebase_grounding` config). Missing config = thorough mode with all defaults.

### FR-2: Interview Config Block in SKILL.md

Add `<interview_config>` XML section to `discovering-requirements/SKILL.md` containing:
- Config reading via yq (bash snippet)
- Mode behavior table (thorough vs minimal)
- Input style resolution table
- Question pacing rules
- Backpressure protocol (PROHIBITED/REQUIRED lists)
- Construct override documentation (future extension point)

Insertion point: after `</prompt_enhancement_prelude>` (line 94).

### FR-3: Replace Hardcoded Question Limits

Replace "DO limit questions to 2-3 per phase maximum" with config-aware language:
- Thorough mode: 3-6 questions per phase range, but scales down with context richness
- Minimal mode: 1-2 questions per phase
- Both modes: at least `min_confirmation_questions` per phase (floor of 1)

### FR-4: Phase Transition Gates

After each discovery phase (1-7), add a gate block:
- Summarize what was learned (3-5 bullets, cited)
- State what carries forward to next phase
- Present transition prompt (structured or plain per config)
- **Wait for response. Do not auto-continue.**

When `gate_between` is false: one-line transition only.

### FR-5: Pre-Generation Gate

Before Phase 8 (PRD Generation), present completeness summary:
- Phases covered count
- Questions asked/answered count
- Top assumptions with `[ASSUMPTION]` tags and consequences
- Explicit "Ready to generate PRD?" prompt
- **Do not generate until user confirms.**

### FR-6: Backpressure Protocol

Explicit prose prohibitions added to SKILL.md:

**PROHIBITED:**
- Do not answer your own questions
- Do not proceed without explicit user input
- Do not write "Based on common patterns..." or "Typically..." for requirements
- Do not combine multiple phases into one response
- Do not generate the output document in the same response as the last question
- Do not skip phases because "the context seems sufficient"

**REQUIRED:**
- Wait for user response after every question
- Before asking, state: (1) what you know (cited), (2) what you don't know, (3) why it matters
- Separate phases into distinct conversation turns
- Enumerate assumptions with `[ASSUMPTION]` tags before proceeding

### FR-7: Anti-Inference Directives (Phase-Specific)

Phase 4 (Functional Requirements):
- Do not expand user feature lists with "you'll probably also need..." additions
- If something seems missing, ask: "I notice [X] isn't mentioned. Intentional, or should we add it?"

### FR-8: Conditional Phase Logic Update

Replace the existing three-branch IF/ELSE with mode-aware logic:
- `thorough` + fully covered: summarize + ask at least `min_confirm` questions (no skipping)
- `minimal` + fully covered: summarize + one confirmation (current behavior)
- Partially covered: summarize known, ask about gaps (respect pacing)
- Not covered: full discovery (respect pacing)

### FR-9: Construct Override Schema (Forward-Compatible)

Document in config comments and SKILL.md that construct manifests will eventually support:
```json
{ "workflow": { "interview": { "mode": "minimal", "trust_tier": "BACKTESTED" } } }
```
Precedence chain: Construct (if trust >= BACKTESTED) > per_skill config > global mode > default.
**No runtime plumbing in this cycle.** Schema shape only.

---

## 6. Technical Constraints

- **Config mechanism**: `yq eval` with `//` fallback defaults in SKILL.md bash snippets. Same pattern as `plan_and_analyze.codebase_grounding` (proven to work).
- **Behavioral enforcement**: Prose-based only. No hooks, no scripts, no structural validation. Accepted as best-effort.
- **Backward compatibility**: Missing `interview:` section in user's `.loa.config.yaml` resolves to all defaults via yq fallback. Zero breakage for existing users.
- **AskUserQuestion constraints**: max 4 options (5th is auto "Other"), max 12-char headers, markdown previews single-select only. (From `ux-redesign-plan.md`)

---

## 7. Scope

### In Scope (MVP — Sprint 5)

| Item | File |
|------|------|
| Interview config schema | `.loa.config.yaml.example` |
| `<interview_config>` block | `discovering-requirements/SKILL.md` |
| Replace hardcoded question limits | `discovering-requirements/SKILL.md` |
| Phase transition gates (Phases 1-7) | `discovering-requirements/SKILL.md` |
| Pre-generation gate | `discovering-requirements/SKILL.md` |
| Backpressure protocol | `discovering-requirements/SKILL.md` |
| Anti-inference directives | `discovering-requirements/SKILL.md` |
| Conditional phase logic update | `discovering-requirements/SKILL.md` |

### Future (Sprint 6+)

| Item | File |
|------|------|
| Same changes to `designing-architecture/SKILL.md` | designing-architecture/SKILL.md |
| Same changes to `planning-sprints/SKILL.md` | planning-sprints/SKILL.md |
| Smoke test for interview behavior | `.claude/scripts/tests/test-interview-config.sh` |
| Construct runtime override plumbing | construct-workflow-read.sh + SKILL.md |

### Out of Scope

- Structural enforcement (hooks, scripts validating question count)
- Runtime config hot-reload (agent reads config at skill start, not mid-phase)
- AskUserQuestion UI changes (that's Claude Code's domain, not ours)

---

## 8. Risks & Dependencies

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Claude ignores backpressure prose directives | Medium | Medium | Iterate on language. Accepted as best-effort. |
| Config-reading yq snippets not followed by Claude | Low | High | Uses proven pattern from codebase_grounding. |
| Thorough mode feels too slow for power users | Medium | Low | `mode: minimal` available. Question count scales with context. |
| Future construct override creates precedence confusion | Low | Medium | Precedence chain documented in config comments. |

### Dependencies

- `yq` v4+ installed (required by existing Loa workflows)
- Cycle-030 changes landed (post-completion debrief, free-text-first /plan) — these are on the same branch

---

## 9. Source Tracing

| Section | Sources |
|---------|---------|
| Problem Statement | JNova feedback, `ux-redesign-plan.md:93-131`, discovering-requirements/SKILL.md:247 |
| Goals G-1 through G-3 | User interview (this session, Phase 2 + Phase 7) |
| Goal G-4 | User interview (this session, Phase 1 Q1 — "configurable per-phase") |
| Goal G-5 | User interview (this session, Phase 1 Q2 — "lean towards slower and thorough") |
| Goal G-6 | User interview (this session, Phase 1 Q3 — RFC #379 reference) |
| Persona 3 | User interview (this session, Phase 3 — "construct level with UI/bug fixes") |
| FR-1 through FR-9 | `interview-depth-config.md` (context document) |
| Risk tolerance | User interview (this session, Phase 7 — "accept as best-effort") |
