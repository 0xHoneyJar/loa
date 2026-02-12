# Sprint Plan: Bridgebuilder Persona Enrichment for Automated Bridge Loop

**Version:** 1.1 (Flatline-reviewed)
**Date:** 2026-02-12
**Author:** Sprint Planner Agent
**PRD Reference:** grimoires/loa/prd.md (v1.0.0)
**SDD Reference:** grimoires/loa/sdd.md (v1.1.0, Flatline-reviewed)
**Cycle:** cycle-006
**Issue:** [loa #295](https://github.com/0xHoneyJar/loa/issues/295)
**Flatline:** Sprint plan reviewed — 2 HIGH_CONSENSUS auto-integrated, 6 BLOCKERS accepted, 3 DISPUTED accepted

---

## Executive Summary

Enrich the automated `/run-bridge` loop with Bridgebuilder persona depth: JSON-based findings parser with formal schema, PRAISE severity, educational fields, persona file with integrity verification, dual-stream output (findings for convergence + insights for education), and 13 seed finding fixes. Three sprints build incrementally: foundation fixes and parser redesign, then persona and trail hardening, then validation and integration testing.

**Total Sprints:** 3
**Sprint Duration:** 2.5 days each
**Total Files Modified:** ~15 (scripts, tests, config, constraints, docs)
**Regression Gate:** All existing BATS tests must pass at end of each sprint — any regression is a stop-ship (Flatline SKP-001)

---

## Sprint Overview

| Sprint | Theme | Key Deliverables | Dependencies |
|--------|-------|------------------|--------------|
| 1 | Seed Fixes + Parser Redesign | 13 seed fixes, JSON parser, formal schema, PRAISE severity, flock state, tests | None |
| 2 | Persona + Trail Hardening | Persona file, integrity check, SKILL.md enrichment, size enforcement, threat-modeled redaction, .run/ security, config | Sprint 1 |
| 3 | Validation + Integration | E2E test fixtures, legacy fallback, convergence isolation, lore fixes, version bump | Sprint 2 |

---

## Sprint 1: Seed Fixes + Parser Redesign

**Duration:** 2.5 days

### Sprint Goal

Fix all 13 seed findings from late-arriving iteration-1 review agents and redesign the findings parser from regex-based markdown extraction to JSON fenced-block extraction with formal schema validation, strict grammar enforcement, and legacy fallback.

### Deliverables

- [ ] All CRITICAL and HIGH seed findings (#1-5) resolved
- [ ] All MEDIUM seed findings (#6, 7, 8) resolved
- [ ] Findings parser redesigned to extract JSON fenced blocks between markers
- [ ] Formal JSON Schema for enriched findings created and validated
- [ ] PRAISE severity level (weight=0) recognized by parser and state
- [ ] Atomic state updates via `flock` in `bridge-state.sh` with crash safety
- [ ] `update_flatline()` writes `last_score` to state
- [ ] LOW seed findings (#11, 12, 13) resolved
- [ ] `CLAUDE.loa.md` updated (Three-Zone, danger level, state diagram)
- [ ] Extended BATS tests for parser, state, and edge cases
- [ ] All existing tests still pass (regression gate)

### Acceptance Criteria

- [ ] `bridge-findings-parser.sh` extracts enriched findings from JSON fenced block inside `<!-- bridge-findings-start/end -->` markers
- [ ] Parser enforces **strict grammar**: exactly one findings block per review, markers + JSON fence + schema_version required; fail closed with explicit error on violations (Flatline SKP-002)
- [ ] Parser validates JSON with `jq` and validates against formal JSON Schema (Flatline IMP-003)
- [ ] Parser checks `schema_version` field — warns on unknown version, treats as v1 (SDD 3.2.1, IMP-008)
- [ ] JSON Schema at `tests/fixtures/bridge-findings.schema.json` defines: required fields (id, title, severity, category, file, description, suggestion), optional fields (faang_parallel, metaphor, teachable_moment, connection, praise, potential, weight), severity enum (CRITICAL, HIGH, MEDIUM, LOW, VISION, PRAISE), schema_version as integer (Flatline IMP-003, SKP-003)
- [ ] Parser computes `by_severity` including `praise` count (SDD 3.2.6)
- [ ] `SEVERITY_WEIGHTS["PRAISE"]=0` — PRAISE does not affect `severity_weighted_score`
- [ ] `bridge-state.sh` uses `flock`-based `atomic_state_update()` for all read-modify-write operations (SDD 3.4.1, IMP-004)
- [ ] `atomic_state_update()` hard-fails with clear error message if `flock` is unavailable — no silent non-atomic fallback (Flatline IMP-002)
- [ ] `atomic_state_update()` uses write-to-temp + `mv` (atomic rename) with stale-lock detection (5s timeout on flock, error + cleanup on stale lock) (Flatline SKP-004)
- [ ] `update_flatline()` writes `last_score` to bridge state JSON (SDD 3.4.2, seed HIGH-2)
- [ ] `bridge-github-trail.sh` `cmd_vision` uses printf instead of heredoc (seed HIGH-3)
- [ ] `bridge-github-trail.sh` `cmd_comment` uses `printf '%s'` instead of `echo` (seed MEDIUM-7)
- [ ] `bridge-vision-capture.sh` uses process substitution instead of pipe-to-while (seed MEDIUM-1)
- [ ] `constraints.json` has `bridge` and `eval` in category enum (seed HIGH-4)
- [ ] `CLAUDE.loa.md` includes `.run/` in state zone, `run-bridge` in danger level list, HALTED in state diagram (seeds #9, 11, 13)
- [ ] All existing BATS tests pass, new tests added for JSON extraction, schema validation, edge cases (nested fences, multiple blocks, truncated output), flock safety

### Technical Tasks

- [ ] Task 1.1: Add `extract_and_validate_json()` function to `bridge-findings-parser.sh` — JSON fenced block extraction with **strict grammar**: exactly one findings block, markers required, JSON fence required, fail closed with error code on violations (SDD 3.2.1, Flatline SKP-002) → **[G-1, G-4]**
- [ ] Task 1.2: Rename current `parse_findings()` to `parse_findings_legacy()` and add detection logic — if JSON fenced block detected use new path, else legacy fallback (SDD 3.2.5) → **[G-4]**
- [ ] Task 1.3: Add `PRAISE` to `SEVERITY_WEIGHTS` array with weight 0 and add `praise` to `by_severity` output (SDD 3.2.3, 3.2.6) → **[G-2, G-4]**
- [ ] Task 1.4: Add `schema_version` field to parser output JSON (SDD 3.2.4, IMP-008) → **[G-1]**
- [ ] Task 1.5: Add 5 enriched field passthrough (`faang_parallel`, `metaphor`, `teachable_moment`, `connection`, `praise`) to JSON extraction path (SDD 3.2.4) → **[G-1]**
- [ ] Task 1.6: Implement `atomic_state_update()` function with `flock` in `bridge-state.sh` — hard-fail with clear error if flock unavailable, write-to-temp + atomic rename, stale-lock handling (5s flock timeout, cleanup on stale), never silently fall back to non-atomic (SDD 3.4.1, IMP-004, Flatline IMP-002, SKP-004) → **[G-4]**
- [ ] Task 1.7: Wrap all 5 read-modify-write functions in `bridge-state.sh` with `atomic_state_update()` (SDD 3.4.1) → **[G-4]**
- [ ] Task 1.8: Fix `update_flatline()` to write `last_score` (SDD 3.4.2, seed HIGH-2) → **[G-4]**
- [ ] Task 1.9: Fix `cmd_vision` in `bridge-github-trail.sh` — replace heredoc with printf (seed HIGH-3, SDD 3.5.3) → **[G-4]**
- [ ] Task 1.10: Fix `cmd_comment` in `bridge-github-trail.sh` — replace `echo "$body"` with `printf '%s' "$body"` (seed MEDIUM-7, SDD 3.5.3) → **[G-4]**
- [ ] Task 1.11: Fix `bridge-vision-capture.sh` — replace pipe-to-while with process substitution `< <(...)` (seed MEDIUM-1, SDD 3.6) → **[G-4]**
- [ ] Task 1.12: Add `bridge` and `eval` to category enum in `.claude/data/constraints.json` (seed HIGH-4, SDD 5.2) → **[G-4]**
- [ ] Task 1.13: Add `@constraint-generated: bridge` render target to `CLAUDE.loa.md` (seed HIGH-5, SDD 5.3) → **[G-4]**
- [ ] Task 1.14: Update `CLAUDE.loa.md` — add `.run/` to Three-Zone state paths, add `run-bridge` to `high` danger level list, add HALTED transitions to state diagram (seeds #9, 11, 13, SDD 3.9) → **[G-4]**
- [ ] Task 1.15: Seed CRITICAL-1 — verify `sprint_plan_source` field usage in `bridge-github-trail.sh` and add clarifying comment (SDD 3.9 #1) → **[G-4]**
- [ ] Task 1.16: Create formal JSON Schema at `tests/fixtures/bridge-findings.schema.json` — required/optional fields, types, severity enum (CRITICAL|HIGH|MEDIUM|LOW|VISION|PRAISE), enriched field types (string|null), schema_version as integer, backward compatibility policy documented in schema description (Flatline IMP-003, SKP-003) → **[G-1, G-4]**
- [ ] Task 1.17: Extend `bridge-findings-parser.bats` — add tests for: JSON extraction, legacy fallback, invalid JSON rejection, missing schema_version, enriched field extraction, PRAISE weight 0, PRAISE in by_severity, boundary enforcement, **schema validation against JSON Schema**, **edge cases: nested fences, multiple findings blocks, truncated output, marker absence** (SDD 7.1, Flatline SKP-002) → **[G-1, G-4]**
- [ ] Task 1.18: Extend `bridge-state.bats` — add tests for `last_score` write, praise in by_severity, concurrent flock safety, **flock hard-fail on unsupported platform**, **crash-safety (interrupted write recovery)**, **stale-lock detection** (SDD 7.1, Flatline SKP-004) → **[G-4]**

### Definition of Done (Flatline IMP-009)

- [ ] All deliverables checked off
- [ ] All acceptance criteria verified
- [ ] All existing BATS tests pass (0 regressions)
- [ ] New BATS tests added and passing
- [ ] No uncommitted changes or TODO markers in modified files

### Dependencies

- None (first sprint, builds on existing cycle-005 infrastructure)

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| JSON parser breaks legacy review output | Med | High | Legacy fallback path preserves exact current behavior (SDD 3.2.5) |
| `flock` not available on all platforms | Low | Med | Hard-fail with clear error if unavailable — never silently degrade (Flatline IMP-002) |
| Seed fixes create merge conflicts with cycle-005 | Low | Med | Working on feature branch, clean rebase before merge |
| Nested fences or multiple JSON blocks confuse parser | Med | Med | Strict grammar: exactly one block, fail closed on violations (Flatline SKP-002) |
| State corruption from interrupted writes | Low | High | Write-to-temp + atomic `mv`; crash-safety tests; stale-lock cleanup (Flatline SKP-004) |

### Success Metrics

- All 13 seed findings resolved
- Parser correctly extracts JSON fenced block with all 5 enriched fields + PRAISE
- Parser falls back to legacy regex for old-format findings
- `severity_weighted_score` unchanged for identical findings (PRAISE = 0)
- All existing + new BATS tests pass (target: 35+ tests across 3 test files)
- Parser handles edge cases: nested fences, multiple blocks, truncated output (all fail closed)

---

## Sprint 2: Persona + Trail Hardening

**Duration:** 2.5 days

### Sprint Goal

Create the Bridgebuilder persona file with integrity verification, extend the `/run-bridge` SKILL.md with enriched review workflow, add size enforcement and threat-modeled content redaction to the GitHub trail, secure the `.run/` local artifact storage, add new constraints and configuration.

### Deliverables

- [ ] `.claude/data/bridgebuilder-persona.md` created with all 5 required sections
- [ ] Persona integrity verification (base-branch hash comparison) implemented
- [ ] Persona content validation (required section check) implemented
- [ ] `/run-bridge` SKILL.md extended with Phase 3.1 enriched review workflow
- [ ] Size enforcement added to `bridge-github-trail.sh` (65KB truncate, 256KB findings-only)
- [ ] Threat-modeled content redaction added to `bridge-github-trail.sh` with gitleaks-like patterns
- [ ] `.run/` security boundary: gitignore verified, retention policy, post-redaction safety check
- [ ] 3 new constraints (C-BRIDGE-006, 007, 008) added to `constraints.json`
- [ ] `bridgebuilder` config section added to `.loa.config.yaml` and `.loa.config.yaml.example`
- [ ] Enrichment metrics schema added to `bridge-state.sh`
- [ ] Extended BATS tests for trail size enforcement, redaction, and realistic token patterns
- [ ] All tests pass (regression gate)

### Acceptance Criteria

- [ ] Persona file exists at `.claude/data/bridgebuilder-persona.md` with sections: `# Bridgebuilder`, `## Identity`, `## Voice`, `## Review Output Format`, `## Content Policy` (SDD 3.1.1, IMP-001)
- [ ] Content Policy section includes all 5 NEVER rules for security content (SDD 3.1.2, SKP-005)
- [ ] PRAISE and educational field guidance uses soft language ("when warranted", "when confident") not hard quotas (SDD 3.1.3, SKP-004)
- [ ] Token budget section specifies <5K findings, <25K total, hard limits at 65KB/256KB (SDD 3.1.4, SKP-001)
- [ ] Persona integrity check compares hash against `origin/main` and falls back to base-branch version if modified (SDD 3.1.5, SKP-003)
- [ ] Persona validation checks required sections at load time, disables persona on failure (SDD 3.1.1, IMP-001)
- [ ] SKILL.md Phase 3.1 documents: integrity check → validation → lore load → embody persona → dual-stream → save → size check → redact → **post-redaction safety check** → parse → post (SDD 3.3, Flatline SKP-006)
- [ ] `bridge-github-trail.sh` truncates body >65KB preserving findings JSON (SDD 3.5.1)
- [ ] `bridge-github-trail.sh` posts findings-only for body >256KB (SDD 3.5.1)
- [ ] `redact_security_content()` uses **gitleaks-inspired patterns** for realistic token detection: AWS keys (`AKIA...`), GitHub tokens (`ghp_...`, `gho_...`), JWTs (`eyJ...`), generic high-entropy 32+ char strings — with allowlist for known-safe patterns (sha256 hashes in markers, base64 encoded diagram URLs) (Flatline SKP-006)
- [ ] Post-redaction safety check: if any pattern matching `(ghp_|gho_|AKIA|eyJ[A-Za-z0-9])` remains in output, **block posting** and log error (Flatline SKP-006)
- [ ] `.run/` directory is in `.gitignore`, full reviews saved with 0600 permissions, retention policy: reviews older than 30 days auto-cleaned (Flatline SKP-009)
- [ ] C-BRIDGE-006 is ALWAYS, C-BRIDGE-007 and C-BRIDGE-008 are SHOULD (SDD 5.1, SKP-004)
- [ ] `.loa.config.yaml` has `run_bridge.bridgebuilder` section with persona, size, redaction settings (SDD 3.7)
- [ ] Bridge state includes `enrichment` object per iteration (SDD 3.8, IMP-010)
- [ ] Trail BATS tests cover size enforcement (65KB, 256KB), **realistic secret patterns (AWS, GitHub, JWT)**, and **post-redaction safety check** (SDD 7.1, Flatline SKP-006)

### Technical Tasks

- [ ] Task 2.1: Create `.claude/data/bridgebuilder-persona.md` — extract persona from loa-finn#24, include Identity, Voice (6+ examples), Review Output Format (dual-stream instructions), Content Policy (5 NEVER rules), PRAISE Guidance (soft), Educational Field Guidance (soft), Token Budget (SDD 3.1) → **[G-1, G-2, G-3, G-6]**
- [ ] Task 2.2: Implement persona integrity verification in SKILL.md — `git show origin/main:...` hash comparison, fallback to base-branch version, skip on first deployment (SDD 3.1.5, SKP-003) → **[G-4]**
- [ ] Task 2.3: Implement persona content validation — check 5 required sections exist and are non-empty, disable persona + log WARNING on failure (SDD 3.1.1, IMP-001) → **[G-4]**
- [ ] Task 2.4: Extend `/run-bridge` SKILL.md Phase 3 with enriched review handling — add Phase 3.1 section with 10-step workflow for enriched Bridgebuilder review, including **post-redaction safety check step** (SDD 3.3, Flatline SKP-006) → **[G-1, G-2, G-3, G-5]**
- [ ] Task 2.5: Implement `redact_security_content()` in `bridge-github-trail.sh` — **threat-modeled redaction** with gitleaks-inspired patterns: AWS keys (AKIA prefix), GitHub tokens (ghp_/gho_ prefix), JWTs (eyJ prefix), generic high-entropy 32+ chars, common secret patterns (api_key, token, etc.), **with allowlist** for known-safe patterns (sha256 in markers, base64 diagram URLs) (SDD 3.5.2, SKP-005, Flatline SKP-006) → **[G-4]**
- [ ] Task 2.6: Implement size enforcement in `bridge-github-trail.sh` `cmd_comment` — 65KB truncation preserving findings JSON, 256KB findings-only fallback, always save full review to `.run/` **with 0600 permissions** (SDD 3.5.1, SKP-001, Flatline SKP-009) → **[G-3, G-5]**
- [ ] Task 2.7: Add C-BRIDGE-006 (ALWAYS: load persona), C-BRIDGE-007 (SHOULD: praise quality), C-BRIDGE-008 (SHOULD: educational fields) to `constraints.json` (SDD 5.1) → **[G-1, G-2]**
- [ ] Task 2.8: Add `run_bridge.bridgebuilder` section to `.loa.config.yaml` and `.loa.config.yaml.example` — persona_enabled, enriched_findings, insights_stream, praise_findings, integrity_check, token_budget, size_limits, redaction (SDD 3.7) → **[G-5]**
- [ ] Task 2.9: Add `enrichment` metrics tracking to bridge state per iteration — persona_loaded, persona_validation, findings_format, field_fill_rates, praise_count, insights_size_bytes, redactions_applied (SDD 3.8, IMP-010) → **[G-1]**
- [ ] Task 2.10: Implement post-redaction safety check — scan output for known secret prefixes (ghp_, gho_, AKIA, eyJ); if found, block posting and log error with line reference (Flatline SKP-006) → **[G-4]**
- [ ] Task 2.11: Secure `.run/` local artifacts — verify `.run/` is in `.gitignore`, saved reviews use 0600 permissions, add 30-day retention cleanup to bridge finalization (Flatline SKP-009) → **[G-4]**
- [ ] Task 2.12: Extend `bridge-github-trail.bats` — add tests for 65KB truncation, 256KB findings-only fallback, **realistic secret patterns (AWS AKIA..., GitHub ghp_..., JWT eyJ...)**, **allowlist exclusions**, **post-redaction safety check**, printf usage (SDD 7.1, Flatline SKP-006) → **[G-4]**

### Definition of Done (Flatline IMP-009)

- [ ] All deliverables checked off
- [ ] All acceptance criteria verified
- [ ] All existing BATS tests pass (0 regressions)
- [ ] New BATS tests added and passing
- [ ] No uncommitted changes or TODO markers in modified files

### Dependencies

- Sprint 1: Parser redesign (JSON extraction path), JSON Schema, PRAISE severity, flock state updates, seed fixes

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Persona content too generic/formulaic | Med | High | Include diverse voice examples from 25+ actual Bridgebuilder reviews (loa-finn corpus) |
| Size enforcement breaks existing comments | Low | Med | Only triggers above 65KB; current comments are 2-5KB |
| Redaction misses real secrets (false negative) | Med | High | Post-redaction safety check blocks posting if known prefixes detected; gitleaks-inspired patterns for common providers (Flatline SKP-006) |
| Redaction strips legitimate content (false positive) | Med | Low | Allowlist for known-safe patterns; overstripping is safe direction (SDD 6.1) |
| `.run/` artifacts leaked via git | Low | Med | Verify `.gitignore` includes `.run/`, 0600 permissions, retention cleanup (Flatline SKP-009) |

### Success Metrics

- Persona file contains all 5 required sections with diverse voice examples
- Persona integrity check blocks modified persona, allows unmodified
- Size enforcement correctly truncates >65KB and falls back >256KB
- Redaction strips realistic AWS/GitHub/JWT tokens from test fixture
- Post-redaction safety check blocks posting with unredacted secrets
- `.run/` is gitignored, reviews saved with restricted permissions
- All existing + new BATS tests pass

---

## Sprint 3: Validation + Integration

**Duration:** 2.5 days

### Sprint Goal

Create comprehensive test fixtures, validate end-to-end enrichment pipeline (JSON parsing, legacy fallback, convergence isolation, size enforcement, persona integrity, redaction), fix lore cross-references, and finalize documentation with version bump.

### Deliverables

- [ ] Enriched JSON test fixture created (SDD 7.2)
- [ ] Full integration validation against JSON and legacy fixtures
- [ ] Convergence isolation verified (PRAISE weight=0, score unaffected)
- [ ] Size enforcement verified (65KB truncation, 256KB fallback)
- [ ] Persona integrity verified (base-branch hash comparison)
- [ ] Content redaction verified (realistic tokens stripped, safety check blocks leaks)
- [ ] Broken lore cross-references fixed (seed MEDIUM-8)
- [ ] `CLAUDE.loa.md` stale integrity hash recomputed (seed MEDIUM-10)
- [ ] Version bump and CHANGELOG entry
- [ ] E2E Goal Validation

### Acceptance Criteria

- [ ] JSON test fixture matches SDD 7.2 format — enriched findings with all 5 new fields + PRAISE finding
- [ ] Parser extracts all fields from JSON fixture: `faang_parallel`, `metaphor`, `teachable_moment`, `connection`, `praise` (FR-1)
- [ ] Parser falls back to legacy regex for cycle-005 markdown fixture and produces identical output (SDD 3.2.5)
- [ ] `severity_weighted_score` excludes PRAISE (weight=0) — verified with fixture containing CRITICAL(10) + 2x PRAISE(0), expected score = 10, NOT 10 (which is already correct) but importantly NOT 20 or any value that includes PRAISE weight (Flatline IMP-010)
- [ ] `by_severity` includes all 6 levels: critical, high, medium, low, vision, praise (FR-1)
- [ ] Lore YAML cross-references resolve correctly (seed MEDIUM-8)
- [ ] `CLAUDE.loa.md` integrity hash is current after all changes (seed MEDIUM-10)
- [ ] Version bumped to v1.35.0 (or as appropriate)

### Technical Tasks

- [ ] Task 3.1: Create enriched JSON test fixture at `tests/fixtures/enriched-bridge-review.md` — full Bridgebuilder review with opening prose, JSON fenced block with mixed enriched+plain findings and PRAISE finding, closing meditation (SDD 7.2) → **[G-1, G-2]**
- [ ] Task 3.2: Create legacy markdown test fixture at `tests/fixtures/legacy-bridge-review.md` — cycle-005 format with markdown field-based findings, no JSON block (SDD 3.2.5) → **[G-4]**
- [ ] Task 3.3: Validate parser on enriched fixture — all 5 educational fields extracted, PRAISE counted, severity_weighted_score correct (SDD 7.3) → **[G-1, G-4]**
- [ ] Task 3.4: Validate parser on legacy fixture — identical output to current parser behavior, **contract test: pin exact output for known input** (SDD 7.3, Flatline SKP-003) → **[G-4]**
- [ ] Task 3.5: Validate convergence isolation — create fixture with CRITICAL(weight=10) + 2x PRAISE(weight=0), verify `severity_weighted_score` = 10 (not 20, which would indicate PRAISE being counted); verify PRAISE excluded from sprint plan task generation (SDD 4.4, Flatline IMP-010) → **[G-4]**
- [ ] Task 3.6: Validate size enforcement — create >65KB fixture, verify truncation preserves findings JSON; create >256KB fixture, verify findings-only fallback (SDD 7.3) → **[G-3, G-5]**
- [ ] Task 3.7: Validate persona integrity — modify persona on branch, verify base-branch version loaded (SDD 7.3) → **[G-4]**
- [ ] Task 3.8: Validate redaction — include realistic tokens (AWS AKIA..., GitHub ghp_..., JWT eyJ...) in test prose, verify all replaced with `[REDACTED]`; verify post-redaction safety check catches any missed tokens (SDD 7.3, Flatline SKP-006) → **[G-4]**
- [ ] Task 3.9: Fix broken lore cross-references in `.claude/data/lore/*.yaml` — verify `related:` fields reference valid entries (seed MEDIUM-8, SDD 3.9 #8) → **[G-4]**
- [ ] Task 3.10: Recompute `CLAUDE.loa.md` integrity hash after all changes (seed MEDIUM-10, SDD 3.9 #10) → **[G-4]**
- [ ] Task 3.11: Version bump — update version references, add CHANGELOG entry for v1.35.0 (SDD 3.9) → **[G-4]**
- [ ] Task 3.12: Parser performance sanity check — verify parser completes in <5s for a 50KB review with 20 findings on local machine (Flatline IMP-004) → **[G-4]**

### Task 3.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1, G-2, G-3, G-4, G-5, G-6)

**Description:**
Validate that all PRD goals are achieved through the complete implementation.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | Educational fields per finding >= 2 | Parse enriched fixture, check field fill rates | >= 2 of {faang_parallel, metaphor, teachable_moment} per finding |
| G-2 | PRAISE findings per review >= 2 | Parse enriched fixture, count PRAISE severity | >= 2 PRAISE findings in fixture |
| G-3 | Review character count 10-30K | Measure enriched fixture prose length | 10,000-30,000 characters |
| G-4 | Convergence efficiency unchanged | Verify: PRAISE weight=0, score excludes PRAISE, sprint plan skips PRAISE tasks | `severity_weighted_score` with PRAISE = score without PRAISE |
| G-5 | Token overhead < 30K | Check config token_budget.findings + insights | findings: 5000 + insights: 25000 = 30000 max |
| G-6 | User satisfaction "transformative" | Review persona voice examples and dual-stream output | Qualitative — persona has rich voice, diverse examples |

**Acceptance Criteria:**
- [ ] Each goal validated with documented evidence
- [ ] All BATS tests pass (parser, state, trail)
- [ ] No regressions in existing bridge functionality
- [ ] Parser performance sanity check passes (<5s for 50KB/20 findings)

### Definition of Done (Flatline IMP-009)

- [ ] All deliverables checked off
- [ ] All acceptance criteria verified
- [ ] All existing BATS tests pass (0 regressions)
- [ ] New BATS tests added and passing
- [ ] E2E validation table — all rows pass
- [ ] No uncommitted changes or TODO markers in modified files

### Dependencies

- Sprint 2: Persona file, SKILL.md, size enforcement, redaction, constraints, config

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Lore cross-references entangled with other fixes | Low | Low | Isolate lore fixes to dedicated commit |
| Integrity hash recomputation invalidates other checks | Low | Med | Recompute as final task after all other changes |
| Version bump conflicts with concurrent PRs | Low | Low | Use feature branch, merge after approval |

### Success Metrics

- All BATS tests pass (target: 45+ tests across 3 test files)
- JSON and legacy fixtures both parse correctly
- Convergence isolation proven: PRAISE weight=0, score excludes PRAISE
- Lore references resolve correctly
- E2E validation table all rows pass
- Parser performance <5s on reference workload

---

## Risk Register

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R1 | JSON parser breaks legacy output | 1 | Med | High | Legacy fallback preserves current behavior | Agent |
| R2 | Persona becomes formulaic | 2 | Med | High | Diverse voice examples from 25+ reviews | Agent |
| R3 | Size enforcement breaks existing comments | 2 | Low | Med | Only triggers above 65KB (current: 2-5KB) | Agent |
| R4 | Redaction overstrips content | 2 | Med | Low | Allowlist + safe direction (overstrip > understrip) | Agent |
| R5 | Convergence regression from PRAISE | 1-3 | Low | High | Weight=0, verified in tests | Agent |
| R6 | flock unavailable on platform | 1 | Low | Med | Hard-fail, no silent degradation (Flatline IMP-002) | Agent |
| R7 | Sprint timeline aggressive for scope | 1-3 | Med | Med | Regression gate per sprint; stop-ship on test failure (Flatline SKP-001) | Agent |
| R8 | Nested fences/multiple blocks confuse parser | 1 | Med | Med | Strict grammar: exactly one block, fail closed (Flatline SKP-002) | Agent |
| R9 | State corruption from interrupted writes | 1 | Low | High | Write-to-temp + atomic mv; crash-safety tests (Flatline SKP-004) | Agent |
| R10 | Redaction misses real secrets | 2 | Med | High | Post-redaction safety check blocks posting (Flatline SKP-006) | Agent |
| R11 | `.run/` artifacts leaked via git | 2 | Low | Med | Verify gitignore, 0600 permissions, retention cleanup (Flatline SKP-009) | Agent |

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| Seed findings resolved | 13/13 | Count of fixes in code | 1 |
| Parser extracts JSON fenced block | Yes | BATS test | 1 |
| Parser legacy fallback works | Yes | BATS test + contract test | 1, 3 |
| Formal JSON Schema exists | Yes | Schema file + validation tests | 1 |
| PRAISE weight = 0 | Verified | BATS test | 1 |
| flock atomic updates | All 5 functions | BATS test | 1 |
| flock crash safety | Verified | BATS test (interrupted write) | 1 |
| Persona has 5 required sections | Yes | Validation function | 2 |
| Persona integrity blocks modified file | Yes | BATS test | 2 |
| Size enforcement truncates >65KB | Yes | BATS test | 2 |
| Size enforcement findings-only >256KB | Yes | BATS test | 2 |
| Redaction strips realistic secrets | Yes | BATS test (AWS/GitHub/JWT) | 2 |
| Post-redaction safety check works | Yes | BATS test | 2 |
| `.run/` secured | Yes | gitignore + permissions check | 2 |
| All BATS tests pass | 45+ | Test runner | 3 |
| E2E goals validated | 6/6 | Validation table | 3 |
| Parser performance | <5s for 50KB/20 findings | Local timing | 3 |

---

## Dependencies Map

```
Sprint 1 ──────────────▶ Sprint 2 ──────────────▶ Sprint 3
   │                        │                        │
   ├─ Parser redesign       ├─ Persona file          ├─ Integration tests
   ├─ JSON Schema           ├─ Integrity check       ├─ Legacy contract tests
   ├─ PRAISE severity       ├─ SKILL.md enrichment   ├─ Convergence proof
   ├─ flock state + crash   ├─ Size enforcement      ├─ Lore fixes
   ├─ 13 seed fixes         ├─ Threat-modeled redact ├─ Performance sanity
   └─ CLAUDE.loa.md         ├─ .run/ security        ├─ Version bump
                            ├─ Constraints           └─ E2E validation
                            └─ Config
```

---

## Appendix

### A. PRD Feature Mapping

| PRD Feature | Sprint | Status |
|-------------|--------|--------|
| FR-1: Enriched Findings Schema | Sprint 1 (parser, schema), Sprint 2 (constraints), Sprint 3 (validation) | Planned |
| FR-2: Bridgebuilder Persona Integration | Sprint 2 (persona, SKILL.md, integrity) | Planned |
| FR-3: Dual-Stream Output | Sprint 2 (trail, size, redaction), Sprint 3 (validation) | Planned |
| FR-4: Seed Findings Integration | Sprint 1 (all 13 fixes) | Planned |

### B. SDD Component Mapping

| SDD Component | Sprint | Status |
|---------------|--------|--------|
| 3.1 Bridgebuilder Persona File | Sprint 2 | Planned |
| 3.2 Enriched Findings Parser | Sprint 1 | Planned |
| 3.3 Run-Bridge SKILL.md Extension | Sprint 2 | Planned |
| 3.4 Bridge State Extension | Sprint 1 | Planned |
| 3.5 GitHub Trail Extension | Sprint 1 (seed fixes), Sprint 2 (size, redaction, .run/) | Planned |
| 3.6 Vision Capture Fix | Sprint 1 | Planned |
| 3.7 Configuration Extension | Sprint 2 | Planned |
| 3.8 Enrichment Metrics | Sprint 2 | Planned |
| 3.9 Seed Findings | Sprint 1 (all), Sprint 3 (lore, hash) | Planned |

### C. PRD Goal Mapping

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| G-1 | Educational fields per finding >= 2 of {faang_parallel, metaphor, teachable_moment} | Sprint 1: 1.4, 1.5, 1.16; Sprint 2: 2.1, 2.4, 2.7, 2.9; Sprint 3: 3.1, 3.3 | Sprint 3: Task 3.E2E |
| G-2 | PRAISE findings per review >= 2 | Sprint 1: 1.3; Sprint 2: 2.1, 2.7; Sprint 3: 3.1 | Sprint 3: Task 3.E2E |
| G-3 | Review character count (insights stream) 10-30K | Sprint 2: 2.4, 2.6; Sprint 3: 3.6 | Sprint 3: Task 3.E2E |
| G-4 | Convergence efficiency same or better | Sprint 1: 1.1-1.18; Sprint 2: 2.2, 2.3, 2.5, 2.10-2.12; Sprint 3: 3.2, 3.4, 3.5, 3.7-3.12 | Sprint 3: Task 3.E2E |
| G-5 | Token overhead per iteration < 30K | Sprint 2: 2.4, 2.6, 2.8 | Sprint 3: Task 3.E2E |
| G-6 | User satisfaction "transformative" | Sprint 2: 2.1 (persona quality) | Sprint 3: Task 3.E2E |

**Goal Coverage Check:**
- [x] All PRD goals have at least one contributing task
- [x] All goals have a validation task in final sprint (Task 3.E2E)
- [x] No orphan tasks (all tasks annotated with goal contributions)

**Per-Sprint Goal Contribution:**

Sprint 1: G-1 (partial: parser + schema + fields), G-2 (partial: PRAISE severity), G-4 (foundation: parser, state, seeds, crash safety)
Sprint 2: G-1 (complete: persona + constraints), G-2 (complete: persona guidance), G-3 (complete: dual-stream), G-5 (complete: config budgets), G-6 (complete: persona quality)
Sprint 3: G-4 (complete: E2E validation + convergence proof + performance), all goals validated

### D. Flatline Integration Log

| Finding | Score | Category | Integration |
|---------|-------|----------|-------------|
| IMP-002 | 830 | HIGH_CONSENSUS | flock hard-fail, no silent fallback → Sprint 1 Task 1.6, Risk R6 |
| IMP-003 | 780 | HIGH_CONSENSUS | Formal JSON Schema → Sprint 1 Task 1.16, AC |
| IMP-004 | 695 | DISPUTED | Parser perf sanity check → Sprint 3 Task 3.12 |
| IMP-009 | 595 | DISPUTED | Definition of Done per sprint → All sprints |
| IMP-010 | 675 | DISPUTED | Fix Task 3.5 test description → Sprint 3 Task 3.5 |
| SKP-001 | 930 | BLOCKER | Regression gate per sprint, stop-ship → Executive Summary, Risk R7 |
| SKP-002 | 760 | BLOCKER | Strict grammar, edge case tests → Sprint 1 Tasks 1.1, 1.17, Risk R8 |
| SKP-003 | 720 | BLOCKER | Schema versioning + contract tests → Sprint 1 Task 1.16, Sprint 3 Task 3.4 |
| SKP-004 | 880 | BLOCKER | Crash safety, stale-lock handling → Sprint 1 Tasks 1.6, 1.18, Risk R9 |
| SKP-006 | 910 | BLOCKER | Threat-modeled redaction, post-redaction check → Sprint 2 Tasks 2.5, 2.10, 2.12, Risk R10 |
| SKP-009 | 740 | BLOCKER | .run/ security boundary → Sprint 2 Task 2.11, Risk R11 |

---

*Generated by Sprint Planner Agent — Cycle 006 (Flatline-reviewed)*
