# Sprint Plan: Compassionate Excellence — Bridgebuilder Deep Review Integration

> **Cycle**: 047
> **Created**: 2026-02-28
> **PRD**: `grimoires/loa/prd.md`
> **SDD**: `grimoires/loa/sdd.md`
> **Target**: `.claude/` System Zone (scripts, skills, data, lib) + `.loa.config.yaml` + `grimoires/loa/lore/`
> **Source Feedback**: PR #433 — Bridge iter 1 (F-001–F-013), Deep Review Parts 1-5 (R-1–R-6, SPEC-1–SPEC-5), User observations

---

## Sprint Overview

This cycle implements ALL feedback from PR #433's bridge review and deep Bridgebuilder review, organized from verification/hardening through architectural promotion to library extraction and forward-looking design.

| Sprint | Label | Focus | Dependency |
|--------|-------|-------|------------|
| 1 | Verification + Defensive Hardening | FR-1: Gemini trace, Red Team docs, F-004/F-007 fixes, observability | None |
| 2 | Constitutional Architecture | FR-2: SDD map promotion, reverse mapping, lore lifecycle, discoverability | None |
| 3 | Shared Library Extraction | FR-3: findings-lib.sh, compliance-lib.sh, gate separation, prompt_template | Sprint 1 (fence stripping function) |
| 4 | Adaptive Intelligence + Ecosystem Design | FR-4: adaptive budget, cost tracking, economic feedback, cross-repo protocol | Sprint 3 (library functions) |

---

## Sprint 1: Verification + Defensive Hardening

**Goal**: Verify that claimed capabilities (Gemini, Red Team) actually work end-to-end. Address accepted LOW findings from bridge review. Add deliberation observability so we can track how the review system makes decisions.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T1.1 | Investigate Gemini participation in Flatline Protocol | Trace from `.loa.config.yaml` `flatline_protocol.models.tertiary: gemini-2.5-pro` through `flatline-orchestrator.sh` `get_model_tertiary()` to `model-adapter.sh` API call. Verify `MODEL_PROVIDERS[gemini-2.5-pro]` exists and routes correctly. If wiring is broken, fix it. If working, add a verification log line that confirms Gemini was invoked. Document findings in NOTES.md. |
| T1.2 | Document Red Team integration in simstim workflow | Add "Red Team Integration" section to `.claude/skills/simstim-workflow/SKILL.md` explaining: (a) current status (`red_team.simstim.auto_trigger: false`), (b) what happens when enabled (fires after /audit-sprint, before bridge review), (c) how to enable (`red_team.simstim.auto_trigger: true` + `red_team.bridge.enabled: true`), (d) what it reviews (code diff against SDD with prior review/audit findings). Update `.loa.config.yaml.example` with documented keys. |
| T1.3 | Fix F-004: glob `*` matching across `/` boundaries | In `pipeline-self-review.sh` `resolve_pipeline_sdd()`, change the jq glob-to-regex from `gsub("\\*"; ".*")` to a two-pass approach: first `gsub("\\*\\*"; ".*")` for recursive globs, then `gsub("\\*"; "[^/]*")` for single-segment globs. Add comment explaining the distinction. Verify with test paths: `.claude/scripts/flatline-orchestrator.sh` matches `flatline-*.sh` but NOT `.claude/scripts/subdir/flatline-foo.sh`. |
| T1.4 | Harden F-007: fence stripping with preamble text | Modify `strip_code_fences()` in `red-team-code-vs-design.sh` to handle the case where model output starts with prose before a code fence. If the first line is not a fence but the output contains a fence, scan for the first fence line and extract from there. Add test case: input = `"Here is the analysis:\n\`\`\`json\n{\"score\": 800}\n\`\`\`"` → output = `{"score": 800}`. |
| T1.5 | Add deliberation observability to Red Team invocations | In `red-team-code-vs-design.sh`, after prompt assembly and before model invocation, log a `deliberation-metadata.json` file to the sprint output directory containing: `input_channels` (count), `char_counts` (sdd, diff, prior_findings), `token_budget`, `budget_per_channel`, `prior_findings_paths` (list of files used). This file provides the "meeting minutes" for each deliberation — enabling institutional learning about what input mixes produce the best outcomes. |
| T1.6 | Add Red Team placement guidance to run-bridge SKILL.md | Add a "Red Team Gate Placement" subsection documenting: Red Team fires AFTER reviewer + auditor (step 7 in run-mode), as the final quality gate before sprint completion. In run-bridge, it fires within each sprint's implement→review→audit→red-team cycle. Clarify it does NOT replace the Bridgebuilder (which reviews across all sprints at the bridge level). |

---

## Sprint 2: Constitutional Architecture

**Goal**: Promote governance artifacts from data files to constitutional status. Add lifecycle semantics to lore entries so patterns can evolve through challenge and refinement. Enable reverse mapping so we can answer "what implementations does this SDD govern?"

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T2.1 | Promote pipeline-sdd-map.json to constitutional status | Add `constitutional: true` flag to the pipeline-sdd-map.json's self-referencing entry. In `pipeline-self-review.sh`, when a matched pattern has `constitutional: true`, emit a `CONSTITUTIONAL_CHANGE` marker in the findings JSON output (severity: HIGH, category: "constitutional"). The bridge orchestrator or PR comment should surface this marker prominently. This ensures changes to the governance map itself receive scrutiny proportional to their blast radius. |
| T2.2 | Implement reverse SDD mapping | Add `resolve_governed_implementations()` function to `pipeline-self-review.sh` that, given an SDD path, returns all glob patterns governed by that SDD. Implementation: `jq -r --arg sdd "$sdd_path" '.patterns[] \| select(.sdd == $sdd) \| .glob' "$map_file"`. Add a `--reverse <sdd-path>` flag to pipeline-self-review.sh for CLI access. This enables the future use case: "when run-bridge/SKILL.md changes, which scripts need re-review?" |
| T2.3 | Add lifecycle fields to lore entry schema | Extend `grimoires/loa/lore/patterns.yaml` entries with: `status` (enum: Active, Challenged, Deprecated, Superseded; default: Active), `challenges` (array of `{date, source, description}` objects; default: empty), `lineage` (ID of predecessor pattern or null), `superseded_by` (ID of successor pattern or null). Update existing Governance Isomorphism entry with `status: Active`, empty challenges, null lineage. This follows the RFC lifecycle model (Proposed → Active → Deprecated → Historic). |
| T2.4 | Update lore index with lifecycle metadata | Update `grimoires/loa/lore/index.yaml` to include `status` field for each entry. Add a note documenting the lifecycle states and transition rules: Active → Challenged (when counter-evidence found), Challenged → Active (when challenge resolved), Active → Deprecated (when superseded), Deprecated → Superseded (when replacement is Active). |
| T2.5 | Add lore discoverability for bridge reviews | In `bridge-orchestrator.sh` (or as a helper function), before the Bridgebuilder review signal, query lore entries for patterns relevant to the changed files. Relevance determined by tag matching: if changed files include `scripts/` → match tags `pipeline`, `review`; if changed files include `lore/` → match tags `governance`, `architecture`. Discovered lore is included in the bridge review context. If no lore entries exist or match, skip silently. |
| T2.6 | Create Deliberative Council lore entry | Add a new pattern entry to `grimoires/loa/lore/patterns.yaml` for the Deliberative Council pattern discovered in cycle-046 Sprint 2: `id: deliberative-council`, `term: Deliberative Council`, `short: "Later review stages condition on earlier findings, transforming sequential evaluation into structured deliberation"`, `context: (reference Condorcet jury theorem, Google ISSTA Tricorder cascading, jazz ensemble metaphor)`, `source: "bridge-deep-review-part1 / PR #433"`, `tags: [architecture, review, deliberation, pattern]`, `status: Active`. |

---

## Sprint 3: Shared Library Extraction

**Goal**: Factor shared functions out of monolithic scripts into importable libraries. Separate compliance gate extraction from evaluation to enable future gate profiles. These libraries become the substrate for cross-repo compliance and capability-driven orchestration.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T3.1 | Create `.claude/scripts/lib/findings-lib.sh` | Extract `extract_prior_findings()` from `red-team-code-vs-design.sh` into a new shared library. Include `strip_code_fences()` (the hardened version from T1.4). Library must be sourceable (`source .claude/scripts/lib/findings-lib.sh`) with no side effects on source. Functions maintain identical signatures and behavior. Add header comment explaining purpose and consumers. |
| T3.2 | Create `.claude/scripts/lib/compliance-lib.sh` | Extract `extract_sections_by_keywords()` and `load_compliance_keywords()` (the config-reading wrapper) from `red-team-code-vs-design.sh` into a shared library. Add `load_compliance_profile()` function that returns both keywords and prompt_template for a named profile. Add `load_prompt_template()` function that returns the prompt template name for a compliance gate profile. Library is sourceable with no side effects. |
| T3.3 | Update red-team-code-vs-design.sh to source shared libraries | Replace inline function definitions with `source` calls to `findings-lib.sh` and `compliance-lib.sh`. Add backward-compatible wrapper functions that call through to the library functions (e.g., `extract_security_sections()` calls `extract_sections_by_keywords()` with security profile). Script behavior must be identical before and after — zero functional change. Verify by running the existing test cases. |
| T3.4 | Update pipeline-self-review.sh to source shared libraries | Source `findings-lib.sh` for any findings extraction logic. Source `compliance-lib.sh` for section extraction if used. This reduces code duplication between the two scripts and ensures bug fixes in shared functions propagate to both consumers. |
| T3.5 | Separate extraction from evaluation in compliance gate design | In `compliance-lib.sh`, document the separation: extraction (`extract_sections_by_keywords()`) returns raw SDD sections as text; evaluation is the model prompt that interprets those sections against code. Add `get_evaluation_context()` function that returns a structured prompt preamble based on the gate profile's `prompt_template` field. For now, only `security-comparison` template exists (the current default behavior). Document how to add new templates. |
| T3.6 | Add `prompt_template` field to compliance gate config | Update `.loa.config.yaml` to include `prompt_template: "security-comparison"` under `red_team.compliance_gates.security`. Update `.loa.config.yaml.example` with the new field and commented-out examples for future profiles (api_contract, economic_invariant). Document in `compliance-lib.sh` header that template names map to prompt construction patterns. |

---

## Sprint 4: Adaptive Intelligence + Ecosystem Design

**Goal**: Enable the review system to learn from and optimize its own operation. Design (but do not fully implement) the adaptive token budget, cost tracking, and cross-repo governance protocol. These are the seeds for SPEC-2 (reputation-weighted deliberation) and SPEC-5 (economic governance of review depth).

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T4.1 | Implement adaptive token budget (config-gated) | In `red-team-code-vs-design.sh`, add `compute_adaptive_budget()` function that weights channel budgets by input size (larger inputs get proportionally more budget, with floor of 4000 chars per channel). Gated by `red_team.adaptive_budget.enabled: false` (default). When disabled, existing equal-split behavior is unchanged. When enabled, budget allocation logged in deliberation-metadata.json with `mode: "adaptive"` vs `mode: "equal"`. |
| T4.2 | Add cost tracking metadata to bridge state | In `bridge-orchestrator.sh`, after each Red Team invocation, estimate inference cost from char counts (1 token ~ 4 chars) and `COST_INPUT`/`COST_OUTPUT` arrays in model-adapter.sh. Log to `.run/bridge-state.json` under `metrics.cost_estimates[]`: `{iteration, red_team_invocations, estimated_input_tokens, estimated_output_tokens, cost_estimate_usd}`. This provides the data substrate for SPEC-5 (economic governance of review depth). |
| T4.3 | Create economic feedback signal design | Add to `grimoires/loa/lore/cross-repo-compliance-design.md` a new section: "Economic Feedback for Review Depth". Document the design: after each bridge iteration, compute marginal cost (API spend this iteration) and marginal value (findings addressed / cost). When marginal value drops below threshold (configurable), emit `DIMINISHING_RETURNS` signal. This signal could trigger early flatline or prompt human decision. Design only — not wired into orchestrator. |
| T4.4 | Document cross-repo governance protocol | Extend `grimoires/loa/lore/cross-repo-compliance-design.md` with "Specification Change Notification" section. Document: (a) how SDD changes in repo A trigger review in dependent repo B, (b) event format (`{sdd_path, diff_summary, source_repo, source_pr}`), (c) transport options (GitHub webhooks, A2A protocol, shared event store), (d) prerequisite: shared SDD index. Reference loa-finn #31 ModelPort for the capability discovery layer. |
| T4.5 | Document capability-driven orchestration vision | Create `grimoires/loa/lore/capability-orchestration-design.md` documenting the evolution from hardcoded bridge signals to capability-driven discovery. Key concepts: bridge orchestrator queries available review capabilities (security, architecture, contract, economic), composes deliberation chain dynamically, allocates token budgets per capability. Reference: Kubernetes Admission Controllers (composable validation gates), Chromium OWNERS (specification-based review routing). This seeds SPEC-1 (capability markets). |
| T4.6 | Update lore entries with ecosystem cross-references | Add Deliberative Council connections to existing Governance Isomorphism lore entry context field — reference the Condorcet jury parallel, the Google Tricorder cascading analogy, and the web4 "findings must be scarce but perspectives can be infinite" insight from Part 3. Ensure both entries cross-reference each other. Update index.yaml with the new Deliberative Council entry. |
