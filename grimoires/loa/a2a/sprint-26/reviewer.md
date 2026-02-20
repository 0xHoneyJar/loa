# Sprint 26: AGENT-CONTEXT Enrichment + Validation + Tests

## Sprint Overview
- **Global ID**: sprint-26
- **Local ID**: sprint-2 (cycle-030)
- **Goal**: Machine-readable provenance, validation support, and comprehensive test coverage
- **Covers**: FR-4, FR-5, Tests
- **Status**: COMPLETE

## Task Summary

### Task 2.1: Enrich AGENT-CONTEXT with Structured Interfaces [COMPLETE]

**File**: `.claude/scripts/butterfreezone-gen.sh` (lines 701-748)

Modified `extract_agent_context()` to output structured `interfaces:` field with `core:` sub-field per SDD Section 3.4.

| Criterion | Status |
|-----------|--------|
| AGENT-CONTEXT `interfaces:` becomes multi-line with `core:` sub-field | PASS |
| Top-5 limit per group preserved | PASS |
| Without constructs, only `core:` sub-field present | PASS |
| AGENT-CONTEXT still passes structure validation | PASS |
| `has_construct_iface_groups` boolean flag for `set -u` safety | PASS |

**Key implementation detail**: Used same `has_construct_iface_groups=false` boolean flag pattern and `declare -A construct_iface_groups=()` initialization as sprint-1 for `set -u` compatibility. The `interfaces` variable now contains the full multiline block including the `interfaces:` key, replacing the old `interfaces: ${interfaces}` template.

### Task 2.2: Update Validation Script [COMPLETE]

**File**: `.claude/scripts/butterfreezone-validate.sh` (lines 192-224)

| Criterion | Status |
|-----------|--------|
| `validate_agent_context()` accepts both flat and structured `interfaces` field | PASS |
| New `validate_core_skills_manifest()` check added | PASS |
| Missing `core-skills.json` produces warning (exit 2), not failure (exit 1) | PASS |
| Valid `core-skills.json` produces PASS with skill count | PASS |
| Invalid JSON in `core-skills.json` produces warning, not failure | PASS |
| `butterfreezone-validate.sh` passes on regenerated BUTTERFREEZONE.md | PASS (19/19, 0 warnings) |

**New validation checks**:
- `agent_context_structured`: Advisory check for structured interfaces (v1.40+)
- `core_skills_manifest`: Advisory check for core-skills.json presence and validity

### Task 2.3: Comprehensive Test Suite [COMPLETE]

**File**: `tests/test_butterfreezone_provenance.sh` (12 test cases)

| # | Test | Category | Status |
|---|------|----------|--------|
| 1 | classify core skill | unit | PASS |
| 2 | classify construct skill | unit | PASS |
| 3 | classify project skill | unit | PASS |
| 4 | classify with missing core-skills.json | degradation | PASS |
| 5 | classify with missing constructs-meta | degradation | PASS |
| 6 | classify with stale /tmp/ entries | filtering | PASS |
| 7 | segmented output: core only | integration | PASS |
| 8 | segmented output: core + construct | integration | PASS |
| 9 | segmented output: all three groups | integration | PASS |
| 10 | AGENT-CONTEXT structured interfaces | integration | PASS |
| 11 | validation passes with new format | integration | PASS |
| 12 | validation warns without core-skills.json | degradation | PASS |

Tests use temp directories with mock data. No real framework files modified.

### Task 2.4: End-to-End Verification [COMPLETE]

| Criterion | Status |
|-----------|--------|
| `butterfreezone-gen.sh` produces correct segmented output | PASS |
| `butterfreezone-validate.sh` passes (exit 0, 19/19, 0 warnings) | PASS |
| `test_butterfreezone_provenance.sh` passes (12/12, 17 assertions) | PASS |
| No regression on `test_run_state_verify.sh` (7/7) | PASS |
| No regression on `test_construct_workflow.sh` (23/23) | PASS |

## Files Changed

| File | Action | Lines Changed |
|------|--------|--------------|
| `.claude/scripts/butterfreezone-gen.sh` | MODIFIED | +35 -12 (structured AGENT-CONTEXT interfaces) |
| `.claude/scripts/butterfreezone-validate.sh` | MODIFIED | +25 -4 (structured format + manifest check) |
| `tests/test_butterfreezone_provenance.sh` | **NEW** | ~470 (12 test cases) |
| `BUTTERFREEZONE.md` | REGENERATED | Full regeneration with structured AGENT-CONTEXT |

## Risks Addressed

| Risk | Mitigation Applied |
|------|-------------------|
| Mesh script compatibility | `interfaces:` on own line still matchable by grep; sub-fields are additive |
| `set -u` with empty associative arrays | `has_construct_iface_groups` boolean flag |
| Validation backward compatibility | Accepts both flat `interfaces: [...]` and structured `interfaces:` + `core:` |
