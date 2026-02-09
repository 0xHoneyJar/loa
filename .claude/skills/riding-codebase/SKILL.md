---
name: ride
description: Analyze codebase to extract reality into Loa artifacts
context: fork
agent: Explore
allowed-tools: Read, Grep, Glob, Bash(git *)
---

# Riding Through the Codebase

You are analyzing an existing codebase to generate evidence-grounded Loa artifacts following the v0.6.0 Enterprise-Grade Managed Scaffolding model.

> *"The Loa rides through the code, channeling truth into the grimoire."*

## Core Principles

```
CODE IS TRUTH → Loa channels CODE → Grimoire reflects REALITY
```

1. **Never trust documentation** - Verify everything against code
2. **Flag, don't fix** - Dead code/issues flagged for human decision
3. **Evidence required** - Every claim needs `file:line` citation
4. **Target repo awareness** - Grimoire lives WITH the code it documents

---

## Phase 0: Preflight & Mount Verification

### 0.1 Verify Loa is Mounted

Check for `.loa-version.json`. If missing, instruct user to run `/mount` first. Extract and display framework version.

### 0.2 System Zone Integrity Check (BLOCKING)

Verify `.claude/checksums.json` against actual file hashes. If drift detected:

- Display drifted files list
- Offer options: move customizations to `.claude/overrides/`, `--force-restore` to reset, `/update-loa --force-restore` to sync
- BLOCK unless `--force-restore` passed

If no checksums file exists (first ride), skip with warning.

### 0.3 Detect Execution Context

```bash
if [[ -f ".claude/commands/ride.md" ]] && [[ -d ".claude/skills/riding-codebase" ]]; then
  IS_FRAMEWORK_REPO=true
else
  IS_FRAMEWORK_REPO=false
  TARGET_REPO="$CURRENT_DIR"
fi
```

### 0.4 Target Resolution (Framework Repo Only)

If `IS_FRAMEWORK_REPO=true`, use `AskUserQuestion` to select target repo. The Loa rides codebases, not itself.

### 0.5 Initialize Ride Trajectory

```bash
TRAJECTORY_FILE="grimoires/loa/a2a/trajectory/riding-$(date +%Y%m%d).jsonl"
mkdir -p grimoires/loa/a2a/trajectory
```

Log preflight completion to trajectory.

---

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

### 4-Step Clearing

1. **Extract**: Max 10 files, 20 words per finding, with `file:line` refs
2. **Synthesize**: Write to `grimoires/loa/reality/` or NOTES.md
3. **Clear**: Remove raw output from context
4. **Summary**: `"Probe: N files → M relevant → reality/"`

### RLM Pattern Alignment

- **Retrieve**: Probe first, don't load eagerly
- **Load**: JIT retrieval of relevant sections only
- **Modify**: Synthesize to grimoire, clear working memory
</attention_budget>

---

## Phase 0.5: Codebase Probing (RLM Pattern)

Before loading any files, probe the codebase to determine optimal loading strategy.

### 0.5.1 Run Codebase Probe

Use `.claude/scripts/context-manager.sh probe "$TARGET_REPO" --json` to get file count, line count, estimated tokens, and codebase size category. Fall back to eager loading if probe unavailable.

### 0.5.2 Determine Loading Strategy

| Codebase Size | Lines | Strategy |
|---------------|-------|----------|
| Small | <10K | Full load — fits in context |
| Medium | 10K-50K | Prioritized — high-relevance first |
| Large | >50K | Excerpts only — too large for full load |

### 0.5.3 Generate Loading Plan

Create `grimoires/loa/reality/loading-plan.md` with files categorized by should-load decision. For prioritized/excerpts strategies, sort files by relevance score using `.claude/scripts/context-manager.sh should-load "$file" --json`.

Log probe results to trajectory.

---

## Phase 1: Interactive Context Discovery

### 1.1 Check for Existing Context

Scan `grimoires/loa/context/` for existing documentation files.

### 1.2 Context File Prompt

Use `AskUserQuestion` to offer the user a chance to add context files (architecture docs, tribal knowledge, roadmaps) to `grimoires/loa/context/` before the interview.

### 1.3 Analyze Existing Context (Pre-Interview)

If context files exist, analyze them BEFORE the interview. Generate `grimoires/loa/context/context-coverage.md` listing:
- Files analyzed with key topics
- Topics already covered (will skip in interview)
- Gaps to explore in interview
- Claims extracted to verify against code

### 1.4 Interactive Discovery (Gap-Focused Interview)

Use `AskUserQuestion` for each topic, skipping questions answered by context files:

1. **Architecture**: Project description, tech stack, organization, entry points
2. **Domain**: Core entities, external services, feature flags
3. **Tribal Knowledge** (Critical): Surprises, unwritten rules, untouchable areas, scary parts
4. **Work in Progress**: Intentionally incomplete code, planned features
5. **History**: Codebase age, architecture evolution

### 1.5 Generate Claims to Verify (MANDATORY OUTPUT)

**YOU MUST CREATE** `grimoires/loa/context/claims-to-verify.md` with tables for:
- Architecture Claims (claim, source, verification strategy)
- Domain Claims
- Tribal Knowledge (handle carefully)
- WIP Status

Even if interview is skipped, create this file from existing context.

### 1.6 Tool Result Clearing Checkpoint

Clear raw interview data. Summarize captured claims count and top investigation areas.

---

## Phase 2: Code Reality Extraction

### Setup

```bash
mkdir -p grimoires/loa/reality
cd "$TARGET_REPO"
```

Apply the loading strategy from Phase 0.5 to control which files get fully loaded, excerpted, or skipped.

### Extraction Steps

Execute the following extractions, writing results to `grimoires/loa/reality/`:

| Step | Output File | What to Extract |
|------|-------------|-----------------|
| 2.2 | `structure.md` | Directory tree (max depth 4, excluding node_modules/dist/build) |
| 2.3 | `api-routes.txt` | Route definitions (@Get, @Post, router.*, app.get, etc.) |
| 2.4 | `data-models.txt` | Models, entities, schemas, CREATE TABLE, interfaces |
| 2.5 | `env-vars.txt` | process.env.*, os.environ, os.Getenv references |
| 2.6 | `tech-debt.txt` | TODO, FIXME, HACK, XXX, @deprecated, @ts-ignore |
| 2.7 | `test-files.txt` | Test files (*.test.ts, *.spec.ts, *_test.go, test_*.py) |

**See**: `resources/references/deep-analysis-guide.md` for detailed extraction commands and loading strategy helpers.

### 2.8 Tool Result Clearing Checkpoint (MANDATORY)

Clear raw tool outputs. Report counts for routes, entities, env vars, tech debt, tests. Include loading strategy results (files loaded/excerpted/skipped, tokens saved).

---

## Phase 2b: Code Hygiene Audit

Generate `grimoires/loa/reality/hygiene-report.md` flagging potential issues for HUMAN DECISION:

- Files outside standard directories
- Potential temporary/WIP folders
- Commented-out code blocks
- Potential dependency conflicts

**See**: `resources/references/deep-analysis-guide.md` for the hygiene report template and dead code philosophy.

---

## Phase 3: Legacy Documentation Inventory

### 3.1 Find All Documentation

Find all .md, .rst, .txt, .adoc files (excluding node_modules, .git, grimoires/loa). Save to `grimoires/loa/legacy/doc-files.txt`.

### 3.2 Assess AI Guidance Quality (CLAUDE.md)

Score existing CLAUDE.md on: length (>50 lines), tech stack mentions, pattern/convention guidance, warnings. Score out of 7; below 5 is insufficient.

### 3.3 Create Inventory

Create `grimoires/loa/legacy/INVENTORY.md` listing all docs with type and key claims.

---

## Phase 4: Three-Way Drift Analysis

### 4.1 Drift Categories

| Category | Definition | Impact |
|----------|------------|--------|
| **Missing** | Code exists, no documentation | Medium |
| **Stale** | Docs exist, code changed | High |
| **Hallucinated** | Docs claim things code doesn't support | Critical |
| **Ghost** | Documented feature not in code | Critical |
| **Shadow** | Code exists, completely undocumented | Medium |
| **Aligned** | Documentation matches code | Healthy |

### 4.2 Legacy Claim Verification (MANDATORY)

Extract claims from legacy docs. For EACH claim, verify against code reality. Determine status: VERIFIED | STALE | HALLUCINATED | MISSING.

### 4.3 Generate Drift Report

Create `grimoires/loa/drift-report.md` with summary table, drift score, breakdown by type, critical items with verification evidence.

**See**: `resources/references/analysis-checklists.md` for the full drift report template.

Log drift analysis to trajectory.

---

## Phase 5: Consistency Analysis (MANDATORY OUTPUT)

**YOU MUST CREATE** `grimoires/loa/consistency-report.md`.

Analyze naming patterns (entities, functions, files), compute consistency score (1-10), identify conflicts and improvement opportunities. Flag breaking changes without implementing.

**See**: `resources/references/analysis-checklists.md` for the consistency report template.

Log to trajectory.

---

## Phase 6: Loa Artifact Generation (WITH GROUNDING MARKERS)

**MANDATORY**: Every claim in PRD and SDD MUST use grounding markers:

| Marker | When to Use |
|--------|-------------|
| `[GROUNDED]` | Direct code evidence with `file:line` citation |
| `[INFERRED]` | Logical deduction from multiple sources |
| `[ASSUMPTION]` | No direct evidence — needs validation |

### 6.1 Generate PRD

Create `grimoires/loa/prd.md` with evidence-grounded user types, features, and requirements. Include Source of Truth notice and Document Metadata.

### 6.2 Generate SDD

Create `grimoires/loa/sdd.md` with verified tech stack, module structure, data model, and API surface. All with grounding markers and evidence.

### 6.3 Grounding Summary Block

Append to BOTH PRD and SDD: counts and percentages of GROUNDED/INFERRED/ASSUMPTION claims, plus assumptions requiring validation.

**Quality Target**: >80% GROUNDED, <10% ASSUMPTION

**See**: `resources/references/output-formats.md` for PRD, SDD, and grounding summary templates.

Log to trajectory.

---

## Phase 6.5: Reality File Generation (Token-Optimized Codebase Interface)

Generate token-optimized reality files for the `/reality` command in `grimoires/loa/reality/`:

| File | Purpose | Token Budget |
|------|---------|-------------|
| `index.md` | Hub/routing file | < 500 |
| `api-surface.md` | Public function signatures, API endpoints | < 2000 |
| `types.md` | Type/interface definitions grouped by domain | < 2000 |
| `interfaces.md` | External integration patterns, webhooks | < 1000 |
| `structure.md` | Annotated directory tree, module responsibilities | < 1000 |
| `entry-points.md` | Main files, CLI commands, env requirements | < 500 |

Also generate `.reality-meta.json` with token counts and staleness threshold.

**Total budget**: < 7000 tokens across all files.

**See**: `resources/references/output-formats.md` for all reality file templates.

Log to trajectory.

---

## Phase 7: Governance Audit

Generate `grimoires/loa/governance-report.md`:

| Artifact | Check for |
|----------|-----------|
| CHANGELOG.md | Version history |
| CONTRIBUTING.md | Contribution process |
| SECURITY.md | Security disclosure policy |
| CODEOWNERS | Required reviewers |
| Semver tags | Release versioning |

---

## Phase 8: Legacy Deprecation

For each file in `legacy/doc-files.txt`, prepend a deprecation notice pointing to `grimoires/loa/prd.md` and `grimoires/loa/sdd.md` as the new source of truth, with reference to `grimoires/loa/drift-report.md`.

---

## Phase 9: Trajectory Self-Audit (MANDATORY OUTPUT)

**YOU MUST CREATE** `grimoires/loa/trajectory-audit.md`.

### 9.1 Review Generated Artifacts

Count grounding markers ([GROUNDED], [INFERRED], [ASSUMPTION]) in both PRD and SDD.

### 9.2 Generate Audit

Include: execution summary table (all phases with status/output/findings), grounding analysis for PRD and SDD, claims requiring validation, hallucination checklist, reasoning quality score (1-10).

**See**: `resources/references/analysis-checklists.md` for the full self-audit template.

**IMPORTANT**: If trajectory file is empty at Phase 9, flag as failure.

Log to trajectory.

---

## Phase 10: Maintenance Handoff

### 10.1 Update NOTES.md

Add session continuity entry and ride results (routes documented, entities, tech debt, drift score, governance gaps).

### 10.2 Completion Summary

```
The Loa Has Ridden

Grimoire Artifacts Created:
- grimoires/loa/prd.md (Product truth)
- grimoires/loa/sdd.md (System truth)
- grimoires/loa/drift-report.md (Three-way analysis)
- grimoires/loa/consistency-report.md (Pattern analysis)
- grimoires/loa/governance-report.md (Process gaps)
- grimoires/loa/reality/* (Raw extractions + token-optimized files)

Next Steps:
1. Review drift-report.md for critical issues
2. Address governance gaps
3. Schedule stakeholder PRD review
4. Run /implement for high-priority drift
```

---

## Uncertainty Protocol

If code behavior is ambiguous:

1. State: "I'm uncertain about [specific aspect]"
2. Quote the ambiguous code with `file:line`
3. List possible interpretations
4. Ask for clarification via `AskUserQuestion`
5. Log uncertainty in `NOTES.md`

**Never assume. Always ground in evidence.**

---

## Trajectory Logging (MANDATORY)

**YOU MUST LOG EACH PHASE** to `grimoires/loa/a2a/trajectory/riding-{date}.jsonl`.

### Log Format

Each phase appends a JSON line:

```json
{"timestamp": "ISO8601", "agent": "riding-codebase", "phase": N, "action": "phase_name", "status": "complete", "details": {...}}
```

### Phase-Specific Details

| Phase | Action | Key Details Fields |
|-------|--------|--------------------|
| 0 | `preflight` | `loa_version` |
| 0.5 | `codebase_probe` | `strategy`, `total_files`, `total_lines`, `estimated_tokens` |
| 1 | `claims_generated` | `claim_count`, `output` |
| 2 | `code_extraction` | `routes`, `entities`, `env_vars` |
| 2b | `hygiene_audit` | `items_flagged` |
| 3 | `legacy_inventory` | `docs_found` |
| 4 | `drift_analysis` | `drift_score`, `ghosts`, `shadows`, `stale` |
| 5 | `consistency_analysis` | `score`, `output` |
| 6 | `artifact_generation` | `prd_claims`, `sdd_claims`, `grounded_pct` |
| 6.5 | `reality_generation` | `files`, `total_tokens`, `within_budget` |
| 7 | `governance_audit` | `gaps` |
| 8 | `legacy_deprecation` | `files_marked` |
| 9 | `self_audit` | `quality_score`, `assumptions`, `output` |
| 10 | `handoff` | `total_duration_minutes` |
