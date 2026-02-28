# PRD: Bridgebuilder Design Review — Pre-Implementation Architectural Intelligence

> **Cycle**: 044
> **Created**: 2026-02-28
> **Status**: Draft
> **Author**: Loa (grounded in 180+ Bridgebuilder comments across 59 PRs, 4 repos, 7 days)

---

## 1. Problem Statement

The Bridgebuilder persona generates the deepest architectural insights in the Loa ecosystem — 53 SPECULATION findings, 13 VISIONs, and 2 REFRAMEs in the past 7 days alone. But it operates exclusively **post-implementation**: after code is written, in the Run Bridge loop (implement → review → fix → converge). The most valuable insights — frame-questioning, architectural alternatives, FAANG parallels — arrive too late to influence the design.

Empirical evidence from loa-dixie PR #47 shows that in one observed case, 5 out of 5 Bridgebuilder SPECULATION findings from a single review cycle were directly implemented in the next cycle. Broader implementation rates across all 53 recent SPECULATIONs need further analysis, but the pattern is clear: these were architectural proposals that would have been more valuable *before* implementation, when they could shape the design rather than require retrofitting.

Meanwhile, the Flatline Protocol already reviews planning documents (PRD, SDD, sprint plan) but uses adversarial multi-model scoring — optimized for error detection, not architectural depth. Flatline catches bugs. The Bridgebuilder surfaces the architectural questions that prevent entire categories of bugs from existing.

**The gap**: No mechanism exists for the Bridgebuilder's educational, frame-questioning, lore-informed review to engage with design documents before code is written.

> Sources: loa-dixie PR #50 Comment 6 (Section V), loa-finn PR #109 ("What Would Make It Deeper"), loa-finn PR #102 (BB-102-P3-04, BB-102-P3-06), loa-freeside PR #100 (Google Design Docs reference), loa-hounfour PR #29 (autopoietic loop observation)

---

## 2. Vision

**The Bridgebuilder as design partner, not periodic reviewer.** The same persona that produces the ecosystem's deepest architectural thinking — with its FAANG parallels, lore-informed context, SPECULATION severity, and REFRAME permission — engages with PRDs and SDDs before implementation begins. Not to design the system (that's the architect's job), but to ask the questions that expand the design space.

This mirrors Google's Design Review process: a readability reviewer checks code quality, a design reviewer checks architectural decisions, but the most valuable reviewer is the **domain expert** who asks "have you considered that this is actually a distributed consensus problem, not a caching problem?" That reframing changes everything that follows.

> Source: loa-dixie PR #50, Comment 6 (Section V) — verbatim proposal by the Bridgebuilder

---

## 3. Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| Front-load architectural insights | SPECULATION/REFRAME findings generated pre-implementation vs post-implementation | >30% shift to pre-implementation |
| Reduce post-implementation rework | % of design review findings that result in SDD modifications before implementation | >50% of HIGH/MEDIUM findings accepted |
| Lore-informed design | Lore entries loaded and referenced during design review | >0 per review (currently 0) |
| Preserve planning velocity | Time added to simstim workflow by design review phase | <5 minutes per review |
| Vision capture from planning | VISION/SPECULATION findings captured from design reviews | >0 per cycle |
| Zero workflow disruption | Existing Flatline review continues unchanged | No regression |

---

## 4. User & Stakeholder Context

### 4.1 Personas

| Persona | Needs | Impact |
|---------|-------|--------|
| **Human Operator** (simstim user) | Sees Bridgebuilder's architectural questions before committing to a design | Primary beneficiary — better-informed design decisions |
| **Loa Agent** (autonomous mode) | Design review as quality gate before implementation | Catches frame errors before they become code |
| **Bridgebuilder Persona** | Reviewed artifacts at the phase where its insights have maximum leverage | Extends its reach from post-implementation to pre-implementation |
| **Flatline Protocol** | Continues adversarial multi-model review unchanged | No change — complementary, not competing |

### 4.2 Existing Infrastructure (Ground Truth)

**Current review architecture:**

| Phase | Reviewer | Purpose | Timing |
|-------|----------|---------|--------|
| Flatline PRD (Phase 2) | Multi-model adversarial | Error detection in requirements | After PRD, before SDD |
| Flatline SDD (Phase 4) | Multi-model adversarial | Error detection in design | After SDD, before sprint plan |
| Flatline Sprint (Phase 6) | Multi-model adversarial | Error detection in sprint plan | After sprint, before implementation |
| Flatline Beads (Phase 6.5) | Multi-model adversarial | Task graph refinement | After sprint, before implementation |
| Run Bridge (post-implementation) | Bridgebuilder persona | Architectural depth + educational enrichment | After code is written |

**What the Bridgebuilder has that Flatline doesn't:**
- Persona with voice, educational depth, and FAANG parallels
- SPECULATION severity (weight 0, architectural proposals)
- REFRAME severity (weight 0, frame-questioning)
- PRAISE severity (celebrating good decisions)
- Lore loading (accumulated ecosystem knowledge)
- Vision capture pipeline (bridge-vision-capture.sh)
- Dual-stream output (findings JSON + insights prose)

**What Flatline has that this phase shouldn't replicate:**
- Multi-model adversarial scoring (Opus + GPT-5.3-codex + Gemini)
- HIGH_CONSENSUS / DISPUTED / BLOCKER categorization
- Convergence scoring and iteration loops
- Auto-integration of high-consensus findings

**Key files:**
- `.claude/data/bridgebuilder-persona.md` — persona definition
- `.claude/scripts/bridge-orchestrator.sh` — Run Bridge state machine
- `.claude/scripts/bridge-findings-parser.sh` — findings JSON parser
- `.claude/scripts/bridge-vision-capture.sh` — VISION/SPECULATION → vision registry
- `.claude/scripts/flatline-orchestrator.sh` — Flatline Protocol orchestrator
- `.claude/skills/simstim-workflow/SKILL.md` — simstim phase definitions
- `.claude/skills/run-bridge/SKILL.md` — Run Bridge skill
- `.loa.config.yaml` — feature flags and configuration

---

## 5. Functional Requirements

### FR-1: Bridgebuilder Design Review Phase in Simstim

**Scope**: Insert a new phase (3.5) between ARCHITECTURE (Phase 3) and FLATLINE SDD (Phase 4) in the simstim workflow.

| Requirement | Detail |
|-------------|--------|
| FR-1.1 | New phase "BRIDGEBUILDER SDD" (Phase 3.5) runs after SDD creation, before Flatline SDD |
| FR-1.2 | Phase loads the Bridgebuilder persona from `.claude/data/bridgebuilder-persona.md` |
| FR-1.3 | Phase loads relevant lore entries (patterns.yaml + visions.yaml) as context |
| FR-1.4 | Phase produces dual-stream output: findings JSON + insights prose |
| FR-1.5 | Phase supports SPECULATION, REFRAME, PRAISE, and standard severity findings |
| FR-1.6 | Phase captures VISION/SPECULATION findings via bridge-vision-capture.sh (with `--mode design-review` flag that substitutes simstim_id as bridge-id, "1" as iteration, and makes --pr optional) |
| FR-1.7 | Phase is gated by config: `simstim.bridgebuilder_design_review: true` (default: false — promote to true after one cycle of opt-in testing) |
| FR-1.8 | Phase can be skipped by user during simstim (consistent with existing skip behavior) |

**Rationale**: Phase 3.5 (not Phase 3) because the SDD must exist before the Bridgebuilder can review it. Phase 3.5 (not Phase 4) because Bridgebuilder's architectural questions should inform the SDD before Flatline's error detection runs.

**Implementation strategy**: Use the sub-phase pattern (proven by Red Team 4.5 and Beads 6.5) — implement Phase 3.5 entirely in SKILL.md with state tracking via `simstim-orchestrator.sh --update-phase bridgebuilder_sdd`. Do NOT insert into the `PHASES` array, as this would shift all subsequent indices and break `--from` flag mappings, `create_initial_state()` arithmetic, and `force_phase()` validation. The `update_phase()` function creates state keys dynamically without validating against the `PHASES` array, making the sub-phase pattern safe. No schema version bump or migration function needed. *(Amended during SDD Flatline review — original strategy proposed PHASES array insertion, rejected due to index-shift breakage risk.)*

### FR-2: Design Review Mode for Bridgebuilder Persona

**Scope**: Adapt the Bridgebuilder persona for reviewing design documents instead of code diffs.

| Requirement | Detail |
|-------------|--------|
| FR-2.1 | Create `design-review-prompt.md` template that adapts the persona for document review |
| FR-2.2 | Evaluation criteria shift from code quality to architectural soundness |
| FR-2.3 | REFRAME findings are explicitly encouraged (the primary value of design review) |
| FR-2.4 | SPECULATION findings are explicitly encouraged (architectural alternatives) |
| FR-2.5 | Template receives both PRD and SDD as context (PRD for requirement traceability) |
| FR-2.6 | Template loads ecosystem lore for cross-project pattern recognition |

**Evaluation dimensions for design review (replacing code review dimensions):**

| Dimension | Question | Example Finding |
|-----------|----------|-----------------|
| **Architectural Soundness** | Does the design serve the requirements? | "The SDD proposes microservices but the team is 2 people — monolith with clear boundaries may be more appropriate" |
| **Requirement Coverage** | Does every PRD requirement map to an SDD component? | "FR-3.2 (internal service DNS) has no corresponding SDD section" |
| **Scale Alignment** | Do capacity targets match the architecture? | "100K agent subdomains via wildcard is sound; but the Edge Middleware routing needs O(1) lookup, not O(n) scan" |
| **Risk Identification** | What could go wrong that the architect hasn't considered? | "DNSSEC key rotation is mentioned but no automation is designed for DS record updates" |
| **Frame Questioning** | Is this the right problem to solve? | "Is this a DNS migration or a platform foundation? The SDD treats it as DNS plumbing, but the agent economy implications suggest it's closer to a service mesh design" |
| **Pattern Recognition** | Does the design follow or diverge from ecosystem patterns? | "This Terraform state isolation pattern matches arrakis.community but diverges from the compute state — is the divergence intentional?" |

### FR-3: Integration with Existing Pipeline

**Scope**: The design review phase integrates with existing simstim infrastructure without modifying Flatline.

| Requirement | Detail |
|-------------|--------|
| FR-3.1 | Simstim state machine updated: `architecture → bridgebuilder_sdd → flatline_sdd` |
| FR-3.2 | `.run/simstim-state.json` tracks the new phase (status, timestamps, findings count) |
| FR-3.3 | simstim-orchestrator.sh updated to support `--update-phase bridgebuilder_sdd` |
| FR-3.4 | Findings from design review are saved to `.run/bridge-reviews/design-review-{cycle}.json` |
| FR-3.5 | VISION/SPECULATION findings feed into vision registry (same pipeline as Run Bridge) |
| FR-3.6 | Flatline SDD review (Phase 4) runs unchanged after Bridgebuilder design review |
| FR-3.7 | If Bridgebuilder produced REFRAME findings, present them to user before Flatline runs |

### FR-4: Standalone Invocation

**Scope**: The design review can be invoked outside of simstim.

| Requirement | Detail |
|-------------|--------|
| FR-4.1 | New skill `/design-review` that can be invoked independently |
| FR-4.2 | Accepts path to SDD (defaults to `grimoires/loa/sdd.md`) |
| FR-4.3 | Optionally accepts path to PRD for requirement traceability |
| FR-4.4 | Produces same dual-stream output as the simstim-integrated version |
| FR-4.5 | Can be used during `/architect` phase as an opt-in quality gate |

### FR-5: Configuration

**Scope**: All behavior is configurable via `.loa.config.yaml`.

| Requirement | Detail |
|-------------|--------|
| FR-5.1 | `simstim.bridgebuilder_design_review: true/false` (default: false — matches progressive rollout pattern of other new features) |
| FR-5.2 | `bridgebuilder_design_review.persona_path` (default: `.claude/data/bridgebuilder-persona.md`) |
| FR-5.3 | `bridgebuilder_design_review.lore_enabled: true/false` (default: true) |
| FR-5.4 | `bridgebuilder_design_review.vision_capture: true/false` (default: true) |
| FR-5.5 | `bridgebuilder_design_review.evaluation_dimensions` (configurable list) |
| FR-5.6 | `bridgebuilder_design_review.token_budget` (same defaults as run_bridge.bridgebuilder) |

### FR-6: HITL Interaction Model

**Scope**: Design review findings are presented to the user in simstim HITL mode.

| Requirement | Detail |
|-------------|--------|
| FR-6.1 | REFRAME findings are always presented to user (never auto-integrated — they question the frame) |
| FR-6.2 | HIGH/MEDIUM severity findings are presented with suggested SDD modifications |
| FR-6.3 | SPECULATION findings are presented as "architectural alternatives to consider" |
| FR-6.4 | PRAISE findings are shown (positive reinforcement for good design decisions) |
| FR-6.5 | User can: Accept (modify SDD), Reject, or Defer (capture as vision for future) |
| FR-6.6 | Deferred findings are automatically captured in vision registry with provenance |
| FR-6.7 | REFRAME acceptance state transitions: **Accept minor** → modify SDD section in-place, continue to Phase 4. **Accept major** → mark SDD artifact as `needs_rework`, transition back to Phase 3 (architecture) with REFRAME context preserved. **Reject** → log rationale to trajectory, continue. **Defer** → capture as vision, continue. |
| FR-6.8 | After Phase 3.5 completes (if SDD was modified), update SDD artifact checksum in simstim state to prevent spurious drift warnings in Phase 4 |

---

## 6. Technical & Non-Functional Requirements

### NFR-1: Latency

Design review targets <60 seconds for a typical SDD (~5,000 tokens), with a hard timeout at 120 seconds (consistent with Flatline timeout). This is a single model call with persona + lore context, not a multi-model adversarial process. On timeout: log warning, save partial findings if any, continue to Phase 4 (graceful degradation per NFR-3).

### NFR-2: Token Efficiency

| Component | Budget |
|-----------|--------|
| Persona | ~5,000 tokens (bridgebuilder-persona.md is ~4,500 words) |
| Lore context | ~1,000 tokens (configurable, same as Run Bridge) |
| PRD input | ~3,000 tokens (summarized, not full) |
| SDD input | ~5,000 tokens (full document) |
| Output (findings) | ~5,000 tokens |
| Output (insights) | ~25,000 tokens (matching run_bridge.bridgebuilder.token_budget.insights_tokens) |
| **Total per review** | ~48,000 tokens |

**Note**: Token budgets reuse `run_bridge.bridgebuilder.token_budget` defaults (findings: 5K, insights: 25K, total: 30K output). Input context (persona + lore + PRD + SDD) is additional. SDDs exceeding 5K tokens use the same truncation strategy as Run Bridge (SDD 3.5.1). PRD summarization is performed inline by the reviewing model, not as a separate step.

### NFR-3: No Impact on Existing Phases

The design review phase is additive. It must not modify Flatline behavior, Run Bridge behavior, or any existing phase's logic. If the phase fails, it logs a warning and simstim continues to Flatline SDD (graceful degradation).

### NFR-4: Reuse of Existing Infrastructure

| Component | Reuse Strategy |
|-----------|----------------|
| Persona loading | Same mechanism as Run Bridge Phase 3.1 (steps 1-4) |
| Lore loading | Same mechanism as Run Bridge Phase 3.1 (step 3) |
| Findings parsing | Same `bridge-findings-parser.sh` (add REFRAME to severity weight map with weight 0, add `reframe` counter to `by_severity` output) |
| Vision capture | Same `bridge-vision-capture.sh` (add `--mode design-review` flag) |
| Content redaction | Same redaction pipeline (SDD 3.5.2) |
| State management | Extend existing `simstim-orchestrator.sh` |

### NFR-5: Observability

- Findings saved to `.run/bridge-reviews/design-review-{cycle}.json`
- Phase timing logged to simstim state
- Vision capture events logged to trajectory JSONL
- Lore entries loaded logged for debugging

---

## 7. Scope & Prioritization

### MVP (This Cycle)

| Priority | Item | Rationale |
|----------|------|-----------|
| P0 | Design review prompt template (`design-review-prompt.md`) | Core artifact — defines what the Bridgebuilder looks for in design documents |
| P0 | Simstim Phase 3.5 integration | The primary delivery mechanism |
| P0 | Config flag (`simstim.bridgebuilder_design_review`) | Required for opt-in/opt-out |
| P0 | Simstim state machine update | Phase tracking and resume support |
| P1 | Lore loading in design review context | Ecosystem knowledge informing design review |
| P1 | Vision capture from design review findings | Completing the autopoietic loop |
| P1 | HITL interaction model (Accept/Reject/Defer) | User agency over findings |
| P2 | Standalone `/design-review` skill | Independent invocation (requires separate SDD section for skill directory, state behavior, and /architect integration before implementation) |

### Future Scope (Not This Cycle)

| Item | Rationale |
|------|-----------|
| Cross-repo design review (loading context from ecosystem repos) | Requires cross-repo lore federation (loa-dixie PR #47 speculation) |
| Multi-model design dialectic (Opus + GPT collaborative, not adversarial) | loa-freeside PR #96 proposed this geometry — deeper exploration needed |
| "Slow review" protocol (asynchronous design review over days) | loa-finn PR #109 speculation — requires async infrastructure |
| PRD design review (Phase 1.5) | Lower leverage than SDD review — PRD is less architectural |
| Constitutional Commentary format (separate from SDD) | loa-finn PR #102 BB-102-P3-06 — larger scope, different artifact type |

### Explicitly Out of Scope

- Modifying the Flatline Protocol
- Modifying the Run Bridge loop
- Changing the Bridgebuilder persona for code review (only adding design review mode)
- Multi-model design review (this uses single-model Bridgebuilder, not Flatline's adversarial pattern)
- Any changes to `.claude/` System Zone files beyond what the implementation skill writes

---

## 8. Risks & Dependencies

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Design review adds latency to simstim | **LOW** | Single model call (~30-60s). Config flag to disable. Comparable to Flatline phase. |
| Bridgebuilder findings conflict with Flatline findings | **MEDIUM** | Different concerns but sequential contradiction possible. When Flatline contradicts an accepted Bridgebuilder finding, Flatline takes precedence for error detection; the architectural consideration is deferred to vision registry. User is informed of the conflict. |
| Design review prompt quality | **MEDIUM** | Reuse proven persona. Iterate prompt through Run Bridge testing. |
| REFRAME findings confuse users | **LOW** | Present with clear labeling. "The Bridgebuilder is questioning whether..." prefix. |
| Token budget exceeded for large SDDs | **MEDIUM** | Same truncation strategy as Run Bridge (SDD 3.5.1). SDD summary if >5K tokens. |

### Dependencies

| Dependency | Status | Impact |
|------------|--------|--------|
| Bridgebuilder persona (`.claude/data/bridgebuilder-persona.md`) | Exists | Core dependency — defines the reviewer's voice |
| bridge-findings-parser.sh | Exists | Parses structured findings JSON |
| bridge-vision-capture.sh | Exists | Captures VISION/SPECULATION to registry |
| simstim-orchestrator.sh | Exists | State machine management — needs extension |
| Lore system (patterns.yaml, visions.yaml) | Exists | Optional but high-value context for reviews |

---

## 9. Architectural Insight: Why This Matters

The Bridgebuilder's own analysis (loa-dixie PR #50) identified three tiers in Google's design review:

| Tier | Focus | Loa Equivalent |
|------|-------|----------------|
| **Readability Reviewer** | Code quality, style, conventions | Flatline (adversarial error detection) |
| **Design Reviewer** | Architectural decisions, patterns | **This feature** (Bridgebuilder on SDD) |
| **Domain Expert** | Problem-space understanding, frame-questioning | REFRAME severity in design review |

The current Loa workflow has Tier 1 (Flatline) and Tier 3 partially (REFRAME is allowed but unused in planning). This PRD adds Tier 2 — the design reviewer who asks "does the architecture serve the requirements?" — and activates Tier 3 at the phase where frame-questioning has maximum leverage.

The loa-hounfour PR #29 observation is the strongest empirical argument: "Each cycle deepens the protocol. The review IS functioning as design — just at the wrong phase." Moving the Bridgebuilder to the planning phase closes this gap.

---

## 10. References

| Document | Location |
|----------|----------|
| Bridgebuilder Design Partner Proposal (Primary Source) | loa-dixie PR #50, Comment 6 (Section V) |
| "Speculation That Became Code" (Empirical Evidence) | loa-dixie PR #47, Comment 5 (Part IV) |
| Flatline for Architectural Reviews Proposal | loa-finn PR #109 ("What Would Make It Deeper") |
| Constitutional Commentary / KEP Format | loa-finn PR #102 (BB-102-P3-06) |
| Google Design Docs Reference | loa-freeside PR #100 (Constellation Review) |
| Multi-Model Review Geometries | loa-freeside PR #96 (Collaborative geometry for architecture) |
| Autopoietic Loop (Review as Design) | loa-hounfour PR #29, Comment 1 |
| Bridgebuilder Persona | `.claude/data/bridgebuilder-persona.md` |
| Run Bridge Skill | `.claude/skills/run-bridge/SKILL.md` |
| Simstim Workflow | `.claude/skills/simstim-workflow/SKILL.md` |
| Flatline Protocol | `.claude/scripts/flatline-orchestrator.sh` |
