# Sprint Plan: Cycle-073 — Config Documentation + Onboarding Wizard

**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`
**Issue**: #510
**Date**: 2026-04-15
**Cycle**: 073

---

## Flatline AUTO-INTEGRATED Findings

_PRD and SDD are in Draft status. No Flatline review has been run yet. This table will be populated after the first bridge review._

| Finding | Severity | Sprint Impact |
|---------|----------|--------------|
| — | — | — |

---

## Scope Summary

This cycle is **documentation-only** — no pipeline behavior changes, no new scripts. All five deliverables are content files or SKILL.md instruction files. Automated tests are not applicable; acceptance criteria are validated via grep-based structural checks and manual wizard walkthrough.

| Deliverable | File(s) | Action |
|-------------|---------|--------|
| D1 | `docs/CONFIG_REFERENCE.md` | New |
| D2 | `.claude/skills/loa-setup/SKILL.md`, `.claude/skills/loa-setup/index.yaml` | New |
| D3 | `README.md` | Additive (~15 lines) |
| D4 | `.claude/skills/loa/SKILL.md` | Additive (~20 lines) |
| D5 | 5 × SKILL.md files | Additive `## Cost` section each |

---

## Sprint 1: CONFIG_REFERENCE.md (Deliverable 1)

**Goal**: A comprehensive, user-facing configuration reference that makes every configuration decision legible before the user commits to it — with full cost transparency, decision guidance, and cross-links.

### Task 1.1: Document Scaffold + Cost Matrix + Decision Guide

**Files**: `docs/CONFIG_REFERENCE.md` (new — create `docs/` directory first)
**Description**: Create the document with its opening sections. The cost matrix and decision guide must appear before all section entries so users encounter them first.

Write in order:
1. Document title + pricing verified timestamp (NFR-2 format: `_Pricing verified: 2026-04-15. Prices change — recheck before large commitments._`)
2. `## Overview` — one-paragraph explanation of what this document is and how to use it
3. `## Cost Matrix` — full 10-row table as specified in FR-1.3 / SDD §3.4, with the "moderate workflow" assumption footnoted
4. `## Decision Guide` — Mermaid `flowchart TD` routing users from usage tier + budget + workflow pace to a recommended feature set (SDD §2.2). Include a fallback decision table beneath the Mermaid block in case rendering fails
5. `## Pricing Footnotes` section placeholder (to be completed after section entries)

**Acceptance Criteria**:
- [ ] `docs/CONFIG_REFERENCE.md` file exists and parses as valid Markdown
- [ ] `## Cost Matrix` table present with all 10 feature rows (Flatline, Simstim, Spiral standard, Spiral full, Run Bridge, Post-PR Validation, Red Team standard, Red Team deep, Continuous Learning, Prompt Enhancement)
- [ ] Cost Matrix includes columns: Feature, Per-Invocation Low, Per-Invocation High, Models Used, Monthly at Moderate Workflow
- [ ] Moderate workflow assumption (2 planning cycles/week, 4 PRs/week) is footnoted on the cost matrix
- [ ] `## Decision Guide` section present with Mermaid flowchart
- [ ] Mermaid flowchart covers all three decision axes: usage tier, budget tier, workflow pace
- [ ] Fallback decision table present beneath Mermaid block
- [ ] Pricing verified timestamp present in correct NFR-2 format
- [ ] `> [!NOTE]` or equivalent admonition on the cost matrix noting prices are approximate and reference Anthropic/OpenAI/Google pricing pages

**Verification commands**:
```bash
test -f docs/CONFIG_REFERENCE.md
grep -c '^## Cost Matrix' docs/CONFIG_REFERENCE.md  # expect >= 1
grep -c 'Pricing verified' docs/CONFIG_REFERENCE.md  # expect >= 1
grep -c 'flowchart TD' docs/CONFIG_REFERENCE.md      # expect >= 1
```

---

### Task 1.2: Primary Sections (simstim → flatline_protocol)

**Files**: `docs/CONFIG_REFERENCE.md` (extend)
**Depends on**: T1.1
**Description**: Add all 11 primary section entries in the canonical order from FR-1.2 / SDD §2.1. Each section follows the per-section entry template from SDD §2.1 exactly.

Sections in order:
1. `### simstim`
2. `### run_mode`
3. `### hounfour`
4. `### vision_registry`
5. `### spiral`
6. `### run_bridge`
7. `### post_pr_validation`
8. `### prompt_isolation`
9. `### continuous_learning` (include `compound_learning` and `flatline_integration` as sub-sections)
10. `### red_team`
11. `### flatline_protocol`

For each section, provide all fields from the entry template (FR-1.1):
- `> **ELI5**:` paragraph (≤3 sentences, no jargon)
- `**Version introduced**` and `**Recommendation**` and `**Default**` lines
- `> **Cost Warning**` callout for any section with cost ≥$5/invocation (FR-1.4 format)
- `#### Sub-keys` table (Key | Type | Default | Description)
- `#### Cost` block (per invocation range, monthly at moderate, models used)
- `#### Risks if enabled` bullet list
- `#### Risks if disabled` bullet list
- `#### Setup requirements` bullet list
- `#### See also` links to protocol file, reference doc, and SKILL.md where they exist

Cost Warning required for: simstim, spiral, run_bridge, post_pr_validation, red_team, flatline_protocol, continuous_learning (if Flatline integration).

**Acceptance Criteria**:
- [ ] All 11 primary sections present under `## Primary Sections` heading
- [ ] Sections appear in the exact order specified in FR-1.2
- [ ] Every section contains all 9 required fields (ELI5, version, recommendation, default, sub-keys, cost, risks-enabled, risks-disabled, setup requirements)
- [ ] `> **Cost Warning**` callout present for: simstim, spiral, run_bridge, post_pr_validation, red_team, flatline_protocol, and continuous_learning Flatline integration
- [ ] All `#### See also` links use relative paths (not absolute URLs) and point to files that exist in the repo
- [ ] `hounfour` section documents `metering.enabled` and `daily_micro_usd` budget cap sub-keys (referenced by Cost Warning callouts in other sections)
- [ ] `spiral` section documents both `standard` and `full` pipeline profiles with their cost differences

**Verification commands**:
```bash
grep -c '^### simstim\|^### run_mode\|^### hounfour\|^### vision_registry\|^### spiral\|^### run_bridge\|^### post_pr_validation\|^### prompt_isolation\|^### continuous_learning\|^### red_team\|^### flatline_protocol' docs/CONFIG_REFERENCE.md  # expect 11
grep -c 'Cost Warning' docs/CONFIG_REFERENCE.md  # expect >= 7
```

---

### Task 1.3: Secondary Sections + Safety Hooks Summary

**Files**: `docs/CONFIG_REFERENCE.md` (extend)
**Depends on**: T1.2
**Description**: Add the Safety Hooks reference section (not a YAML key — sourced from CLAUDE.loa.md hook table) and all 15 secondary sections under `## Secondary Sections`.

Safety Hooks section (between primary and secondary sections):
- `### Safety Hooks (reference — not a YAML key)` heading
- Brief ELI5 and table of all 7 hooks from CLAUDE.loa.md with Event, Purpose, and Deny Rules note
- No Cost Warning needed (hooks are local, no API calls)

Secondary sections in order (matching FR-1.2 list):
1. `### paths`
2. `### ride`
3. `### plan_and_analyze`
4. `### interview`
5. `### autonomous_agent`
6. `### workspace_cleanup`
7. `### goal_traceability`
8. `### effort`
9. `### context_editing`
10. `### memory_schema`
11. `### skills`
12. `### oracle`
13. `### visual_communication`
14. `### butterfreezone`
15. `### bridgebuilder_design_review`

Secondary sections may use a lighter template than primary sections: ELI5, Default + rationale, Sub-keys table, and See also. Full risk/cost fields only required if the section has ≥$5/invocation cost (check `.loa.config.yaml.example` for oracle — it may invoke external APIs). Recommendation and Version introduced are still required for all secondary sections.

Complete `## Pricing Footnotes` at the end of the document with: Anthropic pricing assumptions (Opus $15/$75 MTok, Sonnet $3/$15 MTok), OpenAI (GPT-5.3-codex ~$10/$30 MTok), Google (Gemini 2.5 Pro ~$1.25/$10 MTok), and the stale-warning note (NFR-2).

**Acceptance Criteria**:
- [ ] `### Safety Hooks` section present between primary and secondary sections with 7-row hook table
- [ ] All 15 secondary sections present under `## Secondary Sections` heading
- [ ] Every secondary section has: ELI5, Default + rationale, Sub-keys table, Recommendation, Version introduced
- [ ] `## Pricing Footnotes` section present at document end with all four provider pricing rows
- [ ] PRD AC NFR-4: every top-level key visible in `.loa.config.yaml.example` has a corresponding entry in the document

**Verification commands**:
```bash
grep -c '^### ' docs/CONFIG_REFERENCE.md  # expect >= 27 (11 primary + 1 hooks + 15 secondary)
grep -c '^## Pricing Footnotes' docs/CONFIG_REFERENCE.md  # expect 1
```

---

### Task 1.4: Cross-Link Audit + RTFM Scope Extension

**Files**: `docs/CONFIG_REFERENCE.md` (review/patch), `.claude/skills/rtfm-testing/SKILL.md` (additive)
**Depends on**: T1.3
**Description**: Two parts:

**Part A — Cross-link audit**: Walk every `#### See also` block in CONFIG_REFERENCE.md. Verify each linked path exists. Remove or correct any broken links. Ensure all 11 primary sections link to their corresponding reference doc in `.claude/loa/reference/` where one exists, and to their SKILL.md where the feature is skill-invoked.

**Part B — RTFM scope extension**: Add a note to `.claude/skills/rtfm-testing/SKILL.md` (additive, ≤50 words) instructing that when `/rtfm` is invoked, the `docs/` directory is in scope alongside any other paths already checked. Per SDD OQ-5 resolution, this is a SKILL.md instruction change only — no script modification.

**Acceptance Criteria**:
- [ ] Every `#### See also` path in CONFIG_REFERENCE.md resolves to an existing file in the repo (checked via grep + test -f)
- [ ] `flatline_protocol` section links to `.claude/loa/reference/flatline-reference.md`
- [ ] `spiral` section links to the harness and orchestrator reference files
- [ ] `run_bridge` section links to `.claude/loa/reference/run-bridge-reference.md`
- [ ] `hounfour` section links to the metering ledger reference
- [ ] `.claude/skills/rtfm-testing/SKILL.md` updated to include `docs/` in scope
- [ ] No existing content removed from `rtfm-testing/SKILL.md`

**Test**:
```bash
# Manual: spot-check 5 random See also links resolve
grep -oE '\`[^`]+\`' docs/CONFIG_REFERENCE.md | grep '^\`\.' | head -20
# Then: test -f <each path>
```

---

## Sprint 2: `/loa setup` Wizard Skill (Deliverable 2)

**Goal**: A Claude-driven onboarding wizard that takes a new user from cloned repo to working `.loa.config.yaml` in ≤10 conversational turns, with full cost transparency and idempotent handling of existing configs.

### Task 2.1: Skill Registration + Phase 1 + Phase 2 Instructions

**Files**: `.claude/skills/loa-setup/SKILL.md` (new), `.claude/skills/loa-setup/index.yaml` (new)
**Description**: Create the wizard skill with its full Phase 1 and Phase 2 instructions.

`index.yaml` must include: skill name (`loa-setup`), description, trigger (invokable via `/loa setup`), and any metadata fields required by the skill index schema.

`SKILL.md` structure:
- `## Overview` — what the wizard does, when to use it (1 paragraph)
- `## Phase 1: Environment Detection` — instructions to Claude to:
  - Run `loa-setup-check.sh --json` via Bash tool and parse JSONL output
  - Check boolean presence of `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY` — only via the check script output, never by echoing env vars directly (NFR-6 / SDD §4.1)
  - Record: `beads_installed`, `ck_installed`, `yq_installed`, `config_exists`, `required_deps_ok`
  - If `config_exists: true`, set `idempotency_mode: true` and note this for Phase 3
  - Present a brief environment summary to the user before proceeding
- `## Phase 2: Profile Questionnaire` — instructions to present questions one at a time (FR-2.3):
  - Q1: Usage tier (solo / small team <10 / enterprise) — gate: team features
  - Q2: Monthly budget ($0–$10 / $10–$50 / $50–$200 / $200+) — gate: expensive feature eligibility
  - Q3: Workflow pace (HITL / semi-auto / fully auto) — maps to run_mode + simstim + spiral flags
  - Q4: API key confirmation — conditional on Q2 ≥ $10/month AND at least one key detected in Phase 1
  - Q5: Quality posture (must-have / nice-to-have / not needed) — maps to flatline_protocol + red_team
  - Q6: Off-hours scheduling — conditional on Q2 ≥ $50/month
  - Enumerated choices only — if user provides unexpected answer, re-present valid options (SDD §4.3)
  - Maximum 7 turns to reach Phase 3 (6 questions + 1 confirmation gate)

**Acceptance Criteria**:
- [ ] `.claude/skills/loa-setup/index.yaml` exists and is valid YAML
- [ ] `.claude/skills/loa-setup/SKILL.md` exists
- [ ] SKILL.md contains `## Phase 1: Environment Detection` section
- [ ] SKILL.md explicitly instructs Claude NOT to read, echo, or log API key values — only consume boolean output from `loa-setup-check.sh`
- [ ] SKILL.md contains `## Phase 2: Profile Questionnaire` section with all 6 questions documented
- [ ] Q4 conditional (budget ≥ $10/month AND key detected) is explicitly stated
- [ ] Q6 conditional (budget ≥ $50/month) is explicitly stated
- [ ] Enumerated-choices constraint documented (no free-form text answers drive feature matrix)
- [ ] ≤7 turns documented as the maximum path to Phase 3 (satisfies NFR-3 ≤10 total turns)

---

### Task 2.2: Phase 3 — Config Generation + Idempotency Instructions

**Files**: `.claude/skills/loa-setup/SKILL.md` (extend)
**Depends on**: T2.1
**Description**: Add Phase 3 instructions to the SKILL.md covering both the fresh-config and idempotency branches.

Fresh config branch instructions:
- Map Q1–Q6 answers through the Profile → Feature matrix (SDD §3.2) to derive `feature_set`
- For each enabled feature, load the canonical section template (SDD §3.3 examples)
- Assemble sections in YAML key order matching `.loa.config.yaml.example`
- Display pre-write summary: `[ENABLED]`/`[DISABLED]` line per feature, per-feature cost range for ≥$5 features, total estimated monthly cost range
- Ask confirmation: "Write this configuration to `.loa.config.yaml`? (yes / no / show full YAML)"
- Validate generated YAML via `yq '.' <(echo "$yaml")` before writing. If yq missing, fall back to jq structural check; if both missing, warn and ask confirmation before writing
- Write only on explicit "yes"

Idempotency branch instructions (when `config_exists: true`):
- Read existing `.loa.config.yaml` via Read tool
- For each section the wizard would touch, parse current value via `yq`
- Present per-section diff: "Section `flatline_protocol`: current `enabled: false` → proposed `enabled: true`"
- Ask per-section: "Update? (yes / no / skip all)"
- Preserve verbatim any section the user declines
- Validate merged output via `yq` before writing

Config templates (inline in SKILL.md instructions, not as external files):
Include the minimal template blocks from SDD §3.3 for: `flatline_protocol` (nice-to-have/medium), `spiral` (full-auto/unlimited), `run_mode` (HITL), `simstim` (semi-auto), `run_bridge` (depth 1), `hounfour` (provider routing), `red_team` (standard).

**Acceptance Criteria**:
- [ ] SKILL.md contains `## Phase 3: Config Generation` section
- [ ] Fresh-config path documented: answer mapping → feature set → template assembly → pre-write summary → confirmation → YAML validation → write
- [ ] Idempotency path documented: read existing → per-section diff → per-section confirm → merge → validate → write
- [ ] Pre-write summary format documented: `[ENABLED]`/`[DISABLED]` lines with cost ranges for ≥$5 features
- [ ] Confirmation gate explicitly required before any file write
- [ ] YAML validation step documented with yq primary + jq fallback + user-confirm-if-both-missing path
- [ ] Minimal config templates for all 7 feature keys documented inline in SKILL.md
- [ ] Generated config uses `{env:PROVIDER_API_KEY}` placeholders for auth, never literal key values (NFR-6)
- [ ] `spiral.budget_cents` and `hounfour.metering.daily_micro_usd` template values populated with sensible safe defaults (not zero)

**Manual test cases** (to be run by reviewer):
```
TC-1: Fresh repo, Q2=$0-10, Q3=HITL → config has run_mode only, no external providers
TC-2: Fresh repo, Q2=$50-200, Q3=semi-auto, Q5=must-have → config has simstim + flatline_protocol + run_bridge
TC-3: Existing config, user declines all updates → file unchanged after wizard
TC-4: Existing config, user accepts flatline update only → only flatline_protocol section updated
TC-5: yq not installed → wizard shows warning, requires explicit confirmation before write
TC-6: openai key detected → hounfour configured with openai provider when a multi-model feature enabled
```

---

### Task 2.3: Phase 4 — Post-Config Explanation Instructions

**Files**: `.claude/skills/loa-setup/SKILL.md` (extend)
**Depends on**: T2.2
**Description**: Add Phase 4 instructions and error handling section to the SKILL.md.

Phase 4 instructions — after writing config, Claude must print:
- Summary table: feature | enabled/disabled
- One-sentence description of each enabled feature
- Recommended next command based on workflow pace:
  - HITL → `/loa` for status, then `/run sprint-plan` when ready
  - Semi-auto → `/simstim` for HITL-accelerated development
  - Fully auto → `/run sprint-plan` for autonomous cycle
- "For full configuration reference, see `docs/CONFIG_REFERENCE.md`"

Error handling section — Claude instructions for each error case from SDD §6:
- `loa-setup-check.sh` not found → report error, skip Phase 1 output, ask API key questions manually
- No API keys detected → disable multi-model feature recommendations, warn and continue
- YAML parse error on generated config → report error line, do not write, offer to re-generate
- User declines all questions → do not write config, suggest reading CONFIG_REFERENCE.md directly

**Acceptance Criteria**:
- [ ] SKILL.md contains `## Phase 4: Post-Config Explanation` section
- [ ] Phase 4 instructions include: summary table, one-sentence per enabled feature, next-step command (workflow-dependent), link to docs/CONFIG_REFERENCE.md
- [ ] SKILL.md contains `## Error Handling` section with all 4 error cases from SDD §6
- [ ] Each error case specifies: condition, Claude's response, recovery path
- [ ] SKILL.md total length is coherent — instructions are prose directives to Claude, not code
- [ ] No API key material appears in any example output shown in SKILL.md

**Final SKILL.md structural check**:
- [ ] Sections in order: Overview, Phase 1, Phase 2, Phase 3, Phase 4, Error Handling
- [ ] Total wizard turns to "config written" ≤ 10 for the default-everything path
- [ ] NFR-5 explicitly stated: generate minimal config — only enable what user said yes to

---

## Sprint 3: README + `/loa` Ambient Cost Awareness (Deliverables 3 + 4)

**Goal**: Surface cost information at the two highest-visibility entry points — the README quick-start and the `/loa` status command.

### Task 3.1: README "Before You Spend" Warning Callout

**Files**: `README.md` (additive, ~15 lines)
**Description**: Read the existing `## Quick Start` section. Insert a `> [!WARNING]` admonition block immediately before the first command in Quick Start that triggers any external API call.

The callout must (FR-3.1, FR-3.2, FR-3.3):
- Use `> [!WARNING]` GitHub admonition syntax so it renders visually
- Name the three most expensive features: Flatline Protocol, Simstim, Spiral
- Include approximate per-invocation costs for each (from the Cost Matrix)
- Link to `docs/CONFIG_REFERENCE.md#cost-matrix` for the full table
- Recommend running `/loa setup` before enabling autonomous modes
- Not gate or block access to the quick-start commands below it

**Acceptance Criteria**:
- [ ] `> [!WARNING]` admonition present in README Quick Start section
- [ ] Warning names Flatline Protocol, Simstim, and Spiral with approximate costs
- [ ] Warning links to `docs/CONFIG_REFERENCE.md`
- [ ] Warning recommends `/loa setup`
- [ ] Quick-start commands below the warning are unchanged and accessible
- [ ] No other README content modified
- [ ] Admonition renders correctly in GitHub Markdown preview (manual check)

**Verification command**:
```bash
grep -c '\[!WARNING\]' README.md  # expect >= 1
```

---

### Task 3.2: `/loa` Ambient Cost-Awareness Section

**Files**: `.claude/skills/loa/SKILL.md` (additive, ~20 lines)
**Description**: Read the existing `.claude/skills/loa/SKILL.md`. Add a `## Cost Awareness` section with instructions to Claude on how to surface cost information during `/loa` invocations.

Per SDD §2.4 and FR-4.1 through FR-4.4, the instructions must direct Claude to:
1. Read `.loa.config.yaml` via Read tool (if it exists — skip silently if missing)
2. Check each of the five expensive feature flags: `flatline_protocol.enabled`, `spiral.enabled`, `run_bridge.enabled`, `post_pr_validation.phases.bridgebuilder_review.enabled`, `red_team.enabled`
3. For each flag that is `true`, output one cost-awareness line with feature name and estimated per-cycle cost (cost values from the Cost Matrix in CONFIG_REFERENCE.md)
4. If `hounfour.metering.enabled: true` and `hounfour.metering.ledger_path` is set, read today's entries from the ledger and show cumulative spend vs. daily budget cap; skip this line gracefully if ledger missing or today has no entries
5. Output nothing for cost awareness when all expensive features are disabled (FR-4.4 — no "no active features" noise)

Output format when features are active (FR-4.2):
```
Active expensive features: Flatline (~$25/planning cycle), Spiral (~$12/cycle) | Budget cap: $500/day | Run /loa setup to adjust
```

**Acceptance Criteria**:
- [ ] `.claude/skills/loa/SKILL.md` has new `## Cost Awareness` section
- [ ] Section instructs Claude to read `.loa.config.yaml` (not hardcode feature state)
- [ ] All 5 expensive feature flags documented: flatline_protocol, spiral, run_bridge, post_pr_validation bridgebuilder, red_team
- [ ] Output format matches FR-4.2 specification
- [ ] Metering ledger read instruction present (with graceful-skip if missing)
- [ ] "Output nothing when all disabled" instruction explicitly stated
- [ ] No existing content in loa/SKILL.md removed or altered

**Manual test cases**:
```
TC-A: .loa.config.yaml with flatline_protocol.enabled: true → /loa output shows cost line
TC-B: .loa.config.yaml with all expensive features disabled → /loa output shows no cost line
TC-C: No .loa.config.yaml → /loa shows no cost line, no error
TC-D: metering.enabled: true, ledger has today's entry → /loa shows spend vs. budget
```

---

## Sprint 4: Skill-Level Cost Warnings (Deliverable 5)

**Goal**: Every skill that can spend ≥$5/invocation carries a scannable `## Cost` section so users encounter the information at point of use, not after the bill arrives.

### Task 4.1: `## Cost` Sections — All 5 SKILL.md Files

**Files**:
- `.claude/skills/simstim-workflow/SKILL.md` (additive)
- `.claude/skills/spiraling/SKILL.md` (additive)
- `.claude/skills/run-bridge/SKILL.md` (additive)
- `.claude/skills/red-teaming/SKILL.md` (additive)
- `.claude/skills/run-mode/SKILL.md` (additive)

**Description**: Read each SKILL.md. Identify the first substantive section (typically `## Overview` or equivalent). Insert a `## Cost` section immediately after it. If a SKILL.md already has a `## Cost` section, update it in place rather than adding a duplicate.

Each `## Cost` section must follow the template from SDD §2.5 and FR-5.2:

```markdown
## Cost

**Estimated per invocation**: $X–$Y (see [Cost Matrix](../../../docs/CONFIG_REFERENCE.md#cost-matrix))
**External providers called**: [list of models and providers]
**To cap spend**: Set `hounfour.metering.budget.daily_micro_usd` in `.loa.config.yaml`. Budget enforcement is active when `hounfour.metering.enabled: true`.
**If cost is a concern**: Run `/loa setup` — the wizard will guide you to a budget-appropriate configuration.

_Pricing verified: 2026-04-15. Prices change — recheck before large commitments._
```

Per-skill cost values (from Cost Matrix, SDD §3.4):
- `simstim-workflow`: $25–$65/full cycle | Opus + GPT-5.3-codex + Gemini
- `spiraling`: $10–$15/cycle (standard) or $20–$35/cycle (full) | Sonnet (exec) + Opus (judge); full profile: all models
- `run-bridge`: $10–$20/depth-5 run | Opus + GPT-5.3-codex
- `red-teaming`: $5–$15/standard, $15–$30/deep | Opus + GPT-5.3-codex
- `run-mode`: note that run-mode itself is low-cost; the cost callout should explain that run_mode orchestrates sessions that may invoke expensive sub-skills; reference flatline and bridgebuilder costs in that context

**Acceptance Criteria**:
- [ ] `## Cost` section added to `simstim-workflow/SKILL.md`
- [ ] `## Cost` section added to `spiraling/SKILL.md`
- [ ] `## Cost` section added to `run-bridge/SKILL.md`
- [ ] `## Cost` section added to `red-teaming/SKILL.md`
- [ ] `## Cost` section added to `run-mode/SKILL.md`
- [ ] Each `## Cost` section is ≤150 words (NFR-7)
- [ ] Each section contains: cost range, external providers, how to cap spend via hounfour.metering, link to /loa setup
- [ ] Each section links to `docs/CONFIG_REFERENCE.md#cost-matrix`
- [ ] No existing instruction content in any SKILL.md removed or altered
- [ ] All 5 SKILL.md files remain parseable (valid YAML front-matter + Markdown)
- [ ] Pricing verified timestamp in correct NFR-2 format

**Verification commands**:
```bash
grep -l '^## Cost' \
  .claude/skills/simstim-workflow/SKILL.md \
  .claude/skills/spiraling/SKILL.md \
  .claude/skills/run-bridge/SKILL.md \
  .claude/skills/red-teaming/SKILL.md \
  .claude/skills/run-mode/SKILL.md | wc -l  # expect 5
```

---

## Full Acceptance Criteria Checklist

### D1 — CONFIG_REFERENCE.md

- [ ] `docs/CONFIG_REFERENCE.md` exists and parses as valid Markdown
- [ ] Cost Matrix table with all 10 required feature rows present before section entries
- [ ] Decision Guide flowchart/table present before section entries
- [ ] All 11 primary sections (simstim → flatline_protocol) with complete entries
- [ ] Safety Hooks reference section present
- [ ] All 15 secondary sections with required fields
- [ ] Zero top-level keys from `.loa.config.yaml.example` undocumented
- [ ] `> **Cost Warning**` callout present for all features with cost ≥$5/invocation
- [ ] Pricing verified timestamp in document footer
- [ ] All `#### See also` cross-links resolve to existing repo paths
- [ ] Document renders correctly in GitHub Markdown preview (no broken tables, no unrendered Mermaid)

### D2 — `/loa setup` Wizard

- [ ] `.claude/skills/loa-setup/SKILL.md` exists
- [ ] `.claude/skills/loa-setup/index.yaml` exists
- [ ] Phase 1 runs automatically on invocation, detects env without logging key values
- [ ] Phase 2 presents ≤6 questions, conditionals correctly gated
- [ ] Phase 3 displays cost summary before writing any file
- [ ] Phase 3 requires explicit confirmation before writing
- [ ] Idempotency branch: diff-and-confirm per section, no section overwritten without confirmation
- [ ] Phase 4 prints next-step guidance and CONFIG_REFERENCE.md link
- [ ] Generated config validated via yq before write
- [ ] Generated config enables no feature the user did not explicitly request (NFR-5)
- [ ] No API key content appears anywhere in wizard output or generated config (NFR-6)
- [ ] Manual TC-1 through TC-6 pass

### D3 — README Cost Warning

- [ ] `> [!WARNING]` admonition present in Quick Start section
- [ ] Warning names Flatline, Simstim, Spiral with approximate costs
- [ ] Warning links to `docs/CONFIG_REFERENCE.md`
- [ ] Warning does not block quick-start commands
- [ ] Admonition renders in GitHub README preview

### D4 — `/loa` Ambient Cost Awareness

- [ ] `## Cost Awareness` section added to `.claude/skills/loa/SKILL.md`
- [ ] All 5 expensive feature flags covered
- [ ] Cost-awareness line format matches FR-4.2
- [ ] Metering ledger read with graceful-skip on missing file/today's entries
- [ ] No output when all expensive features disabled
- [ ] Reads from `.loa.config.yaml` at runtime (not hardcoded)
- [ ] Manual TC-A through TC-D pass

### D5 — Skill-Level Cost Warnings

- [ ] `## Cost` section in all 5 SKILL.md files
- [ ] Each section ≤150 words (NFR-7)
- [ ] Correct cost range, providers, hounfour pointer, /loa setup link in each
- [ ] No existing SKILL.md content removed
- [ ] All 5 files parseable after modification

### Quality Gate

- [ ] No new secrets or key material introduced anywhere
- [ ] CI passes (lint, if applicable)
- [ ] `grep -c '\[!WARNING\]' README.md` ≥ 1
- [ ] `grep -c 'Cost Warning' docs/CONFIG_REFERENCE.md` ≥ 7
- [ ] `grep -l '^## Cost' .claude/skills/{simstim-workflow,spiraling,run-bridge,red-teaming,run-mode}/SKILL.md | wc -l` = 5

---

## Dependency Map

```
T1.1 (scaffold)
  └── T1.2 (primary sections)
        └── T1.3 (secondary sections + hooks)
              └── T1.4 (cross-link audit + RTFM scope)

T2.1 (wizard P1+P2)
  └── T2.2 (wizard P3)
        └── T2.3 (wizard P4 + error handling)

T3.1 (README warning)          ← independent, can run in parallel with T1/T2
T3.2 (/loa ambient)            ← independent, can run in parallel with T1/T2

T4.1 (5× SKILL.md ## Cost)    ← independent, can run in parallel with T1/T2
     └── requires T1.1 complete (for CONFIG_REFERENCE.md link to exist)
```

T1 must complete before T4.1 (the `## Cost` sections link to `docs/CONFIG_REFERENCE.md#cost-matrix`). T3.1 and T3.2 can proceed in parallel with T1 and T2. T2 tasks are fully sequential.
