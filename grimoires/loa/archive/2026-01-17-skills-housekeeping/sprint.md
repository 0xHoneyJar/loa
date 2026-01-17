# Sprint Plan: RLM-Inspired Context Improvements

**Version**: 1.0.0
**Date**: 2026-01-17
**Status**: Active
**PRD Reference**: `grimoires/loa/prd.md`
**SDD Reference**: `grimoires/loa/sdd.md`
**Feature Branch**: `feature/rlm-context-improvements`

---

## Overview

This sprint plan breaks down the RLM-Inspired Context Improvements feature into 6 focused sprints. The implementation follows the SDD's phased approach: probe infrastructure, skill integration, schema validation, benchmarking, quality assurance, and validation.

**Total Estimated Effort**: ~780 lines of new/modified code
**Sprint Duration**: Each sprint represents a logical unit of work
**Team**: Solo developer with AI assistance

---

## Sprint Summary

| Sprint | Focus | Key Deliverables | Priority |
|--------|-------|------------------|----------|
| 1 | Probe Infrastructure | `context_probe_file()`, `context_probe_dir()`, `context_should_load()` | P0 |
| 2 | Ride Skill Enhancement | Phase 0 probing, relevance scoring, loading strategies | P0 |
| 3 | Schema Validation | Assertion helpers, `validate_with_assertions()` | P1 |
| 4 | Benchmark Framework | `rlm-benchmark.sh`, baseline collection | P2 |
| 5 | Quality & Polish | Test coverage, documentation, edge cases | P1 |
| 6 | Validation & Handoff | Integration testing, metrics validation, release | P0 |

---

## Sprint 1: Probe Infrastructure

**Goal**: Implement the core probe-before-load pattern in `context-manager.sh`

**Files Modified**:
- `.claude/scripts/context-manager.sh` (+150 lines)
- `.loa.config.yaml` (+20 lines)

### Tasks

#### Task 1.1: Implement `context_probe_file()` function
**Description**: Create function to probe file metadata without loading content
**Acceptance Criteria**:
- Returns JSON object with: file path, lines, size_bytes, type, extension, estimated_tokens
- Handles missing files gracefully with error JSON
- Uses `wc -l`, `stat`, and `file` commands
- Token estimation uses ~4 chars per token heuristic

**Test Requirements**:
```bash
@test "context_probe_file returns correct metadata for .ts file"
@test "context_probe_file handles missing file gracefully"
@test "context_probe_file estimates tokens correctly"
```

#### Task 1.2: Implement `context_probe_dir()` function
**Description**: Create function to probe directory for file inventory
**Acceptance Criteria**:
- Returns JSON with: directory, total_files, total_lines, files array
- Supports configurable max_depth (default: 3)
- Supports extension filtering (default: ts,js,py,go,rs,sol,sh)
- Excludes node_modules, .git, dist, build by default
- Caps at 100 files to prevent runaway probing

**Test Requirements**:
```bash
@test "context_probe_dir returns file inventory"
@test "context_probe_dir respects max_depth"
@test "context_probe_dir excludes node_modules"
```

#### Task 1.3: Implement `context_should_load()` function
**Description**: Determine if a file should be fully loaded based on probe data
**Acceptance Criteria**:
- Returns decision JSON with: file, decision (load/skip/excerpt), reason, probe data
- Respects `max_eager_load_lines` config threshold
- Integrates with relevance checking for large files
- Exit code 0 for load, 1 for skip

**Test Requirements**:
```bash
@test "context_should_load returns true for small files"
@test "context_should_load returns false for large low-relevance files"
@test "context_should_load returns true for large high-relevance files"
```

#### Task 1.4: Implement `context_check_relevance()` function
**Description**: Calculate relevance score using keyword patterns
**Acceptance Criteria**:
- Returns score 0-10 based on keyword occurrences
- Uses configurable keyword list from `.loa.config.yaml`
- Caps contribution per keyword to prevent single-keyword dominance
- Fast execution (grep-based, not full parse)

**Test Requirements**:
```bash
@test "context_check_relevance returns high score for export-heavy files"
@test "context_check_relevance returns low score for plain text"
```

#### Task 1.5: Add `probe` command to context-manager.sh
**Description**: Add CLI command dispatcher for probe functionality
**Acceptance Criteria**:
- `context-manager.sh probe <path>` works for files and directories
- `--json` flag for machine-readable output
- Help text documents usage
- Error handling for invalid paths

**Test Requirements**:
```bash
@test "probe command works on files"
@test "probe command works on directories"
@test "probe command outputs valid JSON with --json flag"
```

#### Task 1.6: Add configuration options to `.loa.config.yaml`
**Description**: Add new configuration section for probe-before-load
**Acceptance Criteria**:
- `context_management.probe_before_load: true` (default enabled)
- `context_management.max_eager_load_lines: 500`
- `context_management.require_relevance_check: true`
- `context_management.relevance_keywords: [...]`
- `context_management.exclude_patterns: [...]`
- `context_management.token_budget: {...}`

**Test Requirements**:
```bash
@test "config options are respected by probe functions"
```

### Sprint 1 Deliverables
- [ ] All 4 probe functions implemented and passing tests
- [ ] `probe` CLI command functional
- [ ] Configuration options documented
- [ ] Unit tests: `tests/unit/context-manager-probe.bats`

---

## Sprint 2: Ride Skill Enhancement

**Goal**: Integrate probe-before-load into the `/ride` skill

**Files Modified**:
- `.claude/skills/riding-codebase/SKILL.md` (+100 lines for Phase 0, +50 lines for Phase 2 mods)

### Tasks

#### Task 2.1: Add Phase 0: Codebase Probing
**Description**: Insert new phase before existing Phase 1 in SKILL.md
**Acceptance Criteria**:
- Phase 0 runs `context_probe_dir()` on target repository
- Extracts summary: total_files, total_lines, estimated_tokens
- Logs probe results to trajectory
- Determines loading strategy based on codebase size

**Test Requirements**:
- Manual verification with `/ride` on test codebase
- Trajectory log contains Phase 0 entries

#### Task 2.2: Implement loading strategy decision matrix
**Description**: Create decision logic for codebase size categories
**Acceptance Criteria**:
- Small (<10K lines): Load all files
- Medium (10K-50K): Prioritized loading
- Large (>50K): Probe + excerpts only
- Strategy logged to trajectory

**Test Requirements**:
- Verify correct strategy selected for each size category

#### Task 2.3: Generate loading plan
**Description**: Create loading plan based on probe results
**Acceptance Criteria**:
- Files categorized: Will Load Fully, Will Use Excerpts, Will Skip
- Respects exclude patterns from config
- Plan visible in trajectory log
- Plan summary shown to user

**Test Requirements**:
- Loading plan correctly categorizes test files

#### Task 2.4: Modify Phase 2 for targeted loading
**Description**: Update Phase 2 to use loading plan from Phase 0
**Acceptance Criteria**:
- Only files in "Will Load Fully" category are fully read
- Files in "Will Use Excerpts" get grep-based excerpts
- Files in "Will Skip" are not loaded
- Token savings reported at end of ride

**Test Requirements**:
- Verify token reduction on medium/large codebases

#### Task 2.5: Add relevance scoring to file prioritization
**Description**: Use relevance scores to prioritize file loading order
**Acceptance Criteria**:
- High relevance files (score 7+) loaded first
- Medium relevance (4-6) loaded if budget allows
- Low relevance (0-3) skipped unless explicitly requested
- Scoring criteria documented in SKILL.md

**Test Requirements**:
- File loading order respects relevance scores

### Sprint 2 Deliverables
- [ ] Phase 0 fully documented in SKILL.md
- [ ] Phase 2 modifications complete
- [ ] Loading strategy decision matrix implemented
- [ ] Token savings reporting functional
- [ ] Integration test: `/ride` on Loa codebase shows savings

---

## Sprint 3: Schema Validation Enhancement

**Goal**: Add programmatic assertion mode to schema-validator.sh

**Files Modified**:
- `.claude/scripts/schema-validator.sh` (+100 lines)

### Tasks

#### Task 3.1: Implement `assert_field_exists()` function
**Description**: Assert that a field exists in JSON/YAML data
**Acceptance Criteria**:
- Returns 0 if field exists, 1 if missing
- Outputs "ASSERTION_FAILED: Field 'X' does not exist" on failure
- Works with nested fields using dot notation
- Handles null values appropriately

**Test Requirements**:
```bash
@test "assert_field_exists passes for existing field"
@test "assert_field_exists fails for missing field"
```

#### Task 3.2: Implement `assert_field_matches()` function
**Description**: Assert that a field value matches a regex pattern
**Acceptance Criteria**:
- Returns 0 if matches, 1 if not
- Outputs "ASSERTION_FAILED: Field 'X' value 'Y' does not match pattern 'Z'"
- Handles missing fields gracefully
- Supports common patterns (semver, status enums, dates)

**Test Requirements**:
```bash
@test "assert_field_matches passes for valid version"
@test "assert_field_matches fails for invalid status"
```

#### Task 3.3: Implement `assert_array_not_empty()` function
**Description**: Assert that an array field has at least one element
**Acceptance Criteria**:
- Returns 0 if array length > 0, 1 if empty
- Outputs "ASSERTION_FAILED: Array 'X' is empty"
- Handles missing field as empty array

**Test Requirements**:
```bash
@test "assert_array_not_empty passes for populated array"
@test "assert_array_not_empty fails for empty array"
```

#### Task 3.4: Implement `validate_with_assertions()` function
**Description**: Run schema-specific assertions on a file
**Acceptance Criteria**:
- Extracts frontmatter/data from markdown files
- Runs appropriate assertions based on schema type
- Returns list of all failed assertions
- Supports: prd, sdd, sprint, trajectory-entry schemas

**Test Requirements**:
```bash
@test "validate_with_assertions passes for valid PRD"
@test "validate_with_assertions fails for invalid SDD"
```

#### Task 3.5: Add `assert` command to schema-validator.sh
**Description**: Add CLI command for running assertions
**Acceptance Criteria**:
- `schema-validator.sh assert <file>` runs assertions
- `--schema <name>` overrides auto-detection
- `--json` for machine-readable output
- Returns non-zero exit code if any assertion fails

**Test Requirements**:
```bash
@test "assert command validates PRD file"
@test "assert command outputs JSON with --json"
```

#### Task 3.6: Integrate with grounding-check.sh
**Description**: Add assertions as a verification type in grounding check
**Acceptance Criteria**:
- `grounding-check.sh --include-assertions` runs schema assertions
- Assertion failures count against grounding ratio
- Clear reporting of which assertions passed/failed

**Test Requirements**:
- Grounding check includes assertion results

### Sprint 3 Deliverables
- [ ] All 3 assertion helper functions implemented
- [ ] `validate_with_assertions()` covers all schema types
- [ ] `assert` CLI command functional
- [ ] Integration with grounding-check.sh
- [ ] Unit tests: `tests/unit/schema-validator-assert.bats`

---

## Sprint 4: Benchmark Framework

**Goal**: Create benchmark infrastructure to measure RLM pattern effectiveness

**Files Created**:
- `.claude/scripts/rlm-benchmark.sh` (~350 lines)
- `grimoires/pub/research/benchmarks/` directory structure

### Tasks

#### Task 4.1: Create rlm-benchmark.sh script skeleton
**Description**: Set up script structure with command dispatcher
**Acceptance Criteria**:
- Standard Loa script structure (set -euo pipefail, sourcing, help)
- Commands: run, baseline, compare, history, report
- Configuration loading from `.loa.config.yaml`
- JSON output support with --json flag

**Test Requirements**:
```bash
@test "rlm-benchmark.sh --help shows usage"
```

#### Task 4.2: Implement `benchmark_current_pattern()` function
**Description**: Simulate current loading pattern (load all files)
**Acceptance Criteria**:
- Counts total files, total lines, estimated tokens
- Measures time to enumerate all files
- Does not actually load content (simulates token cost)
- Returns metrics JSON

**Test Requirements**:
```bash
@test "benchmark_current_pattern returns metrics for codebase"
```

#### Task 4.3: Implement `benchmark_rlm_pattern()` function
**Description**: Simulate RLM loading pattern (probe + selective)
**Acceptance Criteria**:
- Runs probe phase first
- Applies relevance filtering
- Calculates reduced token count
- Measures probe overhead
- Returns metrics JSON including savings percentage

**Test Requirements**:
```bash
@test "benchmark_rlm_pattern shows token reduction"
```

#### Task 4.4: Implement `cmd_run` command
**Description**: Run benchmark comparison on a codebase
**Acceptance Criteria**:
- Runs both patterns on specified directory
- Outputs comparison table with: mode, files, lines, tokens, time
- Calculates token_reduction_percent
- Supports --iterations for statistical significance

**Test Requirements**:
```bash
@test "run command produces comparison data"
```

#### Task 4.5: Implement `cmd_baseline` command
**Description**: Capture baseline metrics for future comparison
**Acceptance Criteria**:
- Saves current metrics to `grimoires/pub/research/benchmarks/baseline.json`
- Includes timestamp, codebase path, metrics
- Warns if baseline already exists (--force to overwrite)

**Test Requirements**:
```bash
@test "baseline command creates baseline.json"
```

#### Task 4.6: Implement `cmd_compare` command
**Description**: Compare current metrics against baseline
**Acceptance Criteria**:
- Loads baseline from file
- Runs current benchmark
- Shows delta for each metric
- Highlights improvements/regressions with colors
- Outputs pass/fail based on PRD targets

**Test Requirements**:
```bash
@test "compare command shows delta from baseline"
```

#### Task 4.7: Implement `cmd_report` command
**Description**: Generate markdown report for research folder
**Acceptance Criteria**:
- Creates `grimoires/pub/research/benchmarks/report-{date}.md`
- Includes: methodology, results table, analysis, conclusions
- Charts represented as ASCII tables
- References PRD success criteria

**Test Requirements**:
```bash
@test "report command generates markdown file"
```

### Sprint 4 Deliverables
- [ ] `rlm-benchmark.sh` fully functional
- [ ] All 5 commands implemented
- [ ] Baseline collected on Loa codebase
- [ ] Initial benchmark report generated
- [ ] Unit tests: `tests/unit/rlm-benchmark.bats`

---

## Sprint 5: Quality & Polish

**Goal**: Comprehensive testing, documentation, and edge case handling

**Files Modified**:
- Test files in `tests/`
- Documentation in CLAUDE.md
- Error handling across all modified scripts

### Tasks

#### Task 5.1: Create comprehensive unit test suite
**Description**: Ensure >80% coverage for new functionality
**Acceptance Criteria**:
- `tests/unit/context-manager-probe.bats` complete (15+ tests)
- `tests/unit/schema-validator-assert.bats` complete (10+ tests)
- `tests/unit/rlm-benchmark.bats` complete (10+ tests)
- All tests pass in CI

**Test Requirements**:
- Run full test suite: `bats tests/unit/`

#### Task 5.2: Create integration tests
**Description**: Test end-to-end workflows
**Acceptance Criteria**:
- `tests/integration/probe-ride-workflow.bats` tests /ride with probing
- `tests/integration/benchmark-workflow.bats` tests benchmark lifecycle
- Tests use realistic codebase fixtures

**Test Requirements**:
- Run: `bats tests/integration/`

#### Task 5.3: Add edge case handling
**Description**: Handle unusual inputs gracefully
**Acceptance Criteria**:
- Empty directories don't crash probe
- Binary files are detected and skipped
- Symlink loops are detected
- Permission denied errors are caught
- Unicode filenames work correctly

**Test Requirements**:
```bash
@test "probe handles empty directory"
@test "probe skips binary files"
@test "probe detects symlink loops"
```

#### Task 5.4: Update CLAUDE.md documentation
**Description**: Document new functionality for users
**Acceptance Criteria**:
- Context Manager section updated with probe commands
- Schema Validator section updated with assert commands
- New rlm-benchmark.sh section added
- Configuration options documented
- Examples provided for common use cases

#### Task 5.5: Add trajectory logging for all new operations
**Description**: Ensure full audit trail
**Acceptance Criteria**:
- Probe operations logged with metrics
- Assertion results logged
- Benchmark runs logged
- All logs follow trajectory-entry schema

**Test Requirements**:
- Verify trajectory entries created for each operation

#### Task 5.6: Performance optimization
**Description**: Ensure probe overhead meets <5% target
**Acceptance Criteria**:
- Probe operations complete in <100ms for typical codebase
- No unnecessary file I/O
- jq operations minimized for large outputs
- Caching considered for repeated probes

**Test Requirements**:
- Benchmark probe time vs full load time

### Sprint 5 Deliverables
- [ ] 35+ unit tests passing
- [ ] Integration tests passing
- [ ] Edge cases handled
- [ ] Documentation complete
- [ ] Trajectory logging verified
- [ ] Performance within targets

---

## Sprint 6: Validation & Handoff

**Goal**: Validate success criteria and prepare for release

### Tasks

#### Task 6.1: Validate PRD success criteria
**Description**: Verify all PRD metrics are met
**Acceptance Criteria**:
- [ ] `/ride` uses 30% fewer tokens on codebases >50K lines (benchmark report)
- [ ] Accuracy improves 25% on standardized test suite (manual verification)
- [ ] Probe functions add <5% overhead (benchmark timing)
- [ ] Schema validation catches 100% of structural errors (test suite)
- [ ] Benchmark data published to research folder

#### Task 6.2: Run benchmark on test codebases
**Description**: Collect final benchmark data
**Acceptance Criteria**:
- Loa (self) - ~15K lines, medium complexity
- At least one external codebase for validation
- Results documented in `grimoires/pub/research/benchmarks/final-report.md`

#### Task 6.3: Create release notes
**Description**: Document changes for v0.14.0 release
**Acceptance Criteria**:
- Feature summary with user benefits
- Configuration migration guide (if any)
- Breaking changes documented (none expected)
- Acknowledgment of RLM research source

#### Task 6.4: Security review
**Description**: Ensure no security issues introduced
**Acceptance Criteria**:
- No command injection in probe functions
- No path traversal vulnerabilities
- Safe handling of untrusted file content
- Config values validated before use

#### Task 6.5: Final integration testing
**Description**: Full workflow test
**Acceptance Criteria**:
- Fresh project setup works
- `/mount` + `/ride` with probing works
- Schema validation integrated
- Benchmark produces valid reports
- No regressions in existing functionality

#### Task 6.6: Version bump and PR
**Description**: Prepare release
**Acceptance Criteria**:
- Version bumped to 0.14.0 in `.loa-version.json`
- Checksums regenerated
- PR created with full description
- CI passes

### Sprint 6 Deliverables
- [ ] All PRD metrics validated
- [ ] Final benchmark report published
- [ ] Release notes complete
- [ ] Security review passed
- [ ] Integration tests passed
- [ ] PR ready for merge

---

## Risk Mitigation

| Risk | Mitigation | Sprint |
|------|------------|--------|
| Probe overhead exceeds 5% | Cache probe results, optimize jq usage | 5 |
| Relevance scoring misses files | Conservative defaults, user override config | 2 |
| Breaking existing /ride | Feature flag `probe_before_load`, rollback plan | 1 |
| Benchmark results inconclusive | Multiple test codebases, statistical iterations | 4 |

---

## Dependencies

| Sprint | Depends On | Blocking |
|--------|------------|----------|
| Sprint 1 | None | Sprint 2 |
| Sprint 2 | Sprint 1 | Sprint 5 |
| Sprint 3 | None | Sprint 5 |
| Sprint 4 | Sprint 1 | Sprint 6 |
| Sprint 5 | Sprint 2, 3, 4 | Sprint 6 |
| Sprint 6 | Sprint 5 | Release |

**Critical Path**: Sprint 1 -> Sprint 2 -> Sprint 5 -> Sprint 6

---

## Success Metrics Summary

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Token reduction | -30% | `rlm-benchmark.sh compare` |
| Accuracy improvement | +25% | Manual testing on large codebase |
| Probe overhead | <5% | Benchmark timing data |
| Test coverage | >80% | Test suite results |
| Zero regressions | 0 | Existing test suite |

---

*Sprint plan generated by planning-sprints agent*
*Source: PRD and SDD for RLM-Inspired Context Improvements*
