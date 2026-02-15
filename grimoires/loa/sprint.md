# Sprint Plan: BUTTERFREEZONE Polish — PR #336 Findings

> Cycle: cycle-017 (continued)
> Source: [PR #336 Bridgebuilder Review](https://github.com/0xHoneyJar/loa/pull/336)
> Branch: `feat/cycle-017-butterfreezone-excellence`

## Overview

Single fixup sprint addressing remaining output quality issues identified during Bridgebuilder review of PR #336. All 5 code findings (HIGH, 2 MEDIUM, 2 LOW) were fixed in commits `b90966a` and `c3400d6`. This sprint addresses the **output quality issues** visible in the generated BUTTERFREEZONE.md and the **PROCESS.md documentation gap** noted by Bridgebuilder.

**Team**: 1 engineer (autonomous)
**Dependencies**: None — all changes in `.claude/scripts/` (System Zone) and `PROCESS.md`

---

## Sprint 1: Output Quality & Documentation Polish

**Goal**: Fix mid-word truncation in generated output, eliminate false-positive limitation detection, clarify PROCESS.md quality bar documentation, and verify via self-hosting.

### Task 1.1: Fix word-boundary truncation in `extract_project_description()`

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Description**: Lines 446 and 456 use `head -c 200` which truncates descriptions mid-word. The AGENT-CONTEXT `purpose` field and Header description both show text cut mid-word (e.g., "...quality gates, per" instead of completing the sentence).

Replace `head -c 200` with word-boundary-aware truncation that:
1. Takes up to 200 characters
2. Truncates at the last word boundary (space) within the limit
3. Never cuts mid-word

**Implementation**: Replace `| head -c 200` with a sed or awk snippet that reads up to 200 chars and trims to last space boundary. For example:
```bash
| cut -c1-200 | sed 's/ [^ ]*$//'
```

Apply to both occurrences:
- Line 446: Strategy 2 (README first paragraph)
- Line 456: Strategy 3 (README section)

**Acceptance Criteria**:
- [ ] No mid-word truncation in AGENT-CONTEXT `purpose` field
- [ ] No mid-word truncation in Header description
- [ ] Descriptions end at a complete word
- [ ] Character budget still respected (~200 chars max)

### Task 1.2: Fix word-boundary truncation in `infer_module_purpose()`

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Description**: Line 514 uses `head -c 80` to truncate module purposes, causing the evals module to show "Benchmarking and regression framework for the Loa agent development system. Ensu" — cut mid-word.

Fix:
1. Increase limit from 80 to 120 characters (80 is too aggressive for README first-paragraph descriptions)
2. Use word-boundary-aware truncation (same approach as Task 1.1)

**Acceptance Criteria**:
- [ ] Module purposes never truncated mid-word
- [ ] Limit increased to 120 chars
- [ ] evals module shows complete description

### Task 1.3: Fix false-positive "No automated tests detected" in `extract_limitations()`

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Description**: Line 1242 only checks for `*.test.*`, `*.spec.*`, `*_test.*` file patterns with `maxdepth 3`. The Loa repo has a `tests/` directory with 142 files but they use different naming conventions (e.g., `.bats`, `.sh`, plain `.ts`), so the check returns a false positive.

Fix: Before the filename pattern check, also check for the **existence of standard test directories** (`tests/`, `test/`, `spec/`, `__tests__/`, `e2e/`). If any exist and contain files, skip the "No automated tests detected" limitation.

```bash
# Check for test directories first
local has_test_dir=false
for td in tests test spec __tests__ e2e; do
    if [[ -d "$td" ]] && [[ -n "$(find "$td" -maxdepth 2 -type f 2>/dev/null | head -1)" ]]; then
        has_test_dir=true
        break
    fi
done

# Only check filename patterns if no test directory found
if [[ "$has_test_dir" == "false" ]]; then
    test_count=$(find . -maxdepth 3 \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" \) 2>/dev/null | wc -l)
    (( test_count == 0 )) && inferred="${inferred}- No automated tests detected\n"
fi
```

**Acceptance Criteria**:
- [ ] Loa repo no longer shows "No automated tests detected"
- [ ] Repos with `tests/` directory are correctly detected as having tests
- [ ] Repos with **no** test directory and no test files still get the limitation
- [ ] `*.test.*` pattern check still works as fallback

### Task 1.4: Clarify PROCESS.md Header quality bar documentation

**File**: `PROCESS.md`

**Description**: Bridgebuilder noted that the PROCESS.md contract section implies optional sections have no quality bar, but the validator actually fails if "No description available" appears *anywhere* in the file. The Header row in the contract table already says "(never 'No description available')" but this should be made more explicit as a validator-enforced constraint.

Add a note after the contract table clarifying:
- The validator (`butterfreezone-validate.sh`) enforces that the literal string "No description available" must not appear in any section
- Descriptions in required sections must be substantive (not stubs or truncated fragments)

**Acceptance Criteria**:
- [ ] PROCESS.md clarifies that "No description available" is validator-enforced
- [ ] Quality bar is documented as applying to all sections, not just Header

### Task 1.5: Self-hosting — Regenerate and validate Loa BUTTERFREEZONE.md

**Description**: Run the modified generator on the Loa repo and verify all fixes:

1. Run `.claude/scripts/butterfreezone-gen.sh --verbose`
2. Run `.claude/scripts/butterfreezone-validate.sh --strict`
3. Verify:
   - AGENT-CONTEXT `purpose` field ends at a complete word
   - Header description ends at a complete word
   - Module map purposes end at complete words (especially evals)
   - "No automated tests detected" no longer appears in Known Limitations
   - 13/13 validator checks pass
   - Word count ≥800

**Acceptance Criteria**:
- [ ] `butterfreezone-gen.sh --verbose` completes without errors
- [ ] `butterfreezone-validate.sh --strict` passes 13/13 with zero failures
- [ ] No mid-word truncation visible in any section
- [ ] Known Limitations section is either absent or contains only real limitations
- [ ] Word count ≥800
