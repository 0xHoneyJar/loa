# Sprint Plan: BUTTERFREEZONE — Agent-Grounded README Standard

**Cycle**: cycle-009
**Source PRD**: `grimoires/loa/prd.md` v1.1.0
**Source SDD**: `grimoires/loa/sdd.md` v1.1.0
**Sprints**: 3
**Team**: 1 AI agent (Claude)
**Sprint Duration**: ~2-3 hours each

---

## Sprint Overview

| Sprint | Goal | Key Deliverable |
|--------|------|----------------|
| Sprint 1 | Generation Core | `butterfreezone-gen.sh` + BATS tests |
| Sprint 2 | Validation + Hook | `butterfreezone-validate.sh` + bridge hook + BATS tests |
| Sprint 3 | Skill + Lore + Config | `/butterfreezone` skill + lore entries + config schema + integration |

---

## Sprint 1: Generation Core

**Goal**: Build the `butterfreezone-gen.sh` script that produces a valid BUTTERFREEZONE.md from any Loa-managed codebase.

### Task 1.1: Script Skeleton and CLI Interface
**Description**: Create `.claude/scripts/butterfreezone-gen.sh` with argument parsing, help text, exit codes, and the main generation flow structure.
**Acceptance Criteria**:
- Script at `.claude/scripts/butterfreezone-gen.sh` with 0755 permissions
- Supports `--output`, `--config`, `--tier`, `--dry-run`, `--json`, `--verbose`, `--help` flags
- Exit codes: 0 (success), 1 (failure), 2 (config error), 3 (bootstrap/Tier 3)
- `LC_ALL=C` and `TZ=UTC` set at script top for determinism
- flock-based concurrency protection (SDD 3.1.13)
- Config loading with defaults fallback (SDD 5.2)
- `--json` output follows stable schema: `{ "status": "ok|error", "tier": N, "output": "path", "sections": [...], "word_count": N, "errors": [] }` (Flatline IMP-010)
**Dependencies**: None
**Testing**: `butterfreezone-gen.sh --help` prints usage; `--dry-run` exits cleanly; `--json` output validates against schema

### Task 1.2: Input Tier Detection
**Description**: Implement `detect_input_tier()` and `has_content()` functions per SDD 3.1.2.
**Acceptance Criteria**:
- Returns 1 when `grimoires/loa/reality/api-surface.md` has >10 words
- Returns 2 when `package.json`, `Cargo.toml`, `pyproject.toml`, or `go.mod` exists, or source files found within maxdepth 3
- Returns 3 when no useful input available
- `--tier N` CLI flag forces specific tier
**Dependencies**: Task 1.1
**Testing**: BATS tests for each tier detection path

### Task 1.3: Section Extractors (Tier 2 + Tier 3)
**Description**: Implement all 8 section extractor functions for Tier 2 (static analysis) and Tier 3 (bootstrap stub). Tier 1 (reality files) delegates to existing reality file parsing.
**Acceptance Criteria**:
- `extract_agent_context`: Reads project name from package.json/Cargo.toml/.loa.config.yaml/git remote; type from manifest; version from git tag or manifest
- `extract_capabilities`: Uses Tier 2 grep patterns from SDD 3.1.3 (exports, pub fn, def/class, exported Go funcs, shell functions)
- `extract_architecture`: Analyzes directory tree structure with naming conventions
- `extract_interfaces`: Detects routes, CLI commands, exported APIs via patterns
- `extract_module_map`: Builds table from top-level directories with file counts
- `extract_ecosystem`: Parses dependency manifests for related repos
- `extract_limitations`: Extracts from README.md if present
- `extract_quick_start`: Extracts from README.md if present
- All Tier 2 greps use `tier2_grep()` wrapper with timeout 30, maxdepth bounds, vendor exclusion (SDD 3.1.14)
- Defensive file filtering: skip binary files (`-type f` + file magic check), handle malformed manifests gracefully, detect and skip symlink loops (`find -L` with `-maxdepth`) (Flatline IMP-005)
- Config-overridable grep pattern sets via `butterfreezone.extractors.patterns` for repo-specific tuning (Flatline SKP-002)
- Tier 3 produces minimal stub with AGENT-CONTEXT only
- Per-extractor error handling via `run_extractor()` wrapper (SDD 3.1.11)
**Dependencies**: Task 1.1, Task 1.2
**Testing**: BATS tests for each extractor with mock repo structures

### Task 1.4: Provenance Tagging and Document Assembly
**Description**: Implement provenance tagging, word-count budget enforcement, manual section preservation, security redaction, canonical sort, and checksum generation.
**Acceptance Criteria**:
- `tag_provenance()`: Tier 1 → CODE-FACTUAL, Tier 2 → DERIVED, Tier 3 → OPERATIONAL (exceptions: ecosystem/quick_start always OPERATIONAL)
- `enforce_word_budget()`: Per-section and total limits via `wc -w`; truncation follows priority order (SDD 3.1.6)
- `preserve_manual_sections()`: Section-anchored sentinels `<!-- manual-start:SECTION_ID -->` (SDD 3.1.5)
- `redact_content()`: Enumerated secret classes — AWS AKIA keys, GitHub tokens (ghp_/gho_/ghs_/ghr_), JWT (eyJ), private keys (BEGIN.*PRIVATE), DSN strings, generic `secret=`/`password=` patterns. Allowlist for sha256 hashes in markers and base64 diagram URLs. Fail-closed: unknown high-entropy strings flagged as warnings. (Flatline IMP-003, SKP-005)
- `sort_sections()`: Canonical order per `CANONICAL_ORDER` array (SDD 3.1.12)
- All `find` output piped through `sort -z` for deterministic ordering; table generation uses `LC_ALL=C sort` (Flatline SKP-003)
- `generate_ground_truth_meta()`: Per-section SHA-256, `generated_at` excluded from checksum input (SDD 3.1.7)
- `needs_regeneration()`: HEAD SHA + config mtime comparison (SDD 3.1.10)
- `atomic_write()`: Write to `.tmp` then `mv` (SDD 3.1.9)
- Reference syntax: `file:symbol` preferred, `file:L42` for line refs (SDD 3.1.15)
**Dependencies**: Task 1.3
**Testing**: BATS tests for word budget enforcement, deterministic output, checksum generation, security redaction, manual section preservation

### Task 1.5: BATS Test Suite for butterfreezone-gen
**Description**: Create comprehensive BATS test suite covering all generation scenarios.
**Acceptance Criteria**:
- File at `tests/unit/butterfreezone-gen.bats`
- Tests from SDD 7.1: tier detection (3 tests), agent context, provenance tags, word budget (2 tests), checksums, manual preservation, atomic write, security redaction, dry-run, determinism, exit codes
- Security redaction test corpus: AWS key fixture, GitHub token fixture, JWT fixture, private key fixture, allowlist passthrough (sha256 hash, base64 URL) (Flatline IMP-003)
- Edge case tests: binary file skip, malformed package.json, symlink loop handling, empty repo (Flatline IMP-005)
- JSON schema validation test for `--json` output (Flatline IMP-010)
- Minimum 15 tests, all passing
- Uses setup/teardown with temp directory for mock repos
**Dependencies**: Tasks 1.1-1.4
**Testing**: `bats tests/unit/butterfreezone-gen.bats` — all pass

---

## Sprint 2: Validation + Bridge Hook

**Goal**: Build the validation script, integrate into RTFM, and hook generation into the bridge orchestrator's FINALIZING phase.

### Task 2.1: butterfreezone-validate.sh
**Description**: Create `.claude/scripts/butterfreezone-validate.sh` with all 7 validation checks per SDD 3.2.
**Acceptance Criteria**:
- Script at `.claude/scripts/butterfreezone-validate.sh` with 0755 permissions
- Supports `--file`, `--strict`, `--json`, `--quiet`, `--help` flags
- Exit codes: 0 (pass), 1 (failures), 2 (warnings only)
- Check 1: Existence — file exists
- Check 2: AGENT-CONTEXT — block present with required fields (name, type, purpose, version)
- Check 3: Provenance — all `## ` sections have `<!-- provenance: TAG -->` comment
- Check 4: References — `file:symbol` refs validated (file exists + symbol grep); `file:L42` refs validate file exists only. Only scans backtick-fenced references.
- Check 5: Word budget — total `wc -w` under configured limit
- Check 6: ground-truth-meta — block present, HEAD SHA compared (advisory)
- Check 7: Freshness — `generated_at` within staleness window (advisory)
- `--strict` mode: advisory warnings become failures
- `--json` mode: stable schema `{ "status": "pass|fail|warn", "checks": [...], "errors": [], "warnings": [] }` (Flatline IMP-010)
**Dependencies**: Sprint 1 complete (needs a valid BUTTERFREEZONE.md to test against)
**Testing**: BATS tests

### Task 2.2: Bridge Orchestrator Hook
**Description**: Modify `.claude/scripts/bridge-orchestrator.sh` FINALIZING phase to emit `SIGNAL:BUTTERFREEZONE_GEN` between GROUND_TRUTH_UPDATE and RTFM_GATE.
**Acceptance Criteria**:
- New `is_butterfreezone_enabled()` function checks config (`butterfreezone.enabled` AND `butterfreezone.hooks.run_bridge`)
- BUTTERFREEZONE_GEN signal emitted after GT update
- On success: `git add BUTTERFREEZONE.md` to stage for commit
- On failure: Warning logged, workflow continues (non-blocking)
- Bridge state updated: `.finalization.butterfreezone_generated` field added
- Guarded by config check — disabled config = zero code path change
**Dependencies**: Task 2.1 (validation script called by RTFM gate after gen)
**Testing**: Existing bridge-orchestrator BATS tests still pass; manual verification of hook

### Task 2.3: BATS Test Suite for butterfreezone-validate
**Description**: Create BATS tests for the validation script.
**Acceptance Criteria**:
- File at `tests/unit/butterfreezone-validate.bats`
- Tests from SDD 7.1: missing file, valid file, missing agent context, missing provenance, missing file ref, stale SHA (advisory), strict mode, word budget
- Minimum 8 tests, all passing
**Dependencies**: Task 2.1
**Testing**: `bats tests/unit/butterfreezone-validate.bats` — all pass

---

## Sprint 3: Skill + Lore + Config + Integration

**Goal**: Register the `/butterfreezone` skill, add lore entries, update config schema, and run end-to-end integration.

### Task 3.1: /butterfreezone Skill Registration
**Description**: Create the skill definition and register in the skill index.
**Acceptance Criteria**:
- Directory at `.claude/skills/butterfreezone-gen/`
- `SKILL.md` with objective, input guardrails (safe danger level), constraints, workflow
- Workflow: check config → invoke `butterfreezone-gen.sh --verbose` → invoke `butterfreezone-validate.sh` → report
- Registered in `.claude/data/skills/index.yaml` with `danger_level: safe`
**Dependencies**: Sprint 2 complete
**Testing**: Skill can be invoked (dry-run mode)

### Task 3.2: Lore Glossary Entries
**Description**: Add 3 lore entries to `.claude/data/lore/mibera/glossary.yaml` per SDD 3.5.
**Acceptance Criteria**:
- `glossary-butterfreezone`: "The zone where only truth survives — no butter, no hype"
- `glossary-lobster`: "Agent that demands code-grounded facts — rejects marketing butter"
- `glossary-grounding-ritual`: "The ritual of binding claims to checksums — truth made verifiable"
- Each entry has: id, term, short, context, source, tags, related, loa_mapping
- Entries follow existing schema format exactly
**Dependencies**: None
**Testing**: YAML validation (`yq '.' glossary.yaml` succeeds)

### Task 3.3: Config Schema and Documentation
**Description**: Add `butterfreezone:` section to `.loa.config.yaml.example` and update CLAUDE.md reference.
**Acceptance Criteria**:
- `.loa.config.yaml.example` gains `butterfreezone:` block per SDD 5.1
- All config values documented with comments
- Default values match SDD specification
- `.claude/loa/CLAUDE.loa.md` gains BUTTERFREEZONE section in reference table
**Dependencies**: None
**Testing**: `yq '.' .loa.config.yaml.example` succeeds

### Task 3.4: Integration Test — Generate BUTTERFREEZONE.md for Loa
**Description**: Run `butterfreezone-gen.sh` against the Loa codebase itself and validate the output.
**Acceptance Criteria**:
- `butterfreezone-gen.sh` generates valid `BUTTERFREEZONE.md` for the Loa repo
- `butterfreezone-validate.sh` passes all checks on generated file
- Output is under 3200 words
- All provenance tags present
- AGENT-CONTEXT block correctly populated
- ground-truth-meta checksums valid
- File:symbol references resolve
- Two consecutive runs produce identical output (determinism)
**Dependencies**: Tasks 3.1, 3.2, 3.3
**Testing**: End-to-end execution + validation + determinism check

---

## Go/No-Go Criteria

Per-sprint gates (Flatline IMP-001):

| Sprint | Go Criteria | No-Go Action |
|--------|------------|--------------|
| Sprint 1 | `butterfreezone-gen.sh --dry-run` exits 0; 15+ BATS tests pass; redaction test corpus passes | Patch-forward: fix failing tests before Sprint 2 |
| Sprint 2 | Validation passes on Sprint 1 output; existing bridge BATS still pass | Patch-forward: disable hook via config, fix in Sprint 3 |
| Sprint 3 | Integration test: 2 consecutive identical runs; validate passes all checks | Defer skill registration; ship gen+validate as MVP |

## Risk Mitigation

| Risk | Sprint | Mitigation |
|------|--------|-----------|
| Tier 2 grep patterns miss Loa's shell-heavy codebase | 1 | Shell function patterns included; config-overridable pattern sets (Flatline SKP-002) |
| Security redaction leaks secrets or over-redacts | 1 | Enumerated secret classes with test corpus; fail-closed for unknown patterns (Flatline SKP-005) |
| Non-deterministic output across environments | 1 | `find | sort -z`, `LC_ALL=C`, `TZ=UTC`, stable table generation (Flatline SKP-003) |
| Bridge orchestrator modification breaks existing tests | 2 | Hook guarded by config check; existing tests verified |
| Word budget too tight for Loa's 47 commands | 1 | Integration test in Sprint 3 validates real-world budget |
| BATS test environment differences | 1, 2 | Tests use temp directories with controlled structure |

---

## Success Criteria

After all 3 sprints:
1. `butterfreezone-gen.sh --dry-run` produces valid output for Loa repo
2. `butterfreezone-validate.sh` passes all checks
3. 23+ BATS tests passing (15 gen + 8 validate)
4. Bridge orchestrator hook functional (config-guarded)
5. Lore entries in glossary.yaml
6. Config schema in .loa.config.yaml.example
7. Skill registered and invocable

---

*Sprint plan for cycle-009. Global sprint IDs: 18-20.*
