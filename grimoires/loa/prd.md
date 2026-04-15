# Product Requirements Document: Config Documentation + Onboarding Wizard

**Issue**: #510
**Date**: 2026-04-15
**Cycle**: 073
**Status**: Draft
**Author**: @janitooor

---

## Problem Statement

Loa's `.loa.config.yaml` is the single most consequential file a new user will interact with — it controls which multi-model pipelines run, how much money gets spent, and what quality gates fire. Today, that file has no comprehensive documentation. New users face:

1. **Invisible cost exposure**: Enabling `flatline_protocol.enabled: true` can trigger $25-40 in API calls per planning phase with zero warning. `spiral.enabled: true` with a task can spend $50+ unattended. Users discover this via their billing dashboard, not at configuration time.

2. **Configuration paralysis**: The example config is 400+ lines across 30+ sections with no explanation of tradeoffs, no audience guidance ("who should enable this"), and no rationale for defaults. ELI5 explanations don't exist anywhere.

3. **Setup friction**: `/loa setup` is a shell script (`loa-setup-check.sh`) that validates the environment but does not generate configuration. New users get a pass/fail checklist and then face a blank `.loa.config.yaml`. The wizard gap is the #1 support category in the feedback channel.

4. **No ambient cost awareness**: README quick-start doesn't mention API costs. `/loa` ambient greeting doesn't surface active expensive features. Skill SKILL.md files for expensive skills don't carry cost warnings.

The result: users enable features because they sound useful, get surprised by API bills, and lose trust in the framework. The fix is documentation-first: make every configuration decision legible before the user commits to it.

---

## Assumptions

1. **Anthropic pricing is stable at these reference rates**: Opus input $15/MTok, output $75/MTok; Sonnet input $3/MTok, output $15/MTok; GPT-5.3-codex input ~$10/MTok, output ~$30/MTok; Gemini 2.5 Pro input ~$1.25/MTok, output ~$10/MTok. Costs in docs should be approximate ranges, not contractual guarantees, and must include a disclaimer that prices change.

2. **"Per invocation" means one full skill execution** — e.g., one `/simstim` run from PRD to PR, one `/run-bridge --depth 5`, one Flatline protocol run across all three phases.

3. **Monthly estimates assume a "moderate" workflow** — 2 planning cycles/week, 4 PRs/week — unless labeled otherwise. Cost matrix must show the assumptions.

4. **The setup wizard runs inside a Claude Code conversation** via the `/loa setup` skill invocation path. It is not a standalone shell script. The existing `loa-setup-check.sh` validates prerequisites; the wizard is a Claude-driven conversation above it.

5. **API key detection means presence check only** — the wizard checks whether `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and `GOOGLE_API_KEY` are set in the environment. It never reads, logs, or transmits key content (NFR-8 from the existing check script).

6. **"Idempotent wizard" means**: re-running on a repo with an existing `.loa.config.yaml` offers a diff-and-confirm flow rather than overwriting. Sections already present are preserved unless the user explicitly re-configures them.

7. **Expensive is defined as ≥$5 per typical invocation**. Features below this threshold get a cost note in their reference entry but not a full warning banner.

8. **The CONFIG_REFERENCE.md sections listed in the brief** (simstim, run_mode, hounfour, vision_registry, spiral, run_bridge, post_pr_validation, prompt_isolation, continuous_learning, red_team, flatline_protocol, harness/safety hooks) map directly to top-level YAML keys in `.loa.config.yaml`. The document should follow the same section order as the YAML file for cross-referencing ease.

9. **The `/loa` ambient greeting** refers to the status output Claude produces when `/loa` is invoked with no arguments. Adding a cost-awareness banner there means modifying the `/loa` skill's SKILL.md to include a section that surfaces currently-enabled expensive features and their estimated monthly burn at the configured workflow rate.

10. **"ELI5 explanation"** means a plain-English paragraph written for someone who has never heard of multi-model review or autonomous coding agents — not simplified API docs. The target reader is a senior engineer evaluating whether to adopt Loa for their team.

---

## Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| Cost transparency | New users encounter at least one cost-contextualized decision point before enabling any feature that costs ≥$5/invocation | 100% of expensive features carry a cost callout in CONFIG_REFERENCE.md |
| Reference completeness | Every top-level key in `.loa.config.yaml` and `.loa.config.yaml.example` has a corresponding entry in CONFIG_REFERENCE.md | 0 undocumented keys at merge time |
| Wizard adoption | A new user can go from cloned repo to recommended `.loa.config.yaml` via wizard alone, without reading source code | Wizard generates a valid, working config in <10 minutes of conversational setup |
| Wizard idempotency | Re-running `/loa setup` on a repo with existing config does not overwrite user customizations | Manual test: run wizard twice, confirm second run produces identical or additive output |
| Cost matrix accuracy | Spot-check 5 features: measured API cost within 2× of documented estimate | ≤2× variance at time of publication (stale warning if >6 months) |
| Skill-level warnings | All SKILL.md files for skills with estimated per-invocation cost ≥$5 contain a `## Cost` section | 100% of applicable skills |
| README coverage | README quick-start section contains a cost-awareness callout before the first command that incurs API costs | Present in README, verified by Flatline RTFM check |
| `/loa` ambient | `/loa` invocation with expensive features enabled surfaces a cost estimate line for each active expensive feature | Present when features are enabled, absent when all disabled |

---

## Functional Requirements

### FR-1: `docs/CONFIG_REFERENCE.md` — Comprehensive Configuration Reference

**FR-1.1** — The document must contain one entry per top-level `.loa.config.yaml` key. Each entry must include:

- **Section header** matching the YAML key name
- **ELI5 explanation** (plain English, ≤3 sentences, no jargon, targeted at first-time users)
- **Default value and rationale** — what ships by default and why that default was chosen
- **All sub-keys** with type, allowed values, and description
- **Estimated cost per invocation** for features that invoke external APIs — expressed as a range (e.g., "$8–$18 per full run") with the pricing assumptions listed in a footer
- **Monthly cost estimate** at moderate workflow (2 planning cycles/week, 4 PRs/week) — clearly labeled with the assumed rate
- **Risks if enabled**: what can go wrong (cost overrun, false positives blocking PR, unattended execution)
- **Risks if disabled**: what quality or safety coverage is lost
- **Setup assumptions**: what must be configured before this feature works (API keys, tools installed, state files)
- **Recommendation** — one of: `Recommended for all`, `Recommended for teams`, `Power user / opt-in`, `Experimental / use with caution`
- **Version introduced** — the `v1.X.Y` or `cycle-NNN` when the feature was added

**FR-1.2** — Sections must appear in this order (matching the canonical YAML key order in `.loa.config.yaml.example`):

1. `simstim`
2. `run_mode`
3. `hounfour`
4. `vision_registry`
5. `spiral`
6. `run_bridge`
7. `post_pr_validation`
8. `prompt_isolation`
9. `continuous_learning` (including `compound_learning` and `flatline_integration`)
10. `red_team`
11. `flatline_protocol`
12. Safety hooks summary (sourced from CLAUDE.loa.md hook table — reference only, not a YAML key)
13. Secondary sections: `paths`, `ride`, `plan_and_analyze`, `interview`, `autonomous_agent`, `workspace_cleanup`, `goal_traceability`, `effort`, `context_editing`, `memory_schema`, `skills`, `oracle`, `visual_communication`, `butterfreezone`, `bridgebuilder_design_review`

**FR-1.3** — A **Cost Matrix** table must appear near the top of the document (before individual section entries), showing:

| Feature | Per-Invocation Cost (low) | Per-Invocation Cost (high) | Models Used | Monthly at Moderate Workflow |
|---------|--------------------------|---------------------------|-------------|------------------------------|
| Flatline Protocol (3-phase) | $20 | $45 | Opus + GPT-5.3-codex + Gemini | $160–$360 |
| Simstim (full cycle) | $25 | $65 | Opus + GPT-5.3-codex + Gemini | $200–$520 |
| Spiral (per cycle, standard profile) | $10 | $15 | Sonnet (exec) + Opus (judge) | $80–$120 (3 cycles/sprint) |
| Spiral (per cycle, full profile) | $20 | $35 | All models | $160–$280 |
| Run Bridge (depth 5) | $10 | $20 | Opus + GPT-5.3-codex | $40–$80/PR |
| Post-PR Validation (Bridgebuilder) | $5 | $15 | Opus + GPT-5.3-codex | $20–$60/PR |
| Red Team (standard mode) | $5 | $15 | Opus + GPT-5.3-codex | varies |
| Red Team (deep mode) | $15 | $30 | Opus + GPT-5.3-codex | varies |
| Continuous Learning (Flatline integration) | $1 | $5 | Opus | $8–$40/week |
| Prompt Enhancement (invisible mode) | <$0.10 | $0.50 | Sonnet | negligible |

> The cost matrix rows above are the specification for what the PRD requires in the final document. The actual numeric ranges must be validated against API pricing at implementation time and confirmed via a real test run before merge.

**FR-1.4** — Each entry for a feature with cost ≥$5/invocation must include a `> **Cost Warning**` callout block immediately before the sub-key table, formatted as:

```markdown
> **Cost Warning**: This feature makes API calls to external LLM providers. Estimated cost: $X–$Y per invocation. Ensure `hounfour.metering.enabled: true` and set a `daily_micro_usd` budget cap before enabling.
```

**FR-1.5** — The document must include a **Decision Guide** section (before the detailed entries) that presents a flowchart in Mermaid or a decision table: given the user's workflow type (solo developer, small team, enterprise CI), what combination of features should they enable?

**FR-1.6** — Each section entry must link to: (a) the relevant protocol file in `.claude/protocols/` if one exists, (b) the reference doc in `.claude/loa/reference/` if one exists, and (c) the relevant SKILL.md if the feature is skill-invoked.

---

### FR-2: Enhanced `/loa setup` Wizard

**FR-2.1** — The wizard must be invokable via the `/loa setup` skill path (the `loa-setup` skill, which does not yet exist as a SKILL.md — this deliverable creates it).

**FR-2.2** — Phase 1: **Environment Detection** (non-interactive, runs automatically)
- Call `loa-setup-check.sh --json` and interpret the output
- Report: which required deps are present, which optional tools are missing
- Detect presence of: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY` — boolean only, never surface key values
- Detect installed tools: `br` (beads), `ck`, `gitleaks`, `trufflehog`, `yq` version
- Check if `.loa.config.yaml` already exists (triggers idempotency branch)

**FR-2.3** — Phase 2: **Profile Questionnaire** (interactive — one question at a time)
The wizard must ask these questions in order, using the user's answers to gate later questions:

1. **Usage tier** — "Are you a solo developer, part of a small team (<10), or in an enterprise context?" — gates whether agent teams features are recommended
2. **Budget posture** — "What's your rough monthly API budget for AI coding tools? ($0–$10 / $10–$50 / $50–$200 / $200+)" — directly controls which expensive features are recommended
3. **Workflow pace** — "Do you prefer (a) interactive HITL with full review cycles, (b) semi-autonomous with oversight, or (c) fully autonomous with minimal interruptions?" — maps to `run_mode`, `simstim`, `spiral` recommendations
4. **API keys available** — based on detection in Phase 1, confirm which providers to enable in `hounfour` routing
5. **Quality posture** — "How important is adversarial multi-model review for this project? (must-have / nice-to-have / not needed)" — gates `flatline_protocol` and `red_team`
6. **Scheduling** — Only asked if budget ≥$50/month: "Do you want Spiral to run during off-hours automatically? (yes/no)" — gates `spiral.scheduling`

**FR-2.4** — Phase 3: **Config Generation**
- Produce a `.loa.config.yaml` that reflects the user's answers
- Before writing, display a human-readable summary: "Here's what I'm enabling and why" — one line per feature enabled
- For each enabled feature with cost ≥$5/invocation, show: "This will cost approximately $X–$Y per [run/month] at your stated workflow"
- Ask for confirmation before writing
- If `.loa.config.yaml` already exists: perform a section-by-section diff and ask the user to confirm each changed section

**FR-2.5** — Phase 4: **Post-Config Explanation**
After writing the config, the wizard must print:
- A summary of what was enabled and disabled
- One-sentence explanation of each enabled feature
- The command to run next (`/loa` for status, or specific skill based on their workflow choice)
- A link to `docs/CONFIG_REFERENCE.md` for deeper reading

**FR-2.6** — Idempotency: The wizard MUST NOT overwrite an existing section of `.loa.config.yaml` without explicit confirmation per section. If the user declines to update a section, that section is preserved verbatim.

**FR-2.7** — The wizard must validate the generated config is parseable YAML before writing (via `yq` or a jq-based structural check).

---

### FR-3: Cost Warnings in README Quick Start

**FR-3.1** — The README `## Quick Start` section must include a **"Before You Spend"** callout block before the first command that invokes an external API. The block must:
- List the three most expensive features by default (Flatline, Simstim, Spiral)
- Show a "what will this cost?" reference pointing to CONFIG_REFERENCE.md cost matrix
- Recommend running `/loa setup` wizard before enabling autonomous modes

**FR-3.2** — The callout must use a GitHub-compatible `> [!WARNING]` admonition or equivalent so it renders visually in the README.

**FR-3.3** — The README must not gate access to quick-start instructions behind the warning — it is informational, not a blocker.

---

### FR-4: Cost Warnings in `/loa` Ambient Greeting

**FR-4.1** — When `/loa` is invoked with no arguments, if any of the following are enabled in `.loa.config.yaml`, the status output must include a cost-awareness line:
- `flatline_protocol.enabled: true`
- `spiral.enabled: true`
- `run_bridge.enabled: true`
- `post_pr_validation.phases.bridgebuilder_review.enabled: true`
- `red_team.enabled: true`

**FR-4.2** — The cost-awareness line format must be:
```
Active expensive features: Flatline (~$25/planning cycle), Spiral (~$12/cycle) | Budget cap: $500/day | Run /loa setup to adjust
```

**FR-4.3** — If `hounfour.metering.enabled: true` and a `daily_micro_usd` budget is set, the ambient greeting must also show today's spend vs. budget (pulled from `hounfour.metering.ledger_path`).

**FR-4.4** — If no expensive features are enabled, no cost line appears.

---

### FR-5: Cost Warnings in Expensive Skill SKILL.md Files

**FR-5.1** — The following SKILL.md files must each contain a `## Cost` section immediately after the `## Overview` (or first substantive section):
- `simstim-workflow/SKILL.md`
- `spiraling/SKILL.md`
- `run-bridge/SKILL.md`
- `red-teaming/SKILL.md`
- `flatline-knowledge/SKILL.md` (if it makes API calls)
- `run-mode/SKILL.md`

**FR-5.2** — The `## Cost` section must include:
- Estimated cost range per invocation
- Which external API providers are called
- How to cap spend (pointing to `hounfour.metering`)
- A note to run `/loa setup` if cost is a concern

**FR-5.3** — SKILL.md files must not be modified in ways that break their existing instruction content. The `## Cost` section is additive.

---

## Non-Functional Requirements

**NFR-1** — CONFIG_REFERENCE.md must be reviewable by a non-technical stakeholder — use plain language in all ELI5 sections, define all acronyms on first use.

**NFR-2** — All cost estimates must include a timestamp or version reference indicating when pricing was last verified. Format: `_Pricing verified: YYYY-MM-DD. Prices change — recheck before large commitments._`

**NFR-3** — The wizard must complete the questionnaire phase in ≤10 questions regardless of answers. No decision tree should require more than 10 turns to reach config generation.

**NFR-4** — CONFIG_REFERENCE.md must be maintained alongside the YAML example file. The acceptance criteria must include a check that every key in `.loa.config.yaml.example` appears in CONFIG_REFERENCE.md.

**NFR-5** — The wizard-generated config must be minimal by default: only enable features the user explicitly said "yes" to. Do not enable features speculatively.

**NFR-6** — No key material (API keys) ever appears in wizard output, config file comments, or log files.

**NFR-7** — The `## Cost` section in SKILL.md files must be ≤150 words — a scannable callout, not a documentation chapter.

**NFR-8** — CONFIG_REFERENCE.md must link back to the source YAML key for every entry, making it easy to cross-reference when editing the live config.

---

## Out of Scope

- Automated cost tracking or budget enforcement (owned by `hounfour.metering`, already implemented)
- Config validation at runtime (owned by `validate_model_registry()` in model-adapter.sh)
- Per-user cost dashboards or reporting UI
- Documentation for constructs (separate system)
- OpenClaw integration documentation
- Documentation for the `butterfreezone` ecosystem fields (internal metadata, not user-facing config)
- Changes to the Flatline Protocol itself or any pipeline behavior — this cycle is documentation only

---

## Acceptance Criteria

### Deliverable 1: CONFIG_REFERENCE.md

- [ ] `docs/CONFIG_REFERENCE.md` exists and is parseable Markdown
- [ ] Cost Matrix table appears before section entries, with all 10 required feature rows
- [ ] Decision Guide flowchart or table appears before section entries
- [ ] All 11 primary sections (simstim through flatline_protocol) have entries
- [ ] All 13 secondary sections have entries
- [ ] Zero top-level keys from `.loa.config.yaml.example` are undocumented
- [ ] Each section entry contains: ELI5, default+rationale, all sub-keys, cost, risks-enabled, risks-disabled, setup-assumptions, recommendation, version-introduced
- [ ] All features with cost ≥$5/invocation have a `> **Cost Warning**` callout
- [ ] Pricing verified timestamp appears in document footer
- [ ] All cross-links to protocol files, reference docs, and SKILL.md files resolve (no 404s)
- [ ] Document renders correctly in GitHub Markdown preview (no broken tables, no unrendered Mermaid)
- [ ] Flatline RTFM check passes against the document (if RTFM tooling covers docs/)

### Deliverable 2: `/loa setup` Wizard

- [ ] `loa-setup` skill SKILL.md exists at `.claude/skills/loa-setup/SKILL.md`
- [ ] `/loa setup` invocation triggers the wizard (skill loads and runs Phase 1 automatically)
- [ ] Phase 1 detects `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY` presence (boolean) without logging values
- [ ] Phase 1 calls `loa-setup-check.sh --json` and interprets output
- [ ] Phase 2 presents ≤10 questions, one at a time
- [ ] Phase 3 displays cost summary before writing any file
- [ ] Phase 3 asks for confirmation before writing `.loa.config.yaml`
- [ ] Phase 4 prints next-step guidance and link to CONFIG_REFERENCE.md
- [ ] Idempotency: running wizard on a repo with existing config triggers diff-and-confirm, not overwrite
- [ ] Generated config is valid YAML (yq-parseable)
- [ ] Generated config enables no feature the user did not explicitly request
- [ ] No API key content appears in wizard output or generated config comments
- [ ] Wizard completes in <10 conversational turns for a "default everything" user path
- [ ] Manual test: fresh repo → wizard → working config → `/loa` status reports correctly

### Deliverable 3: README Cost Warnings

- [ ] `> [!WARNING]` or equivalent admonition appears in README Quick Start section
- [ ] Warning lists Flatline, Simstim, and Spiral by name with approximate costs
- [ ] Warning links to `docs/CONFIG_REFERENCE.md`
- [ ] Warning does not block access to quick-start commands
- [ ] Admonition renders in GitHub README preview

### Deliverable 4: `/loa` Ambient Cost Awareness

- [ ] `/loa` skill SKILL.md updated to surface cost-awareness line when expensive features are enabled
- [ ] Cost-awareness line lists each active expensive feature with per-cycle cost estimate
- [ ] Cost-awareness line shows today's spend vs. budget when metering is enabled
- [ ] No cost line appears when all expensive features are disabled
- [ ] The script/skill logic reads from `.loa.config.yaml` at runtime (not hardcoded)

### Deliverable 5: Skill-Level Cost Warnings

- [ ] `## Cost` section added to: `simstim-workflow/SKILL.md`, `spiraling/SKILL.md`, `run-bridge/SKILL.md`, `red-teaming/SKILL.md`, `run-mode/SKILL.md`
- [ ] Each `## Cost` section includes: cost range, providers called, how to cap spend, link to `/loa setup`
- [ ] Each `## Cost` section is ≤150 words
- [ ] No existing instruction content in any SKILL.md is removed or altered
- [ ] All SKILL.md files remain parseable YAML front-matter + Markdown

### Quality Gate

- [ ] Flatline Protocol review passes on CONFIG_REFERENCE.md (if enabled)
- [ ] No new secrets or key material introduced
- [ ] CI passes (lint, if applicable)

---

## Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| `.loa.config.yaml.example` complete | Existing | Source of truth for all config keys |
| `loa-setup-check.sh` | Existing | Phase 1 engine for wizard |
| `hounfour.metering` ledger | Existing | Powers FR-4.3 live spend display |
| `/loa` skill SKILL.md | Existing | Will be modified for FR-4 |
| Flatline Protocol | Existing | Will review CONFIG_REFERENCE.md |
| Pricing data | Research required | Must verify current Anthropic, OpenAI, Google rates |

---

## Open Questions

1. Should CONFIG_REFERENCE.md live at `docs/CONFIG_REFERENCE.md` (new `docs/` directory) or at a path inside `.claude/loa/reference/`? The issue specifies `docs/`, but the project currently has no `docs/` directory. Recommendation: create `docs/` as a user-facing documentation directory distinct from the agent-facing `.claude/loa/reference/`.

2. The `/loa` skill does not have a standalone SKILL.md that can be easily edited for FR-4. How is the `/loa` ambient output currently generated? If it's inline in the `loa` skill script, FR-4 may require a skill modification rather than just a SKILL.md addition.

3. Should the wizard generate a `.loa.config.yaml` from scratch using a template, or produce a diff/patch to apply to the example file? Template approach is simpler but risks drifting from example file; patch approach is more robust but complex.

4. What is the canonical monthly workflow assumption for the cost matrix? The PRD proposes "2 planning cycles/week, 4 PRs/week" as "moderate." This needs confirmation from the maintainer before the cost matrix is written.

5. Should the RTFM check (`.claude/skills/rtfm-testing`) be extended to cover `docs/` in addition to its current scope? If CONFIG_REFERENCE.md is in `docs/`, it should be in scope.
