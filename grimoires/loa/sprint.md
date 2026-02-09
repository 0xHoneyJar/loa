# Sprint Plan: RTFM Testing Skill

**Version**: 2.0.0
**Date**: 2026-02-09
**PRD**: grimoires/loa/prd.md
**SDD**: grimoires/loa/sdd.md
**Issue**: #236
**PR**: #259

---

## Overview

| Field | Value |
|-------|-------|
| Total Sprints | 2 |
| Sprint Duration | Single session each |
| Developer | Claude (AI agent) |
| Scope | Sprint 1: MVP (complete) / Sprint 2: PR #259 review feedback |

---

## Sprint 1: Core `/rtfm` Skill

**Goal**: Deliver a working `/rtfm` command that spawns zero-context tester agents, parses structured gap reports, and writes test results.

### Task 1: Create SKILL.md with Tester Prompt

**File**: `.claude/skills/rtfm-testing/SKILL.md`

Create the main skill definition containing:
- Objective section
- Tester capabilities manifest (knows/does_not_know lists from PRD FR-2)
- Cleanroom tester prompt with rules, gap format, output format
- Context isolation canary check
- Task templates (6 pre-built: install, quickstart, mount, beads, gpt-review, update)
- Gap parser logic (extract [GAP] markers, count by type/severity, determine verdict)
- Report template
- 5-phase workflow (arg resolution → doc bundling → tester spawn → gap parsing → report)

**Acceptance Criteria**:
- [x] Tester prompt is cleanroom (no verbatim text from zscole/rtfm-testing)
- [x] Capabilities manifest explicitly lists knows and does_not_know
- [x] Canary check embedded in prompt
- [x] All 6 gap types defined (MISSING_STEP, MISSING_PREREQ, UNCLEAR, INCORRECT, MISSING_CONTEXT, ORDERING)
- [x] All 3 severity levels defined (BLOCKING, DEGRADED, MINOR)
- [x] Verdict rules: SUCCESS (0 blocking) / PARTIAL (>0 blocking, progress) / FAILURE (stuck)
- [x] 6 task templates with default doc mappings
- [x] Workflow phases 0-4 documented

**Estimated Effort**: Medium

### Task 2: Create index.yaml

**File**: `.claude/skills/rtfm-testing/index.yaml`

Create skill metadata following Loa conventions:
- name, version, model, color, danger_level, categories
- Triggers: `/rtfm`, `test documentation`, `validate docs usability`
- Inputs: docs (string[]), task (string)
- Outputs: report path

**Acceptance Criteria**:
- [x] danger_level is `safe`
- [x] model is `sonnet`
- [x] Triggers match command invocation patterns
- [x] Categories include `quality`

**Estimated Effort**: Low

### Task 3: Create Command File

**File**: `.claude/commands/rtfm.md`

Create command definition with:
- Arguments: docs (positional), --task, --template, --auto, --model
- Agent routing to rtfm-testing skill
- Pre-flight checks
- Output path declaration

**Acceptance Criteria**:
- [x] All arguments from SDD Section 4.1 defined
- [x] Routes to `skills/rtfm-testing/` agent
- [x] Default model is sonnet
- [x] --template accepts: install, quickstart, mount, beads, gpt-review, update

**Estimated Effort**: Low

### Task 4: Smoke Test on README.md

Run `/rtfm README.md` against Loa's actual README and verify:

**Acceptance Criteria**:
- [x] Tester subagent spawns successfully
- [ ] Canary check passes — WARNING: tester recognized Loa (expected for known projects)
- [x] Gaps are found and reported in [GAP] format
- [x] Verdict is returned (FAILURE — 5 blocking gaps in README)
- [x] Report is written to `grimoires/loa/a2a/rtfm/report-2026-02-09.md`
- [x] Summary displayed to user with gap count and verdict

**Estimated Effort**: Low (validation only)

---

## Dependencies

```
Task 1 (SKILL.md) ──┐
Task 2 (index.yaml) ─┼──→ Task 4 (Smoke Test)
Task 3 (rtfm.md) ───┘
```

Tasks 1-3 are independent and can be implemented in parallel. Task 4 requires all three.

---

## Out of Scope (Phase 2)

- Baseline registry (`baselines.yaml`)
- `/review` golden path integration (`--auto`)
- Sonnet vs haiku model comparison
- Gap verdict mapping to `/validate docs`

---

## Sprint 1 Success Criteria

Sprint 1 is complete when:
1. All 3 files created and committed
2. `/rtfm README.md` produces a valid gap report
3. Canary check validates context isolation
4. Report written to `grimoires/loa/a2a/rtfm/`

---

## Sprint 2: PR #259 Review Feedback — Hardening & Resilience

**Goal**: Address the 4 actionable Bridgebuilder findings and 2 decision trail gaps from PR #259 review. Harden canary verification, add parser resilience, improve documentation clarity, and replace hard size limits with progressive degradation.

**Source**: [PR #259 Bridgebuilder Review](https://github.com/0xHoneyJar/loa/pull/259) — Findings 1-4 + Decision Trail Check

### Task 1: Planted Canary for Deterministic Context Isolation

**File**: `.claude/skills/rtfm-testing/SKILL.md`

**Bridgebuilder Finding 1** (Medium): The current canary relies on the tester self-reporting prior knowledge — epistemically unfalsifiable. LLMs cannot reliably introspect on their own knowledge provenance (Goodhart's Law applied to self-assessment). Netflix solved the equivalent problem in Chaos Engineering with external observation rather than self-reporting.

Implement a "planted canary" mechanism that injects a fictitious detail into the doc bundle and mechanically verifies whether the tester references the planted detail or uses real project knowledge instead.

Changes to SKILL.md:
- Add `<planted_canary>` section describing the mechanism
- Modify workflow Phase 1 (Document Bundling) to optionally inject a planted project name
- Modify `<tester_prompt>` canary check to reference the planted name
- Modify `<gap_parser>` canary validation to check planted name in tester response
- Document canary as two-layer defense: Layer 1 (self-report, suggestive) + Layer 2 (planted, deterministic)

**Acceptance Criteria**:
- [x] SKILL.md contains `<planted_canary>` section with injection rules
- [x] Workflow Phase 1 includes planted canary injection step
- [x] Canary validation in gap_parser checks both self-report AND planted name
- [x] Canary result in report shows: `PASS (planted)` / `WARNING (self-report only)` / `FAIL (planted name ignored)`
- [x] SDD security section (Section 11) updated with two-layer canary architecture and documented limitations

**Estimated Effort**: Medium

### Task 2: Gap Parser Fallback Mode

**File**: `.claude/skills/rtfm-testing/SKILL.md`

**Bridgebuilder Finding 2** (Medium): The gap parser assumes perfect LLM format compliance. No fallback for: bold `**[GAP]**` markers, non-standard severity names (e.g., `Critical` vs `BLOCKING`), prose-only responses, or hallucinated gap types. LLMs are probabilistic — format compliance cannot be guaranteed (Postel's Law: "be liberal in what you accept").

Add a degraded parsing mode and a new `MANUAL_REVIEW` verdict.

Changes to SKILL.md:
- Add `### Fallback Parsing` subsection to `<gap_parser>`
- Add `### Severity Normalization` (map common synonyms: Critical→BLOCKING, High→BLOCKING, Medium→DEGRADED, Low→MINOR, Info→MINOR)
- Add `MANUAL_REVIEW` verdict to verdict determination table
- Add retry-once logic for empty/malformed responses

**Acceptance Criteria**:
- [x] gap_parser section includes `### Fallback Parsing` with 4-step escalation (structured → normalized → raw-with-manual-review → retry)
- [x] Severity normalization table maps at least 6 common synonyms to the 3 canonical levels
- [x] Verdict determination table includes `MANUAL_REVIEW` for unparseable-but-non-empty responses
- [x] Report template includes fallback indicator when degraded parsing was used
- [x] SDD updated with gap parser failure modes documentation

**Estimated Effort**: Medium

### Task 3: Zone Constraint Clarity

**File**: `.claude/skills/rtfm-testing/SKILL.md`

**Bridgebuilder Finding 3** (Low): Zone constraints declare `NEVER: .claude/` but the skill lives in `.claude/skills/rtfm-testing/`. The constraints describe the tester subagent's scope, not the orchestrator's, but this isn't explicit. Docker's security model has the same layered-access confusion — Kubernetes solved it by labeling security context at every boundary.

Rewrite `<zone_constraints>` to explicitly label orchestrator vs tester subagent scope.

**Acceptance Criteria**:
- [x] zone_constraints has separate sections for "Orchestrator" and "Tester subagent"
- [x] Tester subagent section specifies: READ only bundled docs, WRITE none, NEVER .claude/system/grimoire
- [x] Orchestrator section specifies: READ any doc file, WRITE grimoires/loa/a2a/rtfm/

**Estimated Effort**: Low

### Task 4: Progressive Size Limits

**File**: `.claude/skills/rtfm-testing/SKILL.md`

**Bridgebuilder Finding 4** (Low): The 50KB limit is a cliff — at 49KB everything works, at 51KB the skill rejects entirely. Cloudflare Workers had the same UX problem; GitHub PR review solved it with progressive degradation. The 50KB limit is really a context window budget disguised as a file size limit.

Replace the hard 50KB rejection with a three-tier progressive approach and add a pre-flight size estimate.

Changes to SKILL.md:
- Modify workflow Phase 0 (Argument Resolution) to report estimated bundle size
- Modify workflow Phase 1 (Document Bundling) with three tiers:
  - Under 50KB: bundle all, single tester run (current behavior)
  - 50KB-100KB: warn user, offer per-doc individual testing
  - Over 100KB: reject with guidance to split or use --task to focus
- Update the hard "reject if > 50KB" to use the tiered logic

**Acceptance Criteria**:
- [x] Phase 0 reports estimated bundle size in pre-flight output
- [x] Phase 1 implements three-tier size handling (50KB / 100KB / >100KB)
- [x] Tier 2 (50-100KB) offers per-doc testing as alternative to rejection
- [x] Error messages include actionable guidance (split docs, use --task, use --template)
- [x] SDD config section notes `max_doc_size_kb` is configurable

**Estimated Effort**: Low

---

## Sprint 2 Dependencies

```
Task 1 (Planted Canary) ──independent──→
Task 2 (Parser Fallback) ──independent──→
Task 3 (Zone Clarity) ────independent──→
Task 4 (Size Limits) ─────independent──→
```

All 4 tasks are independent — they modify different sections of SKILL.md and can be implemented in any order. No smoke test task needed (Sprint 1 already validated the skill works; these are refinements to existing sections).

---

## Sprint 2 Out of Scope

- Full Phase 2 PRD items (baseline registry, /review integration, haiku validation)
- Canary planted name database/rotation (future hardening)
- Gap parser unit tests (no test infrastructure exists for SKILL.md-only skills)
- Integration with `/validate docs` static rules

---

## Sprint 2 Success Criteria

Sprint 2 is complete when:
1. All 4 SKILL.md sections updated per acceptance criteria
2. SDD security section updated with canary limitations and parser failure modes
3. No regressions — existing tester prompt, gap taxonomy, and report template unchanged
4. All changes committed and pushed to PR #259
