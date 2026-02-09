# SDD: Skill Benchmark Audit — Anthropic Best Practices Alignment

**Version**: 1.0.0
**Status**: Draft
**Author**: Architecture Phase (architect)
**Date**: 2026-02-09
**PRD**: grimoires/loa/prd.md (v1.1.0)
**Issue**: #261

---

## 1. Executive Summary

Bring all 19 Loa skills into compliance with Anthropic's "Complete Guide to Building Skills for Claude" through a structural validation test suite, SKILL.md size refactoring, description standardization, and error handling improvements. All changes are documentation-only — no application code is modified.

The primary deliverable is a CI-runnable test script (`validate-skill-benchmarks.sh`) that enforces Anthropic's standards as a regression gate, plus targeted refactoring of the 1 over-limit skill and 5 under-documented skills.

---

## 2. System Architecture

### 2.1 Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    CI Pipeline                           │
│                                                         │
│  validate-skills.sh ──→ index.yaml schema checks        │
│         (existing)       (name, version, triggers)      │
│                                                         │
│  validate-skill-benchmarks.sh ──→ SKILL.md checks  NEW │
│         (new script)              (word count, desc,    │
│                                    structure, errors)   │
│                                                         │
│  Both scripts: exit 0 = pass, exit 1 = fail             │
└─────────────────────────────────────────────────────────┘
         │                           │
         ▼                           ▼
┌─────────────────┐     ┌──────────────────────────┐
│  .claude/skills/ │     │  .claude/schemas/         │
│  ├── skill-a/    │     │  ├── skill-index.schema   │
│  │   ├── SKILL.md│     │  └── skill-benchmark.json │
│  │   ├── index.yaml     │         (new)             │
│  │   └── resources/│    └──────────────────────────┘
│  ├── skill-b/    │
│  └── ...         │
└─────────────────┘
```

### 2.2 Relationship to Existing Infrastructure

| Existing | New | Relationship |
|----------|-----|-------------|
| `validate-skills.sh` | `validate-skill-benchmarks.sh` | Complementary — existing checks index.yaml, new checks SKILL.md |
| `skill-index.schema.json` | `skill-benchmark.json` | Complementary — existing validates YAML structure, new defines Anthropic benchmark thresholds |
| `validate-e2e.sh` | — | Unchanged — end-to-end tests are a separate concern |

---

## 3. Component Design

### 3.1 Structural Validation Script (FR-4b)

**File**: `.claude/scripts/validate-skill-benchmarks.sh`

**Purpose**: Automated CI-runnable checks for all SKILL.md files against Anthropic's benchmarks.

#### 3.1.1 Check Suite

| # | Check | Pass Criteria | Exit on Fail |
|---|-------|---------------|-------------|
| 1 | SKILL.md exists | File present in skill folder | Yes |
| 2 | Word count | `wc -w` ≤ 5,000 | Yes |
| 3 | No README.md | `README.md` absent from skill folder | Yes |
| 4 | Folder kebab-case | Folder name matches `^[a-z][a-z0-9-]+$` | Yes |
| 5 | Name matches folder | `name` field in frontmatter == folder name | Yes |
| 6 | No XML in frontmatter | No `<` or `>` in YAML frontmatter block | Yes |
| 7 | Description length | ≤ 1,024 characters (from index.yaml) | Yes |
| 8 | Description has WHEN | Contains "Use when" or "Use this" pattern | Warning |
| 9 | Error handling present | ≥ 5 error/troubleshoot/fail references | Warning |
| 10 | Frontmatter valid | YAML between `---` delimiters parses correctly | Yes |

#### 3.1.2 Script Structure

```bash
#!/usr/bin/env bash
# validate-skill-benchmarks.sh - Anthropic skill benchmarks (Issue #261)
set -euo pipefail

SKILLS_DIR=".claude/skills"
MAX_WORDS=5000
MAX_DESC_CHARS=1024
MIN_ERROR_REFS=5

total=0; passed=0; failed=0; warnings=0

for skill_dir in "$SKILLS_DIR"/*/; do
    skill_name=$(basename "$skill_dir")
    ((total++))
    errors=()
    warns=()

    # Check 1: SKILL.md exists
    # Check 2: Word count
    # Check 3: No README.md
    # Check 4: Folder kebab-case
    # Check 5: Name matches folder (frontmatter)
    # Check 6: No XML in frontmatter
    # Check 7: Description length (from index.yaml)
    # Check 8: Description has trigger context
    # Check 9: Error handling references
    # Check 10: Frontmatter parses

    # Report per-skill
done

# Summary with exit code
```

#### 3.1.3 Output Format

Matches existing `validate-skills.sh` output format for consistency:

```
Skill Benchmark Validation (Anthropic Guide)
=============================================

PASS: auditing-security (4,548 words)
PASS: autonomous-agent (4,134 words)
  WARN: bridgebuilder-review - only 2 error refs (min: 5)
PASS: browsing-constructs (1,562 words)
...
FAIL: riding-codebase (6,905 words > 5,000 limit)

Summary
-------
Total: 19
Passed: 18
Failed: 1
Warnings: 3
```

#### 3.1.4 Configuration File

**File**: `.claude/schemas/skill-benchmark.json`

```json
{
  "max_words": 5000,
  "max_description_chars": 1024,
  "min_error_references": 5,
  "description_trigger_patterns": [
    "Use when",
    "Use this",
    "Use if",
    "Invoke when",
    "Trigger when"
  ],
  "forbidden_frontmatter_patterns": ["<[a-zA-Z]", "</[a-zA-Z]"],
  "folder_name_pattern": "^[a-z][a-z0-9-]+$"
}
```

Thresholds are configurable so they can evolve without code changes.

### 3.2 Schema Update

**File**: `.claude/schemas/skill-index.schema.json`

Update the `description` field constraints:

```json
// Before
"description": {
  "type": "string",
  "minLength": 50,
  "maxLength": 500
}

// After
"description": {
  "type": "string",
  "minLength": 50,
  "maxLength": 1024
}
```

This aligns with Anthropic's 1,024-character limit for descriptions.

### 3.3 SKILL.md Size Refactoring (FR-1)

#### 3.3.1 riding-codebase (6,905 → ≤4,500 words)

**Strategy**: Extract phase-specific reference material to linked files.

**Current structure analysis**:
```
riding-codebase/SKILL.md (6,905 words)
├── Core Principles (~200 words)           ← Keep inline
├── Phase 0: Preflight (~400 words)        ← Keep inline
├── Phase 1: Discovery (~800 words)        ← Keep inline (core instructions)
├── Phase 2: Deep Analysis (~1,200 words)  ← Extract templates
├── Phase 3: Synthesis (~1,000 words)      ← Extract output formats
├── Phase 4: Validation (~800 words)       ← Extract checklists
├── Output Format Templates (~1,500 words) ← Extract entirely
└── Edge Cases & Recovery (~800 words)     ← Keep inline
```

**Extraction plan**:
```
riding-codebase/
├── SKILL.md                      (≤4,500 words — instructions only)
├── resources/
│   └── references/
│       ├── output-formats.md     (~1,500 words — PRD/SDD templates)
│       ├── analysis-checklists.md (~800 words — Phase 2-4 checklists)
│       └── deep-analysis-guide.md (~600 words — Phase 2 detailed steps)
└── index.yaml                    (unchanged)
```

**Link pattern in SKILL.md**:
```markdown
## Phase 2: Deep Analysis

[Core instructions remain here — what to analyze and why]

For detailed analysis steps and checklists, see:
`resources/references/deep-analysis-guide.md`
```

**Backup**: Create `SKILL.md.bak` before refactoring. Retain for 7 days per R-5 rollback strategy.

#### 3.3.2 Near-Limit Skills (Audit Only)

For skills between 4,000-5,000 words (auditing-security, implementing-tasks, reviewing-code, autonomous-agent):

- **No immediate refactoring** — they're under the limit
- **Document** which sections could be extracted if they grow
- **Add comments** in SKILL.md: `<!-- extractable: ~800 words -->` near large sections

This gives future maintainers a roadmap without introducing changes that could regress behavior.

### 3.4 Description Standardization (FR-2)

#### 3.4.1 Update Locations

Each skill has descriptions in two places:

| Location | Format | Used By |
|----------|--------|---------|
| `index.yaml` `description` field | Multi-line YAML string | Skill matching engine, `validate-skills.sh` |
| `SKILL.md` frontmatter `description` field | YAML string (optional) | Some skills only |

**Decision**: Update `index.yaml` as the source of truth. SKILL.md frontmatter descriptions are optional and may differ (they're loaded at different disclosure levels).

#### 3.4.2 Description Template

```
Line 1: [WHAT] — action verb, user-facing outcome
Line 2: [WHEN] — "Use when..." with 1-2 specific trigger contexts
Line 3: [CAPABILITIES] — 2-3 concrete things it handles
```

**Constraints**:
- Total ≤ 1,024 characters
- Must preserve existing trigger file paths (per PRD Finding 5)
- Existing `triggers` array in index.yaml remains unchanged

#### 3.4.3 All 19 Descriptions (Before/After)

Descriptions will be drafted per-skill during implementation. Each follows the template above. The implementer will:

1. Read the existing description
2. Read the SKILL.md to understand actual behavior
3. Draft new description following template
4. Verify no trigger file paths are dropped
5. Update `index.yaml`

### 3.5 Error Handling Audit (FR-3)

#### 3.5.1 Target Skills

5 skills with <5 error references need an `## Error Handling` section added to their SKILL.md:

| Skill | Current Refs | Additions Needed |
|-------|-------------|-----------------|
| bridgebuilder-review | 2 | API failures, auth errors, rate limits, dry-run edge cases, large PR handling |
| designing-architecture | 3 | PRD not found, clarification loop timeout, SDD generation failure |
| flatline-knowledge | 4 | NotebookLM auth, API timeout, cache miss, model unavailable |
| mounting-framework | 4 | Permission denied, existing mount, partial install, version mismatch |
| planning-sprints | 2 | PRD/SDD missing, capacity estimation, dependency cycles, empty sprint |

#### 3.5.2 Error Section Template

```markdown
## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "description" | What triggers it | How to fix |

### Troubleshooting

**Skill doesn't trigger**: [specific guidance]
**Unexpected output**: [specific guidance]
**Mid-execution failure**: [recovery steps]
```

#### 3.5.3 Word Budget

Each error handling section adds ~150-300 words. For near-limit skills, this must be accounted for in the word budget:

| Skill | Current Words | + Error Section | New Total | Under Limit? |
|-------|-------------|-----------------|-----------|-------------|
| bridgebuilder-review | 327 | +250 | 577 | Yes |
| designing-architecture | 1,637 | +200 | 1,837 | Yes |
| flatline-knowledge | 687 | +200 | 887 | Yes |
| mounting-framework | 921 | +200 | 1,121 | Yes |
| planning-sprints | 2,586 | +200 | 2,786 | Yes |

None of the target skills are at risk of exceeding the 5,000-word limit after additions.

### 3.6 Negative Trigger Audit (FR-5)

#### 3.6.1 Design Decision

Anthropic's guide recommends `negative_triggers` to prevent misfires. However, Loa's current skill matching architecture uses `triggers` arrays in index.yaml — there is no `negative_triggers` field in the schema.

**Decision**: Add `negative_triggers` as an optional field to the schema. The validation script will check for their presence (warning only, not blocking). Implementation of actual negative trigger matching is deferred — the field serves as documentation for now.

```json
// Addition to skill-index.schema.json
"negative_triggers": {
  "type": "array",
  "items": { "type": "string" },
  "description": "Phrases that should NOT trigger this skill (advisory)"
}
```

### 3.7 Progressive Disclosure Analysis (FR-6)

#### 3.7.1 Current Disclosure Levels

| Level | Mechanism | Current Usage |
|-------|-----------|--------------|
| L1: Frontmatter | YAML between `---` in SKILL.md | 19/19 skills use frontmatter |
| L2: SKILL.md body | Full file loaded on trigger | 19/19 — this IS the instruction set |
| L3: Linked references | `resources/references/*.md` | 0/19 use explicit references/ links |

**Gap**: Level 3 is unused. All content is either in frontmatter (L1) or the SKILL.md body (L2). No skill currently links to reference files for on-demand loading.

#### 3.7.2 L3 Candidates (>3,000 words)

| Skill | Words | Extractable Content | Estimated Savings |
|-------|-------|--------------------|--------------------|
| riding-codebase | 6,905 | Output templates, analysis checklists | ~2,400 words |
| implementing-tasks | 4,596 | Feedback templates, beads integration details | ~800 words |
| auditing-security | 4,548 | Security checklists, OWASP reference | ~700 words |
| reviewing-code | 4,468 | Review rubrics, quality checklists | ~600 words |
| autonomous-agent | 4,134 | State machine diagrams, recovery procedures | ~500 words |
| deploying-infrastructure | 3,880 | IaC templates, monitoring setup | ~400 words |
| discovering-requirements | 3,138 | Interview templates, context synthesis guides | ~300 words |
| translating-for-executives | 3,019 | Output format templates | ~200 words |

**Sprint scope**: Only riding-codebase (the over-limit skill) will be refactored in this issue. Near-limit skills are documented with extractable sections for future work.

---

## 4. Data Architecture

No databases or persistent storage. All data is in:
- SKILL.md files (markdown)
- index.yaml files (YAML)
- skill-benchmark.json (JSON configuration)
- skill-index.schema.json (JSON Schema)

---

## 5. File Inventory

### 5.1 New Files

| File | Purpose | Size |
|------|---------|------|
| `.claude/scripts/validate-skill-benchmarks.sh` | Structural validation script | ~200 lines |
| `.claude/schemas/skill-benchmark.json` | Benchmark thresholds config | ~20 lines |
| `.claude/skills/riding-codebase/resources/references/output-formats.md` | Extracted output templates | ~1,500 words |
| `.claude/skills/riding-codebase/resources/references/analysis-checklists.md` | Extracted checklists | ~800 words |
| `.claude/skills/riding-codebase/resources/references/deep-analysis-guide.md` | Extracted analysis steps | ~600 words |

### 5.2 Modified Files

| File | Changes |
|------|---------|
| `.claude/schemas/skill-index.schema.json` | Raise description maxLength 500→1024, add negative_triggers field |
| `.claude/skills/riding-codebase/SKILL.md` | Reduce from 6,905 to ≤4,500 words via extraction |
| `.claude/skills/*/index.yaml` (19 files) | Update descriptions to WHAT+WHEN+capabilities formula |
| `.claude/skills/bridgebuilder-review/SKILL.md` | Add error handling section |
| `.claude/skills/designing-architecture/SKILL.md` | Add error handling section |
| `.claude/skills/flatline-knowledge/SKILL.md` | Add error handling section |
| `.claude/skills/mounting-framework/SKILL.md` | Add error handling section |
| `.claude/skills/planning-sprints/SKILL.md` | Add error handling section |

### 5.3 Unchanged Files

| File | Reason |
|------|--------|
| `.claude/scripts/validate-skills.sh` | Existing script is complementary, not replaced |
| All other SKILL.md files | No changes needed (under limits, sufficient error handling) |

---

## 6. Testing Strategy

### 6.1 Test Script Self-Validation

The validation script must pass on the repository after all changes are complete:

```bash
# Must exit 0 after all refactoring
.claude/scripts/validate-skill-benchmarks.sh
```

### 6.2 Regression Testing

Before and after each skill modification:

```bash
# Capture baseline
.claude/scripts/validate-skills.sh       # Existing — must still pass
.claude/scripts/validate-skill-benchmarks.sh  # New — captures current state
```

### 6.3 Rollback Verification

```bash
# Each modified SKILL.md has a .bak copy
ls .claude/skills/riding-codebase/SKILL.md.bak
# Restore: cp SKILL.md.bak SKILL.md
```

### 6.4 Word Count Verification

```bash
# Verify riding-codebase is under limit after refactoring
words=$(wc -w < .claude/skills/riding-codebase/SKILL.md)
test "$words" -le 5000 && echo "PASS: $words words" || echo "FAIL: $words words"
```

---

## 7. Implementation Order

| Task | Dependencies | Files | Estimated Effort |
|------|-------------|-------|-----------------|
| T1: Create benchmark config | None | `skill-benchmark.json` | Small |
| T2: Create validation script | T1 | `validate-skill-benchmarks.sh` | Medium |
| T3: Update schema | None | `skill-index.schema.json` | Small |
| T4: Refactor riding-codebase | T2 (to verify) | SKILL.md + 3 reference files | Medium |
| T5: Standardize 19 descriptions | T3 | 19 index.yaml files | Medium |
| T6: Add error handling (5 skills) | T2 (to verify) | 5 SKILL.md files | Medium |
| T7: Run full validation | T1-T6 | — | Small |

**Critical path**: T1 → T2 → T4 (validation script must exist before refactoring to verify compliance).

---

## 8. Security Considerations

| Concern | Mitigation |
|---------|-----------|
| Script injection via skill names | Folder names validated against `^[a-z][a-z0-9-]+$` regex |
| Temp file races | Script uses read-only operations (no temp files needed) |
| Path traversal | All paths are relative to `.claude/skills/`, validated to exist |

---

## 9. Performance Budget

| Operation | Target | Approach |
|-----------|--------|----------|
| Full benchmark validation (19 skills) | <3s | Sequential iteration, no external API calls |
| Single skill validation | <200ms | Direct file reads, `wc -w` + `grep -c` |

---

## 10. Dependencies

| Dependency | Required? | Purpose | Fallback |
|------------|-----------|---------|----------|
| `bash` 4+ | Yes | Script execution | None |
| `wc` | Yes | Word counting | POSIX standard |
| `grep` | Yes | Pattern matching | POSIX standard |
| `jq` | Yes | JSON config parsing | None (exit with error) |
| `yq` | No | YAML parsing (for descriptions) | `grep`-based extraction |

No new external dependencies. All tools are already required by existing Loa scripts.

---

## 11. References

| Document | Relevance |
|----------|-----------|
| PRD v1.1.0 (`grimoires/loa/prd.md`) | All requirements and priorities |
| `validate-skills.sh` | Existing validation pattern to follow |
| `skill-index.schema.json` | Existing schema to extend |
| Anthropic "Complete Guide to Building Skills for Claude" | Primary benchmark source |
| PR #264 review feedback | Priority adjustments and rollback strategy |
