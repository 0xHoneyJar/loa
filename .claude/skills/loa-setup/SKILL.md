---
name: loa-setup
description: "Loa onboarding wizard: environment detection, profile questionnaire, config generation, and post-config explanation in ≤10 turns"
role: planning
capabilities:
  schema_version: 1
  read_files: true
  search_code: false
  write_files: true
  execute_commands:
    allowed:
      - command: ".claude/scripts/loa-setup-check.sh"
        args: ["--json"]
      - command: "yq"
      - command: "jq"
    deny_raw_shell: true
  web_access: false
  user_interaction: true
  agent_spawn: false
  task_management: false
cost-profile: minimal
---

# /loa setup — Onboarding Wizard

## Overview

The `/loa setup` wizard takes a new user from a freshly cloned repo to a working `.loa.config.yaml` in **≤10 conversational turns**. It detects the environment, asks targeted questions about usage tier, budget, and workflow pace, generates a feature-appropriate YAML configuration, and explains what was enabled and what to do next.

Use this wizard:
- When first installing Loa on a new repo
- When you want to adjust your configuration without editing YAML by hand
- When an existing config needs to be audited and updated against new feature options

**NFR-5**: The wizard enables only features the user explicitly requested. No feature is enabled by default unless the user has confirmed it.

**NFR-6**: API key values are never logged, printed, or written to disk. Only boolean presence is read.

The wizard runs in at most 7 turns to reach config generation (6 questions + 1 confirmation gate), plus Phase 4 explanation — ≤10 total turns for the complete flow.

---

## Phase 1: Environment Detection

Run this phase automatically when `/loa setup` is invoked. Do not ask the user for permission — proceed immediately.

### Step 1.1: Run the setup check script

Execute `.claude/scripts/loa-setup-check.sh --json` via Bash tool. Parse each line as a JSON object. The script emits JSONL with `step`, `name`, `status` (`pass`/`warn`/`fail`), and `detail` fields.

**CRITICAL — API key handling**: The check script emits boolean `pass`/`fail` results only. You MUST NOT read, echo, print, or log the value of any environment variable. Do not run `echo $ANTHROPIC_API_KEY` or any similar command. Do not read `.env` files. Consume only the boolean output from `loa-setup-check.sh`.

### Step 1.2: Parse environment state

Record the following boolean facts from the script output:

| Variable | Source | Meaning |
|----------|--------|---------|
| `anthropic_key_present` | Step 1 status == "pass" for ANTHROPIC_API_KEY | Anthropic API key detected |
| `openai_key_present` | Step 1 status == "pass" for OPENAI_API_KEY | OpenAI API key detected |
| `google_key_present` | Step 1 status == "pass" for GOOGLE_API_KEY | Google API key detected |
| `beads_installed` | Step 3 status == "pass" for beads | beads_rust (`br`) available |
| `ck_installed` | Step 3 status == "pass" for ck | ck available |
| `yq_installed` | Step 2 status == "pass" for yq | yq v4+ available |
| `config_exists` | Step 4 status == "pass" for config | `.loa.config.yaml` already exists |
| `required_deps_ok` | All Step 2 entries pass | Required dependencies met |

If the script exits non-zero or is not found, skip to Error Handling (`loa-setup-check.sh not found`).

If `config_exists: true`, set `idempotency_mode: true` — this activates the idempotency branch in Phase 3.

### Step 1.3: Present environment summary

Show the user a brief, readable summary before proceeding:

```
Environment Check
═════════════════
API Keys:
  ANTHROPIC_API_KEY  ✓ detected
  OPENAI_API_KEY     ✗ not detected
  GOOGLE_API_KEY     ✗ not detected

Tools:
  yq v4+     ✓
  jq         ✓
  beads (br) ⚠ not installed (optional)

Config:
  .loa.config.yaml  ✗ not found — will create fresh config

Proceeding to profile questionnaire...
```

Use ✓ for pass, ⚠ for warn, ✗ for fail/missing.

---

## Phase 2: Profile Questionnaire

Present questions **one at a time** — never as a batch. Wait for the user's answer before presenting the next question. Enumerated choices only — if the user provides a free-form answer that does not match a valid option, re-present the valid options without accepting the free-form text.

Maximum 7 turns to reach Phase 3 (6 questions + 1 confirmation gate).

### Q1: Usage Tier

```
Q1 of 6: Who will be using Loa on this repo?

  A) Solo developer
  B) Small team (fewer than 10 people)
  C) Enterprise / large team

Your choice (A/B/C):
```

Record: `usage_tier` = `solo` | `small_team` | `enterprise`

### Q2: Monthly Budget

```
Q2 of 6: What is your monthly AI API budget for this project?

  A) $0–$10  (basic automation only)
  B) $10–$50  (standard quality gates)
  C) $50–$200  (full workflow automation)
  D) $200+  (enterprise workloads)

Your choice (A/B/C/D):
```

Record: `budget_tier` = `minimal` | `standard` | `full` | `unlimited`

### Q3: Workflow Pace

```
Q3 of 6: How much do you want to stay in control of each step?

  A) HITL — I want to approve every decision manually
  B) Semi-auto — I want to supervise but let automation handle routine steps
  C) Fully auto — I want autonomous overnight runs

Your choice (A/B/C):
```

Record: `workflow_pace` = `hitl` | `semi_auto` | `fully_auto`

### Q4: API Key Confirmation

**Conditional**: Only ask Q4 if BOTH conditions are true:
- `budget_tier` is `standard`, `full`, or `unlimited` (budget ≥ $10/month)
- AT LEAST ONE of `openai_key_present` or `google_key_present` is true

If either condition is false, skip Q4 and record `multi_model_confirmed: false`.

```
Q4 of 6: Multi-model features (Flatline Protocol, Simstim) require OpenAI or Google API keys.
We detected an API key. Confirm you want to enable multi-model features?

  A) Yes — enable multi-model features
  B) No — use Anthropic-only features

Your choice (A/B):
```

Record: `multi_model_confirmed` = `true` | `false`

### Q5: Quality Posture

```
Q5 of 6: How important is multi-model adversarial review (Flatline Protocol, Red Team)?

  A) Must-have — I want all quality gates active
  B) Nice-to-have — Enable if cost-appropriate for my budget
  C) Not needed — I'll review manually

Your choice (A/B/C):
```

Record: `quality_posture` = `must_have` | `nice_to_have` | `not_needed`

### Q6: Off-Hours Scheduling

**Conditional**: Only ask Q6 if `budget_tier` is `full` or `unlimited` (budget ≥ $50/month).

If condition is false, skip Q6 and record `scheduling_enabled: false`.

```
Q6 of 6: Do you want to schedule autonomous Spiral cycles during off-hours (nights/weekends)?

  A) Yes — schedule against UTC time windows
  B) No — run manually only

Your choice (A/B):
```

Record: `scheduling_enabled` = `true` | `false`

---

## Phase 3: Config Generation

### Feature Matrix

Map Q1–Q6 answers to features using this matrix:

| Feature | Enabled When |
|---------|-------------|
| `run_mode` | Always (all tiers) |
| `prompt_enhancement` | `budget_tier` != `minimal` |
| `flatline_protocol` | `quality_posture` = `must_have` OR (`nice_to_have` AND `budget_tier` = `full`/`unlimited`) AND `multi_model_confirmed` |
| `simstim` | `workflow_pace` = `semi_auto` OR `fully_auto` AND `budget_tier` != `minimal` |
| `run_bridge` | `workflow_pace` = `semi_auto` OR `fully_auto` AND `budget_tier` = `full`/`unlimited` |
| `spiral` | `workflow_pace` = `fully_auto` AND `budget_tier` = `full`/`unlimited` |
| `red_team` | `quality_posture` = `must_have` AND `budget_tier` = `full`/`unlimited` AND `multi_model_confirmed` |
| `hounfour` | Any feature above is enabled AND at least one API key present |
| `spiral.scheduling` | `scheduling_enabled: true` |

### Fresh Config Branch

When `idempotency_mode: false`:

**Step 3.1: Assemble YAML sections**

For each enabled feature, use the canonical template below. Assemble sections in YAML key order matching `.loa.config.yaml.example`.

**Config templates** (inline — do not reference external files):

`run_mode` (always included):
```yaml
run_mode:
  enabled: true
  defaults:
    max_cycles: 20
    timeout_hours: 8
  git:
    auto_push: true
    create_draft_pr: true
    base_branch: "main"
```

`flatline_protocol` (nice-to-have/medium budget):
```yaml
flatline_protocol:
  enabled: true
  auto_trigger: true
  phases:
    prd: true
    sdd: true
    sprint: true
  models:
    primary: opus
    secondary: gpt-5.3-codex
  thresholds:
    high_consensus: 700
    disputed_delta: 300
    blocker_skeptic: 700
  max_iterations: 5
  secret_scanning:
    enabled: true
```

`spiral` (fully-auto/unlimited budget):
```yaml
spiral:
  enabled: true
  default_max_cycles: 3
  budget_cents: 2000
  wall_clock_seconds: 28800
  harness:
    enabled: true
    pipeline_profile: standard
    executor_model: sonnet
    advisor_model: opus
```

`run_mode` HITL variant (workflow_pace = hitl):
```yaml
run_mode:
  enabled: true
  defaults:
    max_cycles: 5
    timeout_hours: 4
  git:
    auto_push: prompt
    create_draft_pr: true
    base_branch: "main"
```

`simstim` (semi-auto):
```yaml
simstim:
  enabled: true
  flatline:
    auto_accept_high_consensus: true
    show_disputed: true
    show_blockers: true
    phases:
      - prd
      - sdd
      - sprint
  defaults:
    timeout_hours: 24
```

`run_bridge` (depth 1 conservative default):
```yaml
run_bridge:
  enabled: true
  defaults:
    depth: 3
    per_sprint: false
    flatline_threshold: 0.05
    consecutive_flatline: 2
  github_trail:
    post_comments: true
    update_pr_body: true
```

`hounfour` (provider routing):
```yaml
hounfour:
  flatline_routing: true
  metering:
    enabled: true
    ledger_path: .run/cost-ledger.jsonl
    budget:
      daily_micro_usd: 50000000
      warn_at_percent: 80
      on_exceeded: downgrade
  providers:
    openai:
      auth: "{env:OPENAI_API_KEY}"
    google:
      auth: "{env:GOOGLE_API_KEY}"
```

`red_team` (standard):
```yaml
red_team:
  enabled: true
  mode: standard
  thresholds:
    confirmed_attack: 700
    theoretical: 400
    human_review_gate: 800
```

**CRITICAL**: Config templates use `{env:PROVIDER_API_KEY}` placeholders for auth values. NEVER substitute actual key values. The `{env:...}` syntax is resolved at runtime by Hounfour.

`spiral.budget_cents` default: 2000 ($20). Do NOT set to 0.
`hounfour.metering.budget.daily_micro_usd` default: 50000000 ($50/day). Do NOT set to 0.

**Step 3.2: Display pre-write summary**

Before writing, show:
```
Configuration Summary
═════════════════════
[ENABLED]  run_mode
[ENABLED]  flatline_protocol  (~$15–25 per planning cycle)
[ENABLED]  simstim            (~$25–65 per cycle)
[DISABLED] spiral
[DISABLED] red_team
[ENABLED]  hounfour           (metering: $50/day cap)
[DISABLED] run_bridge

Estimated monthly cost: ~$120–200 (8 planning cycles at moderate pace)

Write this configuration to .loa.config.yaml? (yes / no / show full YAML)
```

Show cost ranges only for features with estimated cost ≥$5/invocation.

**Step 3.3: YAML validation**

Before writing, validate the assembled YAML:

```bash
# Primary: yq
echo "$yaml" | yq '.' > /dev/null 2>&1

# Fallback if yq missing: jq structural check
echo "$yaml" | python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)" > /dev/null 2>&1
```

If both yq and jq/python3 are unavailable, warn the user:
```
⚠ YAML validation skipped — yq and jq are both unavailable.
  The generated configuration has not been validated.
  Write anyway? (yes / no)
```

Require explicit "yes" before writing if validation was skipped.

**Step 3.4: Write on confirmation**

Write the assembled YAML to `.loa.config.yaml` only when the user responds "yes". If "show full YAML", display the YAML and re-ask the confirmation question. If "no", exit without writing.

### Idempotency Branch

When `idempotency_mode: true` (existing config detected):

**Step 3.I.1**: Read `.loa.config.yaml` via Read tool.

**Step 3.I.2**: For each section the wizard would touch, parse the current value using `yq`:
```bash
yq eval '.flatline_protocol.enabled' .loa.config.yaml
```

**Step 3.I.3**: For each section where the wizard's proposed value differs from current, present a per-section diff:
```
Section `flatline_protocol`:
  Current:  enabled: false
  Proposed: enabled: true

Update this section? (yes / no / skip all)
```

Options:
- `yes` — apply the wizard's proposed value for this section
- `no` — preserve the current value, continue to next section
- `skip all` — preserve all remaining sections unchanged

**Step 3.I.4**: Merge the user's choices into the existing config. Validate the merged output via yq before writing. Write only on validation pass.

---

## Phase 4: Post-Config Explanation

After writing (or declining to write) the config, output:

### Summary Table

```
Feature Configuration Summary
══════════════════════════════
Feature              Status      Description
────────────────────────────────────────────────────────────
run_mode             ENABLED     Autonomous sprint execution
flatline_protocol    ENABLED     Multi-model adversarial planning review
simstim              ENABLED     HITL-accelerated development workflow
spiral               DISABLED    —
red_team             DISABLED    —
hounfour             ENABLED     Model routing and cost metering
run_bridge           DISABLED    —
```

### Next Step Recommendation

Based on `workflow_pace`:

- **HITL** → "Run `/loa` to see your current status, then `/run sprint-plan` when you have a plan ready."
- **Semi-auto** → "Run `/simstim` to start an HITL-accelerated development cycle."
- **Fully auto** → "Run `/run sprint-plan` to start an autonomous development cycle."

Always append: "For the full configuration reference, see `docs/CONFIG_REFERENCE.md`"

---

## Error Handling

### `loa-setup-check.sh` not found

**Condition**: `.claude/scripts/loa-setup-check.sh` does not exist or exits non-zero with a missing-file error.

**Response**: Report the error clearly. Skip Phase 1 script output. Ask the API key questions manually in Phase 2 by adding: "Which API keys do you have configured? (Anthropic / OpenAI / Google / None)" before Q1. Proceed with Phase 2 using manually-provided answers.

**Recovery path**: Continue to Phase 2 with `beads_installed: false`, `yq_installed: unknown`, `config_exists: false` (conservative defaults).

### No API keys detected

**Condition**: All three key checks (`anthropic_key_present`, `openai_key_present`, `google_key_present`) return false.

**Response**: Warn the user:
```
⚠ No API keys detected. Multi-model features (Flatline Protocol, Simstim,
  Spiral full profile) require at least ANTHROPIC_API_KEY.
  These features will be excluded from the generated configuration.
  You can enable them manually after setting up your API keys.
```

**Recovery path**: Disable multi-model feature recommendations. Set `multi_model_confirmed: false`. Continue to Q1 with `budget_tier` defaulting to `minimal` unless the user specifies otherwise.

### YAML parse error on generated config

**Condition**: yq or jq returns a parse error on the assembled YAML.

**Response**: Report the error with the line number if available:
```
✗ YAML validation failed:
  Error at line 14: unexpected mapping key
  
  The generated configuration is invalid and has not been written.
  Would you like to re-generate the configuration? (yes / no)
```

**Recovery path**: If "yes", re-run Phase 3 from Step 3.1 with the same Q1–Q6 answers. Do NOT write the invalid YAML.

### User declines all questions

**Condition**: User responds "no" or declines to answer all questions without completing the questionnaire.

**Response**: Do not write any configuration file. Show:
```
No configuration written. You can configure Loa manually by:
  1. Copying sections from .loa.config.yaml.example to .loa.config.yaml
  2. Reading the full reference at docs/CONFIG_REFERENCE.md
  3. Running /loa setup again when ready
```

**Recovery path**: Exit gracefully. Do not show an error — declining is a valid user choice.
