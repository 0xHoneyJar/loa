# Sprint 25: Core Skills Manifest + Classification + Segmented Output

## Sprint Overview
- **Global ID**: sprint-25
- **Local ID**: sprint-1 (cycle-030)
- **Goal**: Deliver visible user-facing change — BUTTERFREEZONE.md shows skills grouped by origin
- **Covers**: FR-1, FR-2, FR-3
- **Status**: COMPLETE

## Task Summary

### Task 1.1: Create Core Skills Manifest [COMPLETE]

**File**: `.claude/data/core-skills.json`

Created manifest listing all 29 framework-shipped skill slugs, alphabetically sorted.

| Criterion | Status |
|-----------|--------|
| File exists at `.claude/data/core-skills.json` | PASS |
| Contains `version`, `generated_at`, and `skills` array | PASS |
| `skills` array lists all 29 current core skill slugs | PASS |
| Alphabetically sorted | PASS |
| Valid JSON (passes `jq .`) | PASS |

### Task 1.2: Implement Provenance Classification Function [COMPLETE]

**File**: `.claude/scripts/butterfreezone-gen.sh` (lines 1204-1273)

Added `load_classification_cache()` and `classify_skill_provenance()` functions per SDD Section 3.2.

| Criterion | Status |
|-----------|--------|
| `load_classification_cache()` reads `core-skills.json` and `.constructs-meta.json` once | PASS |
| `/tmp/` test entries filtered from constructs metadata | PASS |
| `classify_skill_provenance("auditing-security")` returns `core` | PASS |
| `classify_skill_provenance("unknown-skill")` returns `project` | PASS |
| If `core-skills.json` missing, cache is empty (no crash) | PASS |
| If `.constructs-meta.json` missing, constructs cache is empty (no crash) | PASS |
| Packs directory fallback detects skills in `.claude/constructs/packs/<pack>/skills/` | PASS |

**Key implementation detail**: `{ grep ... || true; }` pattern used in construct metadata lookup to prevent `set -eo pipefail` from treating grep no-match as a fatal error.

### Task 1.3: Modify extract_interfaces() for Segmented Output [COMPLETE]

**File**: `.claude/scripts/butterfreezone-gen.sh` (lines 1328-1410)

Replaced flat skill listing with grouped output using provenance classification.

| Criterion | Status |
|-----------|--------|
| Skills grouped under `#### Loa Core`, `#### Constructs`, `#### Project-Specific` | PASS |
| Construct skills sub-grouped by pack name with version from manifest | PASS (tested with mock data) |
| Empty groups are omitted | PASS |
| Alphabetical sort within each group (LC_ALL=C) | PASS |
| Without `core-skills.json`, falls back to all skills as `project` (graceful degradation) | PASS |

**Key implementation detail**: Used `has_construct_groups` boolean flag instead of `${#construct_groups[@]}` for `set -u` compatibility with empty associative arrays.

### Task 1.4: Verify Generation [COMPLETE]

Ran `butterfreezone-gen.sh` and verified BUTTERFREEZONE.md output.

| Criterion | Status |
|-----------|--------|
| BUTTERFREEZONE.md regenerated successfully | PASS |
| Interfaces section shows `#### Loa Core` with 29 skills | PASS |
| No `#### Constructs` section (no construct skills installed) | PASS |
| No `#### Project-Specific` section (no project skills present) | PASS |
| No regression in other BUTTERFREEZONE sections | PASS |

## Files Changed

| File | Action | Lines Changed |
|------|--------|--------------|
| `.claude/data/core-skills.json` | **NEW** | 33 |
| `.claude/scripts/butterfreezone-gen.sh` | MODIFIED | +105 (classification functions + segmented output) |
| `BUTTERFREEZONE.md` | REGENERATED | Full regeneration with segmented format |

## Risks Addressed

| Risk | Mitigation Applied |
|------|-------------------|
| Bash associative arrays + `set -u` | Used `has_construct_groups` boolean flag |
| `set -eo pipefail` + grep no-match | Used `{ grep ... \|\| true; }` pattern |
| Staleness detection skipping regeneration | Delete old file before regenerating |
