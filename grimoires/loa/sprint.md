# Sprint Plan: Bridgebuilder Constellation — From Pipeline to Deliberation

> **Cycle**: 046
> **Created**: 2026-02-28
> **PRD**: `grimoires/loa/prd.md`
> **SDD**: `grimoires/loa/sdd.md`
> **Target**: `.claude/` System Zone (scripts, skills, data) + `.loa.config.yaml` + `grimoires/loa/lore/`

---

## Sprint Overview

This cycle implements all actionable suggestions from the Bridgebuilder's review of PR #429, organized from lowest-risk polish to highest-value architectural additions.

| Sprint | Label | Focus | Dependency |
|--------|-------|-------|------------|
| 1 | Code Quality Polish | FR-1: 6 LOW findings from bridge convergence | None |
| 2 | Deliberative Council | FR-2: Prior findings integration into Red Team gate | Sprint 1 (red-team script changes) |
| 3 | Pipeline Self-Review | FR-3: Auto-review when pipeline files change | Sprint 2 (red-team scripting patterns) |
| 4 | Governance Lore + Compliance Generalization | FR-4: Lore entry + parameterized gate | Sprint 1 (keyword extraction dependency) |

---

## Sprint 1: Code Quality Polish

**Goal**: Address all 6 carried LOW findings from PR #429 bridge iterations. Surgical, isolated fixes.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T1.1 | Use `jq -n --arg` for JSON-safe encoding in flatline-orchestrator.sh | The `--argjson tertiary_model` pattern uses `jq -n --arg m "$var" '$m'` instead of `printf '"%s"'`. Model names with quotes/backslashes would be safely encoded (verified by manual test with edge-case input). |
| T1.2 | Remove redundant `rm -f` calls in red-team-code-vs-design.sh | Lines 313 and 316 (`rm -f "$prompt_file"`) removed. The `trap EXIT` on line 262 is the sole cleanup mechanism. Script still cleans up correctly on all exit paths. |
| T1.3 | Capture stderr on model adapter failure in red-team-code-vs-design.sh | Create stderr temp file, redirect model adapter stderr to it, update trap to clean both files. On failure, error message includes last 5 lines of stderr. On success, stderr file silently cleaned by trap. |
| T1.4 | Improve fence stripping robustness in red-team-code-vs-design.sh | Replace line-oriented sed with a `strip_code_fences()` function using awk range pattern as primary and sed as fallback. Handles both inline and multi-line fence formats. |
| T1.5 | Fix version tag in simstim SKILL.md | Replace `(v1.45.0)` with `(cycle-045)` on the dynamic phase count computation line. |
| T1.6 | Name the get_model_tertiary() seam in flatline-orchestrator.sh | Add 3-line comment above `get_model_tertiary()` naming it as a provisional resolution that the Hounfour router (loa-finn #31) will replace. The function signature is the durable contract. |

---

## Sprint 2: Deliberative Council — Prior Findings Integration

**Goal**: Make the Red Team code-vs-design gate context-aware by feeding it findings from earlier review stages. This transforms a sequential pipeline into a deliberative council.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T2.1 | Add `--prior-findings <path>` flag to red-team-code-vs-design.sh | New flag parsed in argument loop. Multiple `--prior-findings` invocations accepted (accumulated into array). Flag is optional — behavior unchanged without it. |
| T2.2 | Implement `extract_prior_findings()` function | Function reads a feedback file, extracts sections under `## Findings`, `## Issues`, `## Changes Required`, or `## Security`. Respects character budget. Returns empty string for missing/empty files. |
| T2.3 | Rebalance token budget for 3-way split | When `--prior-findings` is provided, budget splits to 1/3 SDD sections, 1/3 code diff, 1/3 prior findings (floor 4000 chars each, ceiling 100000). Without the flag, existing 50/50 split is unchanged. |
| T2.4 | Integrate prior findings into model prompt | Prior findings inserted between SDD sections and code diff in the prompt file, with `=== PRIOR REVIEW FINDINGS ===` header and instructional context telling the model to use these to focus its analysis. |
| T2.5 | Wire `--prior-findings` in run-mode SKILL.md | Step 7 (RED_TEAM_CODE gate) updated to pass `--prior-findings grimoires/loa/a2a/sprint-{N}/engineer-feedback.md` and `--prior-findings grimoires/loa/a2a/sprint-{N}/auditor-sprint-feedback.md`. Paths only passed when files exist. |
| T2.6 | Update SDD section 2.2 documentation | Document the deliberative council pattern, token budget rebalancing, and the rationale (Google ISSTA 2023 parallel — ML models that see static analysis findings produce better semantic analysis). |

---

## Sprint 3: Pipeline Self-Review

**Goal**: Enable the review pipeline to review changes to its own code against its own specifications. Pipeline bugs have multiplicative impact — this adds a perceptual modality for self-examination.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T3.1 | Create `detect_pipeline_changes()` function | Function in bridge-orchestrator.sh uses `git diff --name-only` to detect changes in `.claude/scripts/`, `.claude/skills/`, `.claude/data/`, `.claude/protocols/`. Returns file list or empty. |
| T3.2 | Create pipeline SDD mapping file | New file `.claude/data/pipeline-sdd-map.json` mapping glob patterns to their governing SKILL.md/SDD. At minimum: flatline-*.sh, red-team-*.sh, bridge-*.sh, simstim-*.sh. |
| T3.3 | Implement `resolve_pipeline_sdd()` function | Given a list of changed pipeline files, resolve each to its governing SDD via the mapping file. Uses jq to match globs. Returns unique list of SDDs to check against. |
| T3.4 | Implement `run_pipeline_self_review()` function | Orchestrates: filter diff to pipeline files only, resolve SDDs, invoke red-team-code-vs-design.sh for each SDD, collect findings. Output as structured JSON matching existing findings schema. |
| T3.5 | Wire self-review into bridge-orchestrator.sh | New optional phase gated by `run_bridge.pipeline_self_review.enabled` (default: false). Runs before the standard Bridgebuilder review. Findings posted as separate PR comment section with `[Pipeline Self-Review]` prefix. |
| T3.6 | Add config key and documentation | Add `run_bridge.pipeline_self_review.enabled: false` to .loa.config.yaml. Document in run-bridge SKILL.md and reference docs. |

---

## Sprint 4: Governance Lore + Compliance Generalization

**Goal**: Codify the Governance Isomorphism pattern as lore and parameterize the compliance gate for extensibility.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T4.1 | Create Governance Isomorphism lore entry | New entry in `grimoires/loa/lore/patterns.yaml` with id, term, short, context, source, and tags fields. Discoverable via `memory-query.sh` and loadable by bridge reviews. |
| T4.2 | Extract security keywords to config | New `.loa.config.yaml` section: `red_team.compliance_gates.security.keywords` containing the current hardcoded keyword list. Script reads from config, falling back to hardcoded defaults. |
| T4.3 | Parameterize `extract_security_sections()` | Rename to `extract_sections_by_keywords()`. Accept keywords as parameter (pipe-separated regex). Wrapper function `extract_security_sections()` calls it with security keywords for backward compatibility. |
| T4.4 | Add compliance gate profile schema in config | Document the schema for named compliance gate profiles (name, keywords, prompt_template). Create the `security` profile as the first instance. Other profiles (accessibility, performance) documented as future examples. |
| T4.5 | Document cross-repo SDD index schema | Create `grimoires/loa/lore/cross-repo-compliance-design.md` documenting the design for cross-repository compliance checking. This is a design document, not implementation — seeds future cycle work. |
| T4.6 | Update lore index with new patterns | If `grimoires/loa/lore/index.yaml` exists, update it. If not, create the index. Ensure the Governance Isomorphism entry is discoverable by bridge lore loading. |
