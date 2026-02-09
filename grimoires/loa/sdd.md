# SDD: RTFM Testing — Documentation Quality via Fresh Agent Spawns

**Version**: 1.0.0
**Status**: Draft
**Author**: Architecture Phase (architect)
**Date**: 2026-02-09
**PRD**: grimoires/loa/prd.md

---

## 1. Executive Summary

The `/rtfm` skill tests documentation usability by spawning isolated zero-context agents that attempt tasks using only the provided docs. It is a pure Loa skill — SKILL.md + command file + tester prompt — with no build step, no compiled artifacts, and no runtime dependencies beyond Claude Code's `Task` tool.

The architecture follows three principles:
1. **Hermetic isolation** — the tester agent has zero project context
2. **Structured output** — gaps are machine-parseable for future pipeline integration
3. **Minimal surface** — ~3 files total, all markdown/YAML

---

## 2. System Architecture

### Component Overview

```
┌─────────────────────────────────────────────────┐
│                 /rtfm Command                    │
│            .claude/commands/rtfm.md              │
│                                                  │
│  1. Parse args (docs, task, flags)               │
│  2. Bundle doc contents                          │
│  3. Select task template (or custom)             │
│  4. Spawn tester subagent                        │
│  5. Parse gap report                             │
│  6. Present results                              │
│  7. Track iteration / write report               │
└──────────────────────┬──────────────────────────┘
                       │
                       │ Task(subagent_type="general-purpose")
                       │
          ┌────────────▼─────────────┐
          │    Tester Subagent       │
          │                          │
          │  Prompt = capabilities   │
          │        + rules           │
          │        + bundled docs    │
          │        + task            │
          │                          │
          │  Output = structured     │
          │          gap report      │
          └──────────┬───────────────┘
                     │
                     ▼
          ┌──────────────────────────┐
          │   Gap Report Parser      │
          │                          │
          │  Extract [GAP] markers   │
          │  Count by type/severity  │
          │  Determine verdict       │
          └──────────┬───────────────┘
                     │
                     ▼
          ┌──────────────────────────┐
          │   Report Writer          │
          │                          │
          │  grimoires/loa/a2a/rtfm/ │
          │  ├── report-{date}.md    │
          │  └── baselines.yaml      │
          └──────────────────────────┘
```

### Data Flow

```
User invokes /rtfm README.md --task "Install Loa"
  │
  ├── Read README.md contents → doc_bundle string
  │
  ├── Load tester prompt from SKILL.md <tester_prompt> section
  │     ├── Capabilities manifest (what tester knows/doesn't know)
  │     ├── Rules (no inference, be literal, report gaps)
  │     ├── Gap format template
  │     └── Output format template
  │
  ├── Assemble full prompt = tester_prompt + task + doc_bundle
  │
  ├── Task(prompt=assembled, subagent_type="general-purpose", model="sonnet")
  │     └── Returns: structured text with [GAP] markers and verdict
  │
  ├── Parse response:
  │     ├── Extract all [GAP] blocks
  │     ├── Count: total, blocking, degraded, minor
  │     ├── Determine verdict: SUCCESS / PARTIAL / FAILURE
  │     └── Calculate Cold Start Score (blocking count)
  │
  ├── Display summary to user
  │
  └── Write report to grimoires/loa/a2a/rtfm/report-{date}.md
```

---

## 3. File Structure

```
.claude/
├── skills/
│   └── rtfm-testing/
│       ├── SKILL.md           # Skill definition with tester prompt
│       └── index.yaml         # Skill metadata and triggers
├── commands/
│   └── rtfm.md                # Command definition with args/preflight
```

```
grimoires/loa/a2a/rtfm/
├── report-2026-02-09.md       # Test reports (one per run)
└── baselines.yaml             # Baseline registry (Phase 2)
```

Total: **3 files** to create (SKILL.md, index.yaml, rtfm.md), plus reports generated at runtime.

---

## 4. Component Design

### 4.1 Command File: `.claude/commands/rtfm.md`

```yaml
---
name: "rtfm"
version: "1.0.0"
description: "Test documentation usability by spawning zero-context agents"

arguments:
  - name: "docs"
    type: "string[]"
    required: false
    description: "Documentation files to test"
    examples: ["README.md", "INSTALLATION.md"]
  - name: "task"
    type: "string"
    required: false
    description: "Custom task for the tester to attempt"
    flag: "--task"
  - name: "template"
    type: "string"
    required: false
    description: "Pre-built task template ID"
    flag: "--template"
    examples: ["install", "quickstart", "mount"]
  - name: "auto"
    type: "boolean"
    required: false
    description: "Auto-detect docs changed in current sprint"
    flag: "--auto"
  - name: "model"
    type: "string"
    required: false
    description: "Model for tester subagent"
    flag: "--model"
    default: "sonnet"

agent: "rtfm-testing"
agent_path: "skills/rtfm-testing/"

pre_flight:
  - check: "file_exists_any"
    paths: ["$ARGUMENTS.docs"]
    error: "No documentation files found. Provide file paths or use --auto."

outputs:
  - path: "grimoires/loa/a2a/rtfm/"
    type: "directory"
    description: "RTFM test reports"

mode:
  default: "foreground"
  allow_background: false
---
```

### 4.2 Skill Metadata: `.claude/skills/rtfm-testing/index.yaml`

```yaml
name: "rtfm-testing"
version: "1.0.0"
model: "sonnet"
color: "cyan"

effort_hint: low
danger_level: safe
categories:
  - quality

description: |
  Test documentation usability by spawning fresh zero-context agents.
  Identifies gaps that human reviewers miss due to the curse of knowledge.

triggers:
  - "/rtfm"
  - "test documentation"
  - "validate docs usability"

inputs:
  - name: "docs"
    type: "string[]"
    required: false
  - name: "task"
    type: "string"
    required: false

outputs:
  - path: "grimoires/loa/a2a/rtfm/report-{date}.md"
    description: "RTFM test report with gaps and verdict"
    format: detailed
```

### 4.3 SKILL.md Structure

The SKILL.md contains these sections:

#### Objective

Spawn a zero-context agent to test documentation. Parse structured gap report. Track iterations. Write report.

#### Tester Capabilities Manifest

Embedded YAML defining the tester's "knowledge floor" (from PRD FR-2).

#### Tester Prompt (Cleanroom)

The prompt that instructs the tester agent. Key rules:
1. Use ONLY the docs — no prior knowledge
2. Be literal — ambiguity = gap
3. No inference — "install dependencies" without a command = gap
4. Report every gap in `[GAP]` format
5. Return structured output with verdict

#### Task Templates

Lookup table mapping template IDs to task descriptions and default doc files.

#### Gap Parser Logic

Instructions for extracting `[GAP]` markers, counting by type/severity, determining verdict.

#### Report Template

Markdown template for output.

#### Workflow

```
Phase 0: Argument Resolution
  - If --auto: detect doc files changed in current sprint
  - If --template: resolve to task + doc files
  - If positional args: use as doc file paths
  - If --task: use as custom task
  - Default: infer from primary doc filename

Phase 1: Document Bundling
  - Read each doc file
  - Concatenate with headers: "=== FILE: README.md ==="
  - Verify total size < 50KB (reject if larger)
  - Include context isolation canary

Phase 2: Tester Spawn
  - Assemble tester prompt + task + bundled docs
  - Task(prompt, subagent_type="general-purpose", model=config.model)
  - Wait for response

Phase 3: Gap Parsing
  - Parse [GAP] markers from response
  - Extract: type, location, problem, impact, severity, suggestion
  - Count totals
  - Determine verdict (SUCCESS/PARTIAL/FAILURE)

Phase 4: Report & Display
  - Write report to grimoires/loa/a2a/rtfm/report-{date}.md
  - Display summary: gap count, blocking count, verdict
  - If FAILURE/PARTIAL: suggest user fix gaps and re-run
  - Track iteration number

Phase 5: Baseline Check (Phase 2 scope)
  - If baselines.yaml exists and doc has baseline
  - If doc SHA differs from certified SHA
  - Warn about potential regression
```

### 4.4 Context Isolation Canary (Two-Layer)

#### Layer 1: Self-Report (Suggestive)

Embedded in the tester prompt — asks the tester to honestly report whether it recognizes the project from training data.

**Limitation**: LLMs cannot reliably distinguish "I know this from training data" from "I learned this from the docs." This is suggestive but not deterministic.

#### Layer 2: Planted Canary (Deterministic)

A fictitious project name is injected into the doc bundle via a `=== PROJECT CONTEXT ===` header. The gap parser checks whether the tester references the planted name or the real one.

- Uses the planted name → PASS (isolation verified mechanically)
- Uses the real name → COMPROMISED (prior knowledge detected)
- Uses neither → INCONCLUSIVE (fall back to Layer 1 result)

**Combined result** determines the canary status in the report: PASS, WARNING, or COMPROMISED. See SKILL.md `<planted_canary>` section for the full decision matrix.

---

## 5. Tester Prompt Design

### Structure

```
[CAPABILITIES MANIFEST]
You know: {knows list}
You do NOT know: {does_not_know list}

[RULES]
1. Use ONLY the docs below
2. Be literal — ambiguity = gap
3. No inference — missing how = gap
4. {canary check}

[GAP FORMAT]
[GAP] <TYPE>
Location: <where in docs>
Problem: <what's wrong>
Impact: <what you can't do>
Severity: BLOCKING | DEGRADED | MINOR
Suggestion: <what docs should say>

[OUTPUT FORMAT]
## Canary Check
{answer}

## Task Attempted
{restate task}

## Execution Log
{step by step}

## Gaps Found
{all [GAP] reports}

## Result
SUCCESS | PARTIAL | FAILURE

## Cold Start Score
{blocking gap count}

## Summary
{brief assessment}

---

TASK: {task}

---

DOCUMENTATION:

{bundled docs}
```

### Prompt Size Budget

| Component | Estimated Tokens |
|-----------|-----------------|
| Capabilities + rules + format | ~800 |
| Task description | ~50 |
| Bundled docs (README only) | ~1,500 |
| Bundled docs (INSTALLATION only) | ~5,000 |
| **Total (README only)** | **~2,350** |
| **Total (both docs)** | **~7,350** |

Response budget: ~2,000-4,000 tokens. Total cost: ~$0.02-0.04/iteration with sonnet.

---

## 6. Gap Report Schema

### Raw Format (from tester)

```
[GAP] MISSING_PREREQ
Location: Step 1 "Clone the repository"
Problem: No repository URL specified
Impact: Cannot clone the repository
Severity: BLOCKING
Suggestion: Add: git clone https://github.com/org/repo.git
```

### Parsed Summary

```markdown
| # | Type | Severity | Location | Problem |
|---|------|----------|----------|---------|
| 1 | MISSING_PREREQ | BLOCKING | Step 1 | No repo URL |
```

### Verdict Rules

| Condition | Verdict |
|-----------|---------|
| 0 blocking gaps | SUCCESS |
| >0 blocking but tester made partial progress | PARTIAL |
| Tester could not start or gave up | FAILURE |

---

## 7. Task Templates

```yaml
templates:
  install:
    task: "Install this tool on a fresh repository following only the documentation below."
    docs: ["INSTALLATION.md"]
  quickstart:
    task: "Follow the quick start guide to run your first development cycle."
    docs: ["README.md"]
  mount:
    task: "Install this framework onto an existing project repository."
    docs: ["README.md", "INSTALLATION.md"]
  beads:
    task: "Set up the beads_rust task tracking tool."
    docs: ["INSTALLATION.md"]
  gpt-review:
    task: "Configure the GPT cross-model review feature."
    docs: ["INSTALLATION.md"]
  update:
    task: "Update this framework to the latest version."
    docs: ["INSTALLATION.md"]
```

Default inference: `README.md` → `quickstart`, `INSTALLATION.md` → `install`, other → generic.

---

## 8. `/review` Integration (Phase 2)

### Doc Change Detection

```bash
git diff main...HEAD --name-only | grep -E '\.(md|txt|rst)$'
```

Filter to known doc files: README.md, INSTALLATION.md, PROCESS.md, docs/**/*.md.

### Golden Path Extension

`/review` would call `/rtfm --auto` after `/review-sprint` + `/audit-sprint`. Phase 2 scope.

---

## 9. Baseline Registry (Phase 2)

### File: `grimoires/loa/a2a/rtfm/baselines.yaml`

```yaml
baselines:
  README.md:
    task: "quickstart"
    cold_start_score: 1
    certified_date: "2026-02-15T10:30:00Z"
    certified_sha: "abc123def456"
    model: "sonnet"
```

On SUCCESS: update baseline. On doc change since certification: warn about drift.

---

## 10. Configuration

```yaml
# .loa.config.yaml
rtfm:
  enabled: true
  model: "sonnet"
  max_doc_size_kb: 50
  capabilities_override:
    knows: []
    does_not_know: []
  auto:
    enabled: true
    doc_patterns:
      - "README.md"
      - "INSTALLATION.md"
      - "PROCESS.md"
      - "docs/**/*.md"
```

---

## 11. Security Considerations

1. **Prompt injection via docs** — Tester has no elevated permissions, output is parsed not executed. Rules 7-8 in the tester prompt explicitly instruct the agent to treat docs as untrusted input and refuse conflicting instructions.
2. **Context isolation — Two-layer canary architecture**:
   - **Layer 1 (Self-report, suggestive)**: Tester is asked to report if it recognizes the project from training data. Limitation: LLMs cannot reliably introspect on knowledge provenance (Goodhart's Law). The smoke test confirmed this — the tester recognized Loa from training data.
   - **Layer 2 (Planted canary, deterministic)**: A fictitious project name is injected into the doc bundle. The parser mechanically checks whether the tester references the planted name or the real one. This catches name-level knowledge leakage without relying on self-reporting.
   - **Limitations**: Neither layer catches concept-level leakage (e.g., knowing what "grimoires" means without the docs explaining it). Planted names may coincidentally match real project names. Both layers together provide meaningful but not complete coverage.
3. **No file writes by tester** — The `general-purpose` subagent spawned via Task tool returns text output only and cannot write files in the parent session. This is an implementation characteristic of Claude Code's Task tool, not an explicitly enforced security boundary.
4. **Gap parser resilience** — The parser accepts format variants (bold markers, synonym severities) and falls back to MANUAL_REVIEW on unparseable output rather than silently dropping gaps. This prevents a compromised tester from hiding findings by using non-standard formatting.

---

## 12. Testing Strategy

1. Run `/rtfm README.md` — verify gaps found
2. Run `/rtfm INSTALLATION.md` — verify gaps found
3. Run `/rtfm README.md INSTALLATION.md` — verify combined flow
4. Run `/rtfm --template install` — verify template resolution
5. Run `/rtfm --task "custom" README.md` — verify custom tasks
6. Verify canary catches context leakage
7. Verify reports written to correct path
8. Model comparison: sonnet vs haiku gap counts (NFR-2)

---

## 13. Implementation Estimate

| Component | Files | Effort |
|-----------|-------|--------|
| SKILL.md | 1 | Medium |
| index.yaml | 1 | Low |
| rtfm.md command | 1 | Low |
| **Total** | **3 files** | **Low-Medium** |

---

## 14. References

- PRD: `grimoires/loa/prd.md`
- Bridgebuilder Review: PR #256 comments
- Skill reference: `.claude/skills/reviewing-code/` (architecture pattern)
- Command reference: `.claude/commands/validate.md` (command pattern)
