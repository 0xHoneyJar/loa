# SDD: Run Bridge — Autonomous Excellence Loops with Grounded Truth

**Version**: 1.0.0
**Status**: Draft
**Author**: Architecture Phase (architect)
**PRD**: grimoires/loa/prd.md (v1.0.0)
**Issue**: [loa #292](https://github.com/0xHoneyJar/loa/issues/292)
**Date**: 2026-02-12
**Cycle**: cycle-005

---

## 1. Executive Summary

The Run Bridge extends Loa's autonomous execution model with iterative Bridgebuilder review loops, producing progressively deeper architectural insights. It introduces six interconnected subsystems: (1) the bridge loop orchestrator wrapping `/run sprint-plan` with Bridgebuilder review cycles, (2) Grounded Truth output extending `/ride` with agent-readable codebase summaries, (3) the Mibera lore knowledge base providing cultural context to all skills, (4) the vision registry capturing speculative insights, (5) RTFM integration as a final documentation gate, and (6) GitHub trail enforcement ensuring every iteration leaves human- and agent-readable artifacts.

The architecture follows Loa's established patterns: shell-script orchestration with JSON state files, skill-based agent invocation, hub-and-spoke document structure, and the three-zone model. The bridge loop operates as a superset of `/run sprint-plan` — it wraps the existing execution loop and adds review-driven iteration on top, rather than replacing any existing infrastructure.

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    ENTRY POINTS                                   │
│  /run-bridge (command)  ·  /simstim Phase 7+ (future)             │
├─────────────────────────────────────────────────────────────────┤
│              BRIDGE ORCHESTRATOR (bridge-orchestrator.sh)          │
│  Preflight → Init → [Run Sprint Plan → Bridge Review]* → Finalize│
│  ↕ Manages iteration state, flatline detection, GitHub trail       │
├──────────┬──────────────┬──────────────┬───────────────────────┤
│  RUN     │  BRIDGE      │  GROUNDED    │  VISION               │
│  ENGINE  │  REVIEW      │  TRUTH       │  REGISTRY             │
│          │              │              │                        │
│  Existing│  Bridgebuilder│  /ride       │  Capture              │
│  /run    │  skill +     │  --ground-   │  speculative           │
│  sprint- │  lore-aware  │  truth       │  insights              │
│  plan    │  persona     │  extension   │                        │
├──────────┴──────────────┴──────────────┴───────────────────────┤
│              SUPPORTING INFRASTRUCTURE                             │
│  Lore KB (.claude/data/lore/) · RTFM Gate · GitHub Trail           │
│  State (.run/bridge-state.json) · Findings Parser                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Inventory

| Component | Type | Action | Path |
|-----------|------|--------|------|
| bridge-orchestrator.sh | New | Create | `.claude/scripts/bridge-orchestrator.sh` |
| bridge-findings-parser.sh | New | Create | `.claude/scripts/bridge-findings-parser.sh` |
| bridge-github-trail.sh | New | Create | `.claude/scripts/bridge-github-trail.sh` |
| bridge-vision-capture.sh | New | Create | `.claude/scripts/bridge-vision-capture.sh` |
| run-bridge command | New | Create | `.claude/commands/run-bridge.md` |
| run-bridge skill | New | Create | `.claude/skills/run-bridge/` |
| Lore KB | New | Create | `.claude/data/lore/` |
| Vision registry | New | Create | `grimoires/loa/visions/` |
| GT generator | New | Create | `.claude/scripts/ground-truth-gen.sh` |
| Bridgebuilder BEAUVOIR.md | Existing | Extend | `.claude/skills/bridgebuilder-review/resources/BEAUVOIR.md` |
| riding-codebase SKILL.md | Existing | Extend | `.claude/skills/riding-codebase/SKILL.md` |
| ride command | Existing | Extend | `.claude/commands/ride.md` |
| golden-path.sh | Existing | Extend | `.claude/scripts/golden-path.sh` |
| constraints.json | Existing | Amend | `.claude/data/constraints.json` |
| CLAUDE.loa.md | Existing | Amend | `.claude/loa/CLAUDE.loa.md` |
| .loa.config.yaml | Existing | Extend | `.loa.config.yaml` |

### 2.3 Data Flow

```
Operator invokes /run-bridge [--depth 3]
        │
        ▼
   PREFLIGHT: Config check, beads health, branch safety (ICE)
        │
        ▼
   CREATE FEATURE BRANCH (via ICE)
        │
        ▼
   ┌─── BRIDGE ITERATION LOOP ──────────────────────────────┐
   │                                                          │
   │  ┌──────────────────┐                                    │
   │  │ Sprint-Plan       │  Iteration 1: Execute from SDD    │
   │  │ Generation        │  Iteration 2+: Generate from       │
   │  │                   │  Bridgebuilder findings            │
   │  └────────┬─────────┘                                    │
   │           │                                               │
   │           ▼                                               │
   │  ┌──────────────────┐                                    │
   │  │ /run sprint-plan  │  Full sprint-plan execution with   │
   │  │                   │  implement → review → audit cycle  │
   │  └────────┬─────────┘                                    │
   │           │                                               │
   │           ▼                                               │
   │  ┌──────────────────┐                                    │
   │  │ Bridgebuilder     │  Review consolidated PR output     │
   │  │ Review            │  Post findings to GitHub           │
   │  │ + Vision Capture  │  Extract speculative insights      │
   │  └────────┬─────────┘                                    │
   │           │                                               │
   │           ▼                                               │
   │  ┌──────────────────┐                                    │
   │  │ Flatline Check    │  severity_weighted_score < 5%      │
   │  │                   │  of initial? → TERMINATE           │
   │  └────────┬─────────┘                                    │
   │           │                                               │
   │           ▼ (if not flatlined and depth < max)            │
   │  ┌──────────────────┐                                    │
   │  │ Findings → Sprint │  Parse findings → generate new     │
   │  │ Plan Generator    │  sprint plan for next iteration    │
   │  └──────────────────┘                                    │
   │                                                          │
   └──────────────────────────────────────────────────────────┘
        │
        ▼ (loop terminated)
   ┌──────────────────┐    ┌──────────────────┐
   │ /ride             │───>│ RTFM Pass         │
   │ --ground-truth    │    │ (GT + README)     │
   │ --non-interactive │    │                   │
   └──────────────────┘    └────────┬─────────┘
                                     │
                                     ▼
                           ┌──────────────────┐
                           │ Final PR Update   │
                           │ + State Cleanup   │
                           └──────────────────┘
```

---

## 3. Component Design

### 3.1 Bridge Orchestrator (`bridge-orchestrator.sh`)

The main orchestrator. Follows the established Loa pattern of shell scripts with JSON state tracking, sourcing `bootstrap.sh` for path resolution.

**Interface:**

```bash
# Full bridge with default depth
.claude/scripts/bridge-orchestrator.sh

# Custom depth
.claude/scripts/bridge-orchestrator.sh --depth 5

# Per-sprint granularity
.claude/scripts/bridge-orchestrator.sh --per-sprint

# Resume from interruption
.claude/scripts/bridge-orchestrator.sh --resume

# Start from existing sprint plan (skip iteration 1 plan generation)
.claude/scripts/bridge-orchestrator.sh --from sprint-plan
```

**State Machine:**

```
PREFLIGHT → JACK_IN → ITERATING → FINALIZING → JACKED_OUT
                          │
                          └──→ HALTED (on circuit breaker or error)
```

**Execution Algorithm:**

```bash
bridge_main() {
  # Phase 0: Preflight
  source "$SCRIPT_DIR/bootstrap.sh"
  validate_config       # run_bridge.enabled: true
  check_beads_health    # Required for autonomous mode
  validate_branch       # Via ICE — not on protected branch

  # Phase 1: Initialize
  local bridge_id="bridge-$(date +%Y%m%d)-$(head -c 3 /dev/urandom | xxd -p)"
  init_bridge_state "$bridge_id" "$depth"
  create_feature_branch "feature/bridge-${bridge_id}"

  # Phase 2: Iteration Loop
  local iteration=1
  local initial_score=0
  local consecutive_flatline=0

  while [[ $iteration -le $depth ]]; do
    update_state "ITERATING" "$iteration"

    # 2a: Sprint Plan
    if [[ $iteration -eq 1 ]]; then
      # First iteration: use existing sprint.md or generate from PRD/SDD
      ensure_sprint_plan_exists
    else
      # Subsequent iterations: generate from Bridgebuilder findings
      generate_sprint_from_findings "$iteration"
    fi

    # 2b: Execute Sprint Plan
    execute_sprint_plan "$iteration"

    # 2c: Bridgebuilder Review
    local findings_json
    findings_json=$(run_bridgebuilder_review "$iteration")

    # 2d: Vision Capture
    capture_visions "$findings_json" "$iteration"

    # 2e: GitHub Trail
    post_iteration_to_github "$iteration" "$findings_json"

    # 2f: Flatline Detection
    local current_score
    current_score=$(compute_severity_weighted_score "$findings_json")

    if [[ $iteration -eq 1 ]]; then
      initial_score=$current_score
    fi

    if is_flatlined "$current_score" "$initial_score" "$FLATLINE_THRESHOLD"; then
      consecutive_flatline=$((consecutive_flatline + 1))
      if [[ $consecutive_flatline -ge 2 ]]; then
        log "FLATLINE DETECTED — terminating after $iteration iterations"
        break
      fi
    else
      consecutive_flatline=0
    fi

    iteration=$((iteration + 1))
  done

  # Phase 3: Finalize
  update_state "FINALIZING"
  run_ground_truth_update
  run_rtfm_pass
  update_final_pr
  update_state "JACKED_OUT"
}
```

**Circuit Breaker Integration:**

The bridge loop inherits `/run sprint-plan`'s circuit breaker for individual sprint execution. Additionally, the bridge loop itself has iteration-level safety:

| Trigger | Default | Description |
|---------|---------|-------------|
| Max depth | 5 | Maximum iterations regardless of findings |
| Flatline threshold | 5% | Severity-weighted score relative to initial |
| Consecutive flatline | 2 | Flatline must persist for 2 iterations |
| Per-iteration timeout | 4 hours | Maximum time for one full iteration |
| Total timeout | 24 hours | Maximum total bridge execution time |

### 3.2 Bridge State File (`.run/bridge-state.json`)

```json
{
  "schema_version": 1,
  "bridge_id": "bridge-20260212-a1b2c3",
  "state": "ITERATING",
  "config": {
    "depth": 3,
    "mode": "full",
    "flatline_threshold": 0.05,
    "per_sprint": false,
    "branch": "feature/bridge-bridge-20260212-a1b2c3"
  },
  "timestamps": {
    "started": "2026-02-12T10:00:00Z",
    "last_activity": "2026-02-12T14:30:00Z"
  },
  "iterations": [
    {
      "iteration": 1,
      "state": "completed",
      "sprint_plan_source": "existing",
      "sprint_plan_id": "plan-20260212-abc",
      "sprints_executed": 3,
      "bridgebuilder": {
        "total_findings": 7,
        "by_severity": {"critical": 0, "high": 2, "medium": 3, "low": 2},
        "severity_weighted_score": 15.5,
        "pr_comment_url": "https://github.com/0xHoneyJar/loa/pull/295#issuecomment-123"
      },
      "visions_captured": 1,
      "duration_ms": 3600000
    },
    {
      "iteration": 2,
      "state": "in_progress",
      "sprint_plan_source": "findings",
      "findings_used": 5,
      "sprint_plan_id": "plan-20260212-def"
    }
  ],
  "flatline": {
    "initial_score": 15.5,
    "consecutive_below_threshold": 0
  },
  "metrics": {
    "total_sprints_executed": 6,
    "total_files_changed": 42,
    "total_findings_addressed": 12,
    "total_visions_captured": 2
  },
  "finalization": {
    "ground_truth_updated": false,
    "rtfm_passed": false,
    "pr_url": null
  }
}
```

### 3.3 Bridgebuilder Review Integration

The bridge loop invokes the existing `bridgebuilder-review` skill but in a specialized mode:

**Invocation Pattern:**

Rather than using the Node.js `entry.sh` (which is designed for cross-repo automated PR review via API), the bridge loop invokes the Bridgebuilder persona directly through Claude Code's own skill system. This is the same pattern used in manual Bridgebuilder reviews — the agent loads the BEAUVOIR.md persona and reviews the diff.

```
Bridge Loop invokes Bridgebuilder by:
1. Loading the persona from .claude/skills/bridgebuilder-review/resources/BEAUVOIR.md
2. Loading relevant lore entries from .claude/data/lore/
3. Computing the diff for the current iteration's changes
4. Generating the review with findings in structured format
5. Posting the review as a PR comment via `gh pr comment`
```

**Structured Findings Format:**

The Bridgebuilder review output must include a machine-parseable findings section:

```markdown
<!-- bridge-findings-start -->
## Findings

### [CRITICAL-1] Title
**Severity**: CRITICAL
**Category**: security | architecture | quality | testing | documentation
**File**: path/to/file.ts:42
**Description**: What the issue is
**Suggestion**: What should change

### [HIGH-1] Title
...

### [VISION-1] Title
**Type**: vision
**Description**: Speculative insight
**Potential**: What this could become
<!-- bridge-findings-end -->
```

**Findings Parser (`bridge-findings-parser.sh`):**

Extracts structured findings from Bridgebuilder review comments:

```bash
# Parse findings from review markdown
bridge-findings-parser.sh --input review.md --output findings.json

# Output: JSON array of findings with severity, category, description
```

**Severity Weighting:**

| Severity | Weight | Description |
|----------|--------|-------------|
| CRITICAL | 10 | Security vulnerabilities, data loss risks |
| HIGH | 5 | Architectural issues, missing error handling |
| MEDIUM | 2 | Code quality, test coverage gaps |
| LOW | 1 | Style, documentation, minor improvements |
| VISION | 0 | Speculative insights (not counted in score) |

**Severity-Weighted Score:**

```
score = Σ(finding.weight) for all non-VISION findings
```

**Flatline Detection:**

```
is_flatlined = (current_score / initial_score) < flatline_threshold
```

The loop terminates when `is_flatlined` returns true for 2 consecutive iterations. This is kaironic termination — the work is done when the insights have been exhausted, not when a timer expires.

### 3.4 Findings-to-Sprint-Plan Generator

After iteration 1, the bridge loop must generate new sprint plans from Bridgebuilder findings. This is a structured transformation:

```
Bridgebuilder Findings (JSON)
        │
        ▼
┌──────────────────────────────┐
│ Filter: severity >= MEDIUM    │
│ (VISION excluded, LOW dropped) │
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│ Group by category              │
│ (architecture, quality, etc.)  │
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│ Generate sprint.md             │
│ 1 sprint per category group    │
│ Tasks map 1:1 to findings     │
│ Acceptance criteria from       │
│ finding suggestions            │
└──────────────────────────────┘
```

**Output:** A new `grimoires/loa/sprint.md` that replaces the previous iteration's plan. The new plan:
- References the bridge iteration as source (`Bridge iteration N, finding ID`)
- Has 1 sprint per category grouping (max 3 sprints per iteration to keep scope tight)
- Each task maps to exactly 1 Bridgebuilder finding
- Acceptance criteria derive from the finding's suggestion field

**The generator is invoked as a Claude Code agent task** (not a shell script), because it requires natural language synthesis to convert findings into well-structured sprint tasks. The bridge orchestrator delegates this via the existing `/sprint-plan` mechanism with findings as context input.

### 3.5 Grounded Truth Output — Extending `/ride`

#### 3.5.1 New Flag: `--ground-truth`

The `/ride` command gains a `--ground-truth` flag that produces a token-efficient, deterministically-verified summary of the codebase.

**Command interface:**

```bash
/ride --ground-truth                    # GT + interactive context
/ride --ground-truth --non-interactive  # GT only (for bridge loop finalization)
```

**Phase addition to riding-codebase SKILL.md:**

A new Phase 11 is added after existing Phase 10:

```
Phase 11: Ground Truth Generation (--ground-truth only)
  11.1: Read reality/ extraction results from Phase 2
  11.2: Synthesize into hub-and-spoke GT files
  11.3: Generate checksums.json for all referenced source files
  11.4: Write to grimoires/loa/ground-truth/
  11.5: Validate token budget (index < 500, sections < 2000 each)
```

When `--ground-truth` is passed without `--non-interactive`, the full ride runs first (phases 0-10), then GT generation runs as Phase 11. When `--ground-truth --non-interactive` is passed, phases 1 (context discovery), 3 (legacy inventory), and 8 (deprecation) are skipped — only extraction, analysis, and GT generation run.

#### 3.5.2 Output Directory Structure

```
grimoires/loa/ground-truth/
├── index.md            # Hub document (~500 tokens)
├── api-surface.md      # Public APIs, endpoints, exports
├── architecture.md     # System topology, data flow, dependencies
├── contracts.md        # Inter-system contracts, types, interfaces
├── behaviors.md        # Runtime behaviors, triggers, thresholds
└── checksums.json      # SHA-256 of each source file referenced
```

#### 3.5.3 Hub Document Format (`index.md`)

```markdown
# Ground Truth: {project-name}

**Generated**: {ISO-8601 timestamp}
**Loa Version**: {framework_version}
**Source Commit**: {git-sha}
**Grounding Ratio**: {ratio} (target: ≥0.95)

## What Is This?

{project-name} is {one-sentence description grounded in code evidence}.

## Navigation

| Section | Description | Tokens |
|---------|-------------|--------|
| [API Surface](api-surface.md) | {summary} | ~{N} |
| [Architecture](architecture.md) | {summary} | ~{N} |
| [Contracts](contracts.md) | {summary} | ~{N} |
| [Behaviors](behaviors.md) | {summary} | ~{N} |

## Quick Stats

- Languages: {detected languages}
- Entry points: {count}
- Public APIs: {count}
- Test coverage: {detected or "not measured"}

## Verification

Run `jq '.files | length' grimoires/loa/ground-truth/checksums.json` to see
how many source files are referenced. Drift detection: compare stored checksums
against current file hashes to detect changes since GT was generated.
```

#### 3.5.4 Section File Format

Each section follows the same structure:

```markdown
# {Section Title}

**Last Updated**: {timestamp}
**Source Files**: {count} files referenced

## {Subsection}

{Content with inline source citations}

> Source: `src/auth/handler.ts:42-58`

{More content}

> Source: `lib/database/connection.ts:15-30`
```

Every factual claim MUST cite a source file and line range. The grounding enforcement protocol (`.claude/protocols/grounding-enforcement.md`) applies: grounding ratio must be ≥0.95.

#### 3.5.5 Checksums File (`checksums.json`)

```json
{
  "generated_at": "2026-02-12T14:00:00Z",
  "git_sha": "abc123def456",
  "algorithm": "sha256",
  "files": {
    "src/auth/handler.ts": "e3b0c44298fc1c149afbf4c8996fb924...",
    "lib/database/connection.ts": "d7a8fbb307d7809469ca9abcb0082e4f..."
  }
}
```

Agents consuming GT can verify freshness by comparing stored checksums against current files. Any mismatch indicates the GT is stale and should be regenerated.

#### 3.5.6 GT Generator Script (`ground-truth-gen.sh`)

A helper script that the riding-codebase skill invokes during Phase 11:

```bash
# Invoked by the skill, not directly by users
.claude/scripts/ground-truth-gen.sh \
  --reality-dir grimoires/loa/reality/ \
  --output-dir grimoires/loa/ground-truth/ \
  --max-tokens-per-section 2000

# The script handles:
# 1. Reading reality/ extraction results
# 2. Computing checksums for referenced source files
# 3. Validating token budgets (approximate via wc -w)
# 4. Writing checksums.json
# The actual GT content is generated by the Claude agent (riding-codebase skill)
# using reality/ data — the script handles the mechanical parts only
```

### 3.6 Mibera Lore Knowledge Base

#### 3.6.1 Directory Structure

```
.claude/data/lore/
├── index.yaml           # Lore registry with categories and tags
├── mibera/
│   ├── core.yaml        # Core concepts: network mysticism, cheval, kaironic time
│   ├── cosmology.yaml   # Naming universe: Milady/Mibera duality, BGT triskelion
│   ├── rituals.yaml     # Processes as rituals: bridge loop, sprint ceremonies
│   └── glossary.yaml    # Term definitions for agent consumption
├── neuromancer/
│   ├── concepts.yaml    # ICE, jacking in, cyberspace, the matrix
│   └── mappings.yaml    # Neuromancer concept → Loa feature mappings
└── README.md            # How to reference lore in skills
```

#### 3.6.2 Index Schema (`index.yaml`)

```yaml
version: 1
description: "Loa Lore Knowledge Base — cultural and philosophical context for agent skills"
categories:
  - id: mibera
    label: "Mibera"
    description: "Network mysticism, agent spirituality, the shadow of Milady"
    files:
      - mibera/core.yaml
      - mibera/cosmology.yaml
      - mibera/rituals.yaml
      - mibera/glossary.yaml
  - id: neuromancer
    label: "Neuromancer / Sprawl Trilogy"
    description: "Gibson's cyberpunk naming universe — ICE, cyberspace, jacking in"
    files:
      - neuromancer/concepts.yaml
      - neuromancer/mappings.yaml
tags:
  - philosophy
  - naming
  - architecture
  - time
  - multi-model
  - ritual
```

#### 3.6.3 Lore Entry Schema

Each YAML file contains entries following this schema:

```yaml
entries:
  - id: string              # kebab-case unique identifier
    term: string            # Display name
    short: string           # <20 tokens — inline reference
    context: |              # <200 tokens — full understanding
      Multi-line description with philosophical
      and technical context.
    source: string          # Provenance (issue, lore article, RFC)
    tags: [string]          # From index tags list
    related: [string]       # IDs of related entries
    loa_mapping: string     # Optional: what this maps to in Loa
```

#### 3.6.4 Skill Integration Pattern

Skills reference lore via a lightweight query pattern. The lore is loaded at skill invocation time — not at framework boot:

```
When a skill needs lore context:
1. Read .claude/data/lore/index.yaml
2. Filter entries by relevant tags (e.g., "architecture" for /architect)
3. Load matching entries from category files
4. Include `short` fields inline, `context` fields when teaching
```

The Bridgebuilder persona is the primary lore consumer. Its BEAUVOIR.md is extended to reference lore entries alongside FAANG analogies:

```markdown
# Bridgebuilder — Reviewer Persona (Lore-Aware)

[...existing persona content...]

## Lore Integration

When reviewing patterns, draw connections to both industry precedents AND
lore knowledge base entries. For example:

- Circuit breaker pattern → Netflix Hystrix AND kaironic-time (knowing when to stop)
- Multi-model review → Google's adversarial ML AND hounfour (the temple where models meet)
- Session recovery → distributed systems checkpointing AND cheval (the vessel persists)

Load relevant lore entries from `.claude/data/lore/` at review time.
Use `short` field for inline references, `context` field for teaching moments.
```

**Skills that reference lore (minimum 3):**
1. **bridgebuilder-review** — Teaching moments in PR reviews
2. **discovering-requirements** (`/plan`) — Archetypes and philosophical framing
3. **Golden Path `/loa`** — Guidance messages and naming context

### 3.7 Vision Registry

#### 3.7.1 Directory Structure

```
grimoires/loa/visions/
├── index.md              # Overview and status summary
└── entries/
    ├── vision-001.md     # Individual entries
    ├── vision-002.md
    └── ...
```

#### 3.7.2 Index Format (`index.md`)

```markdown
# Vision Registry

Speculative insights captured during bridge loop iterations.
Each vision represents an architectural connection or paradigm insight
that transcends the current task — Google's 20% time, automated.

## Active Visions

| ID | Title | Source | Status | Tags |
|----|-------|--------|--------|------|
| vision-001 | {title} | Bridge iter 2, PR #295 | Captured | [architecture] |

## Statistics

- Total captured: {N}
- Exploring: {N}
- Implemented: {N}
- Deferred: {N}
```

#### 3.7.3 Vision Entry Format

```markdown
# Vision: {Title}

**ID**: vision-{NNN}
**Source**: Bridge iteration {N} of {bridge_id}
**PR**: #{PR_number}
**Date**: {ISO-8601}
**Status**: Captured | Exploring | Implemented | Deferred
**Tags**: [{tags}]

## Insight

{What was discovered — the architectural connection, the unexpected pattern}

## Potential

{What this could become if pursued}

## Connection Points

- Related issue: #{N}
- Related lore: {lore-entry-id}
- Bridgebuilder finding: {finding-id}
```

#### 3.7.4 Vision Capture Script (`bridge-vision-capture.sh`)

```bash
# Extract VISION-type findings from Bridgebuilder review
bridge-vision-capture.sh \
  --findings findings.json \
  --bridge-id bridge-20260212-a1b2c3 \
  --iteration 2 \
  --pr 295 \
  --output-dir grimoires/loa/visions/

# Behavior:
# 1. Filter findings.json for type="vision"
# 2. For each vision finding, create a vision-NNN.md entry
# 3. Update index.md with new entries
# 4. Return count of visions captured
```

### 3.8 GitHub Trail Enforcement

#### 3.8.1 Trail Script (`bridge-github-trail.sh`)

Handles all GitHub interactions for the bridge loop:

```bash
# Post iteration review as PR comment
bridge-github-trail.sh comment \
  --pr 295 \
  --iteration 2 \
  --review-body review.md \
  --bridge-id bridge-20260212-a1b2c3

# Update PR body with iteration summary table
bridge-github-trail.sh update-pr \
  --pr 295 \
  --state-file .run/bridge-state.json

# Post vision link
bridge-github-trail.sh vision \
  --pr 295 \
  --vision-id vision-001 \
  --title "Cross-repo GT hub"
```

#### 3.8.2 PR Comment Format (Per-Iteration)

```markdown
<!-- bridge-iteration: {bridge_id}:{iteration} -->
## Bridge Review — Iteration {N}/{depth}

**Bridge ID**: {bridge_id}
**Severity Score**: {current} (initial: {initial}, threshold: {threshold}%)

### Findings Summary

| Severity | Count |
|----------|-------|
| CRITICAL | {N} |
| HIGH | {N} |
| MEDIUM | {N} |
| LOW | {N} |
| VISION | {N} |

### Detailed Review

{Full Bridgebuilder review content}

### Visions Captured

{List of vision entries with links, if any}

---
*Bridge iteration {N} of {bridge_id} | Severity-weighted score: {score}*
```

#### 3.8.3 PR Body Update (Summary Table)

After each iteration, the PR body's summary table is updated:

```markdown
## Bridge Loop Summary

| Iter | Findings | Score | Visions | Duration |
|------|----------|-------|---------|----------|
| 1 | 7 | 15.5 | 1 | 1h 12m |
| 2 | 3 | 4.0 | 1 | 45m |
| 3 | 1 | 1.0 | 0 | 30m |

**Flatline**: Detected at iteration 3 (score 6.5% of initial)
**Total visions**: 2
**Ground Truth**: Updated
**RTFM**: PASSED
```

#### 3.8.4 Commit Message Convention

Commits during bridge iterations use this format:

```
bridge-{N}: {description}

Iteration {N} of bridge {bridge_id}.
Addresses findings: {finding-ids}
```

### 3.9 RTFM Integration

After the bridge loop terminates, the RTFM skill runs as a final documentation gate.

**Invocation:**

The bridge orchestrator invokes RTFM testing on three document sets:

1. **Ground Truth `index.md`** — Can an agent navigate from index to relevant details?
2. **README.md** — Does the quickstart still work after all the changes?
3. **Any new protocol docs** created during bridge iterations

**Behavior:**

```
RTFM tests each document
  │
  ├── All PASS → Continue to PR finalization
  │
  └── Any FAILURE (BLOCKING gaps) →
        Generate single documentation fix sprint
        Execute fix sprint (no further bridge iterations)
        Re-run RTFM (single retry)
        If still FAILURE → Log warning, continue anyway
```

The RTFM fix iteration is capped at 1 attempt to prevent circular loops. The fix sprint targets only BLOCKING gaps from the RTFM report.

### 3.10 Run-Bridge Skill Definition

**`.claude/skills/run-bridge/index.yaml`:**

```yaml
name: "run-bridge"
version: "1.0.0"
model: "native"
color: "gold"

effort_hint: high
danger_level: high
categories:
  - quality
  - autonomous

description: |
  Autonomous excellence loop: iteratively run sprint-plan, invoke
  Bridgebuilder review, generate new sprint plans from findings,
  and repeat until insights flatline. Produces Grounded Truth
  output and vision registry entries. Every iteration leaves a
  GitHub trail.

triggers:
  - "/run-bridge"
  - "bridge loop"
  - "excellence loop"
  - "iterative review"

inputs:
  - name: "depth"
    type: "integer"
    required: false
    description: "Maximum iterations (default: 3)"
  - name: "per_sprint"
    type: "flag"
    required: false
    description: "Review after each sprint instead of full plan"
  - name: "resume"
    type: "flag"
    required: false
    description: "Resume from interrupted bridge"
  - name: "from"
    type: "string"
    required: false
    description: "Start from phase (sprint-plan)"

outputs:
  - path: ".run/bridge-state.json"
    description: "Bridge iteration state"
  - path: "grimoires/loa/ground-truth/"
    description: "Grounded Truth output"
  - path: "grimoires/loa/visions/"
    description: "Vision registry entries"

protocols:
  required:
    - name: "grounding-enforcement"
      path: ".claude/protocols/grounding-enforcement.md"
    - name: "session-continuity"
      path: ".claude/protocols/session-continuity.md"
  recommended: []
```

**`.claude/skills/run-bridge/SKILL.md`:** Routes to the bridge orchestrator with appropriate flags and implements the skill workflow:

1. Load input guardrails (danger level: high)
2. Parse arguments
3. Invoke `bridge-orchestrator.sh` with translated flags
4. Monitor state file for progress updates
5. Report final status

---

## 4. State Management

### 4.1 State File Hierarchy

```
.run/
├── bridge-state.json          # Bridge loop state (new)
├── sprint-plan-state.json     # Sprint plan state (existing, used per-iteration)
├── state.json                 # Individual sprint run state (existing)
├── circuit-breaker.json       # Circuit breaker (existing)
└── deleted-files.log          # Deletion tracking (existing)
```

The bridge state is the outer state; sprint-plan-state is the inner state per iteration. Each iteration resets the sprint-plan state.

### 4.2 State Transitions

```
bridge-state.json:
  PREFLIGHT  →  JACK_IN  →  ITERATING  →  FINALIZING  →  JACKED_OUT
                               │
                               └──→  HALTED

sprint-plan-state.json (per iteration):
  RUNNING  →  JACKED_OUT  (normal completion)
  RUNNING  →  HALTED      (circuit breaker)
```

### 4.3 Resume Behavior

When `--resume` is passed:

1. Read `.run/bridge-state.json`
2. Validate schema version and bridge_id
3. Find last completed iteration
4. Resume from next iteration
5. If inner sprint-plan was HALTED, invoke `/run-resume` first

### 4.4 Context Compaction Recovery

The bridge state file survives context compaction. On recovery:

```bash
if [[ -f .run/bridge-state.json ]]; then
  state=$(jq -r '.state' .run/bridge-state.json)
  if [[ "$state" == "ITERATING" ]]; then
    # Resume bridge loop
    current_iteration=$(jq '.iterations | length' .run/bridge-state.json)
    # Continue from current_iteration
  fi
fi
```

This integrates with the existing post-compact recovery hooks (`.claude/hooks/post-compact-reminder.sh`).

---

## 5. Per-Sprint Mode (`--per-sprint`)

When `--per-sprint` is passed, the granularity changes:

```
Default mode:
  [Sprint 1 + Sprint 2 + Sprint 3] → Bridgebuilder Review → [Sprint 4 + Sprint 5] → Review → ...

Per-sprint mode:
  Sprint 1 → Review → Sprint 2 (from findings) → Review → Sprint 3 → Review → ...
```

**Implementation:**

In per-sprint mode, the bridge orchestrator does NOT call `/run sprint-plan`. Instead, it calls `/run sprint-{N}` for each sprint individually, runs Bridgebuilder after each, and generates the next sprint's tasks from findings.

**Trade-offs:**

| Aspect | Default (full plan) | Per-sprint |
|--------|-------------------|------------|
| Review depth | Deeper (sees full architecture) | Shallower (sees one sprint) |
| Feedback loop | Slower (full plan first) | Faster (per sprint) |
| Findings quality | More architectural | More tactical |
| Recommended for | Depth 3+ | Depth 1-2 |

---

## 6. Configuration

### 6.1 New Config Section

```yaml
# .loa.config.yaml
run_bridge:
  enabled: true
  defaults:
    depth: 3
    per_sprint: false
    flatline_threshold: 0.05
    consecutive_flatline: 2
  timeouts:
    per_iteration_hours: 4
    total_hours: 24
  github_trail:
    post_comments: true
    update_pr_body: true
    commit_prefix: "bridge"
  ground_truth:
    enabled: true
    max_tokens_per_section: 2000
    index_max_tokens: 500
  vision_registry:
    enabled: true
    auto_capture: true
  rtfm:
    enabled: true
    max_fix_iterations: 1
  lore:
    enabled: true
    categories:
      - mibera
      - neuromancer
```

### 6.2 Golden Path Integration

The `/loa` status command detects bridge state and provides appropriate guidance:

```bash
# In golden-path.sh, add:
golden_detect_bridge_state() {
    if [[ -f ".run/bridge-state.json" ]]; then
        local state
        state=$(jq -r '.state' .run/bridge-state.json 2>/dev/null)
        echo "$state"
    else
        echo "none"
    fi
}
```

When bridge state is ITERATING, `/loa` reports:
```
Bridge Loop: Iteration 2/3 (severity score: 4.0, initial: 15.5)
Next: Awaiting Bridgebuilder review → findings → sprint generation
```

---

## 7. Constraint Amendments

### 7.1 New Constraints

| ID | Name | Type | Text |
|----|------|------|------|
| C-BRIDGE-001 | `bridge_uses_run_sprint_plan` | ALWAYS | ALWAYS use `/run sprint-plan` (not direct `/implement`) within bridge iterations |
| C-BRIDGE-002 | `bridge_github_trail` | ALWAYS | ALWAYS post Bridgebuilder review as PR comment after each bridge iteration |
| C-BRIDGE-003 | `gt_grounding_required` | ALWAYS | ALWAYS ensure Grounded Truth claims cite `file:line` source references |
| C-BRIDGE-004 | `lore_yaml_format` | ALWAYS | ALWAYS use YAML format for lore entries with `id`, `term`, `short`, `context`, `source`, `tags` fields |
| C-BRIDGE-005 | `vision_traceability` | ALWAYS | ALWAYS include source bridge iteration and PR in vision entries |

### 7.2 Process Compliance

The bridge loop wraps `/run sprint-plan`, which already enforces the implement→review→audit cycle. The bridge loop adds Bridgebuilder review as an additional quality layer on top — it does not bypass any existing gates.

---

## 8. Error Handling

### 8.1 Error Taxonomy

| Error | Severity | Recovery |
|-------|----------|----------|
| Sprint plan execution HALTED | High | Save bridge state, create INCOMPLETE PR, await `/run-bridge --resume` |
| Bridgebuilder review fails | Medium | Skip review for this iteration, continue to next iteration |
| GT generation fails | Low | Log warning, skip GT, continue to PR |
| RTFM fails | Low | Log warning, include in PR summary |
| Vision capture fails | Low | Log warning, continue |
| GitHub trail fails (no `gh`) | Medium | Log locally, warn that trail is incomplete |
| Flatline detection error | Low | Default to "not flatlined", continue |

### 8.2 Partial Completion

If the bridge loop HALTs mid-iteration:
1. Bridge state saved with current iteration's progress
2. Any completed iterations' findings are preserved
3. PR created as `[INCOMPLETE]` with iteration summary table
4. `--resume` continues from the interrupted point

---

## 9. Testing Strategy

### 9.1 Framework Eval Tasks

| Task ID | What It Tests |
|---------|--------------|
| `bridge-state-schema-valid` | Bridge state JSON matches schema |
| `bridge-findings-parser-works` | Findings parser extracts structured data from review markdown |
| `gt-index-under-500-tokens` | Ground Truth index.md stays under token budget |
| `gt-checksums-match` | checksums.json matches actual file hashes |
| `lore-index-valid` | Lore index.yaml references existing files |
| `lore-entries-have-required-fields` | All lore entries have id, term, short, context, source, tags |
| `vision-entries-have-traceability` | Vision entries have source, PR, date fields |
| `golden-path-bridge-detection` | golden-path.sh detects bridge state correctly |

### 9.2 BATS Tests

| Test File | What It Tests |
|-----------|--------------|
| `bridge-orchestrator.bats` | State transitions, flatline detection, resume logic |
| `bridge-findings-parser.bats` | Markdown parsing, severity weighting, edge cases |
| `bridge-github-trail.bats` | Comment format, PR body update, vision links |
| `ground-truth-gen.bats` | Checksum generation, token budget validation |
| `lore-validation.bats` | YAML schema validation, cross-references |

### 9.3 Integration Tests

- Full bridge loop on a test fixture (2 iterations, --per-sprint, flatline at 2)
- GT generation on a known codebase with checksum verification
- RTFM pass on generated GT files

---

## 10. Implementation Phases

### Phase 1: Foundation — Lore KB + Vision Registry + GT Infrastructure (Sprint 1)

**Deliverables:**
1. `.claude/data/lore/` directory with core Mibera and Neuromancer entries
2. `grimoires/loa/visions/` directory with index.md template
3. `.claude/scripts/ground-truth-gen.sh` — checksum generation and validation
4. Riding-codebase SKILL.md extension with Phase 11 (GT generation)
5. Ride command extension with `--ground-truth` and `--non-interactive` flags
6. Lore validation tests (BATS + eval tasks)
7. GT validation tests (BATS + eval tasks)

### Phase 2: Bridge Core — Orchestrator + Findings Parser + State Management (Sprint 2)

**Deliverables:**
1. `.claude/scripts/bridge-orchestrator.sh` — main loop with state machine
2. `.claude/scripts/bridge-findings-parser.sh` — structured extraction
3. `.run/bridge-state.json` schema and state management
4. Findings-to-sprint-plan generator (agent-based)
5. Flatline detection algorithm
6. Resume and context recovery logic
7. Bridge orchestrator tests (BATS + eval tasks)

### Phase 3: GitHub Trail + Bridgebuilder Integration + RTFM Gate (Sprint 3)

**Deliverables:**
1. `.claude/scripts/bridge-github-trail.sh` — comment posting, PR updates
2. `.claude/scripts/bridge-vision-capture.sh` — vision extraction
3. Bridgebuilder BEAUVOIR.md extension for lore-aware reviews
4. Structured findings format in Bridgebuilder output
5. RTFM integration as post-loop gate
6. `/run-bridge` command and skill registration
7. Golden path bridge state detection
8. Configuration section in `.loa.config.yaml`
9. Constraint amendments
10. End-to-end integration tests
11. Version bump and CHANGELOG

---

## 11. Security Considerations

| Concern | Mitigation |
|---------|-----------|
| Bridge loop runs indefinitely | Hard depth limit (max 5), total timeout (24h), flatline detection |
| Bridgebuilder review posts to GitHub | Uses existing `gh` auth, draft PRs only, respects ICE |
| Lore injection via YAML | Lore files are in System Zone (.claude/data/), not user-editable |
| Vision entries contain unvalidated content | Visions are in State Zone (grimoires/), human review expected |
| GT checksums could be forged | Checksums computed from actual files at generation time |
| Sprint plans generated from findings | Goes through full implement→review→audit cycle |

---

## 12. Risk Mitigation

| Risk (from PRD) | Architectural Mitigation |
|-----------------|-------------------------|
| Bridge loop without meaningful findings | Flatline detection (2 consecutive below 5%) + hard depth limit |
| GT drifts from reality | Checksum verification + bridge loop regeneration at finalization |
| Bridgebuilder quality degrades at depth | Severity-weighted scoring ensures diminishing returns are detected |
| Lore feels forced | Optional integration (skills can opt out), curated corpus, `short` field for minimal references |
| RTFM creates circular fix loops | Single fix iteration cap |

---

## Next Step

After SDD approval: `/sprint-plan` to create sprint plan with task breakdown for Phases 1-3.
