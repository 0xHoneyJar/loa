---
name: rtfm
description: Run documentation-driven testing against Ground Truth and protocols
role: review
allowed-tools: Read, Grep, Glob, Bash(bats tests/*), Bash(npm test *), Bash(.claude/scripts/rtfm-*)
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: false
  execute_commands:
    allowed:
      - command: "bats"
        args: ["tests/*"]
      - command: "npm"
        args: ["test", "*"]
    deny_raw_shell: true
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
parallel_threshold: 3000
timeout_minutes: 15
zones:
  system:
    path: .claude
    permission: none
  state:
    paths: [grimoires/loa]
    permission: read-write
  app:
    paths: [src, lib, app]
    permission: none
---

# RTFM Testing Skill

<objective>
Spawn a zero-context agent to test documentation usability. The tester operates under strict "no inference" rules and reports every gap it encounters. Parse the structured gap report, determine a verdict, and write results to the RTFM report directory.

This is a hermetic documentation test — the agent equivalent of a hermetic build. No implicit dependencies, no ambient state. If the zero-context agent can't follow the docs, the docs have gaps.
</objective>

The documentation paths checked always include `docs/` (`docs/CONFIG_REFERENCE.md` and its siblings are first-class documentation artifacts) alongside any other paths in scope.

<zone_constraints>
Orchestrator (the agent executing this skill):
- READ: Documentation files specified by user (any path)
- READ: This SKILL.md and index.yaml (loaded by framework)
- WRITE: grimoires/loa/a2a/rtfm/ (reports and baselines)

Tester subagent (the zero-context agent spawned via Task tool):
- READ: Only the bundled documentation provided in the prompt
- WRITE: None (output returned as text response, not file writes)
- NEVER: .claude/ (system zone), source code, grimoire state, parent conversation
</zone_constraints>

<tester_capabilities_manifest>
## Capabilities Manifest

The tester agent's "knowledge floor" — what it knows and doesn't know.
This defines the hermetic base image for documentation testing.

```yaml
knows:
  - terminal/shell basics (cd, ls, mkdir, cat, echo)
  - git basics (clone, commit, push, pull, checkout)
  - package managers exist (npm, pip, cargo) but NOT which one to use for any given project
  - environment variables concept (export, .env files exist)
  - text editor usage (nano, vim, or any editor)
  - GitHub web interface basics (repos, issues, PRs)
  - markdown file format
  - YAML file format basics
  - HTTP/HTTPS concept
  - file permissions basics (chmod)

does_not_know:
  - Claude Code (what it is, how it works, how to install it)
  - Loa (any concept: grimoires, beads, skills, slash commands, golden path)
  - .claude/ directory conventions
  - YAML configuration patterns for AI tools
  - Anthropic API or any LLM API
  - what "slash commands" are in an AI agent context
  - what "mounting a framework" means
  - what "grimoires" or "beads" or "constructs" mean
  - what a "sprint plan" or "PRD" or "SDD" is in this context
  - any prior knowledge about the specific project being documented
```
</tester_capabilities_manifest>

<planted_canary>
## Planted Canary — Deterministic Context Isolation Verification

The self-report canary (Layer 1) asks the tester to honestly report whether it recognizes the project. This is suggestive but unfalsifiable — LLMs cannot reliably introspect on knowledge provenance.

The planted canary (Layer 2) provides deterministic verification by injecting a fictitious project name into the doc bundle and checking whether the tester uses it.

### How It Works

1. During Phase 1 (Document Bundling), prepend a planted header to the bundle:
   ```
   === PROJECT CONTEXT ===
   Project Name: {planted_name}
   === END PROJECT CONTEXT ===
   ```
2. The planted name is a randomly generated plausible name (e.g., "Nexus", "Anvil", "Stratum") that does NOT match the real project name.
3. During Phase 3 (Gap Parsing), check the tester's Canary Check section:
   - If tester uses the planted name → **PASS (planted)**: isolation verified mechanically
   - If tester uses the real project name (not the planted one) → **FAIL (planted)**: prior knowledge leaked
   - If tester says "Not stated in documentation" despite planted name being present → **DEGRADED**: tester may not have read the context header

### Planted Name Generation

Use a simple rotation to avoid reusing names across iterations:

```yaml
planted_names:
  - "Nexus"
  - "Anvil"
  - "Stratum"
  - "Conduit"
  - "Lattice"
  - "Forge"
  - "Meridian"
  - "Trellis"
```

Select by: `planted_names[iteration_number % length]`

Combined-result table: Canary Validation in the gap parser below. Limits: a planted name can coincide with a real project in training data, and Layer 2 catches name-level leakage only, not concept-level (knowing what "grimoires" means).
</planted_canary>

<tester_prompt>
## Cleanroom Tester Prompt

Assembled and sent verbatim to the Task subagent ({braces} resolve at runtime): `resources/cleanroom-prompt.md` — the complete prompt, including the required output format and the `TASK: {task}` / `DOCUMENTATION: {bundled_docs}` blocks.
</tester_prompt>

<task_templates>
## Task Templates

Pre-built tasks for common documentation testing scenarios.

```yaml
templates:
  install:
    task: "Install this tool on a fresh repository following only the documentation below. Start from a clean directory. Report every step you take and every point where the documentation fails you."
    docs: ["INSTALLATION.md"]

  quickstart:
    task: "Follow the quick start guide to set up and use this tool for the first time. Report every step and every gap you encounter."
    docs: ["README.md"]

  mount:
    task: "Install this framework onto an existing project repository following only the documentation below. Assume you have an existing git repo with some code in it."
    docs: ["README.md", "INSTALLATION.md"]

  beads:
    task: "Set up the task tracking tool mentioned in the documentation following only the instructions below."
    docs: ["INSTALLATION.md"]

  gpt-review:
    task: "Configure the cross-model review feature mentioned in the documentation following only the instructions below."
    docs: ["INSTALLATION.md"]

  update:
    task: "Update this framework to the latest version following only the documentation below."
    docs: ["INSTALLATION.md"]
```

### Default Task Inference

When no --task or --template is provided, infer from the primary doc filename:
- README.md → quickstart template
- INSTALLATION.md → install template
- PROCESS.md → "Follow this process documentation to understand and execute the described workflow."
- Any other → "Follow this documentation to accomplish its stated purpose. Report every gap you find."
</task_templates>

<gap_parser>
## Gap Parser

After receiving the tester's response, parse the structured output:

### Extraction

1. Find all `[GAP]` markers in the response (match both `[GAP]` and `**[GAP]**` bold variants)
2. For each gap, extract the fields:
   - Type: the word after `[GAP]` (e.g., MISSING_STEP). If type is not in the 6 canonical types, map to closest match or use UNCLEAR as fallback.
   - Location: text after "Location:"
   - Problem: text after "Problem:"
   - Impact: text after "Impact:"
   - Severity: text after "Severity:" — normalize using severity mapping below
   - Suggestion: text after "Suggestion:"

### Severity Normalization

Map non-canonical severity names to the 3 canonical levels:

| Tester Wrote | Normalize To |
|-------------|-------------|
| BLOCKING, Critical, High, Showstopper | BLOCKING |
| DEGRADED, Medium, Moderate, Warning | DEGRADED |
| MINOR, Low, Info, Informational, Cosmetic | MINOR |

If severity is missing or unrecognizable, default to DEGRADED (conservative: not blocking but not ignored).

### Counting

- total_gaps: count of all [GAP] markers (including normalized variants)
- blocking: count where normalized severity = BLOCKING
- degraded: count where normalized severity = DEGRADED
- minor: count where normalized severity = MINOR

### Verdict Determination

| Condition | Verdict |
|-----------|---------|
| 0 BLOCKING gaps | SUCCESS |
| >0 BLOCKING gaps but tester made partial progress | PARTIAL |
| Tester could not start the task or gave up early | FAILURE |
| Response non-empty but no parseable [GAP] markers or ## Result section | MANUAL_REVIEW |
| Response empty or clearly malformed | Retry once, then MANUAL_REVIEW |

### Fallback Parsing

If the response contains no parseable `[GAP]` markers, escalate through these steps:

1. **Check for ## Result section**: If the response has `## Result` with SUCCESS and no gap markers, treat as valid SUCCESS (tester found no gaps).
2. **Check for prose gaps**: If the response describes problems but not in `[GAP]` format, set verdict to `MANUAL_REVIEW`. Write the raw tester output to the report verbatim under a "## Raw Tester Output (unparsed)" section.
3. **Retry on empty**: If the response is empty or under 100 characters, retry the tester spawn once with the same prompt. If the retry also fails, set verdict to `MANUAL_REVIEW`.
4. **Report indicator**: When fallback parsing is used, add `**Parsing**: Fallback (see raw output)` to the report header alongside Canary status.

### Canary Validation

#### Layer 1: Self-Report Check

Check the "## Canary Check" section for the tester's self-report:
- If tester says "I recognize this from prior knowledge" → Layer 1: WARNING
- If tester identifies the project only from docs → Layer 1: PASS
- If tester says "Not stated in documentation" → Layer 1: PASS (docs incomplete)

#### Layer 2: Planted Name Check

Check if the tester referenced the planted name or the real project name:
- If tester uses the planted name from the PROJECT CONTEXT header → Layer 2: PASS
- If tester uses the real project name instead of the planted one → Layer 2: FAIL
- If tester says neither name → Layer 2: INCONCLUSIVE

#### Combined Result

| Layer 1 | Layer 2 | Report As |
|---------|---------|-----------|
| PASS | PASS | **PASS** |
| PASS | FAIL | **COMPROMISED** — self-report unreliable |
| WARNING | PASS | **WARNING** — honest self-report, isolation held |
| WARNING | FAIL | **COMPROMISED** — confirmed leak |
| Any | INCONCLUSIVE | Use Layer 1 result only |

Log combined canary result in report.
</gap_parser>

<report_template>
## Report Template

Write to: `grimoires/loa/a2a/rtfm/report-{YYYY-MM-DD}.md`

If a report for today already exists, append a counter: `report-{YYYY-MM-DD}-2.md`

```markdown
# RTFM Report: {doc_files}

**Task**: {task_description}
**Model**: {model}
**Date**: {date}
**Iteration**: {iteration_number}
**Canary**: {PASS | WARNING | COMPROMISED}
**Parsing**: {Structured | Fallback (see raw output)}

## Verdict: {SUCCESS | PARTIAL | FAILURE | MANUAL_REVIEW}

| Metric | Value |
|--------|-------|
| Total Gaps | {total_gaps} |
| Blocking | {blocking} |
| Degraded | {degraded} |
| Minor | {minor} |
| Cold Start Score | {blocking} |

## Gap Summary

| # | Type | Severity | Location | Problem |
|---|------|----------|----------|---------|
{for each gap: | N | type | severity | location | problem |}

## Detailed Gaps

{full [GAP] reports from tester, verbatim}

## Tester Execution Log

{execution log from tester, verbatim}

## Iteration History

| Iteration | Gaps | Blocking | Result | Date |
|-----------|------|----------|--------|------|
{for each iteration: | N | total | blocking | verdict | date |}
```
</report_template>

<workflow>
## Workflow

### Phase 0: Argument Resolution

1. Parse ARGUMENTS string for:
   - Positional file paths (e.g., README.md INSTALLATION.md)
   - `--task "custom task description"`
   - `--template install|quickstart|mount|beads|gpt-review|update`
   - `--auto` flag (detect changed docs in sprint)
   - `--model sonnet|haiku` (default: sonnet)

2. Resolve docs and task:
   - If `--template` provided: look up in task_templates, get task + docs
   - If `--auto`: run `git diff main...HEAD --name-only` and filter for .md files matching known doc patterns (README.md, INSTALLATION.md, PROCESS.md, docs/**/*.md)
   - If positional args: use as doc file paths
   - If `--task` provided: use as task description
   - If no task: infer from primary doc filename using default inference rules

3. Validate:
   - All doc files exist and are readable
   - At least one doc file specified
   - Report estimated bundle size to user (sum of doc file sizes + ~200 bytes per file for headers)

4. Size pre-flight: display the estimate before bundling, e.g. `Estimated bundle size: 73KB (exceeds 50KB standard tier — per-doc testing will be offered)`.

### Phase 1: Document Bundling

1. Read each doc file
2. Select planted canary name: `planted_names[iteration_number % length]`
3. Prepend planted context header to bundle:
   ```
   === PROJECT CONTEXT ===
   Project Name: {planted_name}
   === END PROJECT CONTEXT ===
   ```
4. Concatenate doc files with clear headers:
   ```
   === FILE: README.md ===

   {contents of README.md}

   === END FILE: README.md ===
   ```
5. Calculate total bundle size and apply tiered handling:

#### Size Limit Tiers

| Tier | Bundle Size | Behavior |
|------|------------|----------|
| Standard | Under 50KB | Bundle all docs, single tester run (default) |
| Large | 50KB–100KB | Warn user. Offer choice: (a) test each doc individually, or (b) proceed with bundled test (may degrade tester quality due to context pressure) |
| Oversized | Over 100KB | Reject with actionable guidance: split docs, use `--task` to focus on specific sections, or use `--template` for targeted testing |

The 50KB threshold is configurable via `.loa.config.yaml` (`rtfm.max_doc_size_kb`, default: 50). The 100KB hard limit is 2x the configured threshold.

### Phase 2: Tester Spawn

1. Assemble the full prompt:
   - Tester prompt (from <tester_prompt> section above)
   - Replace `{task}` with resolved task
   - Replace `{bundled_docs}` with bundled doc contents
2. Spawn the tester:
   ```
   Task(
     prompt = assembled_prompt,
     subagent_type = "general-purpose",
     model = resolved_model
   )
   ```
3. Wait for response

### Phase 3: Gap Parsing

1. Parse tester response using gap_parser rules
2. Extract all [GAP] blocks
3. Count by type and severity
4. Determine verdict
5. Validate canary check

### Phase 4: Report & Display

1. Create `grimoires/loa/a2a/rtfm/` directory if not exists
2. Write report using report_template
3. Display summary to user:

```
RTFM Test Results
═══════════════════════════════════════
Docs:     {doc files}
Task:     {task}
Model:    {model}
Canary:   {PASS/WARNING}

Verdict:  {SUCCESS/PARTIAL/FAILURE}

Gaps Found: {total} ({blocking} blocking, {degraded} degraded, {minor} minor)

{if FAILURE or PARTIAL:}
Fix the gaps above and run /rtfm again to retest.
Cold Start Score: {blocking} (target: 0)
{end if}

{if SUCCESS:}
RTFM CERTIFIED — documentation passes zero-context usability test.
{end if}

Report: grimoires/loa/a2a/rtfm/report-{date}.md
```
</workflow>
