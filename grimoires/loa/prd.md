# PRD: Multi-Model Bridgebuilder Review

**Version:** 1.1
**Date:** 2026-04-13
**Author:** PRD Architect Agent
**Status:** Draft
**Flatline Review:** 3-model (Opus + GPT-5.3-codex + Gemini 2.5 Pro) — 7 HIGH_CONSENSUS integrated, 0 DISPUTED, 6 BLOCKERS (3 overridden, 2 deferred, 1 accepted)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [User Personas & Use Cases](#user-personas--use-cases)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [User Experience](#user-experience)
8. [Technical Considerations](#technical-considerations)
9. [Scope & Prioritization](#scope--prioritization)
10. [Success Criteria](#success-criteria)
11. [Risks & Mitigation](#risks--mitigation)
12. [Appendix](#appendix)

---

## 1. Executive Summary

This PRD defines the addition of multi-model adversarial review capabilities to the Bridgebuilder skill, along with a comprehensive review depth enhancement to close the quality gap between manual and automated reviews. Currently, Bridgebuilder operates as a single-model (Claude) code reviewer invoked during run-bridge iterations post-implementation. The Flatline Protocol provides multi-model review at the planning stage (PRD, SDD, sprint plan), but no equivalent exists at the development cycle end.

This feature introduces opt-in multi-model review (Anthropic Claude, OpenAI Codex 5.2, Google Gemini) with a full adversarial pipeline: independent parallel reviews, cross-scoring, and consensus classification. Simultaneously, it enhances review depth to match the richness of manual invocations — FAANG parallels, metaphors, frame-questioning, lore integration, cross-repo context, and business model insights — making automated reviews accessible to both technical and non-technical stakeholders reading GitHub PR comments directly.

The feature is entirely opt-in via `.loa.config.yaml`, with zero impact on existing single-model behavior when disabled.

> Sources: Phase 1 Q1-Q4, Phase 3 Q1-Q3, Phase 4 Q1-Q4

---

## 2. Problem Statement

### The Problem

Automated Bridgebuilder reviews via run-bridge produce narrow, convergence-focused output that falls significantly short of the rich, educational, frame-questioning reviews achieved through manual invocation. Additionally, single-model review creates blind spots and limits confidence in review quality, which becomes increasingly critical as Loa moves toward more autonomous agent workflows.

### User Pain Points

- **Depth gap**: Automated reviews are code-level and findings-driven. Manual reviews bring in FAANG parallels, metaphors, corporate history, revenue model insights, and broader milieu context that educate the entire team — including non-technical stakeholders
- **Single-model blind spots**: One model cannot catch everything. Codex 5.2 brings thoroughness that Claude may miss; Gemini brings alternate perspectives that both may overlook
- **Manual effort to achieve quality**: The operator must craft detailed manual prompts with rich context, cross-repo references, and explicit permission directives to achieve the review depth that should be the automated default
- **Non-technical stakeholders are underserved**: Automated reviews lack the metaphors and analogies that make technical work accessible to non-engineering team members reading PR comments on GitHub

### Current State

Bridgebuilder operates as a single-model (Claude Opus 4.6) reviewer with two modes:
- **Single-pass**: Full review in one LLM call
- **Two-pass**: Pass 1 (convergence/analytical, no persona) followed by Pass 2 (enrichment/persona with findings preservation)

The two-pass system was designed to add educational depth, but the enrichment pass remains constrained by token budgets and template-driven prompts that do not grant the expansive thinking permissions present in manual invocations.

Multi-model adversarial review exists in the Flatline Protocol but is scoped to planning documents (PRD, SDD, sprint plan) — not code review.

> Sources: Bridgebuilder codebase analysis (reviewer.ts:790-1118, anthropic.ts:1-223, template.ts, config.ts:9-25), .loa.config.yaml:111-148

### Desired State

Automated run-bridge reviews that:
1. Approach the depth, richness, and educational value of manual Bridgebuilder invocations
2. Leverage multiple models (Claude + Codex 5.2 + Gemini) for diverse perspectives and higher confidence
3. Produce output that serves engineers, future contributors, non-technical stakeholders, and community members — all from the same GitHub PR comments
4. Operate with full autonomy (subagents, orchestration, coordination) to produce the deepest review possible, with no artificial time or token constraints
5. Are entirely opt-in and backwards-compatible

---

## 3. Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Automated reviews match manual review depth | Human rating (1-5) per iteration | Running average trends upward; target >= 4 |
| G-2 | Multi-model consensus increases review confidence | Model agreement patterns on findings | HIGH_CONSENSUS findings > 50% across reviews |
| G-3 | Zero regression on existing single-model behavior | Existing Bridgebuilder tests pass with feature off | CI test suite + manual verification |
| G-4 | Non-technical stakeholders can access review content | Presence of metaphors, analogies, business parallels | Structural depth checklist pass rate >= 80% |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Validation Method | Goal ID |
|--------|------------------|--------|-------------------|---------|
| Human review depth rating | N/A (new) | >= 4.0 average | Per-iteration rating (1-5) | G-1 |
| Structural depth checklist pass rate | N/A (new) | >= 80% elements present | Automated checklist validation | G-1, G-4 |
| Multi-model HIGH_CONSENSUS rate | N/A (new) | >= 50% | Consensus summary metrics | G-2 |
| Existing test suite pass rate | 100% | 100% | CI | G-3 |
| Feature-off behavioral delta | N/A | Zero diff | A/B comparison | G-3 |
| Actionable finding rate | N/A (new) | >= 60% | Findings that result in code changes / total findings | G-1, G-2 |

### [SKP-006] Quality Framework

To prevent metric gaming and ensure ground-truth quality:

- **Rating rubric**: Human ratings use a defined rubric (1 = no depth, findings only; 2 = some context; 3 = adequate depth with some parallels; 4 = rich educational content with FAANG/business parallels; 5 = exceptional, matches best manual reviews)
- **Objective quality metrics** (alongside subjective ratings):
  - **Actionable finding rate**: Findings that result in code changes / total findings (target >= 60%)
  - **Defect detection proxy**: Findings confirmed by multiple models / total unique findings
  - **Depth element quality**: Not just presence but relevance — structural checklist elements must reference specific code in the PR, not be generic filler
- **Anti-gaming**: Structural checklist validates that depth elements reference actual code/context from the PR, not boilerplate patterns

### Constraints

- Feature must be entirely opt-in via `.loa.config.yaml`
- Existing single-model behavior must be completely unaffected when feature is disabled
- No new runtime dependencies beyond zod (existing constraint)
- API keys managed via environment variables (existing pattern)

> Sources: Phase 2 Q1-Q3

---

## 4. User Personas & Use Cases

### Primary Persona: Technical Lead / Operator

**Role:** Hands-on technical lead (e.g., janitooor)
**Technical Proficiency:** Expert — runs autonomous development cycles, configures Loa, reviews output
**Goals:** Maximize review quality and confidence in autonomous workflows; reduce manual intervention needed to achieve deep reviews

**Behaviors:**
- Runs run-bridge cycles across multiple repos (loa, loa-finn, loa-hounfour, loa-freeside, loa-dixie)
- Currently crafts detailed manual prompts with rich context to achieve desired review depth
- Values educational output that teaches and connects work to broader patterns
- Cares about the review serving the entire team, not just themselves

**Pain Points:**
- Must manually invoke Bridgebuilder with expansive prompts to get desired quality
- Automated reviews miss cross-repo context and broader milieu connections
- Single-model reviews lack diverse perspectives that build confidence

### Secondary Persona: Engineering Team Members

**Role:** Engineers and contributors
**Technical Proficiency:** Varies (junior to senior)
**Goals:** Learn from reviews, improve code quality, understand architectural patterns

**Behaviors:**
- Read Bridgebuilder PR comments on GitHub
- Use review insights for learning (FAANG parallels, architectural patterns)
- Onboard through review history as living documentation

### Tertiary Persona: Non-Technical Stakeholders

**Role:** Business team members, managers, non-engineering collaborators
**Technical Proficiency:** Non-technical
**Goals:** Understand what is being built and why, stay connected to engineering progress

**Behaviors:**
- Read PR comments directly on GitHub — no downstream translation layer
- Rely on metaphors, analogies, and business model connections to understand technical work
- GitHub comments must be self-contained and accessible

### Quaternary Persona: Community / Future Contributors

**Role:** Open-source contributors encountering the project
**Goals:** Understand project quality standards and architectural thinking
**Behaviors:** Discover review comments on public PRs; use reviews as documentation of project standards

### Use Cases

#### UC-1: Operator Enables Multi-Model Review

**Actor:** Technical Lead
**Preconditions:** API keys for OpenAI and Google configured in environment; `.loa.config.yaml` accessible
**Flow:**
1. Operator adds multi-model configuration to `.loa.config.yaml`
2. Operator runs `/run-bridge` or Bridgebuilder review
3. System detects multi-model config, validates API keys
4. Each configured model reviews the PR diff independently and in parallel
5. Each model's full review is posted as a separate GitHub comment
6. Cross-scoring runs between models
7. Consensus summary with model attribution is posted as final comment
8. Operator receives non-blocking rating prompt (1-5)

**Postconditions:** PR has full review comments from each model + consensus summary; rating stored
**Acceptance Criteria:**
- [ ] All configured models produce independent reviews
- [ ] Reviews include structural depth elements
- [ ] Consensus summary shows model agreement/disagreement with attribution
- [ ] Rating prompt appears with timeout (non-blocking)
- [ ] Feature disabled = identical behavior to current single-model

#### UC-2: Non-Technical Stakeholder Reads Review

**Actor:** Non-Technical Stakeholder
**Preconditions:** Multi-model review has been posted to a PR
**Flow:**
1. Stakeholder opens PR on GitHub
2. Reads review comments from each model
3. Understands technical decisions through metaphors, business parallels, and FAANG analogies
4. Reads consensus summary to understand where models agreed

**Postconditions:** Stakeholder has accessible understanding of the technical work
**Acceptance Criteria:**
- [ ] Review comments are self-contained
- [ ] Metaphors and business parallels make technical concepts accessible
- [ ] Model attribution is clear and transparent

#### UC-3: Graceful Degradation on Missing API Key

**Actor:** Technical Lead
**Preconditions:** Multi-model configured but one API key is missing
**Flow:**
1. System detects missing API key during review initialization
2. In graceful mode (default): logs warning, skips that model, continues with available models
3. In strict mode (configured): halts and reports the missing key

**Postconditions:** Review completes with available models (graceful) or fails cleanly (strict)
**Acceptance Criteria:**
- [ ] Warning clearly identifies which model/key is missing
- [ ] Available models still produce full reviews
- [ ] Strict mode provides actionable error message

> Sources: Phase 3 Q1-Q3, Phase 5 Q1

---

## 5. Functional Requirements

### FR-1: Provider Adapter Interface

**Priority:** P0 — Must Have
**Description:** An extensible TypeScript provider adapter interface that abstracts model-specific API details. Initial implementations for Anthropic (refactor existing), OpenAI, and Google. Designed so adding a new provider requires only a new adapter file and config entry — no core changes.

**Acceptance Criteria:**
- [ ] `ReviewAdapter` interface defined with methods: `complete(prompt, config) -> ReviewResponse`
- [ ] `AnthropicAdapter` (refactored from existing `adapters/anthropic.ts`)
- [ ] `OpenAIAdapter` (new — Codex 5.2 and future OpenAI models)
- [ ] `GoogleAdapter` (new — Gemini and future Google models)
- [ ] Each adapter handles: auth, HTTP POST, SSE streaming, retry with exponential backoff, timeout, error classification
- [ ] Adding a 4th provider = new adapter file + config entry, no core changes
- [ ] Auth via environment variables: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY`
- [ ] [IMP-003] Canonical `ReviewResponse` schema defined (shared across all adapters): normalized fields for content, findings JSON, token counts (input/output), latency_ms, model_id, provider, error state
- [ ] [IMP-006] Per-adapter timeout, retry, and failure-state semantics: configurable per-provider timeout ceiling, explicit failure states (timeout, auth_error, rate_limited, provider_error, network_error), deterministic behavior on each failure type
- [ ] [IMP-001] Token/cost telemetry per adapter call: input_tokens, output_tokens, latency_ms, estimated_cost_usd logged to telemetry (anomaly detection, vendor comparison, regression visibility)

**Dependencies:** None — foundational component

### FR-2: Multi-Model Review Pipeline

**Priority:** P0 — Must Have
**Description:** When multi-model is enabled, each configured model independently reviews the PR diff in parallel. Each model receives the full review context (persona, diff, cross-repo context, lore). Each model's full review is posted as a separate GitHub PR comment, followed by a consensus summary comment with model attribution.

**Acceptance Criteria:**
- [ ] Configured models execute reviews in parallel
- [ ] Each model receives identical context (persona, diff, lore, cross-repo refs)
- [ ] Each model's full review posted as a separate GitHub comment (preserving each model's voice)
- [ ] Consensus summary comment posted after all individual reviews
- [ ] Findings include model attribution (which model caught what)
- [ ] Consensus markers show where models agreed, disagreed, or uniquely identified issues
- [ ] Partial failure of one model does not block others (respects FR-6 graceful degradation config)
- [ ] Progress visibility: expressive status updates during long-running reviews communicating what is actively happening
- [ ] [IMP-004] GitHub comment size and rate limit handling: split reviews exceeding GitHub's 65,536 character limit into continuation comments; respect GitHub API rate limits with queuing/backoff; handle partial posting failures gracefully

**Dependencies:** FR-1, FR-6

### FR-3: Review Depth Enhancement

**Priority:** P0 — Must Have
**Description:** Enhanced prompting and context that closes the gap between automated and manual Bridgebuilder reviews. Includes an expanded system prompt that grants models permission to be expansive, question the frame, and connect work to broader patterns. A structural depth checklist provides a deterministic baseline that can be tuned. Applies to both single-model and multi-model modes.

**Structural Depth Checklist:**

| Element | Description | Example |
|---------|-------------|---------|
| FAANG parallels | Connections to FAANG engineering decisions | "This is the pattern Netflix used when..." |
| Metaphors/analogies | Architectural concepts made tangible | System-as-organism, code-as-city-planning |
| Frame-questioning reframes | Questioning the problem itself | "Is this really X or is it Y?" |
| Cross-repo context references | Related work across the ecosystem | "This connects to loa-finn#66..." |
| Tech/corporate history | Cambrian explosions, blue-chip open source | "Similar to the moment Linux adopted..." |
| Social/business dimension | Community, team, user impact | "This decision shapes contributor experience..." |
| Revenue/business model parallels | How tech decisions enable business models | "This pattern enabled Stripe's..." |
| Concurrent work awareness | Active issues/PRs across repos | "Consider alongside the work in PR #145..." |

**Acceptance Criteria:**
- [ ] System prompt includes "Permission to Question the Question" directive (FR-8)
- [ ] System prompt encourages FAANG parallels, metaphors, business model connections, tech history
- [ ] Structural depth checklist evaluated per review (automated, results logged)
- [ ] Checklist thresholds configurable in `.loa.config.yaml`
- [ ] Applies equally to single-model and multi-model modes
- [ ] No artificial token budget in multi-model mode (provider context limits are the ceiling)
- [ ] Single-model mode retains existing token budgets (backward compatibility)
- [ ] [IMP-010] Context window heterogeneity handling: when providers have different context window sizes (e.g., Claude 200K, Codex 128K, Gemini 1M), apply deterministic truncation/prioritization — truncate diff first, then cross-repo context, preserve persona and lore last; truncation logged per provider

**Dependencies:** FR-7, FR-8

### FR-4: Consensus & Cross-Scoring

**Priority:** P0 — Must Have
**Description:** After independent model reviews, a cross-scoring phase where models evaluate each other's findings. Uses a Bridgebuilder-specific scoring module that understands the rich schema (faang_parallel, metaphor, teachable_moment, connection) while sharing the consensus algorithm math (HIGH_CONSENSUS, DISPUTED, LOW_VALUE, BLOCKER) with Flatline. Follows the FAANG pattern of domain-specific adapters with common algorithm (Google Critique/Tricorder).

**Acceptance Criteria:**
- [ ] Bridgebuilder-specific scoring module created (domain-specific adapter, shared consensus math)
- [ ] Cross-scoring evaluates agreement on findings AND on depth elements (metaphors, reframes, not just bugs)
- [ ] Consensus classifications: HIGH_CONSENSUS, DISPUTED, LOW_VALUE, BLOCKER
- [ ] Model attribution preserved through scoring (which model originated, which confirmed)
- [ ] Consensus summary includes agreement patterns and divergence analysis
- [ ] Scoring thresholds configurable in `.loa.config.yaml`
- [ ] [IMP-002] Cross-scoring mechanics explicitly defined: fan-out pattern (pairwise or round-robin), findings normalization prerequisites (canonical schema from FR-1), consensus computation owner (TypeScript scoring module, not shell), and aggregation method for combining pairwise scores into global consensus

**Dependencies:** FR-1, FR-2

### FR-5: Human Rating Feedback Loop

**Priority:** P0 — Must Have
**Description:** A non-blocking human rating mechanism that captures review quality feedback for learning and adaptation over time.

**Acceptance Criteria:**
- [ ] Per-iteration: 1-5 rating prompt displayed after each review
- [ ] Rating prompt has configurable timeout (default 60s) — proceeds without rating if human is AFK
- [ ] Rating never blocks autonomous execution
- [ ] Optional end-of-cycle retrospective rating available via command
- [ ] Ratings stored persistently (JSONL pattern, `grimoires/loa/` state zone)
- [ ] Rating data includes: timestamp, iteration, models used, rating value, optional free-text
- [ ] Historical ratings queryable for trend analysis

**Dependencies:** None — independent component

### FR-6: Configuration

**Priority:** P0 — Must Have
**Description:** All multi-model and depth enhancement features are opt-in via `.loa.config.yaml`. Feature disabled = zero behavioral change to existing Bridgebuilder.

**Configuration Schema:**

```yaml
run_bridge:
  bridgebuilder:
    # Existing config preserved unchanged...
    multi_model:
      enabled: false                    # Master toggle (default: off)
      models:
        - provider: anthropic
          model_id: claude-opus-4-6
          role: primary                 # Primary reviewer
        - provider: openai
          model_id: codex-5.2
          role: reviewer
        - provider: google
          model_id: gemini-2.5-pro
          role: reviewer
      iteration_strategy: final         # every | final | [1,3,5]
      api_key_mode: graceful            # graceful | strict
      consensus:
        enabled: true
        scoring_thresholds:
          high_consensus: 700
          disputed_delta: 300
          low_value: 400
          blocker: 700
      token_budget:
        per_model: null                 # null = unconstrained (default)
        total: null                     # null = unconstrained (default)
      depth:
        structural_checklist: true
        checklist_min_elements: 5       # Minimum depth elements per review
        permission_to_question: true    # Condition 3 directive
        lore_active_weaving: true       # Lore woven into narrative
      cross_repo:
        auto_detect: true               # Parse PR/commit for cross-repo refs
        manual_refs: []                 # Additional repos/issues/PRs
      rating:
        enabled: true
        timeout_seconds: 60
        retrospective_command: true
      progress:
        verbose: true                   # Expressive status updates
```

**Acceptance Criteria:**
- [ ] `multi_model.enabled: false` (default) = zero behavioral change
- [ ] Model list is fully configurable (provider + model_id + role)
- [ ] Iteration strategy configurable: `every`, `final`, or specific iteration numbers
- [ ] API key mode configurable: `graceful` (skip missing, warn) or `strict` (fail)
- [ ] All thresholds configurable with sensible defaults
- [ ] Token budgets: `null` = unconstrained (default for multi-model)
- [ ] Configuration validated at startup — clear errors for invalid config

**Dependencies:** None — foundational component

### FR-7: Lore Integration Enhancement

**Priority:** P0 — Must Have
**Description:** Lore context from `.claude/data/lore/` must be actively woven into the review narrative, not just loaded as background context. Models should connect code decisions to lore archetypes, naming etymology, and philosophical framing where relevant.

**Acceptance Criteria:**
- [ ] Lore entries loaded and included in review prompt context
- [ ] System prompt directs models to actively reference lore when connecting code to broader patterns
- [ ] Lore references appear naturally in review prose (not as a forced appendix)
- [ ] Uses `short` fields for inline naming explanations, `context` fields for deeper framing
- [ ] Lore integration works in both single-model and multi-model modes

**Dependencies:** Existing lore infrastructure (`.claude/data/lore/`, `bridge-orchestrator.sh`:443-480)

### FR-8: "Permission to Question the Question" Directive

**Priority:** P0 — Must Have
**Description:** All model review prompts include an explicit directive granting permission to question the frame — not just "review this code for bugs" but "what is being built here, and does the architecture serve that purpose?" Baked into the system prompt template, not dependent on manual invocation.

**Acceptance Criteria:**
- [ ] System prompt includes explicit "Condition 3: Permission to Question the Question" section
- [ ] Directive encourages: frame-questioning, REFRAME findings, challenging assumptions, proposing alternate framings
- [ ] Applies to all models equally in multi-model mode
- [ ] Applies in single-model mode when depth enhancement is enabled
- [ ] Does not override convergence priorities (findings still structured and actionable)

**Dependencies:** None — prompt engineering concern

### FR-9: Cross-Repo Context Sourcing

**Priority:** P0 — Must Have
**Description:** Reviews are enriched with context from related issues and PRs across the ecosystem, sourced both automatically (from PR description links, commit messages, issue references) and manually (configured repo/issue lists in `.loa.config.yaml`).

**Acceptance Criteria:**
- [ ] Auto-detection: parse PR description, commit messages, and linked issues for cross-repo references
- [ ] Manual config: optional list of related repos/issues/PRs in `.loa.config.yaml`
- [ ] Detected references fetched and summarized as context for models
- [ ] Context includes: issue titles, key discussion points, related PR summaries
- [ ] Cross-repo context clearly cited in review output
- [ ] Graceful handling of inaccessible repos/issues (skip with warning)

**Dependencies:** GitHub API access (existing via `gh` CLI)

### FR-10: Configurable Iteration Strategy

**Priority:** P0 — Must Have
**Description:** When multi-model is enabled during run-bridge, the operator configures which iterations receive multi-model review: every iteration, final iteration only, or specific iteration numbers.

**Acceptance Criteria:**
- [ ] `iteration_strategy: every` — all iterations get multi-model review
- [ ] `iteration_strategy: final` — only the last iteration gets multi-model review (default)
- [ ] `iteration_strategy: [1,3,5]` — specific iteration numbers get multi-model review
- [ ] Non-multi-model iterations use single-model (existing behavior)
- [ ] Strategy configurable in `.loa.config.yaml`
- [ ] Bridge orchestrator reads strategy and routes accordingly

**Dependencies:** FR-6, bridge orchestrator modification

### FR-11: Progress Visibility

**Priority:** P0 — Must Have
**Description:** During long-running multi-model reviews, expressive status updates inform the operator that work is active and what is happening. Updates communicate substance, not just "still working..."

**Acceptance Criteria:**
- [ ] Status updates during each phase: model initialization, independent reviews (per model), cross-scoring, consensus calculation
- [ ] Updates include model name and current activity (e.g., "Codex 5.2 analyzing auth patterns across 3 repos")
- [ ] Updates surfaced to operator via existing progress mechanism
- [ ] Configurable verbosity (`progress.verbose` in config)
- [ ] No update gaps longer than 30 seconds during active processing

**Dependencies:** FR-2

> Sources: Phase 1 Q1-Q4, Phase 2 Q1-Q3, Phase 3 Q1-Q3, Phase 4 Q1-Q4

---

## 6. Non-Functional Requirements

### Performance

- No artificial time constraints — quality is the sole constraint
- Models may use subagents, orchestrate, and coordinate to produce the deepest review possible
- Independent model reviews execute in parallel to minimize wall-clock time
- Progress updates every <= 30 seconds during active processing

### Scalability

- Provider adapter interface supports adding new providers via new adapter file + config entry
- Configuration schema supports arbitrary model lists per provider
- Cross-scoring scales to N models (not hardcoded to 2 or 3)

### Security

- Existing gitleaks secret redaction applied before posting to GitHub (unchanged)
- Code sent to external model APIs considered safe (confirmed by operator)
- API keys via environment variables — never logged, never included in review output
- Missing API key handling configurable (graceful degradation or strict fail)

### Reliability

- Partial model failure does not block review completion (graceful degradation mode)
- Per-provider retry with exponential backoff (429, 5xx, network errors)
- SSE streaming per provider avoids Cloudflare TTFB timeout (existing pattern)
- Human rating timeout prevents blocking autonomous execution

### Backward Compatibility

- `multi_model.enabled: false` (default) = zero behavioral change
- All existing Bridgebuilder config, CLI flags, and environment variables unchanged
- Existing two-pass mode operates identically when multi-model is off
- No changes to Flatline Protocol, Phase 3.5 design review, or other skills

> Sources: Phase 5 Q1-Q4

---

## 7. User Experience

### Key User Flows

#### Flow 1: Enable Multi-Model Review
```
Edit .loa.config.yaml → Add multi_model block → Set enabled: true →
Configure models + iteration_strategy → Run /run-bridge → Multi-model reviews posted
```

#### Flow 2: Run-Bridge Iteration with Multi-Model
```
Sprint execution completes → Multi-model check (iteration_strategy) →
  IF multi-model iteration:
    → Launch parallel reviews (all models) → Post individual comments →
    → Cross-scoring phase → Post consensus summary → Rating prompt (60s timeout) →
    → Parse findings → Flatline check → Next iteration
  ELSE:
    → Single-model review (existing flow) → Continue
```

#### Flow 3: Rating Feedback
```
Review posted → Rating prompt appears (1-5) →
  IF human responds within timeout: rating stored
  IF timeout expires: proceeds without rating (logged as skipped)
  IF end-of-cycle: optional retrospective rating via command
```

### GitHub Comment Structure (Multi-Model Review)

For a 3-model review on a PR, the comment sequence:

1. **Comment 1 — Claude Opus 4.6 Review** (full review with findings + insights)
2. **Comment 2 — Codex 5.2 Review** (full review with findings + insights)
3. **Comment 3 — Gemini 2.5 Pro Review** (full review with findings + insights)
4. **Comment 4 — Multi-Model Consensus Summary** (agreement patterns, model attribution, divergence analysis)

Each comment is self-contained and readable independently. The consensus summary ties them together. Not optimizing for brevity — each model gets full space to express its perspective.

> Sources: Phase 3 Q2-Q3, Phase 4 Q1

---

## 8. Technical Considerations

### Architecture

**Provider Adapter Pattern (FAANG: Google Critique/Tricorder)**

Follows the Google internal tooling pattern: shared analysis framework with domain-specific adapters. Each provider adapter is a thin HTTP wrapper; the review logic, prompts, and consensus are in the core.

```
┌─────────────────────────────────────────────────────┐
│              Multi-Model Pipeline                    │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐      │
│  │ Anthropic  │  │  OpenAI   │  │  Google   │      │
│  │ Adapter    │  │  Adapter  │  │  Adapter  │      │
│  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘      │
│        │              │              │              │
│        ▼              ▼              ▼              │
│  ┌─────────────────────────────────────────────┐   │
│  │         Parallel Review Executor             │   │
│  └────────────────────┬────────────────────────┘   │
│                       │                             │
│                       ▼                             │
│  ┌─────────────────────────────────────────────┐   │
│  │    Bridgebuilder Scoring Module              │   │
│  │    (domain-specific schema awareness,        │   │
│  │     shared consensus algorithm with          │   │
│  │     Flatline scoring engine)                 │   │
│  └────────────────────┬────────────────────────┘   │
│                       │                             │
│                       ▼                             │
│  ┌─────────────────────────────────────────────┐   │
│  │         GitHub Comment Poster                │   │
│  │    (per-model comments + consensus summary)  │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Scoring Architecture (FAANG: Domain-Specific Adapters, Common Math)**

The Bridgebuilder scoring module understands the rich finding schema (faang_parallel, metaphor, teachable_moment, connection) and evaluates consensus on depth dimensions — not just bug detection. The consensus algorithm (HIGH_CONSENSUS/DISPUTED/LOW_VALUE/BLOCKER thresholds) is shared with Flatline's scoring engine (`scoring-engine.sh`).

**[IMP-005] Bash/TypeScript Integration Boundary**

The scoring module is implemented in TypeScript (within Bridgebuilder's codebase), not as a shell script. The shared consensus algorithm math is extracted from `scoring-engine.sh` and reimplemented in TypeScript for type safety, testability, and elimination of the TS→shell process boundary. The shell `scoring-engine.sh` remains unchanged for Flatline's use. This is a deliberate duplication — the math is simple (threshold comparisons), and the cost of maintaining it in two places is lower than the cost of cross-language process coordination.

### Integrations

| System | Integration Type | Purpose |
|--------|------------------|---------|
| Anthropic API | HTTP POST + SSE streaming | Claude model reviews |
| OpenAI API | HTTP POST + SSE streaming | Codex 5.2 reviews |
| Google AI API | HTTP POST + SSE streaming | Gemini reviews |
| GitHub API | REST via `gh` CLI | Post review comments, fetch cross-repo context |
| Flatline scoring engine | Shared consensus algorithm | Reuse threshold math for consensus classification |
| Bridge orchestrator | Signal integration | Multi-model iteration routing |
| Lore system | File read | `.claude/data/lore/` context for reviews |

### Dependencies

| Dependency | Status | Risk |
|------------|--------|------|
| `ANTHROPIC_API_KEY` | Available (existing) | None |
| `OPENAI_API_KEY` | Available (confirmed) | None |
| `GOOGLE_API_KEY` | Available (confirmed) | None |
| Flatline consensus algorithm | Exists in `scoring-engine.sh` | Needs extraction into reusable module |
| Bridge orchestrator | Exists in `bridge-orchestrator.sh` | Needs modification for multi-model iteration config |
| Bridgebuilder TypeScript codebase | Exists | New adapters + pipeline changes |

### Technical Constraints

- TypeScript compiled, zero runtime dependencies beyond zod
- No new runtime dependencies permitted
- API calls use HTTP POST with provider-specific auth headers
- SSE streaming required to avoid Cloudflare TTFB timeout (existing pattern from `adapters/anthropic.ts`:34-38)
- Retry with exponential backoff per provider (existing pattern from `adapters/anthropic.ts`:14-15)

> Sources: Phase 1 Q3-Q4, Phase 5 Q1-Q4, Phase 7 Q1-Q2

---

## 9. Scope & Prioritization

### In Scope (This Sprint — All Delivered Together)

| Feature | FR | Effort | Impact |
|---------|----|----- --|--------|
| Provider adapter interface (Anthropic, OpenAI, Google) | FR-1 | M | High |
| Multi-model review pipeline (parallel, per-model comments) | FR-2 | L | High |
| Review depth enhancement (structural checklist, expanded prompts) | FR-3 | M | High |
| Consensus & cross-scoring (Bridgebuilder-specific scorer) | FR-4 | M | High |
| Human rating feedback loop (per-iteration + retrospective) | FR-5 | S | High |
| Configuration (opt-in, model list, iteration strategy) | FR-6 | M | High |
| Lore integration enhancement | FR-7 | S | High |
| "Permission to Question the Question" directive | FR-8 | S | High |
| Cross-repo context sourcing (auto-detect + manual) | FR-9 | M | High |
| Configurable iteration strategy | FR-10 | S | Medium |
| Progress visibility (expressive status updates) | FR-11 | S | Medium |

All features delivered as a single sprint — no phased rollout.

### In Scope (Future Iterations)

- Additional provider adapters (Mistral, Ollama/local, etc.) via plugin interface
- Rating-driven adaptive prompt tuning (system learns from feedback history)
- Phase 3.5 design review multi-model extension
- NotebookLM / Tier 2 knowledge integration for reviews

### Explicitly Out of Scope

| Exclusion | Reason |
|-----------|--------|
| Flatline Protocol modifications | Flatline already handles multi-model at planning stage |
| Phase 3.5 / bridgebuilder_design_review changes | Flatline covers multi-model at design stage; this fills the implementation gap |
| NotebookLM / Tier 2 knowledge | Separate concern, optional Flatline feature |
| Budget enforcement (BudgetEnforcer) | Cost is explicitly not a constraint for this feature |
| Non-GitHub output surfaces | GitHub PR comments are the sole output surface |

> Sources: Phase 6 Q1

---

## 10. Success Criteria

### Launch Criteria

- [ ] All 11 functional requirements pass acceptance criteria
- [ ] Multi-model review produces distinct, full reviews from each configured model
- [ ] Consensus summary correctly attributes findings to models
- [ ] Structural depth checklist validates presence of educational elements
- [ ] `multi_model.enabled: false` produces identical output to current Bridgebuilder
- [ ] Human rating mechanism captures feedback without blocking autonomous flow
- [ ] All existing Bridgebuilder tests pass unchanged
- [ ] Configuration validated at startup with clear error messages

### Post-Launch Success (After 5 Bridge Cycles)

- [ ] Human review depth ratings trending >= 4.0 average
- [ ] Structural depth checklist pass rate >= 80%
- [ ] HIGH_CONSENSUS findings >= 50% across multi-model reviews
- [ ] Non-technical stakeholders report improved understanding (qualitative)
- [ ] No regressions in single-model review quality

### Long-Term Success (After 20 Bridge Cycles)

- [ ] Rating feedback data sufficient to identify prompt tuning opportunities
- [ ] Model strength profiles emerge (which model excels at what)
- [ ] Review depth gap between manual and automated invocations closed
- [ ] Multi-model review becomes the default mode (opt-out rather than opt-in)

---

## 11. Risks & Mitigation

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|---------------------|
| OpenAI/Google API response format differences | Medium | Medium | Provider adapter interface normalizes; per-provider tests |
| Review depth consistency across models | Medium | High | Structural checklist as baseline; human rating feedback for tuning |
| Scoring engine format mismatch | Certain | Medium | Bridgebuilder-specific scoring module, shared consensus math (FAANG: domain-specific adapters, common algorithm) |
| Parallel review partial failures | Low | Medium | Configurable graceful degradation; per-provider retry; progress visibility |
| API rate limiting on external providers | Low | Low | Exponential backoff on 429s; low call frequency per bridge iteration |
| Cross-repo context fetching failures | Low | Low | Graceful skip with warning; review proceeds without missing context |
| GitHub comment posting failures | Low | Medium | Retry with backoff; partial posting better than none |

### Assumptions

1. **[ASSUMPTION]** The Bridgebuilder two-pass mode will be extended to multi-model — each model runs its own two-pass (convergence + enrichment), then cross-scoring happens on combined findings. *If wrong*: review pipeline architecture changes significantly.
2. **[ASSUMPTION]** Human rating storage will use the existing observations.jsonl pattern or similar persistent JSONL in `grimoires/loa/`. *If wrong*: storage architecture needs separate design.

### Dependencies on External Factors

- OpenAI API stability and availability for Codex 5.2
- Google AI API stability and availability for Gemini
- GitHub API rate limits for posting multiple comments per PR

> Sources: Phase 7 Q1-Q2

---

## 12. Appendix

### A. Manual vs Automated Review Comparison

| Dimension | Manual Invocation | Automated (Current) | Automated (Target) |
|-----------|-------------------|--------------------|--------------------|
| Models | Single (Claude) | Single (Claude) | Multi (Claude + Codex + Gemini) |
| Cross-repo context | Manually specified (10+ refs) | None | Auto-detect + manual config |
| Frame-questioning | Explicit permission given | Not prompted | Baked into system prompt |
| FAANG parallels | Explicitly requested | Limited (enrichment pass) | Default in all reviews |
| Business model insights | Explicitly requested | None | Default in all reviews |
| Lore integration | Via persona loading | Loaded but underutilized | Actively woven into narrative |
| Token constraints | None (full model context) | 30K total budget | Unconstrained (default) |
| Metaphors/analogies | Rich and diverse | Template-constrained | Rich and diverse |
| Stakeholder accessibility | High | Low | High |

### B. Configuration Reference

Full `.loa.config.yaml` schema for the multi-model feature:

```yaml
run_bridge:
  bridgebuilder:
    # All existing config preserved unchanged...
    multi_model:
      enabled: false                      # Master toggle
      models:                             # Ordered list of review models
        - provider: anthropic             # Provider name (adapter lookup key)
          model_id: claude-opus-4-6       # Provider-specific model ID
          role: primary                   # primary | reviewer
        - provider: openai
          model_id: codex-5.2
          role: reviewer
        - provider: google
          model_id: gemini-2.5-pro
          role: reviewer
      iteration_strategy: final           # every | final | [1,3,5]
      api_key_mode: graceful              # graceful | strict
      consensus:
        enabled: true
        scoring_thresholds:
          high_consensus: 700
          disputed_delta: 300
          low_value: 400
          blocker: 700
      token_budget:
        per_model: null                   # null = unconstrained
        total: null                       # null = unconstrained
      depth:
        structural_checklist: true
        checklist_min_elements: 5
        permission_to_question: true      # Condition 3 directive
        lore_active_weaving: true         # Lore woven into narrative
      cross_repo:
        auto_detect: true                 # Parse PR/commit for cross-repo refs
        manual_refs: []                   # Additional repos/issues/PRs
      rating:
        enabled: true
        timeout_seconds: 60
        retrospective_command: true
      progress:
        verbose: true
```

### C. Glossary

| Term | Definition |
|------|------------|
| Bridgebuilder | Loa's code review skill — produces structured findings and educational insights |
| Run-bridge | Autonomous excellence loop: iterative sprint execution + Bridgebuilder review cycles |
| Flatline Protocol | Multi-model adversarial review for planning phases (PRD, SDD, sprint plan) |
| Two-pass mode | Bridgebuilder review: Pass 1 (convergence/analytical) then Pass 2 (enrichment/persona) |
| Consensus | Agreement classification: HIGH_CONSENSUS, DISPUTED, LOW_VALUE, BLOCKER |
| Cross-scoring | Phase where models evaluate each other's findings to determine consensus |
| Structural depth checklist | Deterministic validation of review educational elements |
| Permission to Question the Question | Directive granting models freedom to question the problem frame |
| Lore | Naming etymology and philosophical framing from `.claude/data/lore/` |
| Cheval | Python model routing infrastructure used by Flatline Protocol |
| Scoring engine | Consensus calculation module (`scoring-engine.sh`) |
| Provider adapter | TypeScript interface abstracting model-specific API details |

### D. Discovery Log

| Phase | Questions | Key Decisions |
|-------|-----------|---------------|
| Phase 1: Problem & Vision | 4 | Full adversarial pipeline (not lightweight merge); extensible adapter interface; quality over cost |
| Phase 2: Goals & Metrics | 3 | Human rating (primary) + structural checklist (secondary); single sprint delivery |
| Phase 3: Users & Stakeholders | 3 | 4 persona tiers (operator, engineers, non-technical, community); GitHub-native output; full comment per model |
| Phase 4: Functional Requirements | 4 | 11 FRs all P0; cross-repo auto-detect + manual; configurable iteration strategy; revenue/business parallels |
| Phase 5: Technical & Non-Functional | 4 | Configurable key mode; unconstrained tokens default; no time limits; full model autonomy |
| Phase 6: Scope & Prioritization | 1 | Phase 3.5 out of scope (Flatline covers design stage); all 11 FRs in single sprint |
| Phase 7: Risks & Dependencies | 2 | Bridgebuilder-specific scoring module (FAANG pattern); API keys available; rate limits low risk |

### E. Flatline PRD Review Log

**Phase:** PRD review
**Models:** 3 (Opus + GPT-5.3-codex + Gemini 2.5 Pro)
**Agreement:** 100%
**Latency:** 225s

| Category | Count | IDs |
|----------|-------|-----|
| HIGH_CONSENSUS (integrated) | 7 | IMP-001, IMP-002, IMP-003, IMP-004, IMP-005, IMP-006, IMP-010 |
| DISPUTED | 0 | — |
| BLOCKERS | 6 | SKP-001 (overridden), SKP-002 (deferred), SKP-003 (overridden), SKP-004 (overridden), SKP-005 (deferred), SKP-006 (accepted) |

**Blocker Decisions:**

| ID | Severity | Decision | Rationale |
|----|----------|----------|-----------|
| SKP-001 | CRITICAL (910) | Override | Loa + Claude has demonstrably delivered sprints of comparable depth and complexity |
| SKP-002 | CRITICAL (885) | Defer | Will observe real-world behavior before adding hard ceilings |
| SKP-003 | CRITICAL (930) | Override | Repos are open-source — IP/data governance not a concern for current use case |
| SKP-004 | CRITICAL (860) | Override | Trusted operator context — internal use on open-source repos, inputs are controlled |
| SKP-005 | HIGH (770) | Defer | Start with 3 models, observe semantic alignment in practice before adding N>3 normalization specs |
| SKP-006 | HIGH (705) | Accept | Objective quality metrics and rating rubric integrated into Section 3 |

---

*Generated by PRD Architect Agent — Discovery: 7 phases, 16 questions, 2 assumptions confirmed. Flatline: 3-model review, 7 HIGH_CONSENSUS integrated, 1 BLOCKER accepted.*
