# PRD: Skill Benchmark Audit — Anthropic Best Practices Alignment

**Version**: 1.1.0
**Status**: Draft (revised per PR #264 review feedback)
**Author**: Discovery Phase (plan-and-analyze)
**Date**: 2026-02-09
**Issue**: #261

---

## 1. Problem Statement

Anthropic published "The Complete Guide to Building Skills for Claude" — a 30-page specification defining best practices for skill structure, progressive disclosure, description quality, testing, and error handling. Loa has 19 skills built before this guide existed. Without a systematic audit, we risk:

1. **Trigger failures**: Skills that don't fire when users expect them to (description doesn't match Anthropic's WHAT + WHEN formula)
2. **Context window bloat**: 1 skill exceeds Anthropic's 5,000-word SKILL.md hard limit (riding-codebase at 6,905 words), with 4 more near-limit (>4,000 words) — degrading performance when multiple skills load
3. **Missing error recovery**: Users hit errors with no documented troubleshooting path
4. **No testing framework**: Zero structured tests for skill triggering accuracy or completion quality

Additionally, FAANG-level operators (Vercel, Anthropic's own skill repos) provide competitive reference points that Loa's skills should match or exceed.

---

## 2. Benchmark Source Analysis

### 2.1 Anthropic's Official Guide (Primary Benchmark)

Source: `The-Complete-Guide-to-Building-Skill-for-Claude.pdf` (30 pages)

Key benchmarks extracted:

| Area | Benchmark | Loa Status |
|------|-----------|------------|
| **File Structure** | SKILL.md required, kebab-case folder, no README.md | 19/19 pass |
| **SKILL.md Size** | Under 5,000 words; move detail to references/ | 16/19 pass (3 over) |
| **Description** | `[What] + [When] + [Key capabilities]` formula, <1024 chars | Needs audit |
| **Frontmatter** | name (kebab-case), description, no XML tags | Needs audit |
| **Progressive Disclosure** | 3 levels: frontmatter → body → linked files | Partial |
| **Error Handling** | Documented error states and recovery | 11/19 have >10 error refs |
| **Examples** | Concrete usage examples | 19/19 have examples |
| **Testing** | Triggering tests, functional tests, performance comparison | 0/19 structured tests |
| **Negative Triggers** | Phrases that should NOT trigger the skill | Needs audit |

### 2.2 External References (Secondary Benchmarks)

| Source | Repository | Relevance |
|--------|-----------|-----------|
| Anthropic Official | `anthropics/skills` | Reference implementations of skill patterns |
| Vercel | `vercel-labs/agent-skills` | FAANG-level CLI skill patterns |
| Community | `awesome-claude-skills` curated list | Ecosystem patterns and conventions |

---

## 3. Current State Audit

### 3.1 Skill Inventory (19 skills)

| Skill | Lines | Words | Resources/ | Error Refs | Examples | Over 5K Words |
|-------|-------|-------|-----------|------------|----------|---------------|
| auditing-security | 1,046 | 4,548 | yes | 17 | 50 | no |
| autonomous-agent | 1,162 | 4,134 | yes | 25 | 108 | no |
| bridgebuilder-review | 77 | 327 | yes | 2 | 4 | no |
| browsing-constructs | 414 | 1,562 | no | 7 | 34 | no |
| continuous-learning | 453 | 1,819 | yes | 12 | 19 | no |
| deploying-infrastructure | 879 | 3,880 | yes | 17 | 32 | no |
| designing-architecture | 372 | 1,637 | yes | 3 | 20 | no |
| discovering-requirements | 800 | 3,138 | yes | 17 | 44 | no |
| enhancing-prompts | 259 | 1,008 | yes | 10 | 14 | no |
| flatline-knowledge | 220 | 687 | yes | 4 | 16 | no |
| implementing-tasks | 1,107 | 4,596 | yes | 20 | 42 | no |
| mounting-framework | 305 | 921 | no | 4 | 32 | no |
| planning-sprints | 599 | 2,586 | yes | 2 | 32 | no |
| reviewing-code | 1,021 | 4,468 | yes | 21 | 43 | no |
| riding-codebase | 1,686 | 6,905 | yes | 2 | 128 | **YES** |
| rtfm-testing | 519 | 2,882 | no | 12 | 12 | no |
| run-mode | 399 | 1,364 | no | 5 | 36 | no |
| simstim-workflow | 706 | 2,755 | no | 20 | 34 | no |
| translating-for-executives | 702 | 3,019 | yes | 4 | 48 | no |

**Totals**: 12,726 lines, ~50,235 words across 19 skills.

### 3.2 Gap Analysis Summary

| Gap | Count | Skills Affected | Severity |
|-----|-------|-----------------|----------|
| Over 5,000 words | 1 | riding-codebase (6,905) | HIGH |
| Near 5,000 words (>4,000) | 4 | auditing-security, implementing-tasks, reviewing-code, autonomous-agent | MEDIUM |
| Low error handling (<5 refs) | 5 | bridgebuilder-review, designing-architecture, flatline-knowledge, mounting-framework, planning-sprints | MEDIUM |
| Few examples (<10) | 2 | bridgebuilder-review, continuous-learning | LOW |
| No structured test framework | 19 | All | HIGH |
| Description quality unknown | 19 | All (needs per-skill review) | MEDIUM |
| No negative triggers | Unknown | Needs audit | LOW |

---

## 4. Goals

| # | Goal | Success Metric |
|---|------|---------------|
| G-1 | All skills under 5,000 words | 19/19 SKILL.md files ≤ 5,000 words |
| G-2 | Descriptions follow Anthropic formula | 19/19 descriptions include WHAT + WHEN + capabilities |
| G-3 | Error handling documented | 19/19 have ≥ 5 error/troubleshooting references |
| G-4 | Skill test framework exists | Test harness covering trigger accuracy + functional completion |
| G-5 | Progressive disclosure optimized | Skills >3,000 words use references/ for detail offload |

---

## 5. Functional Requirements

### FR-1: SKILL.md Size Reduction (G-1, G-5)

Refactor skills exceeding 5,000 words by extracting detailed content to `references/` files:

- **riding-codebase** (6,905 words → target ≤4,500): Move phase-specific instructions, output format templates, and validation checklists to `references/`
- **Near-limit skills** (>4,000 words): Audit for content that could be linked rather than inlined

**Approach**: For each over-limit skill:
1. Identify sections that are reference material (templates, checklists, detailed examples)
2. Extract to `resources/references/{topic}.md`
3. Replace inline content with a link: `See: resources/references/{topic}.md`
4. Verify skill still triggers and functions correctly

### FR-2: Description Standardization (G-2)

Update all 19 skill descriptions to follow Anthropic's formula:

```
[What it does] + [When to use it] + [Key capabilities]
```

**Requirements**:
- Each description must be under 1,024 characters
- Description must include at least one trigger context ("Use when...")
- Description must list 2-3 key capabilities
- Descriptions appear in both `index.yaml` and SKILL.md frontmatter

**Example transformation**:
```yaml
# Before (implementing-tasks)
description: |
  Use this skill IF user needs to implement sprint tasks from grimoires/loa/sprint.md,
  OR feedback has been received in engineer-feedback.md that needs addressing.
  Implements production-grade code with comprehensive tests, follows existing patterns,
  and generates detailed reports. Produces report at grimoires/loa/a2a/sprint-N/reviewer.md.

# After
description: |
  Execute sprint tasks with production-quality code, tests, and implementation reports.
  Use when implementing tasks from grimoires/loa/sprint.md or addressing feedback in
  engineer-feedback.md / auditor-sprint-feedback.md. Handles feedback-first resolution,
  test generation, and reviewer.md report creation.
```

**Note**: Descriptions should preserve specific file paths referenced by the skill's trigger
logic. Existing trigger phrases in `index.yaml` remain unchanged; descriptions may summarize
but must not drop paths that affect matching precision.

### FR-3: Error Handling Audit (G-3)

For the 5 skills with fewer than 5 error references, add:

1. **Error table**: Common failure modes with causes and resolutions
2. **Troubleshooting section**: "Skill doesn't trigger", "Unexpected output", "API failure" patterns
3. **Recovery guidance**: What to do when the skill fails mid-execution

Target skills: bridgebuilder-review, designing-architecture, flatline-knowledge, mounting-framework, planning-sprints.

### FR-4: Skill Test Framework (G-4)

Create a test harness for validating skill quality:

#### FR-4a: Trigger Accuracy Tests

For each skill, define:
- **Positive triggers**: Phrases that SHOULD invoke the skill (from `triggers` in index.yaml)
- **Negative triggers**: Phrases that should NOT invoke the skill
- **Validation**: Run test phrases against Claude's skill matching and verify accuracy

**Pass criteria**: ≥90% precision and recall on a 20-phrase test set per skill.
**Outcome definitions**: `PASS` (correct skill triggered), `MISS` (expected skill not triggered), `MISFIRE` (wrong skill triggered).

#### FR-4b: Structural Validation Tests

Automated checks (can run in CI):
- SKILL.md exists and has valid frontmatter
- Word count ≤ 5,000
- Description follows WHAT + WHEN + capabilities formula (regex/heuristic check)
- No README.md in skill folder
- Folder name is kebab-case
- Name field matches folder name
- No XML tags in frontmatter
- resources/ directory exists if referenced in SKILL.md

**Pass criteria**: Zero failures across all checks (binary pass/fail). Any single check failure = FAIL for that skill.

#### FR-4c: Functional Smoke Tests

Per-skill test definitions (manual or semi-automated):
- Input scenario → expected behavior → actual behavior
- Performance: measured in tool calls to completion

**Pass criteria**: Skill completes with exit code 0 in ≤10 tool calls. No tool calls returning errors during execution.
**Outcome definitions**: `PASS` (all assertions met), `FLAKY` (intermittent failures across 3 runs), `FAIL` (deterministic failure), `TIMEOUT` (exceeded 10 tool-call budget).

### FR-5: Negative Trigger Audit (G-2)

Review each skill's trigger configuration and add negative triggers where needed:

```yaml
# Example: deploying-infrastructure
triggers:
  - "/deploy"
  - "deploy to production"
negative_triggers:
  - "deploy a feature flag"      # → implementing-tasks
  - "deploy documentation"       # → translating-for-executives
```

This prevents skills from firing incorrectly when trigger phrases overlap.

### FR-6: Progressive Disclosure Optimization (G-5)

For skills with >3,000 words, audit the content structure against Anthropic's 3-level model:

| Level | What Loads | Budget |
|-------|-----------|--------|
| L1: Frontmatter | Always loaded into context | <1,024 chars |
| L2: SKILL.md body | Loaded when skill triggers | ≤5,000 words |
| L3: Linked references | Loaded on-demand during execution | No limit |

Ensure each skill's content is at the right level. Inline instructions needed for every invocation stay in L2. Reference material, templates, and detailed examples move to L3.

---

## 6. Non-Functional Requirements

| # | Requirement |
|---|-------------|
| NFR-1 | Zero behavioral regressions — all skills must function identically after refactoring |
| NFR-2 | No new dependencies — test framework uses existing tooling (bash, node:test) |
| NFR-3 | Backward compatible — existing trigger phrases continue to work |
| NFR-4 | Documentation-only changes — no application code changes in this issue |

---

## 7. Risks

| # | Risk | Impact | Mitigation |
|---|------|--------|------------|
| R-1 | Refactoring breaks skill triggering | HIGH | Test triggers before/after each change |
| R-2 | Content extraction to references/ loses context | MEDIUM | Verify skills still complete functional smoke tests |
| R-3 | Description standardization reduces specificity | LOW | Keep existing trigger phrases; add, don't replace |
| R-4 | Test framework maintenance burden | LOW | Keep tests minimal and automated where possible |
| R-5 | Post-merge regression discovery | HIGH | Keep PR branch open for 7 days post-merge; create SKILL.md.bak copies before refactoring; revert on user-reported trigger failures within the observation window |

---

## 8. Prioritization

| Priority | Requirement | Rationale |
|----------|-------------|-----------|
| P0 | FR-1: Size reduction (riding-codebase) | Active hard-limit violation — stop the bleeding first |
| P0 | FR-4b: Structural validation tests | Automated regression gate for all subsequent changes |
| P1 | FR-2: Description standardization | Affects trigger accuracy across all 19 skills |
| P2 | FR-3: Error handling audit | 5 skills affected, improves user experience |
| P2 | FR-6: Progressive disclosure optimization | Affects near-limit skills |
| P3 | FR-4a: Trigger accuracy tests | Valuable but requires manual validation |
| P3 | FR-5: Negative trigger audit | Prevents misfire but low current impact |
| P3 | FR-4c: Functional smoke tests | Nice-to-have, labor intensive |

**Priority rationale**: FR-1 and FR-4b are both P0 because the riding-codebase violation is actively broken (exceeds Anthropic's hard limit) while structural tests prevent introducing new violations during the remaining work. Following incident response principles: stop the bleeding, then build monitoring.

---

## 9. Success Criteria

| Criterion | Measurement |
|-----------|-------------|
| All SKILL.md files ≤ 5,000 words | `wc -w` on each file |
| All descriptions follow WHAT + WHEN + capabilities | Manual review + regex validation |
| All skills have ≥ 5 error/troubleshooting references | `grep -c` on each file |
| Structural test suite passes for all 19 skills | CI green |
| Zero skill behavioral regressions | Existing functionality preserved |

---

## 10. Out of Scope

- Rewriting skill logic or changing skill behavior
- Adding new skills
- Changing the skill framework architecture (index.yaml structure, etc.)
- Changing CLAUDE.md or CLAUDE.loa.md content
- Implementing the full Anthropic test suite (triggering tests require Claude API access)

---

## 11. Appendix: Audit Methodology

All quantitative claims in Section 3 were measured using the following commands. Word count was chosen over token count because Anthropic's guide specifies word limits (not tokens), and `wc -w` is universally reproducible without requiring a tokenizer dependency.

### Word Count Measurement

```bash
for dir in .claude/skills/*/; do
  name=$(basename "$dir")
  words=$(wc -w < "$dir/SKILL.md" 2>/dev/null || echo "0")
  echo "$name: $words words"
done
```

### Error/Troubleshooting Reference Count

```bash
for dir in .claude/skills/*/; do
  name=$(basename "$dir")
  refs=$(grep -c -iE 'error|troubleshoot|fail' "$dir/SKILL.md" 2>/dev/null || echo "0")
  echo "$name: $refs error refs"
done
```

### Example Count (code blocks + example headers)

```bash
for dir in .claude/skills/*/; do
  name=$(basename "$dir")
  examples=$(grep -c -E '^(###? Example|```)' "$dir/SKILL.md" 2>/dev/null || echo "0")
  echo "$name: $examples examples"
done
```

### Structure Checks

```bash
for dir in .claude/skills/*/; do
  name=$(basename "$dir")
  has_res=$([ -d "$dir/resources" ] && echo "yes" || echo "no")
  has_readme=$([ -f "$dir/README.md" ] && echo "YES-BAD" || echo "no")
  echo "$name: resources=$has_res readme=$has_readme"
done
```

**Decision**: Word count (`wc -w`) was chosen over token count because:
1. Anthropic's guide specifies "5,000 words" not "5,000 tokens"
2. `wc -w` is reproducible on any POSIX system without dependencies
3. Token counts vary by tokenizer implementation; word counts are deterministic

---

## 12. Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-02-09 | Initial PRD from /plan-and-analyze research |
| 1.1.0 | 2026-02-09 | Revised per Bridgebuilder review on PR #264: added audit methodology appendix, explicit test pass/fail thresholds, promoted FR-1 to P0, added rollback strategy R-5, preserved file paths in description examples |

---

## 13. References

| Document | Relevance |
|----------|-----------|
| Anthropic "Complete Guide to Building Skills for Claude" (30pp PDF) | Primary benchmark |
| `anthropics/skills` GitHub repo | Official reference implementations |
| `vercel-labs/agent-skills` GitHub repo | FAANG-level patterns |
| `awesome-claude-skills` curated list | Community best practices |
| Issue #261 | Feature request |
