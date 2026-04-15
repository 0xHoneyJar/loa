# SDD: Config Documentation + Onboarding Wizard

**Cycle**: 073
**Issue**: #510
**PRD**: `grimoires/loa/prd.md`
**Date**: 2026-04-15
**Status**: Draft

---

## Bridgebuilder Design Review Integrations

_PRD is in Draft status. No Flatline review has been run yet. This table will be populated after the first bridge review of this SDD._

| Finding | Severity | Resolution |
|---------|----------|------------|
| — | — | — |

---

## Open Question Resolutions

The PRD surface five open questions. All are resolved here before architecture begins.

| # | Question | Resolution |
|---|----------|------------|
| OQ-1 | Where does CONFIG_REFERENCE.md live? | `docs/CONFIG_REFERENCE.md`. Create `docs/` as the user-facing documentation directory. Distinct from agent-facing `.claude/loa/reference/`. |
| OQ-2 | How is `/loa` ambient output generated? | The `loa` skill's SKILL.md drives the output. FR-4 is implemented by adding a "Cost Awareness" section to `SKILL.md` that instructs Claude to read `.loa.config.yaml` for expensive feature flags and surface cost lines conditionally. No separate script is required. |
| OQ-3 | Template or patch for config generation? | Section-based template approach. The wizard builds a YAML document section by section from canonical templates (one per feature) and writes them together. Idempotency is handled by loading the existing file, preserving unchanged sections verbatim, and only inserting/replacing sections the user confirmed. |
| OQ-4 | Monthly workflow assumption? | 2 planning cycles/week, 4 PRs/week as stated in PRD. Flagged as "assumed moderate workflow" in the cost matrix with instructions to recalibrate after maintainer confirmation (NFR-2 timestamp requirement). |
| OQ-5 | Extend RTFM scope to `docs/`? | Yes. The `rtfm-testing` skill scope extends to `docs/` in this cycle. This is a SKILL.md-only change (no script modification needed); the skill reads the target path from the invocation context. |

---

## 1. System Architecture

### 1.1 Component Overview

This cycle is **documentation-only** — no pipeline behavior changes. All five deliverables are content or skill-instruction files.

```
Deliverable 1: docs/CONFIG_REFERENCE.md (new file)
  ├── Cost Matrix table (10 features, approximate ranges)
  ├── Decision Guide (Mermaid flowchart)
  ├── 11 primary sections (simstim → flatline_protocol)
  └── 13 secondary sections

Deliverable 2: .claude/skills/loa-setup/SKILL.md (new skill)
  │
  ├── Phase 1: Environment Detection (non-interactive)
  │     ├── loa-setup-check.sh --json (existing script, read-only)
  │     ├── API key presence check (boolean, no values logged)
  │     └── .loa.config.yaml existence check → idempotency branch
  │
  ├── Phase 2: Profile Questionnaire (≤6 questions, ≤10 turns total)
  │     ├── Q1: Usage tier (solo / small team / enterprise)
  │     ├── Q2: Monthly budget tier ($0-10 / $10-50 / $50-200 / $200+)
  │     ├── Q3: Workflow pace (HITL / semi-auto / full-auto)
  │     ├── Q4: API keys confirmed (from Phase 1 detection)
  │     ├── Q5: Quality posture (must-have / nice-to-have / not needed)
  │     └── Q6: Scheduling (only if budget ≥ $50/month)
  │
  ├── Phase 3: Config Generation
  │     ├── Profile → feature set mapping (see §3.2)
  │     ├── Cost summary display (per enabled feature ≥$5)
  │     ├── Confirmation gate before any write
  │     ├── Idempotency: section diff for existing config
  │     └── yq YAML validation before writing
  │
  └── Phase 4: Post-Config Explanation
        ├── Feature summary (enabled / disabled)
        ├── Next-step command guidance
        └── Link to docs/CONFIG_REFERENCE.md

Deliverable 3: README.md update (existing file, additive)
  └── > [!WARNING] "Before You Spend" callout in Quick Start

Deliverable 4: .claude/skills/loa/SKILL.md update (existing skill, additive)
  └── Cost-awareness section: conditional cost lines from .loa.config.yaml

Deliverable 5: SKILL.md updates — 5 existing skills (additive ## Cost sections)
  ├── .claude/skills/simstim-workflow/SKILL.md
  ├── .claude/skills/spiraling/SKILL.md
  ├── .claude/skills/run-bridge/SKILL.md
  ├── .claude/skills/red-teaming/SKILL.md
  └── .claude/skills/run-mode/SKILL.md
```

### 1.2 File Map

| File | Action | Purpose |
|------|--------|---------|
| `docs/CONFIG_REFERENCE.md` | New | Comprehensive configuration reference with cost matrix |
| `.claude/skills/loa-setup/SKILL.md` | New | Wizard skill instructions |
| `.claude/skills/loa-setup/index.yaml` | New | Skill registration metadata |
| `README.md` | Modify (+~15 lines) | Add "Before You Spend" callout in Quick Start |
| `.claude/skills/loa/SKILL.md` | Modify (+~20 lines) | Add cost-awareness section for `/loa` ambient |
| `.claude/skills/simstim-workflow/SKILL.md` | Modify (+~100 words) | Add `## Cost` section |
| `.claude/skills/spiraling/SKILL.md` | Modify (+~100 words) | Add `## Cost` section |
| `.claude/skills/run-bridge/SKILL.md` | Modify (+~100 words) | Add `## Cost` section |
| `.claude/skills/red-teaming/SKILL.md` | Modify (+~100 words) | Add `## Cost` section |
| `.claude/skills/run-mode/SKILL.md` | Modify (+~100 words) | Add `## Cost` section |

No scripts are created or modified. No pipeline behavior changes.

---

## 2. Component Design

### 2.1 CONFIG_REFERENCE.md Document Structure

The document follows a strict section order matching `.loa.config.yaml.example` (FR-1.2). Each section is self-contained so users can navigate directly to the key they are configuring.

**Document skeleton (in order)**:

```
# Loa Configuration Reference

> _Pricing verified: YYYY-MM-DD. Prices change — recheck before large commitments._

## Overview

## Cost Matrix

| Feature | Per-Invocation Low | Per-Invocation High | Models | Monthly at Moderate Workflow |
...

## Decision Guide

[Mermaid flowchart or decision table]

## Primary Sections

### simstim
### run_mode
### hounfour
### vision_registry
### spiral
### run_bridge
### post_pr_validation
### prompt_isolation
### continuous_learning
### red_team
### flatline_protocol

### Safety Hooks (reference — not a YAML key)

## Secondary Sections

### paths
### ride
### plan_and_analyze
### interview
### autonomous_agent
### workspace_cleanup
### goal_traceability
### effort
### context_editing
### memory_schema
### skills
### oracle
### visual_communication
### butterfreezone
### bridgebuilder_design_review

## Pricing Footnotes
```

**Per-section entry template** (FR-1.1):

```markdown
### section_name

> **ELI5**: [≤3 sentences, plain English, no jargon]

**Version introduced**: vX.Y.Z / cycle-NNN
**Recommendation**: [Recommended for all | Recommended for teams | Power user / opt-in | Experimental]
**Default**: [value and rationale]

> **Cost Warning**: [For features ≥$5/invocation only — includes provider list, estimated range, hounfour.metering pointer]

#### Sub-keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|

#### Cost
- **Per invocation**: $X–$Y
- **Monthly (moderate workflow)**: $X–$Y
- **Models used**: [list]

#### Risks if enabled
- [bullet list]

#### Risks if disabled
- [bullet list]

#### Setup requirements
- [bullet list]

#### See also
- Protocol: [path if exists]
- Reference: [path if exists]
- Skill: [path if exists]
```

### 2.2 Decision Guide Flowchart

The Decision Guide is a Mermaid `flowchart TD` that routes users from a starting question to a recommended feature set. It uses the same three axes as the wizard questionnaire (usage tier, budget, workflow pace).

```
Start
  → Solo developer? → Budget < $50/month? → HITL workflow?
    → Recommended: beads + prompt_enhancement + run_mode (HITL)
    → Semi/auto workflow? → Recommended: add simstim
  → Small team? → ...
  → Enterprise? → Recommended: full feature set (all quality gates enabled)
```

The flowchart renders in GitHub Markdown preview (AC: renders correctly in GH preview). If Mermaid fails to render, a fallback decision table covers the same content.

### 2.3 `/loa setup` Wizard Phases

#### Phase 1: Environment Detection

Runs non-interactively. Claude executes `loa-setup-check.sh --json` via Bash tool and parses the JSONL output. Detection results:

- `anthropic_key_present`: boolean (from step 1 in check script)
- `openai_key_present`: `OPENAI_API_KEY` env var set (boolean)
- `google_key_present`: `GOOGLE_API_KEY` env var set (boolean)
- `beads_installed`: boolean
- `ck_installed`: boolean
- `yq_installed`: boolean (required for config validation)
- `config_exists`: `.loa.config.yaml` file presence
- `required_deps_ok`: jq, yq, git all present (from step 2)

If `config_exists: true`, the wizard branches into idempotency mode (§2.3.5).

API key detection uses a simple env var presence check via `loa-setup-check.sh`. Claude never reads, echoes, or logs key values — only the boolean output from the script is consumed.

#### Phase 2: Profile Questionnaire

Questions are presented one at a time (FR-2.3). Questions 4 and 6 are conditional:

```
Q1: Usage tier
  Answer gates: team features in recommendation (agent teams, post_pr_validation)

Q2: Budget tier
  Answer gates: which expensive features (≥$5/invocation) are offered
  - $0-$10/month:  no expensive features recommended
  - $10-$50/month: run_mode (HITL) + run_bridge (depth 1)
  - $50-$200/month: add flatline_protocol, simstim
  - $200+/month:   add spiral, red_team

Q3: Workflow pace
  Answer maps to config values:
  - HITL → run_mode.enabled: true, simstim.enabled: false, spiral.enabled: false
  - Semi-auto → run_mode.enabled: true, simstim.enabled: true, spiral.enabled: false
  - Fully auto → all three enabled

Q4: API keys confirmation (conditional — only asked if Q2 budget ≥ $10/month)
  Pre-populated from Phase 1 detection results.
  User confirms which providers to wire into hounfour routing.
  Only shown if at least one key was detected.

Q5: Quality posture
  Maps to: flatline_protocol.enabled, red_team.enabled
  - must-have  → both enabled (gated by budget from Q2)
  - nice-to-have → flatline_protocol only (gated by budget)
  - not needed  → both disabled

Q6: Off-hours scheduling (conditional — only asked if Q2 budget ≥ $50/month)
  Maps to: spiral.scheduling.enabled
```

Maximum turns to reach config generation: 6 questions + 1 confirmation = 7 turns (well within NFR-3 ≤10).

#### Phase 3: Config Generation

**Feature set derivation** (see §3.2 for full mapping table):

1. Take answers from Q1–Q6
2. Look up each answer in the Profile → Feature matrix
3. For each enabled feature, load the canonical section template (see §3.3)
4. Assemble sections in YAML key order matching `.loa.config.yaml.example`

**Pre-write display**:

Before writing any file, Claude displays a human-readable summary:
- One line per enabled feature: `[ENABLED] flatline_protocol — Multi-model adversarial review (~$25/planning cycle)`
- One line per disabled feature: `[DISABLED] spiral — Off-hours autonomous cycles`
- Total estimated monthly cost range based on enabled features

For each feature with cost ≥$5/invocation, the summary includes the cost range explicitly.

**Confirmation gate**:

Claude presents the summary and asks: "Write this configuration to `.loa.config.yaml`? (yes / no / show full YAML)". Writing does not proceed without explicit "yes".

#### Phase 3 (Idempotency Branch)

When `.loa.config.yaml` already exists:

1. Claude reads the existing file
2. For each section the wizard would modify, parse the current value from the file using `yq`
3. Present a diff-style summary: "Section `flatline_protocol`: current value `enabled: false`, proposed value `enabled: true`"
4. Ask per-section: "Update this section? (yes / no / skip all)"
5. Sections the user declines are preserved verbatim
6. Only explicitly confirmed sections are written

This is implemented as SKILL.md instructions to Claude — not as a shell script. Claude uses the Read tool to load the existing config and constructs the diff in conversation.

#### Phase 3 (YAML Validation)

After generating the YAML string and before writing, Claude runs:

```
yq '.' <(echo "$generated_yaml") > /dev/null
```

If `yq` parses without error, proceed. If it fails, Claude reports the parse error and does not write the file.

If `yq` is not installed (detected in Phase 1), Claude performs a structural check using `jq` with `--yaml-output` as fallback. If neither is available, warn the user and ask to confirm before writing (NFR cannot be fully met without yq).

#### Phase 4: Post-Config Explanation

After writing, Claude prints:
- Summary table: feature → enabled/disabled
- One-sentence description of each enabled feature
- The recommended next command (`/loa` for status, `/run sprint-plan` for autonomous, `/simstim` for HITL)
- "For full configuration reference, see `docs/CONFIG_REFERENCE.md`"

### 2.4 `/loa` Ambient Cost Awareness

The `loa` skill's SKILL.md is updated to include a "Cost Awareness" section with these instructions to Claude:

1. Read `.loa.config.yaml` using the Read tool (if it exists)
2. Check each of the five expensive feature flags:
   - `flatline_protocol.enabled`
   - `spiral.enabled`
   - `run_bridge.enabled`
   - `post_pr_validation.phases.bridgebuilder_review.enabled`
   - `red_team.enabled`
3. For each flag that is `true`, output one cost-awareness line with the feature name and estimated per-cycle cost
4. If `hounfour.metering.enabled: true` and `hounfour.metering.ledger_path` is set, read today's spend from the ledger and show it vs. the daily budget
5. If no expensive features are enabled, output nothing (FR-4.4)

**Output format** (FR-4.2):
```
Active expensive features: Flatline (~$25/planning cycle), Spiral (~$12/cycle) | Budget cap: $500/day | Run /loa setup to adjust
```

The `hounfour.metering.ledger_path` is read and the last entry's `cumulative_usd` for today's date is surfaced. If the ledger doesn't exist or today has no entries, skip the spend line rather than erroring.

### 2.5 Skill-Level Cost Sections (FR-5)

Each of the five SKILL.md files receives an additive `## Cost` section immediately after their first substantive section (following `## Overview` or equivalent). The section is ≤150 words (NFR-7).

**Template**:

```markdown
## Cost

**Estimated per invocation**: $X–$Y (see [Cost Matrix](../../../docs/CONFIG_REFERENCE.md#cost-matrix))
**External providers called**: [list of models and providers]
**To cap spend**: Set `hounfour.metering.budget.daily_micro_usd` in `.loa.config.yaml`. Budget enforcement is active when `hounfour.metering.enabled: true`.
**If cost is a concern**: Run `/loa setup` — the wizard will guide you to a budget-appropriate configuration.

_Pricing verified: 2026-04-15. Prices change — recheck before large commitments._
```

Existing content in each SKILL.md is preserved verbatim. The `## Cost` section is inserted additively. If any SKILL.md already has a `## Cost` section, it is updated in place rather than duplicated.

---

## 3. Data Model

### 3.1 Wizard Session State

The wizard maintains state in conversation context only — no files are written during Phases 1 or 2. All state is discarded after Phase 4. There is no persistent wizard state file.

```
wizard_state {
  # Phase 1 outputs
  detection: {
    anthropic_key: bool
    openai_key: bool
    google_key: bool
    beads_installed: bool
    ck_installed: bool
    yq_installed: bool
    config_exists: bool
    required_deps_ok: bool
  }

  # Phase 2 outputs
  answers: {
    usage_tier: "solo" | "team" | "enterprise"
    budget_tier: "low" | "medium" | "high" | "unlimited"
    workflow_pace: "hitl" | "semi_auto" | "full_auto"
    providers: { anthropic: bool, openai: bool, google: bool }
    quality_posture: "must_have" | "nice_to_have" | "not_needed"
    scheduling_enabled: bool  # only set if budget_tier >= high
  }

  # Phase 3 derived
  feature_set: { [feature_key: string]: bool }
  generated_yaml: string
  idempotency_mode: bool
  sections_to_preserve: string[]  # keys to pass through from existing config
}
```

### 3.2 Profile → Feature Mapping Matrix

| Budget Tier | Workflow | Quality | Features Enabled |
|-------------|----------|---------|-----------------|
| low ($0-10) | any | any | `run_mode` (HITL defaults), `beads`, `prompt_enhancement` |
| medium ($10-50) | HITL | not_needed | `run_mode`, `beads`, `prompt_enhancement`, `run_bridge` (depth 1) |
| medium ($10-50) | semi_auto | not_needed | + `simstim` |
| medium ($10-50) | any | nice_to_have | + `flatline_protocol` (sprint only) |
| high ($50-200) | HITL | any | medium_set + `flatline_protocol` (full) |
| high ($50-200) | semi_auto | any | + `simstim`, `post_pr_validation` |
| high ($50-200) | full_auto | must_have | + `red_team` (standard) |
| unlimited ($200+) | full_auto | must_have | all features, `spiral` (standard profile) |
| + scheduling | — | — | `spiral.scheduling.enabled: true` (if Q6 = yes) |

**Provider routing**: `hounfour.flatline_routing` is set to `true` only if at least one of `openai_key` or `google_key` is detected and at least one expensive multi-model feature is enabled. If only `anthropic_key` is present, `flatline_routing` stays `false` (Flatline uses native Opus only).

### 3.3 Config Section Templates

Each feature maps to a canonical YAML section template. Templates are the minimal correct configuration for that feature — they do not include every sub-key, only those required for the feature to work as the user expressed. Optional sub-keys with sensible defaults are omitted (NFR-5).

**Example: flatline_protocol minimal template** (when `quality_posture: nice_to_have` and `budget: medium`):

```yaml
flatline_protocol:
  enabled: true
  auto_trigger: true
  phases:
    prd: false
    sdd: false
    sprint: true   # Sprint only at medium budget
  models:
    primary: opus
    secondary: gpt-5.3-codex
```

**Example: spiral minimal template** (when `workflow: full_auto` and `budget: unlimited`):

```yaml
spiral:
  enabled: true
  default_max_cycles: 3
  budget_cents: 2000
  wall_clock_seconds: 28800
  harness:
    enabled: true
    pipeline_profile: standard
```

### 3.4 Cost Matrix Data

The cost matrix is static content in `docs/CONFIG_REFERENCE.md`. Pricing assumptions are footnoted with the verification date (NFR-2).

| Feature | Per-Invocation Low | Per-Invocation High | Models Used | Monthly (moderate) |
|---------|-------------------|--------------------|--------------|--------------------|
| Flatline Protocol (3-phase) | $20 | $45 | Opus + GPT-5.3-codex + Gemini | $160–$360 |
| Simstim (full cycle) | $25 | $65 | Opus + GPT-5.3-codex + Gemini | $200–$520 |
| Spiral (standard profile) | $10 | $15 | Sonnet (exec) + Opus (judge) | $80–$120 (3 cycles/sprint) |
| Spiral (full profile) | $20 | $35 | All models | $160–$280 |
| Run Bridge (depth 5) | $10 | $20 | Opus + GPT-5.3-codex | $40–$80/PR |
| Post-PR Validation (Bridgebuilder) | $5 | $15 | Opus + GPT-5.3-codex | $20–$60/PR |
| Red Team (standard mode) | $5 | $15 | Opus + GPT-5.3-codex | varies |
| Red Team (deep mode) | $15 | $30 | Opus + GPT-5.3-codex | varies |
| Continuous Learning (Flatline integration) | $1 | $5 | Opus | $8–$40/week |
| Prompt Enhancement (invisible mode) | <$0.10 | $0.50 | Sonnet | negligible |

> Moderate workflow assumption: 2 planning cycles/week, 4 PRs/week. Monthly estimates are approximate. Verify at implementation time against current provider pricing. Spot-check variance target: ≤2× measured vs. documented (AC: Cost matrix accuracy).

---

## 4. Security Design

### 4.1 API Key Handling

**Zero key material** (NFR-6, aligned with loa-setup-check.sh NFR-8):

- The wizard calls `loa-setup-check.sh --json` and consumes only the `status` boolean from each check result
- Claude must never read environment variables directly (e.g., `echo $ANTHROPIC_API_KEY`) — all detection goes through the check script
- The generated `.loa.config.yaml` uses template placeholders (`{env:ANTHROPIC_API_KEY}`) for provider auth, never literal key values
- Wizard output displayed to the user contains no key content — only "ANTHROPIC_API_KEY detected: yes/no" style messages
- SKILL.md instructions for Phase 1 explicitly state: "Do not read, log, or display the content of any API key environment variable"

### 4.2 Config File Safety

**YAML injection prevention**: Config sections are constructed from hardcoded templates with only feature toggles and boolean values substituted. User-supplied strings (answers to Q1–Q6) map to enumerated values, not free-form text that could appear in the YAML output.

**Before writing**: Validate the generated YAML is parseable via `yq '.' <(echo "$yaml")`. Reject and report if validation fails — do not write a malformed config.

**Idempotency write safety**: The idempotency branch reads the existing config, applies only confirmed section changes, and produces a merged output. The merged output is also validated via `yq` before writing.

**File permissions**: The wizard writes `.loa.config.yaml` using the Write tool. No `chmod` is performed — the file inherits the user's umask. This is standard behavior for config files.

### 4.3 Prompt Injection in Wizard Inputs

The wizard answers (Q1–Q6) are constrained to enumerated choices. Claude must not accept free-form text as an answer that modifies template logic. If a user provides an unexpected answer, Claude presents the valid options again rather than treating the unexpected input as a feature toggle.

This matters because answers drive the feature-set matrix in §3.2. A malicious or malformed answer (e.g., injecting YAML syntax via a "budget" answer) cannot affect the generated config because answers are mapped through the fixed matrix, not interpolated.

### 4.4 README Content Safety

The `> [!WARNING]` callout added to the README is informational text only. It contains no executable instructions or links to external services that could be compromised. The costs listed are documented ranges, not API calls.

### 4.5 SKILL.md Content Safety

The `## Cost` sections added to SKILL.md files are read-only advisory text. They do not expand to code execution. They point users to `/loa setup` and `docs/CONFIG_REFERENCE.md`, both of which are local.

---

## 5. Test Design

### 5.1 Test Strategy

This cycle is documentation-only. Automated test files are not required. Acceptance criteria are validated via:

1. **Manual check list** (AC tables in PRD §Acceptance Criteria) — verified by reviewer before merge
2. **Grep-based checks** for structural requirements:
   - All 11 primary sections present in CONFIG_REFERENCE.md
   - All 13 secondary sections present
   - Cost Warning callouts present for each ≥$5 feature
   - `## Cost` section present in each of the 5 SKILL.md files
3. **YAML parse check** for generated config: `yq '.' .loa.config.yaml` must exit 0
4. **Manual wizard walkthrough**: fresh repo → wizard → working config → `/loa` reports correctly

### 5.2 Structural Validation Checks

The following checks can be scripted as one-off validations (not part of the test suite, but executable for verification):

| Check | Command |
|-------|---------|
| CONFIG_REFERENCE.md exists | `test -f docs/CONFIG_REFERENCE.md` |
| All 11 primary sections present | `grep -c '^### ' docs/CONFIG_REFERENCE.md` ≥ 11 |
| Cost Matrix table rows | `grep -c '^\|' docs/CONFIG_REFERENCE.md` ≥ 12 (10 rows + 2 header) |
| Cost Warning callouts (≥7) | `grep -c 'Cost Warning' docs/CONFIG_REFERENCE.md` ≥ 7 |
| loa-setup SKILL.md exists | `test -f .claude/skills/loa-setup/SKILL.md` |
| 5 SKILL.md `## Cost` sections | `grep -l '^## Cost' .claude/skills/{simstim-workflow,spiraling,run-bridge,red-teaming,run-mode}/SKILL.md \| wc -l` = 5 |
| README has [!WARNING] admonition | `grep -c '\[!WARNING\]' README.md` ≥ 1 |
| Pricing verified timestamp present | `grep -c 'Pricing verified' docs/CONFIG_REFERENCE.md` ≥ 1 |

### 5.3 Manual Wizard Test Cases

| Test | Expected |
|------|----------|
| Fresh repo, budget=$0-10, HITL | Config: run_mode only, no external providers |
| Fresh repo, budget=$50-200, semi-auto, must-have quality | Config: simstim + flatline_protocol + run_bridge |
| Existing config, decline all updates | Config file unchanged |
| Existing config, accept flatline update | Only flatline_protocol section updated |
| wizard with no yq installed | Warning shown, user confirms before write |
| wizard with openai key present | hounfour configured with openai provider |
| wizard with no expensive features enabled | `/loa` shows no cost line |
| wizard with flatline enabled | `/loa` shows "Active expensive features: Flatline (~$25/planning cycle)" |

---

## 6. Error Handling

| Error | Handler | Recovery |
|-------|---------|----------|
| `loa-setup-check.sh` not found | Report error, ask user to verify installation, skip Phase 1 output | Continue with manual API key questions |
| `loa-setup-check.sh` exits non-zero | Report which required deps failed, list install instructions | User installs deps, re-runs wizard |
| No API keys detected | Disable multi-model feature recommendations, warn user | User sets env vars and re-runs |
| `yq` not installed | Fall back to jq structural check; if jq also missing, warn and ask confirmation | User installs yq for full validation |
| YAML parse error on generated config | Report parse error line, do not write | User reports issue; wizard re-generates |
| Existing config parse error | Report which section failed to parse, skip that section in idempotency diff | User manually fixes config, re-runs |
| User declines all wizard questions | Do not write config; suggest reading CONFIG_REFERENCE.md directly | No action needed |
| `/loa` skill reads missing `.loa.config.yaml` | Skip cost awareness line entirely (no error, no output) | User runs /loa setup |
| Metering ledger not found during `/loa` | Skip spend line, show only active features | No action needed |
| SKILL.md missing `## Overview` section | Insert `## Cost` before next heading | Additive, no existing content removed |

---

## 7. Migration Notes

**Fully backward-compatible.** All deliverables are additive:

- `docs/CONFIG_REFERENCE.md` is a new directory and file — no existing paths affected
- `loa-setup` SKILL.md is a new skill — no existing skill behavior changed
- README and SKILL.md updates are additive sections — no existing content removed
- `/loa` cost awareness is conditional — surfaces only when expensive features are enabled, invisible otherwise
- `.loa.config.yaml` is only written when the user explicitly confirms — no automatic migration

Users with existing configs are not affected until they run `/loa setup`. At that point, the idempotency branch ensures their existing settings are preserved unless they explicitly approve changes.

The `docs/` directory is new. Projects that have a `docs/` directory with different content are not affected — the wizard creates `docs/CONFIG_REFERENCE.md` only, and does not modify existing files in `docs/`.
