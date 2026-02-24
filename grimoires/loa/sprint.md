# Sprint Plan: Two-Pass Bridge Review (cycle-039)

## Overview

**PRD:** grimoires/loa/prd.md v1.0
**SDD:** grimoires/loa/sdd.md v1.0
**Sprints:** 1 (single sprint, all changes internal to bridgebuilder-review skill)
**Scope:** FR-1 through FR-5

---

## Sprint 1: Two-Pass Bridge Review Pipeline (global sprint-63)

**Goal**: Split the single-LLM-call bridge review into two sequential passes (convergence + enrichment) with fallback safety and full test coverage.

**Scope**: MEDIUM (6 tasks)

### Deliverables

- [ ] `types.ts` extended with `reviewMode` config field and pass-level token tracking on `ReviewResult`
- [ ] `config.ts` resolves `reviewMode` through the existing 5-level precedence chain (CLI > env > YAML > auto-detect > default)
- [ ] `template.ts` has convergence-only prompt builders (no persona) and enrichment prompt builder (persona + findings JSON, no diff)
- [ ] `reviewer.ts` has `processItemTwoPass()` with Pass 1 → Pass 2 flow, finding preservation guard, and fallback to unenriched output
- [ ] All existing tests pass unchanged
- [ ] New tests cover two-pass flow, prompt construction, finding preservation validation, fallback paths, and config resolution

### Acceptance Criteria

- [ ] AC-1: Two-pass mode is the default (`reviewMode: "two-pass"`) — from PRD FR-4.1: `review_mode: "two-pass" | "single-pass"` (default: `"two-pass"`)
- [ ] AC-2: Pass 1 system prompt contains `INJECTION_HARDENING` but NOT persona content — from PRD FR-1.3, FR-1.4, FR-1.5
- [ ] AC-3: Pass 1 output format requests ONLY findings JSON inside `<!-- bridge-findings-start/end -->` markers — from PRD FR-1.1, FR-1.2
- [ ] AC-4: Pass 2 receives findings JSON + condensed PR metadata (file list, no diffs) + full persona — from PRD FR-2.1, FR-2.2, FR-2.3; SDD 3.3
- [ ] AC-5: Pass 2 failure (LLM error, timeout, invalid response) falls back to Pass 1 unenriched output — from PRD FR-2.7; SDD 5.2
- [ ] AC-6: Finding preservation guard rejects if Pass 2 changes finding count, IDs, or severities — from PRD FR-2.4; SDD 3.6
- [ ] AC-7: `reviewMode: "single-pass"` in config runs the existing single-pass path unchanged — from PRD FR-3.5
- [ ] AC-8: Combined Pass 2 output passes `isValidResponse()` check (`## Summary` + `## Findings`) — from PRD FR-3.3
- [ ] AC-9: Combined output parseable by `bridge-findings-parser.sh` (v2 JSON format) — from PRD FR-3.4
- [ ] AC-10: `ReviewResult` includes `pass1Tokens` and `pass2Tokens` for observability — from PRD FR-5.1; SDD 3.9
- [ ] AC-11: Config resolves `review_mode` from CLI (`--review-mode`), env (`LOA_BRIDGE_REVIEW_MODE`), YAML (`bridgebuilder.review_mode`), default (`"two-pass"`) — from PRD FR-4.1 through FR-4.4
- [ ] AC-12: All existing reviewer, template, config, and integration tests pass without modification — from PRD non-goal: "preserve existing architecture"

### Technical Tasks

- [ ] **Task 1.1**: Extend `types.ts` — add `reviewMode` to `BridgebuilderConfig`, add `pass1Output`, `pass1Tokens`, `pass2Tokens` to `ReviewResult` → **[G-1, G-3]**
  - File: `.claude/skills/bridgebuilder-review/resources/core/types.ts`
  - Add `reviewMode: "two-pass" | "single-pass"` to `BridgebuilderConfig` interface
  - Add `pass1Output?: string` to `ReviewResult` for observability (FR-5.2)
  - Add `pass1Tokens?: { input: number; output: number; duration: number }` to `ReviewResult`
  - Add `pass2Tokens?: { input: number; output: number; duration: number }` to `ReviewResult`
  - **AC**: AC-10

- [ ] **Task 1.2**: Extend `config.ts` — add `reviewMode` resolution through 5-level precedence → **[G-3]**
  - File: `.claude/skills/bridgebuilder-review/resources/config.ts`
  - Add `review_mode?: "two-pass" | "single-pass"` to `YamlConfig` interface
  - Add `reviewMode?: string` to `CLIArgs` and `--review-mode` parsing in `parseCLIArgs()`
  - Add `LOA_BRIDGE_REVIEW_MODE?: string` to `EnvVars` interface
  - Resolve in `resolveConfig()`: `cliArgs.reviewMode ?? env.LOA_BRIDGE_REVIEW_MODE ?? yaml.review_mode ?? DEFAULTS.reviewMode`
  - Add to `DEFAULTS`: `reviewMode: "two-pass" as const`
  - Add `reviewMode` to `formatEffectiveConfig()` output
  - Add `reviewMode` to `ConfigProvenance` interface
  - **AC**: AC-1, AC-7, AC-11

- [ ] **Task 1.3**: Add convergence and enrichment prompt builders to `template.ts` → **[G-1, G-2]**
  - File: `.claude/skills/bridgebuilder-review/resources/core/template.ts`
  - Add `CONVERGENCE_INSTRUCTIONS` constant — analytical-only review instructions requesting findings JSON only, no persona, no enrichment fields (SDD 3.1)
  - Add `buildConvergenceSystemPrompt(): string` — returns `INJECTION_HARDENING + CONVERGENCE_INSTRUCTIONS` (SDD 3.1)
  - Add `buildConvergenceUserPrompt(item: ReviewItem, truncated: TruncationResult): string` — reuses PR metadata + file diff rendering from `buildUserPrompt()`, replaces "Expected Response Format" with convergence-specific format requesting only `<!-- bridge-findings-start/end -->` JSON (SDD 3.2)
  - Add `buildConvergenceUserPromptFromTruncation(item: ReviewItem, truncResult: ProgressiveTruncationResult, loaBanner?: string): string` — same convergence format but built from progressive truncation result (SDD 3.2)
  - Add `buildEnrichmentPrompt(findingsJSON: string, item: ReviewItem, persona: string): PromptPair` — system prompt uses existing `buildSystemPrompt(persona)`, user prompt contains condensed PR metadata (file list with stats, NO diffs) + Pass 1 findings JSON + enrichment instructions (add educational fields, generate prose, preserve all findings) (SDD 3.3)
  - **AC**: AC-2, AC-3, AC-4

- [ ] **Task 1.4**: Implement two-pass flow in `reviewer.ts` → **[G-1, G-2, G-3]**
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - Add `extractFindingsJSON(content: string): string | null` — parses findings block from `<!-- bridge-findings-start/end -->` markers, strips code fences, validates JSON has `findings` array, returns JSON string or null (SDD 3.5)
  - Add `validateFindingPreservation(pass1JSON: string, pass2JSON: string): boolean` — checks same finding count, same IDs (order-independent via Set comparison), same severities; returns false on any mismatch (SDD 3.6)
  - Add `finishWithUnenrichedOutput(item: ReviewItem, pass1Response: ReviewResponse, findingsJSON: string): Promise<ReviewResult>` — wraps Pass 1 findings in minimal valid review format (`## Summary` + `## Findings` with markers + `## Callouts`), continues through sanitize + post path (SDD 3.7)
  - Add `processItemTwoPass(item, effectiveItem, incrementalBanner, loaBanner): Promise<ReviewResult>` — full two-pass flow:
    - Pass 1: build convergence prompt → progressive truncation → LLM call 1 → extract findings → save pass1 output
    - Pass 2: build enrichment prompt → LLM call 2 → validate finding preservation → on any failure, fall back to `finishWithUnenrichedOutput()`
    - Populate `pass1Tokens`, `pass2Tokens`, `pass1Output` on result
  - Modify `processItem()` — add gate: `if (this.config.reviewMode === "two-pass") return this.processItemTwoPass(...)` before existing single-pass code (SDD 3.4)
  - **AC**: AC-5, AC-6, AC-8, AC-9, AC-10

- [ ] **Task 1.5**: Create test fixtures for pass validation → **[G-1]**
  - Directory: `.claude/skills/bridgebuilder-review/resources/__tests__/fixtures/`
  - Create `pass1-valid-findings.txt` — well-formed Pass 1 output with `<!-- bridge-findings-start -->` / `<!-- bridge-findings-end -->` markers containing valid findings JSON with 3 findings (CRITICAL, MEDIUM, PRAISE)
  - Create `pass1-no-markers.txt` — prose-only Pass 1 output without bridge-findings markers (should cause fallback)
  - Create `pass2-enriched-valid.txt` — valid combined enriched output with `## Summary`, enriched findings JSON (same 3 IDs + educational fields), `## Findings`, `## Callouts`
  - Create `pass2-finding-added.txt` — Pass 2 output with 4 findings (one extra) — should fail preservation check
  - Create `pass2-severity-changed.txt` — Pass 2 output with same 3 IDs but one severity changed from MEDIUM to HIGH — should fail preservation check
  - **AC**: AC-6, AC-9

- [ ] **Task 1.6**: Add unit and integration tests for two-pass pipeline → **[G-1, G-2, G-3]**
  - Files: `.claude/skills/bridgebuilder-review/resources/__tests__/reviewer.test.ts`, `template.test.ts`, `config.test.ts`
  - **reviewer.test.ts** additions:
    - Test: two-pass mode calls LLM twice (mock LLM tracks call count)
    - Test: single-pass mode calls LLM once (config `reviewMode: "single-pass"`)
    - Test: `extractFindingsJSON()` parses valid findings block from fixture
    - Test: `extractFindingsJSON()` returns null for missing markers
    - Test: `extractFindingsJSON()` returns null for invalid JSON
    - Test: `validateFindingPreservation()` passes when only enrichment fields added
    - Test: `validateFindingPreservation()` fails on count mismatch
    - Test: `validateFindingPreservation()` fails on ID change
    - Test: `validateFindingPreservation()` fails on severity reclassification
    - Test: Pass 2 LLM failure falls back to unenriched output (mock LLM throws on second call)
    - Test: Pass 2 finding modification falls back to unenriched output
    - Test: fallback output passes `isValidResponse()` check
    - Test: `ReviewResult` includes `pass1Tokens` and `pass2Tokens` in two-pass mode
  - **template.test.ts** additions:
    - Test: `buildConvergenceSystemPrompt()` contains INJECTION_HARDENING
    - Test: `buildConvergenceSystemPrompt()` does NOT contain persona text
    - Test: `buildConvergenceUserPrompt()` includes file diffs
    - Test: `buildConvergenceUserPrompt()` requests findings JSON output format only
    - Test: `buildEnrichmentPrompt()` includes persona in system prompt
    - Test: `buildEnrichmentPrompt()` includes findings JSON in user prompt
    - Test: `buildEnrichmentPrompt()` includes file list but NOT file diffs/patches
    - Test: `buildEnrichmentPrompt()` instructs not to add/remove/reclassify findings
  - **config.test.ts** additions:
    - Test: default `reviewMode` is `"two-pass"`
    - Test: CLI `--review-mode single-pass` overrides default
    - Test: env `LOA_BRIDGE_REVIEW_MODE` overrides default
    - Test: YAML `review_mode: single-pass` overrides default
    - Test: CLI takes precedence over env and YAML
  - Run full test suite to confirm zero regressions
  - **AC**: AC-1 through AC-12

### Task 1.E2E: End-to-End Goal Validation

- [ ] Verify G-1 (finding quality): Two-pass convergence prompt allocates full cognitive budget to analysis — system prompt contains analytical instructions only, no persona or enrichment objectives
- [ ] Verify G-2 (enrichment quality): Enrichment prompt receives dedicated persona context with findings pre-identified — persona in system prompt, findings JSON + condensed metadata in user prompt
- [ ] Verify G-3 (output compatibility): Combined output passes `isValidResponse()`, parseable by `bridge-findings-parser.sh`, contains `## Summary` + `## Findings`
- [ ] Verify G-4 (architecture preservation): No changes to findings parser, GitHub trail, convergence scorer, persona file, or any downstream consumer
- [ ] Run full existing test suite — zero regressions

### Dependencies

- Task 1.1 (types) blocks Task 1.2 (config) and Task 1.4 (reviewer) — type definitions needed first
- Task 1.3 (template) blocks Task 1.4 (reviewer) — prompt builders consumed by processItemTwoPass
- Task 1.5 (fixtures) blocks Task 1.6 (tests) — test data needed before test code
- Task 1.4 (reviewer) blocks Task 1.6 (tests) — implementation under test

### Risks & Mitigation

| Risk | Mitigation |
|------|-----------|
| Pass 2 LLM adds/removes findings despite instructions | `validateFindingPreservation()` guard with automatic fallback to Pass 1 output (SDD 3.6) |
| Two-pass mode subtly changes output format | Integration test comparing structure against `isValidResponse()` + findings parser (AC-8, AC-9) |
| Config precedence regression | Existing config tests remain unchanged; new tests cover `reviewMode` at all 4 resolution levels (AC-12) |
| Existing tests break from type changes | `reviewMode` has default value in DEFAULTS; `pass1Tokens`/`pass2Tokens`/`pass1Output` are optional fields (AC-12) |

### Success Metrics

- All existing tests pass with zero modification
- 13 new reviewer tests + 8 new template tests + 5 new config tests = 26 new test cases
- Combined output parseable by `bridge-findings-parser.sh`

---

## Appendix A: Task Dependencies

```
Task 1.1 (types) ──┬──→ Task 1.2 (config)
                    │
                    └──→ Task 1.4 (reviewer)
                              ↑
Task 1.3 (template) ─────────┘
                              │
Task 1.5 (fixtures) ──→ Task 1.6 (tests)
                              ↑
                    Task 1.4 ─┘
```

## Appendix B: File Change Map

| File | Change | Lines (est.) |
|------|--------|-------------|
| `resources/core/types.ts` | Add fields to 2 interfaces | +15 |
| `resources/config.ts` | Add reviewMode resolution | +30 |
| `resources/core/template.ts` | Add 4 new methods + 1 constant | +120 |
| `resources/core/reviewer.ts` | Add 4 new methods + gate in processItem | +180 |
| `resources/__tests__/fixtures/` | 5 new test fixture files | +100 |
| `resources/__tests__/reviewer.test.ts` | 13 new test cases | +200 |
| `resources/__tests__/template.test.ts` | 8 new test cases | +120 |
| `resources/__tests__/config.test.ts` | 5 new test cases | +60 |
| **Total** | | **~825 lines** |

## Appendix C: Goal Traceability

| Goal ID | Goal (from PRD Section 2) | Contributing Tasks |
|---------|---------------------------|--------------------|
| G-1 | Improve finding quality — more precise severity classification, fewer false positives, deeper code analysis | 1.1, 1.3, 1.4, 1.5, 1.6, 1.E2E |
| G-2 | Improve enrichment quality — richer FAANG parallels, more specific metaphors, deeper teachable moments | 1.3, 1.4, 1.6, 1.E2E |
| G-3 | Maintain output compatibility — combined output identical to current format | 1.1, 1.2, 1.4, 1.6, 1.E2E |
| G-4 | Preserve existing architecture — no changes to findings parser, GitHub trail, convergence scorer | 1.E2E |
