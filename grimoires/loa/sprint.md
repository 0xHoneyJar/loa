# Sprint Plan: Two-Pass Bridge Review — Excellence Frontier (cycle-039, Post-Convergence)

## Overview

**PRD:** grimoires/loa/prd.md v1.0
**SDD:** grimoires/loa/sdd.md v1.0
**Source:** Bridgebuilder Deep Review (PR #411 Parts 1-3) + Iteration 3 SPECULATION-1
**Sprints:** 3 (extending the converged codebase with forward-looking architectural improvements)
**Scope:** SPECULATION-level proposals elevated to implementation — striving for excellence at all levels

### Context

The bridge has converged (score 9 → 4 → 0 over 3 iterations, 10 actionable findings addressed). All CRITICAL/HIGH/MEDIUM/LOW findings are resolved. What remains are:

1. **Iteration 3 speculation-1**: Confidence scores for enrichment prioritization
2. **Deep Review Part 3, Section V**: Metacognition — the system knowing what it knows
3. **Deep Review Part 2, Section IV (Connection 4)**: Review pluralism via persona slot
4. **Deep Review Part 3, Permission 1**: Cross-repository perception (Pass 0 prototype)
5. **Deep Review Part 3, Permission 2**: Speculation exploration loop

These proposals transform the two-pass architecture from a "review pipeline optimization" into the "cognitive architecture for machine reflection" that the deep review identified it to be.

---

## Sprint 4: Metacognition — Confidence-Weighted Enrichment (global sprint-66)

**Goal**: Implement speculation-1 from iteration 3 — add optional confidence scoring to Pass 1 findings so Pass 2 can allocate enrichment depth proportionally. This is the first step toward machine self-assessment within the review pipeline.

**Source**: [speculation-1](https://github.com/0xHoneyJar/loa/pull/411#issuecomment-3955184897) (iter 3), [Deep Review Part 3 Section V](https://github.com/0xHoneyJar/loa/pull/411#issuecomment-3955290750)

**Scope**: 5 tasks

### Deliverables

- [ ] Convergence prompt requests optional `confidence` field (0.0-1.0) on each finding
- [ ] `extractFindingsJSON()` parses and validates confidence values at runtime
- [ ] Enrichment prompt includes confidence-based depth guidance
- [ ] `ReviewResult` carries confidence metadata for observability
- [ ] Tests validate confidence parsing, pass-through, and enrichment depth allocation

### Acceptance Criteria

- [ ] AC-1: Convergence prompt schema includes `confidence?: number` guidance with calibration examples
- [ ] AC-2: `extractFindingsJSON()` validates confidence is a number in [0.0, 1.0] when present, silently drops invalid values
- [ ] AC-3: `buildEnrichmentPrompt()` includes confidence-aware depth guidance ("high confidence findings get deeper teaching; low confidence get verification focus")
- [ ] AC-4: `ReviewResult` includes `pass1ConfidenceStats?: { min: number; max: number; mean: number }` for observability
- [ ] AC-5: Findings without confidence are treated as confidence=0.5 (neutral — same depth as current behavior)
- [ ] AC-6: Preservation guard does NOT check confidence (confidence is enrichment metadata, not a finding attribute)
- [ ] AC-7: All existing 380 tests pass with zero modification
- [ ] AC-8: At least 6 new tests covering: confidence parsing, validation, missing confidence, enrichment depth guidance, stats computation, preservation guard independence

### Technical Tasks

- [ ] **Task 4.1**: Update convergence prompt to request confidence scoring
  - File: `.claude/skills/bridgebuilder-review/resources/core/template.ts`
  - In `CONVERGENCE_INSTRUCTIONS` constant, add guidance for optional `confidence` field
  - Include calibration: "1.0 = certain this is a real issue, 0.5 = moderate confidence, 0.1 = uncertain but worth flagging"
  - Do NOT make it required — backward compatibility with models that ignore it
  - **AC**: AC-1, AC-7

- [ ] **Task 4.2**: Parse and validate confidence in `extractFindingsJSON()`
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - After runtime type validation, normalize confidence: `typeof f.confidence === 'number' && f.confidence >= 0 && f.confidence <= 1 ? f.confidence : undefined`
  - Do NOT filter findings lacking confidence — it's optional
  - Add `confidence?: number` to the finding type in the filter's type guard
  - **AC**: AC-2, AC-5, AC-7

- [ ] **Task 4.3**: Add confidence-aware depth guidance to enrichment prompt
  - File: `.claude/skills/bridgebuilder-review/resources/core/template.ts`
  - In `buildEnrichmentPrompt()`, after the "Your Task" section, add confidence guidance:
    - "Findings with confidence > 0.8: Focus on deep teaching — FAANG parallels, metaphors, architecture connections"
    - "Findings with confidence 0.4-0.8: Balance teaching with verification — confirm the analysis before elaborating"
    - "Findings with confidence < 0.4: Focus on verification — investigate whether this is a real issue before teaching"
    - "Findings without confidence: Treat as moderate confidence (0.5)"
  - Only render this section if at least one finding has a confidence value
  - **AC**: AC-3, AC-5, AC-7

- [ ] **Task 4.4**: Add confidence stats to `ReviewResult`
  - File: `.claude/skills/bridgebuilder-review/resources/core/types.ts`
  - Add `pass1ConfidenceStats?: { min: number; max: number; mean: number; count: number }` to `ReviewResult`
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - In `processItemTwoPass()`, after extracting findings, compute stats from parsed confidence values
  - Include in result fields passed to `postAndFinalize()`
  - **AC**: AC-4, AC-7

- [ ] **Task 4.5**: Add comprehensive tests for confidence pipeline
  - File: `.claude/skills/bridgebuilder-review/resources/__tests__/reviewer.test.ts`
  - Test 1: Pass 1 output with confidence values → correctly parsed and passed to enrichment
  - Test 2: Pass 1 output with invalid confidence (negative, >1, string) → silently dropped
  - Test 3: Pass 1 output with no confidence on any finding → enrichment prompt omits confidence section
  - Test 4: Mixed findings (some with confidence, some without) → stats computed from available values only
  - Test 5: Preservation guard passes when confidence differs between Pass 1 and Pass 2 (confidence is NOT a preserved attribute)
  - Test 6: Confidence stats included in ReviewResult
  - File: `.claude/skills/bridgebuilder-review/resources/__tests__/template.test.ts`
  - Test 7: Enrichment prompt includes confidence guidance when findings have confidence
  - Test 8: Enrichment prompt omits confidence guidance when no findings have confidence
  - **AC**: AC-6, AC-8

---

## Sprint 5: Persona Provenance + Review Pluralism Foundation (global sprint-67)

**Goal**: Make the persona slot architecture explicit with provenance tracking, laying the foundation for review pluralism. Currently the persona is loaded as a raw string — this sprint adds identity, versioning, and traceability so different communities could deploy different reviewer personas on the same convergence foundation.

**Source**: [Deep Review Part 2, Section IV, Connection 4](https://github.com/0xHoneyJar/loa/pull/411#issuecomment-3955269032) (web4 review pluralism), [praise-6](https://github.com/0xHoneyJar/loa/pull/411#issuecomment-3955184897) (config provenance chain)

**Scope**: 5 tasks

### Deliverables

- [ ] `PersonaMetadata` type with id, version, hash for identity tracking
- [ ] Persona loaded with metadata extraction from frontmatter
- [ ] `ReviewResult` includes `personaId` and `personaHash` for provenance
- [ ] Enrichment output includes persona attribution line
- [ ] Tests validate persona metadata parsing, provenance tracking, and attribution rendering

### Acceptance Criteria

- [ ] AC-1: `PersonaMetadata` interface: `{ id: string; version: string; hash: string }` extracted from persona frontmatter
- [ ] AC-2: Persona frontmatter parsing extracts `persona-version` and `agent` from existing `<!-- persona-version: 1.0.0 | agent: bridgebuilder -->` comment
- [ ] AC-3: `ReviewResult` includes `personaId?: string` and `personaHash?: string`
- [ ] AC-4: Enrichment prompt footer includes `Reviewed with: {persona.id} v{persona.version}` attribution
- [ ] AC-5: When persona has no frontmatter, defaults to `{ id: "unknown", version: "0.0.0", hash: sha256(content) }`
- [ ] AC-6: Persona hash computed via SHA-256 of trimmed content (consistent with existing persona integrity check in run-bridge)
- [ ] AC-7: All existing tests pass with zero modification
- [ ] AC-8: At least 6 new tests

### Technical Tasks

- [ ] **Task 5.1**: Create `PersonaMetadata` type and frontmatter parser
  - File: `.claude/skills/bridgebuilder-review/resources/core/types.ts`
  - Add `PersonaMetadata` interface: `{ id: string; version: string; hash: string }`
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - Add `parsePersonaMetadata(content: string): PersonaMetadata` private method
  - Parse `<!-- persona-version: X | agent: Y -->` regex from first line of persona content
  - Compute SHA-256 hash of trimmed content using Node.js `crypto` module
  - Fallback: `{ id: "unknown", version: "0.0.0", hash: computedHash }`
  - **AC**: AC-1, AC-2, AC-5, AC-6

- [ ] **Task 5.2**: Wire persona metadata through the pipeline
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - In constructor or init, parse persona metadata from `this.persona`
  - Store as `this.personaMetadata: PersonaMetadata`
  - In `processItemTwoPass()`, include `personaId` and `personaHash` in result fields passed to `postAndFinalize()`
  - **AC**: AC-3, AC-7

- [ ] **Task 5.3**: Add persona attribution to enrichment output
  - File: `.claude/skills/bridgebuilder-review/resources/core/template.ts`
  - In `buildEnrichmentPrompt()`, add instruction at end of "Your Task" section:
    - "Include this attribution line at the very end of the review: `*Reviewed with: {personaId} v{personaVersion}*`"
  - Accept `personaMetadata?: PersonaMetadata` as optional parameter (not breaking)
  - Only render attribution instruction when personaMetadata is provided
  - **AC**: AC-4, AC-7

- [ ] **Task 5.4**: Update `ReviewResult` type
  - File: `.claude/skills/bridgebuilder-review/resources/core/types.ts`
  - Add `personaId?: string` and `personaHash?: string` to `ReviewResult`
  - **AC**: AC-3

- [ ] **Task 5.5**: Add comprehensive tests
  - File: `.claude/skills/bridgebuilder-review/resources/__tests__/reviewer.test.ts`
  - Test 1: Persona with valid frontmatter → correct id, version, hash extracted
  - Test 2: Persona with no frontmatter → defaults to unknown/0.0.0 with hash
  - Test 3: Two-pass ReviewResult includes personaId and personaHash
  - Test 4: Single-pass ReviewResult does NOT include personaId (no persona loaded)
  - File: `.claude/skills/bridgebuilder-review/resources/__tests__/template.test.ts`
  - Test 5: Enrichment prompt includes attribution instruction when personaMetadata provided
  - Test 6: Enrichment prompt omits attribution instruction when personaMetadata not provided
  - **AC**: AC-7, AC-8

---

## Sprint 6: Ecosystem Context Integration — Pass 0 Prototype (global sprint-68)

**Goal**: Add optional ecosystem context to the enrichment prompt so Pass 2 can draw cross-repository architectural connections. This is the "Cross-Repository Perception" from the deep review — a lightweight Pass 0 that loads pattern hints before enrichment begins.

**Source**: [Deep Review Part 3, Permission 1](https://github.com/0xHoneyJar/loa/pull/411#issuecomment-3955290750) (cross-repository perception), [Deep Review Part 2, Section IV](https://github.com/0xHoneyJar/loa/pull/411#issuecomment-3955269032) (four cross-ecosystem connections)

**Scope**: 5 tasks

### Deliverables

- [ ] `EcosystemContext` type for structured cross-repo pattern hints
- [ ] `buildEnrichmentPrompt()` renders ecosystem context section when available
- [ ] Config support for ecosystem context file path
- [ ] Template helper for formatting ecosystem patterns
- [ ] Tests validate context rendering, empty context handling, and config resolution

### Acceptance Criteria

- [ ] AC-1: `EcosystemContext` interface with `patterns: Array<{ repo: string; pr?: number; pattern: string; connection: string }>` and `lastUpdated: string`
- [ ] AC-2: `buildEnrichmentPrompt()` includes "## Ecosystem Context" section when ecosystemContext is provided and non-empty
- [ ] AC-3: Each pattern rendered as: `- **{repo}** (PR #{pr}): {pattern} — *Connection*: {connection}`
- [ ] AC-4: When ecosystemContext is undefined or has empty patterns array, section is omitted entirely
- [ ] AC-5: Config supports `ecosystem_context_path?: string` in YAML config with provenance tracking
- [ ] AC-6: Ecosystem context is loaded from file path at pipeline start (not per-item) — it's static per run
- [ ] AC-7: All existing tests pass with zero modification
- [ ] AC-8: At least 6 new tests

### Technical Tasks

- [ ] **Task 6.1**: Create `EcosystemContext` type
  - File: `.claude/skills/bridgebuilder-review/resources/core/types.ts`
  - Add `EcosystemContext` interface:
    ```
    patterns: Array<{ repo: string; pr?: number; pattern: string; connection: string }>
    lastUpdated: string
    ```
  - Add `ecosystemContext?: EcosystemContext` to `ReviewItem` (optional — no breaking change)
  - **AC**: AC-1, AC-7

- [ ] **Task 6.2**: Add ecosystem context rendering to enrichment prompt
  - File: `.claude/skills/bridgebuilder-review/resources/core/template.ts`
  - Add private helper: `renderEcosystemContext(ctx: EcosystemContext): string[]`
  - Renders "## Ecosystem Context" header + pattern list
  - Each pattern: `- **{repo}** (PR #{pr}): {pattern} — *Connection*: {connection}`
  - If pr is undefined, omit the `(PR #N)` part
  - In `buildEnrichmentPrompt()`, accept optional `ecosystemContext?: EcosystemContext`
  - Render section between PR context and findings (before "## Convergence Findings")
  - Only render when ecosystemContext has at least one pattern
  - **AC**: AC-2, AC-3, AC-4, AC-7

- [ ] **Task 6.3**: Add ecosystem context config resolution
  - File: `.claude/skills/bridgebuilder-review/resources/config.ts`
  - Add `ecosystem_context_path?: string` to `YamlConfig` interface
  - Add `ecosystemContextPath` to effective config resolution with provenance
  - Default: undefined (feature is opt-in)
  - Env override: `BRIDGEBUILDER_ECOSYSTEM_CONTEXT` (path to JSON file)
  - **AC**: AC-5, AC-7

- [ ] **Task 6.4**: Load ecosystem context at pipeline initialization
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - In `ReviewPipeline` constructor, if `config.ecosystemContextPath` is set:
    - Read JSON file, validate schema (must have `patterns` array)
    - Store as `this.ecosystemContext: EcosystemContext | undefined`
    - On parse error, log warning and continue without ecosystem context
  - In `processItemTwoPass()`, pass `this.ecosystemContext` to `buildEnrichmentPrompt()`
  - **AC**: AC-6, AC-7

- [ ] **Task 6.5**: Add comprehensive tests
  - File: `.claude/skills/bridgebuilder-review/resources/__tests__/template.test.ts`
  - Test 1: Enrichment prompt includes ecosystem context section when patterns provided
  - Test 2: Enrichment prompt omits section when ecosystemContext undefined
  - Test 3: Enrichment prompt omits section when patterns array is empty
  - Test 4: Pattern with PR number renders correctly
  - Test 5: Pattern without PR number omits PR reference
  - File: `.claude/skills/bridgebuilder-review/resources/__tests__/reviewer.test.ts`
  - Test 6: Pipeline loads ecosystem context from config path
  - Test 7: Pipeline handles missing/malformed ecosystem context file gracefully
  - File: `.claude/skills/bridgebuilder-review/resources/__tests__/config.test.ts`
  - Test 8: Ecosystem context path resolved from YAML config with provenance
  - **AC**: AC-7, AC-8

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Confidence scoring degrades convergence pass focus | Medium | Confidence is optional — models can ignore it. Calibration guidance keeps it lightweight. |
| Persona frontmatter parsing fails on edge cases | Low | Robust fallback to `unknown/0.0.0` with hash. Regex tested against real persona file. |
| Ecosystem context file schema drift | Low | JSON validation at load time. Graceful fallback on parse error. |
| Token budget impact from additional prompt sections | Medium | Confidence guidance is ~100 tokens. Ecosystem context is bounded by pattern count. Both are conditional. |
| Backward compatibility with single-pass mode | Low | All new features are two-pass-only with optional parameters. Single-pass path untouched. |

## Dependencies

- Sprint 4 (confidence) and Sprint 5 (persona provenance) are independent — can execute in parallel
- Sprint 6 (ecosystem context) depends on Sprint 5 (persona metadata is passed alongside ecosystem context in enrichment prompt) — but only weakly (Sprint 6 can execute without Sprint 5 if needed)

## Success Metrics

| Metric | Target |
|--------|--------|
| All existing 380 tests pass | 100% — zero regressions |
| New test coverage | 20+ new tests across 3 sprints |
| Confidence field adoption | LLM includes confidence on >50% of findings (measured in next bridge run) |
| Persona provenance | Every two-pass ReviewResult includes personaId and personaHash |
| Ecosystem context rendering | Correctly formatted when file exists, silently omitted when not |
