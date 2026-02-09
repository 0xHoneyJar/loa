# Sprint Plan: Bridgebuilder v2 — Loa-Aware Filtering, Progressive Truncation & Persona Packs

**Version**: 1.1.0 (Flatline-hardened)
**Issue**: #263
**PRD**: `grimoires/loa/prd-bridgebuilder-263.md` (v1.1.0)
**SDD**: `grimoires/loa/sdd-bridgebuilder-263.md` (v1.1.0)
**Date**: 2026-02-09
**Developer**: AI Agent (implementing-tasks)

---

## Flatline Protocol Review Summary

| Metric | Value |
|--------|-------|
| Models | Claude Opus 4.6 + GPT-5.2 |
| Agreement | 90% |
| HIGH_CONSENSUS integrated | 3 (IMP-001, IMP-002, IMP-004) |
| DISPUTED accepted | 1 (IMP-009) |
| BLOCKERS accepted | 5 (SKP-001, SKP-002, SKP-003, SKP-004, SKP-005) |

| ID | Finding | Integration |
|----|---------|-------------|
| IMP-001 | Define token budgets and per-model limits | Task 1.7: Token budget table, Task 1.8: per-model coefficients |
| IMP-002 | Formalize priority algorithm (change size, adjacency, scoring) | Task 1.7: Deterministic priority specification |
| IMP-004 | Resolve repo root vs CWD ambiguity for Loa detection | Task 1.2: Git root resolution |
| IMP-009 | Add lightweight performance guardrails | Task 1.11: Performance validation |
| SKP-001 | Canonical Loa root discovery for monorepos/submodules | Task 1.2: Root discovery mechanism |
| SKP-002 | Augment extension-based tier classification with path heuristics | Task 1.3: Path-based classification |
| SKP-003 | Hunk parsing fallback on malformed diffs | Task 1.7: Safe parser with fallback |
| SKP-004 | Token estimation too naive — need calibration and conservative budget | Task 1.7: Budget constants, Task 1.8: Calibration logging |
| SKP-005 | Security files can blow token budget (lockfiles) — size-aware handling | Task 1.7: Size-capped security handling |

---

## Overview

| Metric | Value |
|--------|-------|
| Total Sprints | 2 |
| Sprint 1 Scope | FR-1 (Loa-Aware Filtering) + FR-2 (Progressive Truncation) |
| Sprint 2 Scope | FR-3 (Persona Packs) + FR-4 (--exclude CLI) |
| Codebase | `.claude/skills/bridgebuilder-review/resources/` (TypeScript) |
| Test Framework | `node:test` + `node:assert/strict` |
| Build | `npx tsc` → `dist/` |
| Existing Tests | 25+ (11 test files) |

---

## Sprint 1: Loa-Aware Filtering + Progressive Truncation (MVP)

**Goal**: Bridgebuilder succeeds on Loa-mounted repos and provides partial reviews instead of zero reviews on large PRs.

**Success Criteria**:
- `prompt_too_large` skip rate drops from ~20% to <5% on large repos
- PRs on Loa-mounted repos get reviews without manual `exclude_patterns` config
- All 25+ existing tests continue passing
- New tests cover Loa detection, two-tier exclusion, and 3 progressive truncation levels

### Task 1.1: Expand SECURITY_PATTERNS Registry

**Description**: Expand the existing `SECURITY_PATTERNS` constant in `truncation.ts` from ~8 patterns to 30+ patterns covering supply-chain (CI/CD workflows, Dockerfiles, Makefiles), infrastructure-as-code (Terraform, Helm, k8s), dependency lockfiles (package-lock.json, yarn.lock, go.sum, etc.), and security policy files (SECURITY.md, CODEOWNERS). Convert from simple regex array to structured `Array<{ pattern, category, rationale }>` format per SDD Section 3.6.

**Files**: `resources/core/truncation.ts`

**Acceptance Criteria**:
- [ ] `SECURITY_PATTERNS` expanded to 30+ entries with category and rationale
- [ ] Existing `isHighRisk()` function updated to use new structure
- [ ] All existing security classification tests still pass
- [ ] New test: `.github/workflows/deploy.yml` classified as high-risk
- [ ] New test: `package-lock.json` classified as high-risk
- [ ] New test: `Dockerfile` classified as high-risk
- [ ] New test: `terraform/main.tf` classified as high-risk
- [ ] New test: `CODEOWNERS` classified as high-risk
- [ ] New test: `src/utils.ts` NOT classified as high-risk (no false positives)

**Dependencies**: None
**Estimated Effort**: Small

---

### Task 1.2: Implement Loa Detection Function

**Description**: Add `detectLoa()` function to `truncation.ts` that reads `.loa-version.json`, validates the `framework_version` key contains a valid semver string, and returns a `LoaDetectionResult`. Support explicit override via `config.loaAware` (true/false/undefined). Add `loaAware` field to `BridgebuilderConfig` in `types.ts`. Per SDD Section 3.1, detection uses synchronous I/O (`fs.existsSync` + `fs.readFileSync`) and runs once per `truncateFiles()` call. Per SKP-001 and IMP-004, resolve file paths against git repo root (not CWD) and support monorepo/submodule layouts.

**Files**: `resources/core/truncation.ts`, `resources/core/types.ts`

**Acceptance Criteria**:
- [ ] `LoaDetectionResult` interface exported from `truncation.ts`
- [ ] `detectLoa(config)` returns `{ isLoa: true, version, source: "file" }` when valid `.loa-version.json` exists
- [ ] Returns `{ isLoa: false, source: "file" }` when file is missing
- [ ] Returns `{ isLoa: false, source: "file" }` + logs warning when file is malformed
- [ ] `config.loaAware === true` forces `{ isLoa: true, source: "config_override" }`
- [ ] `config.loaAware === false` forces `{ isLoa: false, source: "config_override" }`
- [ ] `loaAware?: boolean` added to `BridgebuilderConfig` interface
- [ ] `LOA_EXCLUDE_PATTERNS` constant defined (6 patterns: `.claude/*`, `grimoires/*`, `.beads/*`, `.loa-version.json`, `.loa.config.yaml`, `.loa.config.yaml.example`)
- [ ] (SKP-001) File path resolution uses `repoRoot` from config (git root), NOT `process.cwd()`
- [ ] (SKP-001) If `repoRoot` not available, fall back to CWD with stderr warning
- [ ] (IMP-004) Exclude patterns are resolved relative to git repo root, not CWD

**Dependencies**: None
**Estimated Effort**: Small

---

### Task 1.3: Implement Two-Tier Loa Exclusion

**Description**: Add `applyLoaTierExclusion()` function to `truncation.ts` implementing the two-tier strategy from SDD Section 3.2. Files under Loa paths are classified into Tier 1 (content-excluded: markdown, images, fonts, lock files → name + stats only), Tier 2 (summary-included: executable/config files → first hunk + stats), or Exception (matches `SECURITY_PATTERNS` → full diff, never excluded). Add `extractFirstHunk()` helper for Tier 2 processing. Per SKP-002, augment extension-based classification with path-based heuristics.

**Files**: `resources/core/truncation.ts`

**Acceptance Criteria**:
- [ ] `applyLoaTierExclusion()` correctly classifies files by extension AND path into Tier 1/2/Exception
- [ ] Tier 1 files: `.md`, `.png`, `.jpg`, `.gif`, `.svg`, `.ico`, `.lock`, `.woff`, `.woff2`, `.ttf`, `.eot` → stats only
- [ ] Tier 2 files: `.sh`, `.js`, `.ts`, `.py`, `.yml`, `.yaml`, `.json`, `.toml`, `.mjs`, `.cjs` → first hunk + stats
- [ ] Exception: files matching `SECURITY_PATTERNS` get full diff regardless of extension
- [ ] (SKP-002) Path-based heuristics: files under `.github/`, `infra/`, `deploy/`, `k8s/` paths → Tier 2 minimum (never Tier 1)
- [ ] (SKP-002) `SECURITY.md` under Loa paths → Tier 2 (not Tier 1 despite `.md` extension)
- [ ] (SKP-002) Explicit allow/deny overrides via config `tier_overrides` (optional, future-proofing)
- [ ] `extractFirstHunk()` correctly extracts first hunk from unified diff patch
- [ ] `extractFirstHunk()` returns full patch when only one hunk exists
- [ ] Security check runs BEFORE tier classification (per SDD 3.6)
- [ ] Test: `.github/workflows/ci.yml` under Loa path → Tier 2, not Tier 1
- [ ] Test: `grimoires/loa/SECURITY.md` → Tier 2, not Tier 1
- [ ] Test: large generated `.json` blob under Loa path → Tier 1 (content-excluded, stats only)

**Dependencies**: 1.1, 1.2
**Estimated Effort**: Medium

---

### Task 1.4: Integrate Loa Filtering into truncateFiles()

**Description**: Modify `truncateFiles()` to call `detectLoa()` and `applyLoaTierExclusion()` at the start of the pipeline, before existing pattern exclusion (Step 1). Add Loa-excluded files to the existing exclusion list with tier annotations. Extend `TruncationResult` with `allExcluded`, `loaBanner`, and `loaStats` fields per SDD Section 5. When Loa detected, prepend `LOA_EXCLUDE_PATTERNS` to the combined exclude patterns list.

**Files**: `resources/core/truncation.ts`, `resources/core/types.ts`

**Acceptance Criteria**:
- [ ] `truncateFiles()` calls `detectLoa()` when config available
- [ ] Loa patterns prepended to user `excludePatterns` (not replacing)
- [ ] Two-tier exclusion applied to files matching Loa paths
- [ ] `TruncationResult` extended with `allExcluded: boolean`, `loaBanner?: string`, `loaStats?`
- [ ] `allExcluded = true` when all files removed by Loa filtering
- [ ] `loaBanner` populated: `"[Loa-aware: N framework files excluded (M KB saved)]"`
- [ ] Non-Loa repos: zero behavior change (all existing tests pass)
- [ ] `loaAware` config field flows through from config resolution

**Dependencies**: 1.2, 1.3
**Estimated Effort**: Medium

---

### Task 1.5: Empty Diff and Banner Handling in Reviewer

**Description**: Modify `reviewer.ts` to handle `allExcluded` from truncation result. When all files are excluded by Loa filtering, post a summary comment instead of calling LLM, with skip reason `all_files_excluded`. When Loa files are excluded but application files remain, inject the `loaBanner` into the review prompt. Per SDD Section 3.7, implement `buildPromptFromTruncation()` for deterministic truncation→prompt binding.

**Files**: `resources/core/reviewer.ts`, `resources/core/template.ts`

**Acceptance Criteria**:
- [ ] `allExcluded === true` → post summary comment, skip LLM, skip reason `all_files_excluded`
- [ ] Summary comment text: `"All changes in this PR are Loa framework files. No application code changes to review. Override with loa_aware: false to review framework changes."`
- [ ] `loaBanner` prepended to review prompt when Loa files excluded
- [ ] New prompt sections: `## Summary-Only Files` for Tier 2 content
- [ ] `TruncationPromptBinding` interface implemented per SDD 3.7
- [ ] Template injection order: loaBanner → truncationDisclaimer → PR metadata → files → excluded

**Dependencies**: 1.4
**Estimated Effort**: Medium

---

### Task 1.6: Loa Detection and Exclusion Tests

**Description**: Add unit tests for Loa detection and two-tier exclusion to `truncation.test.ts`. Cover all paths: valid file, missing file, malformed JSON, config overrides, tier classification, security exception, all-files-excluded, and pattern prepending.

**Files**: `resources/__tests__/truncation.test.ts`

**Acceptance Criteria**:
- [ ] Test: `detectLoa` with valid `.loa-version.json` → `isLoa: true`
- [ ] Test: `detectLoa` with missing file → `isLoa: false`
- [ ] Test: `detectLoa` with malformed JSON → `isLoa: false`, no throw
- [ ] Test: `detectLoa` with `loaAware: true` → forces `isLoa: true`
- [ ] Test: `detectLoa` with `loaAware: false` → forces `isLoa: false`
- [ ] Test: Tier 1 `.md` files → content-excluded (stats only)
- [ ] Test: Tier 2 `.ts` files → summary-included (first hunk)
- [ ] Test: Security files (`.claude/auth/`) → never excluded
- [ ] Test: All files excluded → `allExcluded: true`
- [ ] Test: Loa patterns prepend to user patterns (both applied)
- [ ] All 25+ existing truncation tests still pass

**Dependencies**: 1.4
**Estimated Effort**: Medium

---

### Task 1.7: Progressive Truncation Engine (Levels 1-3)

**Description**: Implement `progressiveTruncate()` function in `reviewer.ts` per SDD Section 3.3. Replace the hard-skip block at lines 155-191 with a 3-level retry loop. Level 1: drop low-priority files using deterministic rules (security first, then test adjacency, then change size). Level 2: hunk-based truncation with context window reduction (3→1→0 lines). Level 3: stats-only mode. Implement `isAdjacentTest()`, `truncateToHunks()`, and `reduceHunkContext()` helpers. Per Flatline findings, formalize the priority algorithm, add token budget constants, implement safe hunk parsing with fallback, and add size-aware security file handling.

**Files**: `resources/core/reviewer.ts`

**Token Budget Table** (IMP-001):
| Model | Max Input | Max Output | Estimation Coefficient |
|-------|-----------|------------|----------------------|
| claude-sonnet-4-5-20250929 | 200,000 | 8,192 | 0.25 (chars/token) |
| claude-opus-4-6 | 200,000 | 8,192 | 0.25 |
| gpt-5.2 | 128,000 | 4,096 | 0.23 |
| Default | 100,000 | 4,096 | 0.25 |

**Acceptance Criteria**:
- [ ] `progressiveTruncate()` function with `ProgressiveTruncationResult` return type
- [ ] (IMP-001) `TOKEN_BUDGETS` constant with per-model limits and estimation coefficients (table above)
- [ ] (IMP-001) Token estimation uses model-specific coefficient, not hardcoded `chars/4`
- [ ] (IMP-002) Deterministic priority algorithm formalized:
  - Priority 1: `SECURITY_PATTERNS` match (always keep, but size-capped per SKP-005)
  - Priority 2: Test files where basename matches `*.test.*` or `*.spec.*` AND a same-directory non-test file is in the change set
  - Priority 3: Entry points (`index.*`, `main.*`, `app.*`) and config files (`*.config.*`, `*.json`, `*.yaml`)
  - Priority 4: All remaining files, sorted by `additions + deletions` descending
  - Tie-breaker: alphabetical by filename for stable ordering
- [ ] (IMP-002) "Change size" defined as `additions + deletions` from file stats
- [ ] (IMP-002) "Adjacent test" defined as: test file shares same directory as a changed non-test file
- [ ] Level 1: files retained by priority algorithm above
- [ ] Level 2: `truncateToHunks()` parses diff into hunks, reduces context 3→1→0
- [ ] Level 2: `reduceHunkContext()` keeps changed lines, trims context lines
- [ ] Level 2: annotates files with `[N of M hunks included]`
- [ ] (SKP-003) Hunk parser handles edge cases: renames, binary markers, no-newline-at-EOF, CRLF, missing headers
- [ ] (SKP-003) If hunk parsing fails on a file, fall back to full patch for that file (never crash/skip)
- [ ] (SKP-003) Validation step: if rewritten patch is empty or larger than original, use original
- [ ] Level 3: all patches replaced with empty strings (stats only)
- [ ] Each level re-estimates tokens using model-specific coefficient
- [ ] (SKP-004) Budget target: 90% of `maxInputTokens` (more conservative than 95% to account for estimation variance)
- [ ] (SKP-004) Token estimation tracks prompt components separately: `{ persona, template, metadata, diffs, total }`
- [ ] (SKP-005) Size-aware security handling: security files >50KB get hunk-based summary (not full diff) with disclaimer
- [ ] (SKP-005) Security file size cap: first 10 hunks max, with `[N of M hunks included — file truncated due to size]`
- [ ] (SKP-005) Test: massive `package-lock.json` (100KB+) gets hunk summary, not full diff
- [ ] If all levels fail: return `{ success: false }` → skip reason `prompt_too_large_after_truncation`
- [ ] Existing hard-skip at lines 155-191 replaced (no more bare `prompt_too_large` for over-budget)

**Dependencies**: 1.1
**Estimated Effort**: Large

---

### Task 1.8: Adaptive LLM Retry on Token Rejection

**Description**: Add post-failure adaptive retry per SDD Section 3.3 (SKP-004). When the LLM rejects a prompt with a size error despite our estimation passing, drop to the next truncation level and retry ONCE with an 85% budget. Per SKP-004, use per-model coefficients from `TOKEN_BUDGETS` (defined in Task 1.7) rather than a separate constant. Log actual vs estimated metrics including component breakdown for future calibration.

**Files**: `resources/core/reviewer.ts`

**Acceptance Criteria**:
- [ ] LLM rejection matching: `"prompt_too_large"` or `"maximum context length"` in error
- [ ] On rejection at level N: retry at level N+1 with `budget * 0.85`
- [ ] Retry happens at most ONCE per PR (no retry loops)
- [ ] (SKP-004) Uses per-model coefficient from `TOKEN_BUDGETS` (Task 1.7), not separate constant
- [ ] (SKP-004) Logs component breakdown: `persona={P}, template={T}, metadata={M}, diffs={D}, total={N}, budget={B}`
- [ ] Logs: `estimated={N}, actual_rejection_at={M}, ratio={N/M}`
- [ ] If retry also fails or at level 3: `prompt_too_large_after_truncation`

**Dependencies**: 1.7
**Estimated Effort**: Small

---

### Task 1.9: Disclaimer Injection and Skip Reason Differentiation

**Description**: Inject truncation-level disclaimers into the review prompt per SDD Section 3.3. Differentiate `prompt_too_large` (no truncation attempted — zero files) from `prompt_too_large_after_truncation` (tried all 3 levels). Ensure disclaimers appear in the final posted review via `TruncationPromptBinding`.

**Files**: `resources/core/reviewer.ts`, `resources/core/types.ts`

**Acceptance Criteria**:
- [ ] Level 1 disclaimer: `[Partial Review: N low-priority files excluded]`
- [ ] Level 2 disclaimer: `[Partial Review: patches truncated to changed hunks]`
- [ ] Level 3 disclaimer: `[Summary Review: diff content unavailable, reviewing file structure only]`
- [ ] Skip reason `prompt_too_large_after_truncation` added to types
- [ ] `printSummary()` in `main.ts` correctly reports new skip reasons
- [ ] Disclaimer visible in posted review body

**Dependencies**: 1.7, 1.5
**Estimated Effort**: Small

---

### Task 1.10: Progressive Truncation Tests

**Description**: Add unit tests for progressive truncation to `reviewer.test.ts`. Cover all 3 levels, the all-fail path, disclaimer injection, adaptive retry, and deterministic file ordering. Add E2E golden fixtures per SDD Section 7.2. Per Flatline findings, add specific tests for hunk parser edge cases, size-capped security files, priority algorithm determinism, and token estimation component tracking.

**Files**: `resources/__tests__/reviewer.test.ts`, `resources/__tests__/integration.test.ts`

**Acceptance Criteria**:
- [ ] Test: Level 1 fits budget → drops low-priority files, proceeds
- [ ] Test: Level 2 fits budget → hunk truncation, proceeds
- [ ] Test: Level 3 fits budget → stats only, proceeds
- [ ] Test: All levels fail → `prompt_too_large_after_truncation`
- [ ] Test: Disclaimer text appears in prompt at each level
- [ ] Test: Security files retained at all truncation levels
- [ ] Test: Adaptive retry on LLM rejection drops to next level
- [ ] (IMP-002) Test: Priority ordering is deterministic — same input always produces same file order
- [ ] (IMP-002) Test: Adjacent test detection works (test in same dir as changed app file → priority 2)
- [ ] (IMP-002) Test: Tie-breaker is alphabetical when change size is equal
- [ ] (SKP-003) Test: Hunk parser handles rename diff (no hunks, `rename from`/`rename to`)
- [ ] (SKP-003) Test: Hunk parser handles binary file marker → returns stats only
- [ ] (SKP-003) Test: Hunk parser handles missing hunk header → fallback to full patch
- [ ] (SKP-003) Test: Hunk parser handles no-newline-at-EOF marker (` No newline at end of file`)
- [ ] (SKP-004) Test: Token estimation uses model-specific coefficient, not hardcoded 0.25
- [ ] (SKP-005) Test: Massive lockfile (>50KB) gets hunk summary, not full diff
- [ ] (SKP-005) Test: Small security file (<50KB) gets full diff treatment
- [ ] E2E fixture: `loa-repo-small-pr` (5 app files reviewed, 5 excluded)
- [ ] E2E fixture: `loa-repo-all-framework` (all_files_excluded)
- [ ] E2E fixture: `large-pr-level1` (Level 1 truncation)
- [ ] E2E fixture: `security-in-loa-path` (security file NOT excluded)
- [ ] E2E fixture: `massive-lockfile` (lockfile >50KB gets hunk summary)
- [ ] E2E fixture: `rename-and-binary` (rename/binary diffs parsed without crash)
- [ ] All existing reviewer tests still pass

**Dependencies**: 1.7, 1.8, 1.9
**Estimated Effort**: Large

---

### Task 1.11: Build, Test Suite, and Performance Validation

**Description**: Run `npx tsc` to verify the full build compiles cleanly. Run the complete test suite to verify all existing + new tests pass. Fix any type errors or integration issues discovered during compilation. Per IMP-009, add lightweight performance guardrails to validate that truncation operations complete within acceptable bounds.

**Files**: All modified files

**Acceptance Criteria**:
- [ ] `npx tsc` completes with zero errors
- [ ] All existing 25+ tests pass
- [ ] All new Loa detection tests pass
- [ ] All new progressive truncation tests pass
- [ ] All E2E golden fixtures pass
- [ ] `dist/` output is up to date
- [ ] (IMP-009) No O(n*m) algorithms in truncation or priority sorting (verify no nested loops over file list × pattern list; use Set/Map lookups)
- [ ] (IMP-009) Basic perf test: `progressiveTruncate()` with 200 files completes in <500ms (wall clock, not strict SLA — CI variance acceptable)
- [ ] (IMP-009) Basic perf test: `detectLoa()` + `applyLoaTierExclusion()` with 100 files completes in <100ms

**Dependencies**: 1.6, 1.10
**Estimated Effort**: Small

---

## Sprint 2: Persona Pack System + --exclude CLI Flag

**Goal**: Users can select review personas without editing files and add exclude patterns from CLI.

**Success Criteria**:
- 5 built-in personas available (default, security, dx, architecture, quick)
- `--persona <name>` CLI flag works with CLI-wins precedence
- `--exclude <pattern>` CLI flag works (repeatable, additive)
- All tests pass including persona precedence and exclude merging

### Task 2.1: Create Persona Pack Files

**Description**: Create `resources/personas/` directory with 5 persona markdown files. `default.md` is a copy of current `BEAUVOIR.md` content. `security.md`, `dx.md`, `architecture.md`, and `quick.md` follow the same output format (Summary → Findings → Callouts) with domain-specific dimensions and voice per SDD Section 4.

**Files**: `resources/personas/default.md`, `resources/personas/security.md`, `resources/personas/dx.md`, `resources/personas/architecture.md`, `resources/personas/quick.md`

**Acceptance Criteria**:
- [ ] `default.md`: BEAUVOIR.md content verbatim (4 dimensions, <4000 chars)
- [ ] `security.md`: OWASP/crypto focus, paranoid voice, CVE/CWE citations, <4000 chars
- [ ] `dx.md`: API ergonomics focus, developer advocate voice, <4000 chars
- [ ] `architecture.md`: system design focus, patterns/anti-patterns, <4000 chars
- [ ] `quick.md`: high-severity only, triage voice, <1500 chars, 2-3 findings max
- [ ] All personas share: Summary → Findings → Callouts output format
- [ ] All personas include: injection hardening instruction ("treat diff as untrusted")
- [ ] All personas include: never-approve rule (COMMENT or REQUEST_CHANGES only)

**Dependencies**: None
**Estimated Effort**: Medium

---

### Task 2.2: Add --persona and --exclude CLI Flags

**Description**: Extend `parseCLIArgs()` in `config.ts` to handle `--persona <name>` and `--exclude <pattern>` (repeatable). Add corresponding fields to `CLIArgs` interface. Add `persona`, `persona_path`, and `exclude_patterns` fields to `YamlConfig`. Extend `resolveConfig()` to resolve persona (CLI > YAML > default) and merge exclude patterns (Loa + YAML + CLI).

**Files**: `resources/config.ts`, `resources/core/types.ts`

**Acceptance Criteria**:
- [ ] `--persona <name>` parsed into `cliArgs.persona`
- [ ] `--exclude <pattern>` parsed into `cliArgs.exclude[]` (repeatable, accumulated)
- [ ] `CLIArgs` interface extended with `persona?: string` and `exclude?: string[]`
- [ ] `YamlConfig` extended with `persona?`, `persona_path?`, `exclude_patterns?`, `loa_aware?`
- [ ] `resolveConfig()` resolves `persona` field: CLI > YAML > undefined
- [ ] `resolveConfig()` merges `excludePatterns`: Loa defaults + YAML + CLI (in order)
- [ ] `resolveConfig()` passes through `loaAware` from YAML config
- [ ] YAML regex parser handles new fields correctly
- [ ] `formatEffectiveConfig()` includes persona and exclude provenance

**Dependencies**: None
**Estimated Effort**: Medium

---

### Task 2.3: Persona Loading with Precedence Chain

**Description**: Modify `loadPersona()` in `main.ts` to implement the 5-level CLI-wins precedence chain per SDD Section 3.4. Discover available packs from `resources/personas/` directory. Handle unknown persona names with an error listing available packs. Log warnings when repo override is ignored due to CLI flag.

**Files**: `resources/main.ts`

**Acceptance Criteria**:
- [ ] Precedence chain: `--persona` CLI > `persona:` YAML > `persona_path:` YAML > repo override > bundled default
- [ ] `--persona security` loads `resources/personas/security.md`
- [ ] Unknown persona: throws `Error: Unknown persona "foo". Available: default, security, dx, architecture, quick`
- [ ] Available packs discovered via `fs.readdirSync("resources/personas/")`, filtering `.md`
- [ ] When repo override exists AND CLI flag passed: log warning
- [ ] Backward compat: no CLI/YAML persona → existing `grimoires/bridgebuilder/BEAUVOIR.md` → `resources/personas/default.md`
- [ ] `loadPersona()` returns `{ content: string, source: string }` for logging

**Dependencies**: 2.1, 2.2
**Estimated Effort**: Medium

---

### Task 2.4: Config and Persona Tests

**Description**: Add unit tests for new CLI flags, config resolution, persona precedence, and exclude pattern merging.

**Files**: `resources/__tests__/config.test.ts`, `resources/__tests__/integration.test.ts`

**Acceptance Criteria**:
- [ ] Test: `parseCLIArgs(["--persona", "security"])` → `{ persona: "security" }`
- [ ] Test: `parseCLIArgs(["--exclude", "*.md", "--exclude", "dist/*"])` → `{ exclude: ["*.md", "dist/*"] }`
- [ ] Test: `resolveConfig` persona precedence: CLI > YAML > default
- [ ] Test: `resolveConfig` exclude merging: Loa + YAML + CLI in correct order
- [ ] Test: `resolveConfig` passes through `loaAware` from YAML
- [ ] Test: Unknown persona throws error with available list
- [ ] Test: Persona CLI override logs warning about ignored repo override
- [ ] E2E fixture: `persona-cli-override` (security persona used, warning logged)
- [ ] All existing config tests still pass

**Dependencies**: 2.2, 2.3
**Estimated Effort**: Medium

---

### Task 2.5: Build and Full Test Suite Validation

**Description**: Run `npx tsc` to verify Sprint 2 changes compile cleanly. Run the complete test suite (Sprint 1 + Sprint 2 + existing). Fix any issues.

**Files**: All modified files

**Acceptance Criteria**:
- [ ] `npx tsc` completes with zero errors
- [ ] All existing tests pass
- [ ] All Sprint 1 tests pass
- [ ] All Sprint 2 tests pass (persona, CLI flags, exclude merging)
- [ ] `dist/` output is up to date
- [ ] Manual smoke test: `--persona security --exclude "*.md"` runs without error

**Dependencies**: 2.4
**Estimated Effort**: Small

---

## Risk Assessment

| Risk | Sprint | Mitigation |
|------|--------|------------|
| Hunk parsing fragility on edge-case diffs | Sprint 1 | (SKP-003) Safe parser: validate output, fallback to full patch on failure, fixtures for rename/binary/CRLF/no-header |
| YAML regex parser breaks on new fields | Sprint 2 | New fields follow existing flat key-value pattern; tested |
| Token estimation inaccuracy at truncation boundaries | Sprint 1 | (SKP-004) Per-model coefficients, 90% budget target, component-level tracking, calibration logging |
| Loa detection filesystem assumption in CI | Sprint 1 | (SKP-001/IMP-004) Git root resolution, explicit `loa_aware` config override, CWD fallback with warning |
| Extension-based tier misclassification | Sprint 1 | (SKP-002) Path-based heuristic augmentation, `SECURITY.md` → Tier 2, `.github/` paths → Tier 2 minimum |
| Security files blowing token budget | Sprint 1 | (SKP-005) Size-aware handling: >50KB security files get hunk summary (first 10 hunks), not full diff |
| Priority algorithm non-determinism | Sprint 1 | (IMP-002) Formalized scoring with explicit adjacency rules, change size definition, alphabetical tie-breaker |
| Performance degradation with many files | Sprint 1 | (IMP-009) No O(n*m) algorithms, Set/Map lookups, perf test for 200-file case |

## Dependencies

| Dependency | Status | Sprint Impact |
|------------|--------|---------------|
| #257 (--pr flag fix) | Merged | None |
| #260 (token budget fix) | Merged | None |
| Existing 25+ test suite | Green | Must remain green |
| `node:test` framework | Available | No changes needed |

---

## Task Summary

| Sprint | Tasks | Estimated Effort |
|--------|-------|-----------------|
| Sprint 1 | 11 tasks (1.1-1.11) | 3 Small + 5 Medium + 2 Large + 1 Small = ~45 AC items |
| Sprint 2 | 5 tasks (2.1-2.5) | 1 Small + 3 Medium + 1 Small = ~20 AC items |
| **Total** | **16 tasks** | **~65 acceptance criteria** |
