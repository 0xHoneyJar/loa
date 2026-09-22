---
name: ride
description: Analyze codebase to extract reality into Loa artifacts
role: planning
context: fork
allowed-tools: Read, Grep, Glob, Write, Bash(git *)
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: true
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: heavy
---

# Riding Through the Codebase

You are analyzing an existing codebase to generate evidence-grounded Loa artifacts (PRD, SDD, drift and consistency reports) that reflect what the code actually does.

> *"The Loa rides through the code, channeling truth into the grimoire."*

## Core Principles

1. **Never trust documentation** - Verify everything against code
2. **Flag, don't fix** - Dead code/issues flagged for human decision
3. **Evidence required** - Every claim needs `file:line` citation
4. **Target repo awareness** - Grimoire lives WITH the code it documents

Artifacts tagged **WRITE TO DISK** below are created with `Write`, never rendered inline as a substitute; Glob-verify immediately (expect 1 match), retry once, and on repeat failure log `{"phase": N, "action": "write_failed", "artifact": "<name>", "status": "error"}` and continue — Phase 10.0's gate catches what still didn't land.

---

## Phase 0: Preflight & Mount Verification

Check for `.loa-version.json` (if missing, instruct the user to run `/mount` first; extract and display the framework version). Verify `.claude/checksums.json` against actual file hashes (BLOCKING): if drift is detected, display the drifted files, offer to move customizations to `.claude/overrides/` or reset via `--force-restore` / `/update-loa --force-restore`, and block unless `--force-restore` is passed; skip with a warning if no checksums file exists yet (first ride).

```bash
if [[ -f ".claude/commands/ride.md" ]] && [[ -d ".claude/skills/riding-codebase" ]]; then
  IS_FRAMEWORK_REPO=true
else
  IS_FRAMEWORK_REPO=false
  TARGET_REPO="$CURRENT_DIR"
fi
```

If `IS_FRAMEWORK_REPO=true`, use `AskUserQuestion` to select a target repo — the Loa rides codebases, not itself.

```bash
TRAJECTORY_FILE="grimoires/loa/a2a/trajectory/riding-$(date +%Y%m%d).jsonl"
mkdir -p grimoires/loa/a2a/trajectory
```

Log preflight completion to trajectory. Then, if `grimoires/loa/reality/.reality-meta.json` exists and `--fresh` was not passed, compare its `generated_at` timestamp against `ride.staleness_days` in `.loa.config.yaml` (default 7): if the artifacts are still fresh, ask via `AskUserQuestion` whether to re-analyze or skip (skipping exits with a message naming the existing artifact date); `--fresh` always proceeds, as does a missing meta file (first ride). Log the staleness status and artifact age to trajectory.

---

## Enrichment Flags (Opt-In Depth Control)

| Flag | Variable | Phase | Action name |
|------|----------|-------|-------------|
| `--with-gaps` | `ENRICH_GAPS` | 12: Gap Tracker | `gap_tracker` |
| `--with-decisions` | `ENRICH_DECISIONS` | 13: Decision Archaeology | `decision_archaeology` |
| `--with-terms` | `ENRICH_TERMS` | 14: Terminology Extraction | `terminology_extraction` |
| `--with-simplicity` | `ENRICH_SIMPLICITY` | 15: Over-Engineering Audit + shortcut ledger | `simplicity_audit` |

`--enriched` sets all four; unset flags default `false` (standard ride unchanged). Log the resolved set to trajectory (`{"phase": "flags", "action": "enrichment_flags_parsed", ...}`).

See `resources/enrichment-config.md` when any flag is set, for the threshold defaults each phase reads and the optional QMD integration.

---

<context_discipline>
<!-- @skill-include: start context_discipline | hash:582badb8 | DO NOT EDIT — generated from .claude/data/skill-includes/context_discipline.md -->
## Context Discipline

Follow `.claude/protocols/tool-result-clearing.md`. Thresholds: single result >2K tokens /
accumulated >5K / full file >3K / session total >15K → extract findings (≤10 files, ≤20 words
each, with file:line) to `grimoires/loa/NOTES.md`, then reason from the synthesis, not raw dumps.
Session start: read NOTES.md "Session Continuity". Session end / pre-compaction: update it
(decisions → Decision Log, discovered issues → Technical Debt).
<!-- @skill-include: end context_discipline -->
</context_discipline>

---

## Phase 0.5: Codebase Probing

Before loading any files, probe the codebase to pick a loading strategy. Run `.claude/scripts/context-manager.sh probe "$TARGET_REPO" --json` (fall back to eager loading if unavailable) for file count, lines, tokens, and size category:

| Codebase Size | Lines | Strategy |
|---------------|-------|----------|
| Small | <10K | Full load — fits in context |
| Medium | 10K-50K | Prioritized — high-relevance first |
| Large | >50K | Excerpts only — too large for full load |

Create `grimoires/loa/reality/loading-plan.md` with files categorized by should-load decision; for prioritized/excerpts strategies, sort by relevance score using `.claude/scripts/context-manager.sh should-load "$file" --json`. Log probe results to trajectory.

---

## Phase 1: Interactive Context Discovery

### 1.1 Context Discovery Setup

Scan `grimoires/loa/context/` for existing documentation files, then use `AskUserQuestion` to offer the user a chance to add more (architecture docs, tribal knowledge, roadmaps) to `grimoires/loa/context/` before the interview.

### 1.2 Analyze Existing Context (Pre-Interview)

If context files exist, analyze them before the interview and generate `grimoires/loa/context/context-coverage.md` listing the topics covered (skippable in the interview), the gaps still to explore, and the claims extracted to verify against code.

### 1.3 Interactive Discovery (Gap-Focused Interview)

Use `AskUserQuestion` for each topic, skipping questions answered by context files:

1. **Architecture**: Project description, tech stack, organization, entry points
2. **Domain**: Core entities, external services, feature flags
3. **Tribal Knowledge** (Critical): Surprises, unwritten rules, untouchable areas, scary parts
4. **Work in Progress**: Intentionally incomplete code, planned features
5. **History**: Codebase age, architecture evolution

### 1.4 Generate Claims to Verify

Create `grimoires/loa/context/claims-to-verify.md` with tables for: Architecture Claims (claim, source, verification strategy), Domain Claims, Tribal Knowledge (handle carefully), WIP Status - even if the interview was skipped, from existing context alone. **WRITE TO DISK.**

### 1.5 Tool Result Clearing Checkpoint

Clear raw interview data. Summarize captured claims count and top investigation areas.

---

## Phase 2: Code Reality Extraction

```bash
mkdir -p grimoires/loa/reality
cd "$TARGET_REPO"
```

Apply the loading strategy from Phase 0.5, then execute the following extractions, writing results to `grimoires/loa/reality/`:

| Step | Output File | What to Extract |
|------|-------------|-----------------|
| 2.2 | `structure.md` | Directory tree (max depth 4, excluding node_modules/dist/build) |
| 2.3 | `api-routes.txt` | Route definitions (@Get, @Post, router.*, app.get) |
| 2.4 | `data-models.txt` | Models, entities, schemas, CREATE TABLE, interfaces |
| 2.5 | `env-vars.txt` | process.env.*, os.environ, os.Getenv references |
| 2.6 | `tech-debt.txt` | TODO, FIXME, HACK, XXX, @deprecated, @ts-ignore |
| 2.7 | `test-files.txt` | Test files (*.test.ts, *.spec.ts, *_test.go, test_*.py) |

**See**: `resources/references/deep-analysis-guide.md` for detailed extraction commands and loading strategy helpers.

Clear raw tool outputs after extraction; report counts for routes, entities, env vars, tech debt, tests, plus loading-strategy results (files loaded/excerpted/skipped, tokens saved).

---

## Phase 2b: Code Hygiene Audit

Generate `grimoires/loa/reality/hygiene-report.md` flagging potential issues for HUMAN DECISION: files outside standard directories, potential temporary/WIP folders, commented-out code blocks, and potential dependency conflicts. **WRITE TO DISK.**

**See**: `resources/references/deep-analysis-guide.md` for the hygiene report template and dead code philosophy.

---

## Phase 3: Legacy Documentation Inventory

Find all .md, .rst, .txt, .adoc files (excluding node_modules, .git, grimoires/loa) and save to `grimoires/loa/legacy/doc-files.txt`. Score existing CLAUDE.md out of 7 (>50 lines, tech-stack mentions, pattern guidance, warnings; below 5 is insufficient). Create `grimoires/loa/legacy/INVENTORY.md` listing all docs with type and key claims. **WRITE TO DISK.**

---

## Phase 4: Three-Way Drift Analysis

| Category | Definition | Impact |
|----------|------------|--------|
| **Missing** | Code exists, no documentation | Medium |
| **Stale** | Docs exist, code changed | High |
| **Hallucinated** | Docs claim things code doesn't support | Critical |
| **Ghost** | Documented feature not in code | Critical |
| **Shadow** | Code exists, completely undocumented | Medium |
| **Aligned** | Documentation matches code | Healthy |

Extract claims from legacy docs and verify each against code reality (VERIFIED / STALE / HALLUCINATED / MISSING). Create `grimoires/loa/drift-report.md` with a summary table, drift score, breakdown by type, and critical items with verification evidence. **WRITE TO DISK.**

**See**: `resources/references/analysis-checklists.md` for the full drift report template.

Log drift analysis to trajectory.

---

## Phase 5: Consistency Analysis

Create `grimoires/loa/consistency-report.md`: naming-pattern analysis (entities, functions, files), a consistency score (1-10), conflicts/improvement opportunities, and breaking changes flagged (not implemented). **WRITE TO DISK.**

**See**: `resources/references/analysis-checklists.md` for the consistency report template.

Log to trajectory.

---

## Phase 6: Artifact Generation (Grounding Markers)

Every claim in PRD and SDD carries a grounding marker:

| Marker | When to Use |
|--------|-------------|
| `[GROUNDED]` | Direct code evidence with `file:line` citation |
| `[INFERRED]` | Logical deduction from multiple sources |
| `[ASSUMPTION]` | No direct evidence — needs validation |

See `resources/extended-markers.md` when enrichment phases (12-14) need richer attribution, for the `[CLAIMED]`/`[DISPUTED]`/`[UNKNOWN]` syntax and the BUTTERFREEZONE provenance tags.

### 6.1 Generate PRD

Create `grimoires/loa/prd.md`: evidence-grounded user types, features, requirements, a Source of Truth notice, and Document Metadata. **WRITE TO DISK.**

### 6.2 Generate SDD

Create `grimoires/loa/sdd.md` with verified tech stack, module structure, data model, and API surface. All with grounding markers and evidence. **WRITE TO DISK.**

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
| `architecture-overview.md` | System component diagram, data flows, tech stack, entry points | < 1500 |
| `.reality-meta.json` | Token counts and staleness threshold per file | — |

**Total budget**: < 8500 tokens (7000 base + 1500 for architecture-overview). **WRITE TO DISK** all eight, Glob-verified individually.

**See**: `resources/references/output-formats.md` for all reality file templates.

Log to trajectory.

---

## Phase 7: Governance Audit

Generate `grimoires/loa/governance-report.md`. **WRITE TO DISK.**

| Artifact | Check for |
|----------|-----------|
| CHANGELOG.md | Version history |
| CONTRIBUTING.md | Contribution process |
| SECURITY.md | Security disclosure policy |
| CODEOWNERS | Required reviewers |
| Semver tags | Release versioning |

---

## Phase 8: Legacy Deprecation

For each file in `legacy/doc-files.txt`, prepend a deprecation notice pointing to `grimoires/loa/prd.md` and `grimoires/loa/sdd.md` as the new source of truth, referencing `grimoires/loa/drift-report.md`.

---

## Phase 9: Trajectory Self-Audit

Create `grimoires/loa/trajectory-audit.md`. **WRITE TO DISK.**

### 9.1 Review Generated Artifacts

Count grounding markers ([GROUNDED], [INFERRED], [ASSUMPTION]) in both PRD and SDD.

### 9.2 Generate Audit

Include: execution summary table (all phases with status/output/findings), grounding analysis for PRD and SDD, claims requiring validation, hallucination checklist, reasoning quality score (1-10).

**See**: `resources/references/analysis-checklists.md` for the full self-audit template.

An empty trajectory file at this point is a failure. Log to trajectory.

---

## Phase 10: Maintenance Handoff

### 10.0 Artifact Verification Gate (BLOCKING)

Before handoff, Glob-verify every expected artifact exists on disk:

| Artifact | Path |
|----------|------|
| Claims to Verify | `grimoires/loa/context/claims-to-verify.md` |
| Hygiene Report | `grimoires/loa/reality/hygiene-report.md` |
| Drift Report | `grimoires/loa/drift-report.md` |
| Consistency Report | `grimoires/loa/consistency-report.md` |
| PRD | `grimoires/loa/prd.md` |
| SDD | `grimoires/loa/sdd.md` |
| Reality Index | `grimoires/loa/reality/index.md` |
| Governance Report | `grimoires/loa/governance-report.md` |
| Trajectory Audit | `grimoires/loa/trajectory-audit.md` |
| Reality Meta | `grimoires/loa/reality/.reality-meta.json` |
| Legacy Inventory | `grimoires/loa/legacy/INVENTORY.md` |
| Gap Tracker (`ENRICH_GAPS`) | `grimoires/loa/gaps.md` |
| Decision Archaeology (`ENRICH_DECISIONS`) | `grimoires/loa/reality/decisions.md` |
| Domain Terminology (`ENRICH_TERMS`) | `grimoires/loa/reality/terminology.md` |

Count passed/total; retry writing any missing artifact from context and re-verify; log the result. Flag the ride as failed on 0/N verified, or if a critical artifact (drift-report, consistency-report, governance-report, trajectory-audit, hygiene-report) is still missing after the retry.

### 10.1 Update NOTES.md

Add session continuity entry and ride results (routes documented, entities, tech debt, drift score, governance gaps).

### 10.2 Completion Summary

See `resources/completion-summary.md` when the ride finishes, to render the final summary (artifact list, enrichment outputs, next steps) verbatim.

---

## Phase 11: Ground Truth Generation (`--ground-truth` only)

Runs only with `--ground-truth`: produces a token-efficient, deterministically-verified codebase summary for agent consumption. With `--non-interactive` also passed, phases 1, 3, and 8 are skipped — only extraction, analysis, and GT generation run.

**See**: `resources/references/enrichment-phases.md#phase-11-ground-truth-generation` for the full procedure.

---

## Phases 12-15: Enrichment (opt-in, one skip condition)

Each phase (flag/action in the table above) runs only when set, else skip and log `{"phase": N, "action": "<action>", "status": "skipped", "details": {"reason": "<VARIABLE> not set"}}`. Full procedures: `resources/references/enrichment-phases.md` (each phase's own `#phase-NN-...` anchor).

---

## Uncertainty Protocol

If code behavior is ambiguous, state what's unclear, quote the ambiguous code with `file:line`, list the possible interpretations, ask via `AskUserQuestion`, and log it in `NOTES.md`.

---

## Trajectory Logging

Each phase appends a JSON line to `grimoires/loa/a2a/trajectory/riding-{date}.jsonl`: `{"timestamp": "ISO8601", "agent": "riding-codebase", "phase": N, "action": "phase_name", "status": "complete", "details": {...}}`.

See `resources/trajectory-fields.md` when logging a phase, for the exact `action`/`details` fields per phase.
