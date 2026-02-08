# PRD: RTFM Testing — Documentation Quality via Fresh Agent Spawns

**Version**: 1.0.0
**Status**: Draft
**Author**: Discovery Phase (plan-and-analyze)
**Date**: 2026-02-09
**Issue**: #236
**Research**: PR #256

---

## 1. Problem Statement

Loa validates code quality across three dimensions — code quality (`/review-sprint`, `/audit-sprint`, `/gpt-review`), document quality (`/validate docs`, Flatline Protocol), and document usability (nothing). The third column is empty.

Documentation written by the builder is almost always incomplete. The author unconsciously fills gaps from their own context. They assume knowledge. They skip "obvious" steps. The docs pass review because reviewers also have context. Nobody tests whether a fresh user can actually follow them.

Loa's README is 173 lines. INSTALLATION.md is 858 lines. Both were written by people who built Loa. Neither has been validated by a zero-context newcomer.

> Sources: PR #256 research, Bridgebuilder review Finding 6 (three-column quality pipeline gap)

---

## 2. Vision

Create a standalone `/rtfm` skill that spawns fresh zero-context agents to test whether documentation is usable by newcomers. The skill validates that someone (or something) with no prior knowledge can complete a task using only the provided docs.

The methodology is a **hermetic documentation test** — the agent equivalent of Google Bazel's hermetic builds. No implicit dependencies, no ambient state. If the zero-context agent can't follow the docs, the docs have gaps.

> Sources: zscole/rtfm-testing methodology, Bridgebuilder Finding 1 (hermetic build analogy)

---

## 3. Goals & Success Metrics

### Goals

1. Fill the "Doc Usability" column in Loa's quality pipeline
2. Provide a repeatable, automated test for documentation completeness
3. Catch the "curse of knowledge" gaps that human/agent reviewers miss
4. Enable iterative improvement with measurable progress (Cold Start Score)

### Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Cold Start Score for README.md | 1 (certified on first try) | After docs are fixed per initial RTFM run |
| Cold Start Score for INSTALLATION.md | 1 | After docs are fixed per initial RTFM run |
| Gap detection rate vs manual review | >2x more gaps found | Compare RTFM gaps vs human review of same docs |
| Time per test iteration | <60 seconds | Wall clock time for single RTFM test run |
| Cost per test iteration | <$0.05 | API token cost per run |

---

## 4. User & Stakeholder Context

### Primary Persona: Loa Maintainer

- Writes documentation as part of development workflow
- Wants confidence that docs are usable before release
- Currently has no way to test docs from a newcomer perspective

### Secondary Persona: Loa User (Consumer of Docs)

- Encounters Loa for the first time via README or INSTALLATION.md
- Has terminal/git knowledge but zero Loa/Claude Code context
- Needs docs that explain every step without assuming knowledge

### Tertiary Persona: Project Team Using Loa

- Uses Loa on their own codebase
- Writes project-specific docs (README, API docs, guides)
- Wants to validate their own docs before shipping

---

## 5. Functional Requirements

### FR-1: Core RTFM Test Execution

The skill spawns a `Task` subagent with zero project context, providing only the bundled documentation and a task to attempt. The subagent operates under strict "no inference" rules and reports every gap it encounters.

```
/rtfm README.md                        # Test README usability
/rtfm INSTALLATION.md                  # Test installation guide
/rtfm README.md INSTALLATION.md        # Test combined onboarding
/rtfm --task "Install Loa and run /plan on a new project"
```

### FR-2: Tester Capabilities Manifest

**Critical** (per Bridgebuilder Finding 1): Define an explicit capabilities manifest for the tester agent — what it knows and doesn't know. Without this, test results vary based on LLM interpretation of "basic CLI usage."

```yaml
rtfm_tester_capabilities:
  knows:
    - terminal/shell basics (cd, ls, mkdir, cat)
    - git basics (clone, commit, push, pull)
    - package managers exist (npm, pip, cargo) but NOT which to use
    - environment variables concept
    - text editor usage
    - GitHub web interface basics
  does_not_know:
    - Claude Code (what it is, how it works)
    - Loa (any concept: grimoires, beads, skills, commands)
    - .claude/ directory conventions
    - YAML configuration patterns for AI tools
    - Anthropic API or any LLM API
    - What "slash commands" are in this context
```

The manifest is embedded in the tester prompt and versioned alongside the skill. Projects can override it via `.loa.config.yaml` to adjust the "knowledge floor" for their domain.

> Source: Bridgebuilder Finding 1 — Stripe's "Persona Zero" pattern

### FR-3: Structured Gap Reporting

The tester reports gaps in a structured format with 6 types and 3 severity levels:

| Type | Description |
|------|-------------|
| `MISSING_STEP` | Required action not documented |
| `MISSING_PREREQ` | Prerequisite not listed |
| `UNCLEAR` | Instructions are ambiguous |
| `INCORRECT` | Documentation is wrong |
| `MISSING_CONTEXT` | Assumes undocumented knowledge |
| `ORDERING` | Steps in wrong sequence |

| Severity | Definition |
|----------|------------|
| BLOCKING | Cannot proceed without this information |
| DEGRADED | Can proceed but with confusion or workarounds |
| MINOR | Inconvenient but not blocking |

Each gap includes: type, location, problem description, impact, severity, and suggested fix.

### FR-4: Iterative Test Loop

After the first test run, the user fixes gaps and re-runs. The skill tracks iteration count as the **Cold Start Score** (lower = better docs).

```
Iteration 1: 7 gaps, 3 blocking → FAILURE
Iteration 2: 3 gaps, 1 blocking → PARTIAL
Iteration 3: 0 gaps, 0 blocking → SUCCESS → RTFM CERTIFIED
```

### FR-5: Baseline Registry and Regression Detection

**Critical** (per Bridgebuilder Finding 5): Track Cold Start Scores as baselined regression metrics, not one-shot counters.

```yaml
# grimoires/loa/a2a/rtfm/baselines.yaml
baselines:
  README.md:
    task: "Install Loa on a fresh repo and run /plan"
    cold_start_score: 1
    certified_date: "2026-02-15"
    certified_sha: "abc123"
  INSTALLATION.md:
    task: "Follow the complete installation guide"
    cold_start_score: 1
    certified_date: "2026-02-15"
    certified_sha: "def456"
```

When a baselined document is modified after certification, the skill can detect the drift and recommend a retest. Integration with `/review` triggers this automatically when doc files are changed in a sprint.

> Source: Bridgebuilder Finding 5 — Chromium's performance budget pattern

### FR-6: Pre-Built Task Templates

Default task templates for common Loa documentation testing:

| Task ID | Task | Target Docs |
|---------|------|-------------|
| `install` | "Install Loa on a fresh repo" | INSTALLATION.md |
| `quickstart` | "Run your first development cycle" | README.md |
| `beads` | "Set up beads_rust for task tracking" | INSTALLATION.md |
| `gpt-review` | "Configure GPT cross-model review" | INSTALLATION.md |
| `update` | "Update Loa to the latest version" | INSTALLATION.md |
| `mount` | "Mount Loa on an existing project" | README.md + INSTALLATION.md |

Users can also provide custom tasks via `--task "..."`.

### FR-7: Report Output

Write test results to `grimoires/loa/a2a/rtfm/report-{date}.md` with:
- Task attempted
- Execution log (step-by-step what the tester tried)
- All gaps found with structured format
- Result verdict (SUCCESS / PARTIAL / FAILURE)
- Cold Start Score
- Iteration history table

### FR-8: `/review` Integration Point

**Critical** (per Bridgebuilder Finding 7): RTFM integrates at `/review` not `/ship`.

When documentation files are modified in a sprint, RTFM runs automatically as part of the review cycle:

```
/review (Golden Path)
  → /review-sprint sprint-N    (code review)
  → /audit-sprint sprint-N     (security audit)
  → /rtfm --auto               (doc usability, if docs changed)
```

The `--auto` flag checks if doc files were modified in the sprint. If yes, runs RTFM against modified docs. If no, skips silently.

> Source: Bridgebuilder Finding 7 — Meta's documentation CI pattern

---

## 6. Non-Functional Requirements

### NFR-1: Cleanroom Implementation

**Critical** (per Bridgebuilder Finding 4): The tester prompt is a cleanroom implementation inspired by the RTFM methodology but written from scratch. No verbatim copying from zscole/rtfm-testing, which lacks a LICENSE file despite claiming MIT.

> Source: Bridgebuilder Finding 4 — Google's cleanroom policy post-Oracle v. Google

### NFR-2: Model Selection

The tester subagent defaults to `sonnet`. Haiku is available as a cost optimization but must be validated first.

**Validation required** (per Bridgebuilder Finding 3): Run the same test on both sonnet and haiku. If haiku finds 30%+ fewer gaps, it's unreliable (filling gaps unconsciously instead of reporting them). Only promote haiku as default if gap counts are within 10%.

> Source: Bridgebuilder Finding 3 — instruction-following fidelity concern

### NFR-3: Cost Budget

- Target: <$0.05 per test iteration
- Estimated: ~12K tokens per run with sonnet ≈ $0.03
- Even with 5 iterations to certification, total cost < $0.15

### NFR-4: Zero Runtime Dependencies

The skill is pure SKILL.md + Task subagent invocation. No npm packages, no build step, no compiled artifacts. Consistent with Loa's skill architecture.

### NFR-5: Context Isolation

The Task subagent MUST NOT have access to:
- Parent conversation history
- CLAUDE.md or any framework instructions
- grimoire contents
- Source code
- Any file not explicitly bundled as "documentation under test"

This is the fundamental guarantee. Without it, the test is meaningless.

---

## 7. Feedback Loop Architecture

**Critical** (per Bridgebuilder Finding 2): RTFM is not just a test — it's the sensor in a closed-loop quality system.

### Gap Pattern Library

Gaps discovered by RTFM feed back into two places:

1. **Static rules for `/validate docs`** — Recurring gap patterns become rules that `/validate docs` can enforce without spawning an agent. Example: "Every doc that references `.loa.config.yaml` must explain how to create it from the example file."

2. **`/ride` output templates** — If `/ride` generates initial docs and RTFM finds the same gap types repeatedly, the generation templates should be updated to prevent those gaps from being generated in the first place.

```
/ride → generates docs
  ↓
Human edits and refines docs
  ↓
/rtfm → tests if docs are actually usable
  ↓
Gaps feed back to:
  ├── /ride templates (prevent generation of known gap patterns)
  └── /validate docs rules (catch patterns statically)
```

This is the difference between a test and a quality system. A test finds bugs. A quality system makes bugs structurally impossible.

> Source: Bridgebuilder Finding 2 — Netflix's Chaos Engineering pattern library, Kubernetes known-pitfalls database

---

## 8. Scope & Prioritization

### MVP (Sprint 1)

1. Core `/rtfm` command with doc bundling and Task subagent spawn
2. Tester prompt with capabilities manifest
3. Structured gap reporting (6 types, 3 severities)
4. Iterative test loop with Cold Start Score
5. Report output to `grimoires/loa/a2a/rtfm/`
6. Pre-built task templates for Loa's own docs

### Phase 2 (Sprint 2)

7. Baseline registry with regression detection
8. `/review` integration (`--auto` flag)
9. Sonnet vs haiku model validation experiment
10. Gap verdict mapping to Loa's existing validation system

### Future (Not In Scope)

- Feedback loop to `/validate docs` static rules (requires `/validate docs` changes)
- Feedback loop to `/ride` templates (requires `/ride` changes)
- Fourth column: "Operational Readiness" testing (per Bridgebuilder Finding 6)
- Multi-language documentation testing
- Visual documentation testing (screenshots, diagrams)

---

## 9. Architecture Decisions

### ADR-1: Standalone Skill (Option A from PR #256)

**Decision**: Create standalone `/rtfm` skill in Loa core, not loa-constructs.

**Rationale**: Documentation quality is a core framework concern, not an optional add-on. Every Loa project generates docs (`/ride`, `/plan-and-analyze`) and should be able to validate them.

### ADR-2: Cleanroom Tester Prompt

**Decision**: Write tester prompt from scratch, informed by but not copying zscole/rtfm-testing.

**Rationale**: Source repo has no LICENSE file. The methodology is uncopyrightable but the specific prompt text is creative work with unclear licensing.

### ADR-3: Integration at `/review` Not `/ship`

**Decision**: RTFM runs during review phase, not deployment.

**Rationale**: Discovering doc gaps at deploy time is too late. Meta, Vercel, and Netlify all run doc tests alongside code tests in the review phase. "Proofreading your wedding speech at the reception is too late."

### ADR-4: Sonnet Default, Haiku Optional

**Decision**: Default to sonnet for the tester agent. Haiku available but must pass validation.

**Rationale**: RTFM's methodology requires the tester to suppress its strongest instinct (helpfulness). Smaller models follow adversarial constraints less reliably. Validate before promoting.

### ADR-5: Closed-Loop Feedback System (Future)

**Decision**: Design RTFM from day one as a sensor in a closed-loop system, even though the feedback loops to `/validate docs` and `/ride` are not in MVP scope.

**Rationale**: The gap report format and pattern library structure should be designed to support future integration. Building it as a standalone script that later needs to be retrofitted into a pipeline would create technical debt.

---

## 10. Risks & Dependencies

| Risk | Severity | Mitigation |
|------|----------|------------|
| False positives (tester too strict) | Low | Tune capabilities manifest; distinguish "needs terminal knowledge" from "needs Loa knowledge" |
| False negatives (model fills gaps unconsciously) | Medium | Validate with sonnet first; compare haiku gap counts before promoting |
| Token cost at scale | Low | ~$0.03 per iteration; even heavy use is <$1/day |
| Context leakage (Task subagent gets parent context) | High | Verify Task subagent isolation; include canary in test to detect leakage |
| Scope creep to test all docs | Medium | Start with README + INSTALLATION only; expand deliberately |

### Dependencies

- Claude Code `Task` tool with subagent isolation (existing)
- `grimoires/loa/a2a/` directory structure (existing)
- Modifications to `/review` golden path for Phase 2 integration (new)

---

## 11. Quality Pipeline Position

```
Code Quality          Doc Quality           Doc Usability
────────────          ───────────           ─────────────
/review-sprint        /validate docs        /rtfm (NEW)
/audit-sprint         Flatline Protocol
/gpt-review
```

> Source: Bridgebuilder Finding 6. A fourth column (Operational Readiness) is acknowledged but out of scope.

---

## 12. References

- [Issue #236](https://github.com/0xHoneyJar/loa/issues/236) — Original request
- [PR #256](https://github.com/0xHoneyJar/loa/pull/256) — Research and Bridgebuilder review
- [zscole/rtfm-testing](https://github.com/zscole/rtfm-testing) — Methodology inspiration
- Bridgebuilder Review Findings 1-8 — Architecture and quality guidance
