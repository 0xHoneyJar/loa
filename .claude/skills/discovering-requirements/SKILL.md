---
parallel_threshold: 2000
timeout_minutes: 90
zones:
  system:
    path: .claude
    permission: none
  state:
    paths: [grimoires/loa, .beads]
    permission: read-write
  app:
    paths: [src, lib, app]
    permission: read
---

<prompt_enhancement_prelude>
## Invisible Prompt Enhancement

Before executing main skill logic, apply automatic prompt enhancement to user's request.

### Step 1: Check Configuration

Read `.loa.config.yaml` invisible_mode setting:
```yaml
prompt_enhancement:
  invisible_mode:
    enabled: true|false
```

If `prompt_enhancement.invisible_mode.enabled: false` (or not set), skip to main skill logic with original prompt.

### Step 2: Check Command Opt-Out

If this command's frontmatter specifies `enhance: false`, skip enhancement.

### Step 3: Analyze Prompt Quality (PTCF Framework)

Analyze the user's prompt for PTCF components:

| Component | Detection Patterns | Weight |
|-----------|-------------------|--------|
| **Persona** | "act as", "you are", "as a", "pretend", "assume the role" | 2 |
| **Task** | create, review, analyze, fix, summarize, write, debug, refactor, build, implement, design | 3 |
| **Context** | @mentions, file references (.ts, .js, .py), "given that", "based on", "from the", "in the" | 3 |
| **Format** | "as bullets", "in JSON", "formatted as", "limit to", "step by step", "as a table" | 2 |

Calculate score (0-10):
- Task verb present: +3
- Context present: +3
- Format specified: +2
- Persona defined: +2

### Step 4: Enhance If Needed

If score < `prompt_enhancement.auto_enhance_threshold` (default 4):

1. **Classify task type**: debugging, code_review, refactoring, summarization, research, generation, general
2. **Load template** from `.claude/skills/enhancing-prompts/resources/templates/{task_type}.yaml`
3. **Apply template**:
   - Prepend persona if missing
   - Append format if missing
   - Add constraints
   - PRESERVE original text completely

### Step 5: Log to Trajectory (Silent)

Write to `grimoires/loa/a2a/trajectory/prompt-enhancement-{date}.jsonl`:
```json
{
  "type": "prompt_enhancement",
  "timestamp": "ISO8601",
  "command": "plan-and-analyze",
  "action": "ENHANCED|SKIP|DISABLED|OPT_OUT|ERROR",
  "original_score": N,
  "enhanced_score": N,
  "components_added": ["persona", "format"],
  "task_type": "generation",
  "latency_ms": N
}
```

### Step 6: Continue with Prompt

Use the (potentially enhanced) prompt for main skill execution.

**CRITICAL**: Never show enhancement output to user. All analysis is internal only.

### Error Handling

On ANY error during enhancement:
- Log `action: "ERROR"` to trajectory
- Use original prompt unchanged (silent passthrough)
- Continue with main skill execution
</prompt_enhancement_prelude>

<interview_config>
## Interview Depth Configuration

### Config Reading

```bash
interview_mode=$(yq eval '.interview.mode // "thorough"' .loa.config.yaml 2>/dev/null || echo "thorough")
skill_mode=$(yq eval '.interview.per_skill.discovering-requirements // ""' .loa.config.yaml 2>/dev/null || echo "")
[[ -n "$skill_mode" ]] && interview_mode="$skill_mode"

pacing=$(yq eval '.interview.pacing // "sequential"' .loa.config.yaml 2>/dev/null || echo "sequential")
discovery_style=$(yq eval '.interview.input_style.discovery_questions // "plain"' .loa.config.yaml 2>/dev/null || echo "plain")
routing_style=$(yq eval '.interview.input_style.routing_gates // "structured"' .loa.config.yaml 2>/dev/null || echo "structured")
confirmation_style=$(yq eval '.interview.input_style.confirmation // "structured"' .loa.config.yaml 2>/dev/null || echo "structured")
no_infer=$(yq eval '.interview.backpressure.no_infer // true' .loa.config.yaml 2>/dev/null || echo "true")
show_work=$(yq eval '.interview.backpressure.show_work // true' .loa.config.yaml 2>/dev/null || echo "true")
gate_between=$(yq eval '.interview.phase_gates.between_phases // true' .loa.config.yaml 2>/dev/null || echo "true")
gate_before_gen=$(yq eval '.interview.phase_gates.before_generation // true' .loa.config.yaml 2>/dev/null || echo "true")
min_confirm=$(yq eval '.interview.backpressure.min_confirmation_questions // 1' .loa.config.yaml 2>/dev/null || echo "1")
```

### Mode Behavior Table

| Mode | Questions/Phase | Pacing | Phase Gates | Gap Skipping |
|------|----------------|--------|-------------|--------------|
| `thorough` | 3-6 (scales down with context) | sequential | All ON | Suppressed: always ask `min_confirm` questions |
| `minimal` | 1-2 | batch | `before_generation` only | Active: skip covered phases |

### Input Style Resolution

| Interaction Type | `structured` | `plain` |
|-----------------|-------------|---------|
| Routing gates | AskUserQuestion with options | "Continue, go back, or skip ahead?" |
| Discovery questions | AskUserQuestion with suggested answers | Markdown question, user responds freely |
| Confirmations | AskUserQuestion (Yes/Correct/Adjust) | "Is this accurate? [yes/corrections]" |

### Question Pacing

| Pacing | Behavior |
|--------|----------|
| `sequential` | Ask ONE question per turn. Wait for response. Then ask the next. |
| `batch` | Present 3-6 numbered questions. User responds to all at once. |

### Backpressure Protocol (CRITICAL)

When `no_infer` is true (DEFAULT):

**PROHIBITED:**
- DO NOT answer your own questions
- DO NOT proceed without explicit user input
- DO NOT write "Based on common patterns..." or "Typically..." for requirements — that is inference. ASK.
- DO NOT combine multiple phases into one response
- DO NOT generate the output document in the same response as the last question
- DO NOT skip phases because "the context seems sufficient"

**REQUIRED:**
- WAIT for user response after every question
- Before asking, state: (1) What you KNOW (cited), (2) What you DON'T KNOW, (3) Why it matters
- SEPARATE phases into distinct conversation turns
- Enumerate assumptions with [ASSUMPTION] tags before proceeding

### Construct Override (Future — RFC #379)

Schema supports future construct manifest override:
```json
{ "workflow": { "interview": { "mode": "minimal", "trust_tier": "BACKTESTED" } } }
```
Precedence: Construct (if trust >= BACKTESTED) > per_skill config > global mode > default (thorough).
**Not wired yet.** Extension point documented here for forward compatibility.
</interview_config>

# Discovering Requirements

<objective>
Synthesize existing project documentation and conduct targeted discovery
interviews to produce a comprehensive PRD at `grimoires/loa/prd.md`.
</objective>

<persona>
**Role**: Senior Product Manager | 15 years | Enterprise & Startup | User-Centered Design
**Approach**: Read first, ask second. Demonstrate understanding before requesting input.

**Lore Integration**: When framing requirements, reference relevant archetypes from `.claude/data/lore/` to ground the project's philosophical context. Use `short` fields for inline naming explanations (e.g., why a feature is called "bridge" or "vision"). Use `context` fields when a requirement discussion benefits from deeper framing — for instance, connecting iterative refinement patterns to kaironic time concepts. Only reference lore when contextually appropriate; never force philosophical connections.
</persona>

<zone_constraints>
## Zone Constraints

This skill operates under **Managed Scaffolding**:

| Zone | Permission | Notes |
|------|------------|-------|
| `.claude/` | NONE | System zone - never suggest edits |
| `grimoires/loa/`, `.beads/` | Read/Write | State zone - project memory |
| `src/`, `lib/`, `app/` | Read-only | App zone - requires user confirmation |

**NEVER** suggest modifications to `.claude/`. Direct users to `.claude/overrides/` or `.loa.config.yaml`.

Agents MAY proactively run read-only CLI tools (e.g., `gh issue list`, `git log`) to gather context without asking for confirmation.
</zone_constraints>

<integrity_precheck>
## Integrity Pre-Check (MANDATORY)

Before ANY operation, verify System Zone integrity:

1. Check config: `yq eval '.integrity_enforcement' .loa.config.yaml`
2. If `strict` and drift detected -> **HALT** and report
3. If `warn` -> Log warning and proceed with caution
</integrity_precheck>

<factual_grounding>
## Factual Grounding (MANDATORY)

Before ANY synthesis, planning, or recommendation:

1. **Extract quotes**: Pull word-for-word text from source files
2. **Cite explicitly**: `"[exact quote]" (file.md:L45)`
3. **Flag assumptions**: Prefix ungrounded claims with `[ASSUMPTION]`

**Grounded Example:**
```
The SDD specifies "PostgreSQL 15 with pgvector extension" (sdd.md:L123)
```

**Ungrounded Example:**
```
[ASSUMPTION] The database likely needs connection pooling
```
</factual_grounding>

<structured_memory_protocol>
## Structured Memory Protocol

### On Session Start
1. Read `grimoires/loa/NOTES.md`
2. Restore context from "Session Continuity" section
3. Check for resolved blockers

### During Execution
1. Log decisions to "Decision Log"
2. Add discovered issues to "Technical Debt"
3. Update sub-goal status
4. **Apply Tool Result Clearing** after each tool-heavy operation

### Before Compaction / Session End
1. Summarize session in "Session Continuity"
2. Ensure all blockers documented
3. Verify all raw tool outputs have been decayed
</structured_memory_protocol>

<tool_result_clearing>
## Tool Result Clearing

After tool-heavy operations (grep, cat, tree, API calls):
1. **Synthesize**: Extract key info to NOTES.md or discovery/
2. **Summarize**: Replace raw output with one-line summary
3. **Clear**: Release raw data from active reasoning

Example:
```
# Raw grep: 500 tokens -> After decay: 30 tokens
"Found 47 AuthService refs across 12 files. Key locations in NOTES.md."
```
</tool_result_clearing>

<attention_budget>
## Attention Budget

This skill follows the **Tool Result Clearing Protocol** (`.claude/protocols/tool-result-clearing.md`).

### Token Thresholds

| Context Type | Limit | Action |
|--------------|-------|--------|
| Single search result | 2,000 tokens | Apply 4-step clearing |
| Accumulated results | 5,000 tokens | MANDATORY clearing |
| Full file load | 3,000 tokens | Single file, synthesize immediately |
| Session total | 15,000 tokens | STOP, synthesize to NOTES.md |

### Clearing Triggers for Discovery

- [ ] Document search returning >10 files
- [ ] Code analysis returning >20 matches
- [ ] Any API/tool output >2K tokens

### 4-Step Clearing

1. **Extract**: Max 10 files, 20 words per finding
2. **Synthesize**: Write to `grimoires/loa/NOTES.md`
3. **Clear**: Remove raw output from context
4. **Summary**: `"Discovery: N sources → M requirements → NOTES.md"`
</attention_budget>

<trajectory_logging>
## Trajectory Logging

Log each significant step to `grimoires/loa/a2a/trajectory/{agent}-{date}.jsonl`:

```json
{"timestamp": "...", "agent": "...", "action": "...", "reasoning": "...", "grounding": {...}}
```
</trajectory_logging>

<kernel_framework>
## Task
Produce comprehensive PRD by:
1. Ingesting all context from `grimoires/loa/context/`
2. Mapping existing information to 7 discovery phases
3. Conducting targeted interviews for gaps only
4. Generating PRD with full traceability to sources

## Context
- **Input**: `grimoires/loa/context/*.md` (optional), developer interview
- **Output**: `grimoires/loa/prd.md`
- **Integration**: `grimoires/loa/a2a/integration-context.md` (if exists)

## Constraints
- DO NOT ask questions answerable from provided context
- DO cite sources: `> From vision.md:12: "exact quote"`
- DO present understanding for confirmation before proceeding
- DO ask for clarification on contradictions, not assumptions
- DO limit questions to the configured range per phase (thorough: 3-6, minimal: 1-2)
- DO ask at least {min_confirm} confirmation question(s) per phase, even if context covers it
- DO NOT infer answers to questions you have not asked
- When pacing is "sequential": ask ONE question, wait for response, then ask the next
- When pacing is "batch": present questions as a numbered list

## Verification
PRD traces every requirement to either:
- Source document (file:line citation)
- Interview response (phase:question reference)
</kernel_framework>

<codebase_grounding>
## Phase -0.5: Codebase Grounding (Brownfield Only)

**Purpose**: Ground PRD creation in codebase reality to prevent hallucinated requirements.

### Configuration

Read configuration from `.loa.config.yaml` (with defaults):

```bash
# Check if codebase grounding is enabled (default: true)
enabled=$(yq eval '.plan_and_analyze.codebase_grounding.enabled // true' .loa.config.yaml 2>/dev/null || echo "true")

# Get staleness threshold in days (default: 7)
staleness_days=$(yq eval '.plan_and_analyze.codebase_grounding.reality_staleness_days // 7' .loa.config.yaml 2>/dev/null || echo "7")

# Get /ride timeout in minutes (default: 20)
timeout_minutes=$(yq eval '.plan_and_analyze.codebase_grounding.ride_timeout_minutes // 20' .loa.config.yaml 2>/dev/null || echo "20")

# Get skip-on-error behavior (default: false)
skip_on_error=$(yq eval '.plan_and_analyze.codebase_grounding.skip_on_ride_error // false' .loa.config.yaml 2>/dev/null || echo "false")
```

If `enabled: false`, skip Phase -0.5 entirely (equivalent to GREENFIELD behavior).

### Decision Tree

When `/plan-and-analyze` runs, check the `codebase_detection` pre-flight result:

```
IF config.enabled == false:
    → Skip to Phase -1 (feature disabled)
    → Do NOT mention codebase grounding to user

ELSE IF codebase_detection.type == "GREENFIELD":
    → Skip to Phase -1 (no codebase to analyze)
    → Do NOT mention codebase grounding to user

ELSE IF codebase_detection.type == "BROWNFIELD":
    IF codebase_detection.reality_exists == true:
        IF codebase_detection.reality_age_days < config.staleness_days:
            → Use cached reality (no /ride needed)
            → Show: "Using recent codebase analysis (N days old)"
        ELSE IF --fresh flag provided:
            → Run /ride regardless of cache
        ELSE:
            → Prompt user with AskUserQuestion:
              - "Re-run /ride for fresh analysis (recommended)"
              - "Proceed with existing analysis (faster)"
    ELSE:
        → Present recommendation via AskUserQuestion:
          questions:
            - question: "This is a brownfield project with no codebase reality files. How would you like to proceed?"
              header: "Grounding"
              options:
                - label: "Run /ride (Recommended)"
                  description: "Analyze codebase first to ground PRD in code reality"
                - label: "Run /ride --enriched"
                  description: "Full analysis with gap tracking, decision archaeology, and terminology extraction"
                - label: "Skip grounding"
                  description: "Proceed without codebase analysis (not recommended for brownfield)"
              multiSelect: false
        → If "Run /ride": invoke ride skill (standard mode)
        → If "Run /ride --enriched": invoke ride skill with --enriched flag
        → If "Skip grounding":
            - Log warning to NOTES.md blockers:
              "- [ ] [BLOCKER] PRD created without codebase grounding — user skipped /ride for brownfield project"
            - Proceed to Phase -1 without reality context
            - Add warning banner to generated PRD
```

### Running /ride

Invoke the ride skill (NOT the command) for codebase analysis:

```markdown
CODEBASE GROUNDING PHASE

Analyzing your existing codebase to ground PRD requirements in reality.
This typically takes 5-15 minutes depending on codebase size.

Progress:
- [ ] Extracting component inventory
- [ ] Analyzing architecture patterns
- [ ] Identifying existing requirements
- [ ] Building consistency report
```

### /ride Execution

Use the Skill tool to invoke ride:
```
Skill: ride
```

This will produce:
- `grimoires/loa/reality/extracted-prd.md`
- `grimoires/loa/reality/extracted-sdd.md`
- `grimoires/loa/reality/component-inventory.md`
- `grimoires/loa/consistency-report.md`

### Error Recovery

If /ride fails or times out:

1. **Capture error** in NOTES.md Decision Log:
   ```markdown
   | Date | Decision | Rationale | Source |
   |------|----------|-----------|--------|
   | YYYY-MM-DD | /ride failed during codebase grounding | [error message] | Phase -0.5 |
   ```

2. **Check config for auto-skip**:
   ```bash
   skip_on_error=$(yq eval '.plan_and_analyze.codebase_grounding.skip_on_ride_error // false' .loa.config.yaml)
   ```
   If `skip_on_error: true`, automatically skip to Phase -1 with warning.

3. **Otherwise prompt user** with AskUserQuestion:
   ```yaml
   questions:
     - question: "/ride analysis failed. How would you like to proceed?"
       header: "Recovery"
       options:
         - label: "Retry /ride analysis"
           description: "Re-run codebase analysis (recommended)"
         - label: "Skip codebase grounding"
           description: "Proceed without code-based requirements (not recommended)"
         - label: "Abort"
           description: "Cancel /plan-and-analyze entirely"
       multiSelect: false
   ```

4. **Handle user response**:

   **If "Retry"**:
   - Re-run /ride with fresh attempt
   - If fails again, return to step 3 (max 2 retries)

   **If "Skip"**:
   - Log warning to NOTES.md blockers:
     ```markdown
     - [ ] [BLOCKER] PRD created without codebase grounding - /ride failed: [error]
     ```
   - Proceed to Phase -1 without reality context
   - Add warning banner to generated PRD:
     ```markdown
     > ⚠️ **WARNING**: This PRD was created without codebase grounding.
     > Run `/ride` and `/plan-and-analyze --fresh` for accurate requirements.
     ```

   **If "Abort"**:
   - Log abort decision to trajectory
   - Exit cleanly with message: "Aborting /plan-and-analyze. Run /ride manually and retry."

5. **Preserve partial results** if available:
   - If /ride produced any output files before failing, keep them
   - Use whatever reality context exists for Phase 0

### Timeout Handling

Default timeout: 20 minutes (configurable in `.loa.config.yaml`)

```yaml
plan_and_analyze:
  codebase_grounding:
    ride_timeout_minutes: 20
```

### Greenfield Fast Path

For GREENFIELD projects:
- No progress message about codebase
- No delay
- Proceed directly to Phase -1
- Log detection result to trajectory only (not shown to user)
</codebase_grounding>

<workflow>
## Phase -1: Context Assessment

Run context assessment:
```bash
./.claude/scripts/assess-discovery-context.sh
```

| Result | Strategy |
|--------|----------|
| `NO_CONTEXT_DIR` | Create directory, offer guidance, proceed to full interview |
| `EMPTY` | Proceed to full 7-phase interview |
| `SMALL` (<500 lines) | Sequential ingestion, then targeted interview |
| `MEDIUM` (500-2000) | Sequential ingestion, then targeted interview |
| `LARGE` (>2000) | Parallel subagent ingestion, then targeted interview |

## Phase 0: Context Synthesis

### Context Priority Order

Load and synthesize context in priority order:

| Priority | Source | Citation Format | Trust Level |
|----------|--------|-----------------|-------------|
| 1 | `grimoires/loa/reality/` | `[CODE:file:line]` | Highest (code is truth) |
| 2 | `grimoires/loa/context/` | `> From file.md:line` | High (user-provided) |
| 3 | Interview responses | `(Phase N QN)` | Standard |

**Conflict Resolution**: When reality contradicts context:
- Reality wins (code is authoritative)
- Flag the conflict for user: "Note: [context claim] differs from codebase reality [CODE:file:line]"

### Step 0: Present Codebase Understanding (Brownfield Only)

**If reality files exist** (from /ride or cached):

```markdown
## What I've Learned From Your Codebase

Based on analysis of your existing code:

### Architecture
[CODE:src/index.ts:1-50] Your application uses [pattern] architecture with:
- [list key components with code references]

### Existing Features
From component inventory:
- Feature A [CODE:src/features/a.ts:10-45]
- Feature B [CODE:src/services/b.ts:1-100]

### Current State
From consistency report:
- [summary of code consistency findings]

### Proposed Additions
Based on codebase analysis, the following would integrate well:
- [suggested additions grounded in existing patterns]

---
```

### Step 1: Ingest All Context

Read in priority order:
1. `grimoires/loa/reality/*.md` (if exists)
2. `grimoires/loa/context/*.md` (and subdirectories)

### Step 2: Create Context Map
Internally categorize discovered information:

```xml
<context_map>
  <phase name="problem_vision">
    <reality source="extracted-prd.md:10-30">
      Implicit problem statement from codebase
    </reality>
    <found source="vision.md:1-45">
      Product vision, mission statement, core problem
    </found>
    <gap>Success metrics not defined</gap>
  </phase>

  <phase name="goals_metrics">
    <found source="vision.md:47-52">
      High-level goals mentioned
    </found>
    <gap>No quantifiable success criteria</gap>
    <gap>Timeline not specified</gap>
  </phase>

  <phase name="users_stakeholders">
    <found source="users.md:1-289">
      3 personas defined with jobs-to-be-done
    </found>
    <ambiguity>Persona priorities unclear - which is primary?</ambiguity>
  </phase>

  <phase name="functional_requirements">
    <reality source="component-inventory.md:1-200">
      Existing features extracted from code
    </reality>
    <found source="requirements.md:1-100">
      User-documented requirements
    </found>
    <conflict>User docs mention feature X, but not found in codebase</conflict>
  </phase>

  <!-- Continue for all 7 phases -->
</context_map>
```

### Step 3: Present Understanding

**For brownfield projects**, present codebase understanding FIRST:

```markdown
## What I've Learned From Your Codebase

I've analyzed your existing codebase (N files, X lines).

### Existing Architecture
[CODE:src/index.ts:1-50] Your application uses [pattern] with:
- Component A [CODE:src/components/a.tsx:10]
- Service B [CODE:src/services/b.ts:1]

### Implemented Features
Based on code analysis:
- User authentication [CODE:src/auth/index.ts:1-100]
- Data persistence [CODE:src/db/client.ts:1-50]

---

## What I've Learned From Your Documentation

I've reviewed N files (X lines) from your context directory.

### Problem & Vision
> From vision.md:12-15: "exact quote from document..."

I understand the core problem is [summary]. The vision is [summary].

### Users & Stakeholders
> From users.md:23-45: "description of personas..."

You've defined N personas: [list with 1-line each].

### Conflicts Noted
- [if any conflicts between reality and context]

### What I Still Need to Understand
1. **Success Metrics**: What quantifiable outcomes define success?
2. **Persona Priority**: Which user persona should we optimize for first?
3. **Timeline**: What are the key milestones and deadlines?

Should I proceed with these clarifying questions, or would you like to
correct my understanding first?
```

## Step 0.5: Vision Registry Loading (v1.42.0)

**Purpose**: Surface relevant captured visions from previous bridge reviews to inform planning.

### Check Configuration

```bash
vr_enabled=$(yq eval '.vision_registry.enabled // false' .loa.config.yaml 2>/dev/null || echo "false")
```

If `vision_registry.enabled` is `false` or absent: **skip this step entirely** — no mention to user, no code runs.

### Derive Work Context Tags

When enabled, derive tags from available context in priority order:

1. **Sprint file paths** (if `grimoires/loa/sprint.md` exists): Extract `**File**: \`...\`` patterns and map through `vision_extract_tags()` path-to-tag rules
2. **User request keywords**: Match against controlled vocabulary (`architecture`, `security`, `constraints`, `multi-model`, `testing`, `philosophy`, `orchestration`, `configuration`, `eventing`)
3. **PRD section headers** (if `grimoires/loa/prd.md` exists): Map headers to tags (e.g., "Security" → `security`)

Tags are deduplicated and sorted before matching.

### Query Vision Registry

```bash
visions=$(.claude/scripts/vision-registry-query.sh \
  --tags "$work_tags" \
  --status "$(yq eval '.vision_registry.status_filter | join(",")' .loa.config.yaml 2>/dev/null || echo 'Captured,Exploring')" \
  --min-overlap "$(yq eval '.vision_registry.min_tag_overlap // 2' .loa.config.yaml 2>/dev/null || echo '2')" \
  --max-results "$(yq eval '.vision_registry.max_visions_per_session // 3' .loa.config.yaml 2>/dev/null || echo '3')" \
  --include-text \
  --json)
```

### Route by Mode

**Shadow mode** (`vision_registry.shadow_mode: true`):

```bash
# Log silently — do NOT present to user
.claude/scripts/vision-registry-query.sh \
  --tags "$work_tags" \
  --shadow \
  --shadow-cycle "$(yq eval '.active_cycle' grimoires/loa/ledger.json 2>/dev/null)" \
  --shadow-phase "plan-and-analyze" \
  --json > /dev/null
```

- Results logged to `grimoires/loa/a2a/trajectory/vision-shadow-{date}.jsonl`
- Shadow cycle counter incremented in `grimoires/loa/visions/.shadow-state.json`
- If graduation ready (cycles >= threshold AND matches > 0), present graduation prompt (see Step 0.5b)

**Active mode** (`vision_registry.shadow_mode: false`):

Present matched visions to user using the template below, then process user decisions.

### Vision Presentation Template (Active Mode)

For each matched vision, present:

```markdown
---
### Relevant Vision: [title]
**Source**: [source field — e.g., "Bridge iteration 2, PR #100"]
**Relevance**: Matched on tags: [matched_tags joined by ", "]
**Score**: [score] (overlap: [overlap], references: [refs])

> [sanitized insight text — max 500 chars, from vision_sanitize_text()]

**What would you like to do with this vision?**
- **Explore**: Mark for deeper analysis — may inspire requirements
- **Defer**: Interesting but not relevant to current work
- **Skip**: Not useful
---
```

**IMPORTANT**: The relevance explanation is template-based (tag match + score), NOT LLM-generated. Do not fabricate a narrative about why the vision is relevant — state the matched tags and score.

### Process User Decisions

For each vision the user responds to:

| Choice | Action |
|--------|--------|
| **Explore** | Call `vision_update_status(vision_id, "Exploring", visions_dir)`. Record reference via `vision_record_ref()`. Log choice to trajectory JSONL. |
| **Defer** | Log choice to trajectory JSONL. No status change. |
| **Skip** | Log choice to trajectory JSONL. No status change. |

Log format (append to `grimoires/loa/a2a/trajectory/vision-decisions-{date}.jsonl`):
```json
{
  "timestamp": "ISO8601",
  "cycle": "cycle-NNN",
  "phase": "plan-and-analyze",
  "vision_id": "vision-NNN",
  "decision": "explore|defer|skip",
  "score": N,
  "matched_tags": ["tag1", "tag2"]
}
```

### Step 0.5b: Shadow Graduation Prompt

When the query script returns `graduation.ready: true`:

```markdown
## Vision Registry — Shadow Period Complete

Over **N shadow cycles**, **M visions** matched your work context.

The Vision Registry has been silently logging relevance matches during your
planning sessions. Here's what was found:

[summary of top matches from shadow logs]

**Would you like to:**
1. **Enable active mode** — Start seeing relevant visions during planning
2. **Adjust thresholds** — Change tag overlap or max results settings
3. **Keep shadow mode** — Continue silent logging for more data
4. **Disable** — Turn off vision registry entirely
```

On "Enable active mode": Update config via `yq eval '.vision_registry.shadow_mode = false' -i .loa.config.yaml`

---

## Phase 0.5: Targeted Interview

**For each gap/ambiguity identified:**

1. State what you know (with citation)
2. State what's missing or unclear
3. Ask focused questions (respect configured range and pacing)

**Example:**
```markdown
### Goals & Success Metrics

I found high-level goals in vision.md:
> "Achieve product-market fit within 12 months"

However, I didn't find specific success metrics.

**Questions:**
1. What metrics would indicate product-market fit for this product?
2. Are there intermediate milestones (3-month, 6-month)?
```

## Phases 1-7: Conditional Discovery

For each phase, follow this logic:

```
IF phase fully covered AND interview_mode == "minimal":
  → Summarize understanding with citations
  → Ask: "Is this accurate?" (1 confirmation, uses confirmation_style)
  → Move to next phase

ELSE IF phase fully covered AND interview_mode == "thorough":
  → Summarize understanding with citations
  → Ask at least {min_confirm} questions: "Is this accurate?" +
    "What am I missing about [specific aspect]?"
  → DO NOT skip. Context coverage does not exempt from confirmation.
  → Wait for response. Respect pacing setting.

ELSE IF phase partially covered:
  → Summarize what's known (with citations)
  → Ask about gaps (respect configured question range and pacing)

ELSE IF phase not covered:
  → Full discovery (respect configured question range and pacing)
  → Iterate until user confirms phase is complete
```

### Phase 1: Problem & Vision
- Core problem being solved
- Product vision and mission
- Why now? Why you?

#### Phase 1 Transition

When `gate_between` is true:
1. Summarize what was learned in this phase (3-5 bullets, cited)
2. State what carries forward to the next phase
3. Present transition:
   - If `routing_style` == "structured": Use AskUserQuestion:
     question: "Phase 1 complete. Ready for Phase 2: Goals & Success Metrics?"
     header: "Phase 1"
     options:
       - label: "Continue"
         description: "Move to Goals & Success Metrics"
       - label: "Go back"
         description: "Revisit this phase — I have corrections"
       - label: "Skip ahead"
         description: "Jump to PRD generation — enough context gathered"
   - If `routing_style` == "plain":
     "Phase 1: Problem & Vision complete. Moving to Phase 2: Goals & Success Metrics. Continue, go back, or skip ahead?"
4. WAIT for response. DO NOT auto-continue.

When `gate_between` is false:
One-line transition: "Moving to Phase 2: Goals & Success Metrics."

### Phase 2: Goals & Success Metrics
- Business objectives
- Quantifiable success criteria
- Timeline and milestones

#### Phase 2 Transition

When `gate_between` is true:
1. Summarize what was learned in this phase (3-5 bullets, cited)
2. State what carries forward to the next phase
3. Present transition:
   - If `routing_style` == "structured": Use AskUserQuestion:
     question: "Phase 2 complete. Ready for Phase 3: User & Stakeholder Context?"
     header: "Phase 2"
     options:
       - label: "Continue"
         description: "Move to User & Stakeholder Context"
       - label: "Go back"
         description: "Revisit this phase — I have corrections"
       - label: "Skip ahead"
         description: "Jump to PRD generation — enough context gathered"
   - If `routing_style` == "plain":
     "Phase 2: Goals & Success Metrics complete. Moving to Phase 3: User & Stakeholder Context. Continue, go back, or skip ahead?"
4. WAIT for response. DO NOT auto-continue.

When `gate_between` is false:
One-line transition: "Moving to Phase 3: User & Stakeholder Context."

### Phase 3: User & Stakeholder Context
- Primary and secondary personas
- User journey and pain points
- Stakeholder requirements

#### Phase 3 Transition

When `gate_between` is true:
1. Summarize what was learned in this phase (3-5 bullets, cited)
2. State what carries forward to the next phase
3. Present transition:
   - If `routing_style` == "structured": Use AskUserQuestion:
     question: "Phase 3 complete. Ready for Phase 4: Functional Requirements?"
     header: "Phase 3"
     options:
       - label: "Continue"
         description: "Move to Functional Requirements"
       - label: "Go back"
         description: "Revisit this phase — I have corrections"
       - label: "Skip ahead"
         description: "Jump to PRD generation — enough context gathered"
   - If `routing_style` == "plain":
     "Phase 3: User & Stakeholder Context complete. Moving to Phase 4: Functional Requirements. Continue, go back, or skip ahead?"
4. WAIT for response. DO NOT auto-continue.

When `gate_between` is false:
One-line transition: "Moving to Phase 4: Functional Requirements."

### Phase 4: Functional Requirements
- Core features and capabilities
- User stories with acceptance criteria
- Feature prioritization

**Anti-Inference Directive**: When the user provides a feature list, DO NOT expand it with "you'll probably also need..." additions. If you believe something is missing, ASK: "I notice [X] isn't mentioned. Intentional, or should we add it?"

#### EARS Notation (Optional)

For high-precision requirements, use EARS notation from
`resources/templates/ears-requirements.md`:

| Pattern | Format | Use When |
|---------|--------|----------|
| Ubiquitous | `The system shall [action]` | Always-true requirements |
| Event-Driven | `When [trigger], the system shall [action]` | Trigger-based behavior |
| Conditional | `If [condition], the system shall [action]` | Precondition-based |

**When to use EARS**: Security-critical features, regulatory compliance, complex triggers.

#### Phase 4 Transition

When `gate_between` is true:
1. Summarize what was learned in this phase (3-5 bullets, cited)
2. State what carries forward to the next phase
3. Present transition:
   - If `routing_style` == "structured": Use AskUserQuestion:
     question: "Phase 4 complete. Ready for Phase 5: Technical & Non-Functional?"
     header: "Phase 4"
     options:
       - label: "Continue"
         description: "Move to Technical & Non-Functional"
       - label: "Go back"
         description: "Revisit this phase — I have corrections"
       - label: "Skip ahead"
         description: "Jump to PRD generation — enough context gathered"
   - If `routing_style` == "plain":
     "Phase 4: Functional Requirements complete. Moving to Phase 5: Technical & Non-Functional. Continue, go back, or skip ahead?"
4. WAIT for response. DO NOT auto-continue.

When `gate_between` is false:
One-line transition: "Moving to Phase 5: Technical & Non-Functional."

### Phase 5: Technical & Non-Functional
- Performance requirements
- Security and compliance
- Integration requirements
- Technical constraints

#### Phase 5 Transition

When `gate_between` is true:
1. Summarize what was learned in this phase (3-5 bullets, cited)
2. State what carries forward to the next phase
3. Present transition:
   - If `routing_style` == "structured": Use AskUserQuestion:
     question: "Phase 5 complete. Ready for Phase 6: Scope & Prioritization?"
     header: "Phase 5"
     options:
       - label: "Continue"
         description: "Move to Scope & Prioritization"
       - label: "Go back"
         description: "Revisit this phase — I have corrections"
       - label: "Skip ahead"
         description: "Jump to PRD generation — enough context gathered"
   - If `routing_style` == "plain":
     "Phase 5: Technical & Non-Functional complete. Moving to Phase 6: Scope & Prioritization. Continue, go back, or skip ahead?"
4. WAIT for response. DO NOT auto-continue.

When `gate_between` is false:
One-line transition: "Moving to Phase 6: Scope & Prioritization."

### Phase 6: Scope & Prioritization
- MVP definition
- Phase 1 vs future scope
- Out of scope (explicit)

#### Phase 6 Transition

When `gate_between` is true:
1. Summarize what was learned in this phase (3-5 bullets, cited)
2. State what carries forward to the next phase
3. Present transition:
   - If `routing_style` == "structured": Use AskUserQuestion:
     question: "Phase 6 complete. Ready for Phase 7: Risks & Dependencies?"
     header: "Phase 6"
     options:
       - label: "Continue"
         description: "Move to Risks & Dependencies"
       - label: "Go back"
         description: "Revisit this phase — I have corrections"
       - label: "Skip ahead"
         description: "Jump to PRD generation — enough context gathered"
   - If `routing_style` == "plain":
     "Phase 6: Scope & Prioritization complete. Moving to Phase 7: Risks & Dependencies. Continue, go back, or skip ahead?"
4. WAIT for response. DO NOT auto-continue.

When `gate_between` is false:
One-line transition: "Moving to Phase 7: Risks & Dependencies."

### Phase 7: Risks & Dependencies
- Technical risks
- Business risks
- External dependencies
- Mitigation strategies

#### Phase 7 Transition

When `gate_between` is true:
1. Summarize what was learned in this phase (3-5 bullets, cited)
2. State what carries forward to PRD generation
3. Present transition:
   - If `routing_style` == "structured": Use AskUserQuestion:
     question: "Phase 7 complete. Ready for pre-generation review?"
     header: "Phase 7"
     options:
       - label: "Continue"
         description: "Move to pre-generation summary"
       - label: "Go back"
         description: "Revisit this phase — I have corrections"
   - If `routing_style` == "plain":
     "Phase 7: Risks & Dependencies complete. Moving to pre-generation review. Continue or go back?"
4. WAIT for response. DO NOT auto-continue.

When `gate_between` is false:
One-line transition: "Moving to PRD generation."

### Pre-Generation Gate

When `gate_before_gen` is true:

Present completeness summary:

```
Discovery Complete
---
Phases covered: {N}/7
Questions asked: {count}
Assumptions made: {count}

Top assumptions (review before I generate):
1. [ASSUMPTION] {description} — if wrong, {impact}
2. [ASSUMPTION] {description} — if wrong, {impact}
3. [ASSUMPTION] {description} — if wrong, {impact}

Ready to generate PRD?
```

Use `routing_style` for the "Ready to generate?" prompt.
DO NOT generate the PRD until the user explicitly confirms.

When `gate_before_gen` is false:
Proceed directly to generation with a one-line notice: "Generating PRD based on discovery."

## Step 7.5: Vision-Inspired Requirement Proposals (Experimental, v1.42.0)

**Purpose**: When a user chose "Explore" for a vision in Step 0.5, synthesize it with the work context to propose additional requirements the user may not have considered.

**Gate**: This step ONLY runs when ALL conditions are met:
1. `vision_registry.enabled: true` in `.loa.config.yaml`
2. `vision_registry.propose_requirements: true` in `.loa.config.yaml` (default: `false`)
3. At least one vision was marked "Explore" during Step 0.5

If any condition is false: **skip this step silently**.

### Load Explored Visions

For each vision the user chose "Explore" in Step 0.5:

```bash
entry_file="grimoires/loa/visions/entries/${vision_id}.md"
```

Read the full entry file including `## Insight`, `## Potential`, and `## Connection Points` sections.

### Synthesize Proposals

For each explored vision, synthesize with the work context gathered from Phases 1-7 to propose 1-3 requirements. Each proposal must:

1. **Trace to source vision**: `[VISION-INSPIRED: vision-NNN]`
2. **Connect to work context**: Explain how this vision relates to what the user is building
3. **Be concrete and actionable**: Not vague — propose specific functional or non-functional requirements
4. **Respect scope**: Do not propose requirements that contradict user's stated scope

### Present Proposals

```markdown
---
## Vision-Inspired Requirements (Experimental)

The following requirements are inspired by architectural visions captured during
previous bridge reviews. These are proposals — accept, modify, or reject each one.

### Proposal 1: [short title]
**Source**: [VISION-INSPIRED: vision-NNN] — "[vision title]"
**Rationale**: [1-2 sentences connecting the vision insight to the current work context]

> **Proposed Requirement**: [specific requirement text]

**Decision**: Accept / Modify / Reject

### Proposal 2: [short title]
...
---
```

### Process Decisions

| Choice | Action |
|--------|--------|
| **Accept** | Include in PRD under "## Vision-Inspired Requirements" section. Call `vision_update_status(vision_id, "Proposed", visions_dir)`. Record reference. |
| **Modify** | User edits the requirement text. Include modified version in PRD. Status → Proposed. Record reference. |
| **Reject** | Do not include. Log rejection reason to trajectory JSONL. No status change. |

Log all decisions to `grimoires/loa/a2a/trajectory/vision-proposals-{date}.jsonl`:
```json
{
  "timestamp": "ISO8601",
  "cycle": "cycle-NNN",
  "vision_id": "vision-NNN",
  "proposal_title": "short title",
  "decision": "accept|modify|reject",
  "rejection_reason": "optional — only for reject"
}
```

### PRD Integration

Accepted/modified proposals go in a dedicated PRD section:

```markdown
## 9. Vision-Inspired Requirements

> These requirements were proposed by the Vision Registry based on patterns
> observed in previous development cycles. Each traces to a source vision.

### VR-1: [requirement title]
**Source**: [VISION-INSPIRED: vision-NNN]
[requirement text]

> Sources: vision-NNN (bridge iteration N, PR #NNN), Phase X confirmation
```

This section is clearly separated from user-driven requirements and carries full provenance.

---

## Phase 8: PRD Generation

Only generate PRD when:
- [ ] All 7 phases have sufficient coverage
- [ ] All ambiguities resolved
- [ ] Developer confirms understanding is accurate

Generate PRD with source tracing:
```markdown
## 1. Problem Statement

[Content derived from vision.md:12-30 and Phase 1 interview]

> Sources: vision.md:12-15, confirmed in Phase 1 Q2
```
</workflow>

<parallel_execution>
## Large Context Handling (>2000 lines)

If context assessment returns `LARGE`:

### Spawn Parallel Ingestors
```
Task(subagent_type="Explore", prompt="
CONTEXT INGESTION: Problem & Vision

Read these files: [vision.md, any *vision* or *problem* files]
Extract and summarize:
- Core problem statement
- Product vision
- Mission/purpose
- 'Why now' factors

Return as structured summary with file:line citations.
")
```

Spawn 4 parallel ingestors:
1. **Vision Ingestor**: Problem, vision, mission
2. **User Ingestor**: Personas, research, journeys
3. **Requirements Ingestor**: Features, stories, specs
4. **Technical Ingestor**: Constraints, stack, integrations

### Consolidate
Merge summaries into unified context map before proceeding.
</parallel_execution>

<output_format>
PRD structure with source tracing - see `resources/templates/prd-template.md`

Each section must include:
```markdown
> **Sources**: vision.md:12-30, users.md:45-67, Phase 3 Q1-Q2
```
</output_format>

<success_criteria>
- **Specific**: Every PRD requirement traced to source (file:line, [CODE:file:line], or phase:question)
- **Measurable**: Questions reduced by 50%+ when context provided
- **Achievable**: Synthesis completes before any interview questions
- **Relevant**: Developer confirms understanding before proceeding
- **Time-bound**: Context synthesis <5 min for SMALL/MEDIUM
- **Grounded**: Brownfield PRDs cite existing code with [CODE:file:line] format
- **Zero Latency**: Greenfield projects experience no codebase detection delay
</success_criteria>

<uncertainty_protocol>
- If context files contradict each other → Ask developer to clarify
- If context is ambiguous → State interpretation, ask for confirmation
- If context seems outdated → Ask if still accurate
- Never assume → Always cite or ask
</uncertainty_protocol>

<grounding_requirements>
Every claim about existing context must include citation:
- Format: `> From {filename}:{line}: "exact quote"`
- Summaries must reference source range: `(vision.md:12-45)`
- PRD sections must list all sources used
</grounding_requirements>

<edge_cases>
| Scenario | Behavior |
|----------|----------|
| No context directory | Create it, add README.md, proceed to full interview |
| Empty context directory | Note it, proceed to full interview |
| Only README.md exists | Treat as empty, proceed to full interview |
| Contradictory information | List contradictions, ask developer to clarify |
| Outdated information | Ask "Is this still accurate?" before using |
| Very large files (>1000 lines) | Summarize key sections, note full file available |
| Non-markdown files | Note existence, explain can't parse |
| Partial coverage | Conduct mini-interviews for gaps only |
| Developer disagrees with synthesis | Allow corrections, update understanding |
| Reality conflicts with context | Reality wins, flag conflict for user review |
| Stale reality (>7 days) | Prompt user to refresh or proceed with cached |
| /ride failed | Log blocker, proceed without grounding (with warning) |
| Brownfield detected but no reality | Present 3-option AskUserQuestion: Run /ride, Run /ride --enriched, Skip grounding |
| Greenfield project | Skip codebase grounding entirely, no message |
</edge_cases>

<visual_communication>
## Visual Communication (Optional)

Follow `.claude/protocols/visual-communication.md` for diagram standards.

### When to Include Diagrams

PRDs may benefit from visual aids for:
- **User Journeys** (flowchart) - Show user flows through the product
- **Process Flows** (flowchart) - Illustrate business processes
- **Stakeholder Maps** (flowchart) - Show stakeholder relationships

### Output Format

If including diagrams, use Mermaid with preview URLs:

```markdown
### User Registration Journey

```mermaid
graph LR
    A[Landing Page] --> B{Has Account?}
    B -->|No| C[Sign Up Form]
    B -->|Yes| D[Login]
    C --> E[Email Verification]
    E --> F[Onboarding]
    F --> G[Dashboard]
```

> **Preview**: [View diagram](https://agents.craft.do/mermaid?code=...&theme=github)
```

### Theme Configuration

Read theme from `.loa.config.yaml` visual_communication.theme setting.

Diagram inclusion is **optional** for PRDs - use agent discretion based on complexity.
</visual_communication>

<post_completion>
## Post-Completion Debrief

After saving the PRD to `grimoires/loa/prd.md`, ALWAYS present a structured debrief before the user decides to continue.

### Debrief Structure

Present the following in this exact order:

1. **Confirmation**: "✓ PRD saved to grimoires/loa/prd.md"

2. **Key Decisions** (3-5 items): The most impactful choices made during discovery. Each decision should be one line: "• {choice made} (not {alternative rejected})"

3. **Assumptions** (1-3 items): Things assumed true but not explicitly confirmed by the user. Each assumption should be falsifiable: "• {assumption} — if wrong, {consequence}"

4. **Biggest Tradeoff** (1 item): The most consequential either/or decision. Format: "• Chose {A} over {B} — {reason}. Risk: {what could go wrong}"

5. **Steer Prompt**: Use AskUserQuestion:

```yaml
question: "Anything to steer before architecture?"
header: "Review"
options:
  - label: "Continue (Recommended)"
    description: "Design the system architecture now"
  - label: "Adjust"
    description: "Tell me what to change — I'll regenerate the PRD"
  - label: "Stop here"
    description: "Save progress — resume with /plan next time. Not what you expected? /feedback helps us fix it."
multiSelect: false
```

### "Adjust" Flow

When the user selects "Adjust":

1. **Prompt**: "What would you like to change?" (free-text via AskUserQuestion "Other")
2. **Scope**: Regenerate the PRD ONLY (not rerun the entire discovery interview)
3. **Context preserved**: All prior interview answers, context files, and phase state are retained
4. **Output**: After regeneration, re-present the debrief with updated decisions/assumptions/tradeoffs
5. **Diff awareness**: If changes are small, note what changed: "Updated: {decision that changed}"
6. **Loop limit**: Max 3 adjustment rounds before suggesting "Continue" more firmly

### Constraints

- Keep decisions to 3-5 items — not an exhaustive list
- Each item is ONE line — no paragraphs
- "Continue" is always the first option (recommended)
- "Stop here" always includes /feedback mention
- If Flatline will run next, add a one-line banner BEFORE the steer prompt: "Next: Multi-model review (~30 seconds)"
</post_completion>
