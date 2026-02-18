---
name: ride
description: Analyze codebase to extract reality into Loa artifacts
context: fork
agent: Explore
allowed-tools: Read, Grep, Glob, Write, Bash(git *)
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

### 0.6 Artifact Staleness Check

If `grimoires/loa/reality/.reality-meta.json` exists:

1. Read `generated_at` timestamp from the JSON
2. Read `ride.staleness_days` from `.loa.config.yaml` (default: 7)
3. If artifacts are fresh (< staleness_days old) AND `--fresh` flag NOT passed:
   - Use `AskUserQuestion`: "Ride artifacts are N days old. [R]e-analyze or [S]kip?"
   - If skip: Exit with message "Using existing ride artifacts from [date]"
4. If `--fresh` flag: proceed regardless of artifact age
5. If `.reality-meta.json` does not exist: proceed (first ride)

Log staleness check to trajectory:
```json
{"phase": 0.6, "action": "staleness_check", "status": "fresh|stale|first_ride", "artifact_age_days": N}
```

---

## Enrichment Flags (Opt-In Depth Control)

Parse the user's invocation text for enrichment flags. These control whether optional Phases 12-14 run after the standard ride.

### Flag Detection

Scan the user's invocation for these flags:

| Flag | Variable | Default | Effect |
|------|----------|---------|--------|
| `--with-gaps` | `ENRICH_GAPS` | `false` | Enable Phase 12: Gap Tracker |
| `--with-decisions` | `ENRICH_DECISIONS` | `false` | Enable Phase 13: Decision Archaeology |
| `--with-terms` | `ENRICH_TERMS` | `false` | Enable Phase 14: Terminology Extraction |
| `--enriched` | Sets all three above | `false` | Enable all enrichment phases |

### Parsing Rules

1. If `--enriched` is present, set `ENRICH_GAPS=true`, `ENRICH_DECISIONS=true`, `ENRICH_TERMS=true`
2. Individual flags can be combined: `--with-gaps --with-decisions`
3. If NO enrichment flags are present, all variables remain `false` — standard ride proceeds unchanged
4. Log parsed flags to trajectory:
```json
{"phase": "flags", "action": "enrichment_flags_parsed", "status": "complete", "details": {"ENRICH_GAPS": false, "ENRICH_DECISIONS": false, "ENRICH_TERMS": false}}
```

### Configuration Defaults

Read enrichment thresholds from `.loa.config.yaml` (used by Phases 12-14):

```bash
# Gap tracker thresholds
GAP_MAX_OPEN=$(yq eval '.ride.enrichment.gaps.max_open // 200' .loa.config.yaml 2>/dev/null || echo "200")
GAP_WARN_AT=$(yq eval '.ride.enrichment.gaps.warn_at // 150' .loa.config.yaml 2>/dev/null || echo "150")

# Decision archaeology thresholds
DECISION_STALE_MONTHS=$(yq eval '.ride.enrichment.decisions.stale_months // 12' .loa.config.yaml 2>/dev/null || echo "12")
DECISION_EXTRA_PATHS=$(yq eval '.ride.enrichment.decisions.extra_paths // []' .loa.config.yaml 2>/dev/null || echo "[]")

# Terminology thresholds
TERM_MAX_TERMS=$(yq eval '.ride.enrichment.terminology.max_terms // 50' .loa.config.yaml 2>/dev/null || echo "50")
```

### QMD Reality Context (Optional)

During drift analysis, if `.claude/scripts/qmd-context-query.sh` exists and `qmd_context.enabled` is not `false`:

1. Build query from module names being analyzed
2. Run: `.claude/scripts/qmd-context-query.sh --query "<module_names>" --scope reality --budget 2000 --format text`
3. Include output as additional context during drift comparison
4. If script missing, disabled, or returns empty: proceed normally (graceful no-op)

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

### 1.6 File Persistence Checkpoint (CP-1)

**WRITE TO DISK**: Use the `Write` tool to persist `grimoires/loa/context/claims-to-verify.md`.

After writing, verify with `Glob` pattern `grimoires/loa/context/claims-to-verify.md` — must return 1 match. If missing after Write, retry once. If still missing, log to trajectory:
```json
{"phase": 1, "action": "write_failed", "artifact": "claims-to-verify.md", "status": "error"}
```

**Do NOT render the artifact inline without also writing it to disk.**

### 1.7 Tool Result Clearing Checkpoint

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

### 2b.1 File Persistence Checkpoint (CP-2b)

**WRITE TO DISK**: Use the `Write` tool to persist `grimoires/loa/reality/hygiene-report.md`.

After writing, verify with `Glob` pattern `grimoires/loa/reality/hygiene-report.md` — must return 1 match. If missing after Write, retry once. If still missing, log to trajectory:
```json
{"phase": "2b", "action": "write_failed", "artifact": "hygiene-report.md", "status": "error"}
```

---

## Phase 3: Legacy Documentation Inventory

### 3.1 Find All Documentation

Find all .md, .rst, .txt, .adoc files (excluding node_modules, .git, grimoires/loa). Save to `grimoires/loa/legacy/doc-files.txt`.

### 3.2 Assess AI Guidance Quality (CLAUDE.md)

Score existing CLAUDE.md on: length (>50 lines), tech stack mentions, pattern/convention guidance, warnings. Score out of 7; below 5 is insufficient.

### 3.3 Create Inventory

Create `grimoires/loa/legacy/INVENTORY.md` listing all docs with type and key claims.

### 3.4 File Persistence Checkpoint (CP-3)

**WRITE TO DISK**: Use the `Write` tool to persist `grimoires/loa/legacy/INVENTORY.md`.

After writing, verify with `Glob` pattern `grimoires/loa/legacy/INVENTORY.md` — must return 1 match. If missing after Write, retry once. If still missing, log to trajectory:
```json
{"phase": 3, "action": "write_failed", "artifact": "INVENTORY.md", "status": "error"}
```

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

### 4.4 File Persistence Checkpoint (CP-4)

**WRITE TO DISK**: Use the `Write` tool to persist `grimoires/loa/drift-report.md`.

After writing, verify with `Glob` pattern `grimoires/loa/drift-report.md` — must return 1 match. If missing after Write, retry once. If still missing, log to trajectory:
```json
{"phase": 4, "action": "write_failed", "artifact": "drift-report.md", "status": "error"}
```

---

## Phase 5: Consistency Analysis (MANDATORY OUTPUT)

**YOU MUST CREATE** `grimoires/loa/consistency-report.md`.

Analyze naming patterns (entities, functions, files), compute consistency score (1-10), identify conflicts and improvement opportunities. Flag breaking changes without implementing.

**See**: `resources/references/analysis-checklists.md` for the consistency report template.

Log to trajectory.

### 5.1 File Persistence Checkpoint (CP-5)

**WRITE TO DISK**: Use the `Write` tool to persist `grimoires/loa/consistency-report.md`.

After writing, verify with `Glob` pattern `grimoires/loa/consistency-report.md` — must return 1 match. If missing after Write, retry once. If still missing, log to trajectory:
```json
{"phase": 5, "action": "write_failed", "artifact": "consistency-report.md", "status": "error"}
```

---

## Phase 6: Loa Artifact Generation (WITH GROUNDING MARKERS)

**MANDATORY**: Every claim in PRD and SDD MUST use grounding markers:

| Marker | When to Use |
|--------|-------------|
| `[GROUNDED]` | Direct code evidence with `file:line` citation |
| `[INFERRED]` | Logical deduction from multiple sources |
| `[ASSUMPTION]` | No direct evidence — needs validation |

**Extended Markers** (available when enrichment phases run):

| Marker | When to Use | Example |
|--------|-------------|---------|
| `[CLAIMED: source]` | Single-source evidence with attribution | `[CLAIMED: ADR-003 — Dynamic over Privy]` |
| `[DISPUTED: A vs B]` | Conflicting signals between sources | `[DISPUTED: README says Redis, code uses in-memory]` |
| `[UNKNOWN: GAP-NNN]` | Linked to gap tracker entry | `[UNKNOWN: GAP-007 — auth session TTL]` |

These extended markers complement (not replace) the standard markers above and the BUTTERFREEZONE provenance tags (`CODE-FACTUAL`, `DERIVED`, `OPERATIONAL`). Use them in reality files (`grimoires/loa/reality/*.md`) and the gap tracker when enrichment phases produce evidence that warrants richer attribution.

### 6.1 Generate PRD

Create `grimoires/loa/prd.md` with evidence-grounded user types, features, and requirements. Include Source of Truth notice and Document Metadata.

### 6.2 Generate SDD

Create `grimoires/loa/sdd.md` with verified tech stack, module structure, data model, and API surface. All with grounding markers and evidence.

### 6.3 Grounding Summary Block

Append to BOTH PRD and SDD: counts and percentages of GROUNDED/INFERRED/ASSUMPTION claims, plus assumptions requiring validation.

**Quality Target**: >80% GROUNDED, <10% ASSUMPTION

**See**: `resources/references/output-formats.md` for PRD, SDD, and grounding summary templates.

Log to trajectory.

### 6.4 File Persistence Checkpoint (CP-6a, CP-6b)

**WRITE TO DISK**: Use the `Write` tool to persist BOTH artifacts:

| File | Path |
|------|------|
| PRD | `grimoires/loa/prd.md` |
| SDD | `grimoires/loa/sdd.md` |

After writing each, verify with `Glob` — must return 1 match per file. If either missing after Write, retry once. If still missing, log to trajectory:
```json
{"phase": 6, "action": "write_failed", "artifact": "prd.md|sdd.md", "status": "error"}
```

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

Also generate `.reality-meta.json` with token counts and staleness threshold.

**Total budget**: < 8500 tokens across all files (7000 base + 1500 architecture-overview).

**See**: `resources/references/output-formats.md` for all reality file templates.

Log to trajectory.

### 6.5.1 File Persistence Checkpoint (CP-6.5)

**WRITE TO DISK**: Use the `Write` tool to persist ALL reality files:

| File | Path |
|------|------|
| Index | `grimoires/loa/reality/index.md` |
| API Surface | `grimoires/loa/reality/api-surface.md` |
| Types | `grimoires/loa/reality/types.md` |
| Interfaces | `grimoires/loa/reality/interfaces.md` |
| Structure | `grimoires/loa/reality/structure.md` |
| Entry Points | `grimoires/loa/reality/entry-points.md` |
| Architecture Overview | `grimoires/loa/reality/architecture-overview.md` |
| Reality Meta | `grimoires/loa/reality/.reality-meta.json` |

After writing each file, verify with `Glob` — each must return 1 match. Log any failures to trajectory:
```json
{"phase": 6.5, "action": "write_failed", "artifact": "{filename}", "status": "error"}
```

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

### 7.1 File Persistence Checkpoint (CP-7)

**WRITE TO DISK**: Use the `Write` tool to persist `grimoires/loa/governance-report.md`.

After writing, verify with `Glob` pattern `grimoires/loa/governance-report.md` — must return 1 match. If missing after Write, retry once. If still missing, log to trajectory:
```json
{"phase": 7, "action": "write_failed", "artifact": "governance-report.md", "status": "error"}
```

---

## Phase 8: Legacy Deprecation

For each file in `legacy/doc-files.txt`, prepend a deprecation notice pointing to `grimoires/loa/prd.md` and `grimoires/loa/sdd.md` as the new source of truth, with reference to `grimoires/loa/drift-report.md`.

> **Checkpoint coverage note**: Phases 2 (extraction), 3 (`doc-files.txt`), and 8 (deprecation) produce intermediate or modified artifacts not covered by write checkpoints. Phase 2 extractions are working data consumed immediately by later phases. Phase 3's `INVENTORY.md` is covered by CP-3; `doc-files.txt` is an intermediate file. Phase 8 modifies existing files rather than creating new ones, so existence checks do not apply.

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

### 9.3 File Persistence Checkpoint (CP-9)

**WRITE TO DISK**: Use the `Write` tool to persist `grimoires/loa/trajectory-audit.md`.

After writing, verify with `Glob` pattern `grimoires/loa/trajectory-audit.md` — must return 1 match. If missing after Write, retry once. If still missing, log to trajectory:
```json
{"phase": 9, "action": "write_failed", "artifact": "trajectory-audit.md", "status": "error"}
```

---

## Phase 10: Maintenance Handoff

### 10.0 Artifact Verification Gate (BLOCKING)

Before handoff, verify ALL expected artifacts exist on disk using `Glob`.

**Full Mode Checklist**:

| # | Artifact | Path |
|---|----------|------|
| 1 | Claims to Verify | `grimoires/loa/context/claims-to-verify.md` |
| 2 | Hygiene Report | `grimoires/loa/reality/hygiene-report.md` |
| 3 | Drift Report | `grimoires/loa/drift-report.md` |
| 4 | Consistency Report | `grimoires/loa/consistency-report.md` |
| 5 | PRD | `grimoires/loa/prd.md` |
| 6 | SDD | `grimoires/loa/sdd.md` |
| 7 | Reality Index | `grimoires/loa/reality/index.md` |
| 8 | Governance Report | `grimoires/loa/governance-report.md` |
| 9 | Trajectory Audit | `grimoires/loa/trajectory-audit.md` |
| 10 | Reality Meta | `grimoires/loa/reality/.reality-meta.json` |
| 11 | Legacy Inventory | `grimoires/loa/legacy/INVENTORY.md` |

**Enrichment Artifacts** (check only when corresponding flag was set):

| # | Artifact | Path | Condition |
|---|----------|------|-----------|
| 12 | Gap Tracker | `grimoires/loa/gaps.md` | `ENRICH_GAPS == true` |
| 13 | Decision Archaeology | `grimoires/loa/reality/decisions.md` | `ENRICH_DECISIONS == true` |
| 14 | Domain Terminology | `grimoires/loa/reality/terminology.md` | `ENRICH_TERMS == true` |

**Procedure**:
1. For each file, use `Glob` to verify existence
2. Count: passed / total
3. If any missing: attempt to write from context, then re-verify
4. Report final count in completion summary
5. Log verification to trajectory

**The ride MUST NOT complete with 0/N artifacts verified.** If critical artifacts (drift-report, consistency-report, governance-report, trajectory-audit, hygiene-report) are missing, flag as ride failure.

### 10.1 Update NOTES.md

Add session continuity entry and ride results (routes documented, entities, tech debt, drift score, governance gaps).

### 10.2 Completion Summary

```
The Loa Has Ridden

Artifact Verification: X/Y files persisted

Grimoire Artifacts Created:
- grimoires/loa/prd.md (Product truth)
- grimoires/loa/sdd.md (System truth)
- grimoires/loa/drift-report.md (Three-way analysis)
- grimoires/loa/consistency-report.md (Pattern analysis)
- grimoires/loa/governance-report.md (Process gaps)
- grimoires/loa/reality/* (Raw extractions + token-optimized files)
- grimoires/loa/trajectory-audit.md (Self-audit)

Enrichment Outputs (if enabled):
- grimoires/loa/gaps.md (Gap tracker — if --with-gaps)
- grimoires/loa/reality/decisions.md (Decision archaeology — if --with-decisions)
- grimoires/loa/reality/terminology.md (Domain terminology — if --with-terms)

Next Steps:
1. Review drift-report.md for critical issues
2. Address governance gaps
3. /translate-ride for executive communications
4. Schedule stakeholder PRD review
5. Run /implement for high-priority drift
6. Review gaps.md and resolve open gaps (if enrichment ran)
```

---

## Phase 11: Ground Truth Generation (`--ground-truth` only)

This phase runs only when the `--ground-truth` flag is passed. It produces a token-efficient, deterministically-verified codebase summary for agent consumption.

When `--ground-truth --non-interactive` is passed, phases 1 (Interactive Context Discovery), 3 (Legacy Doc Inventory), and 8 (Legacy Deprecation) are skipped — only extraction, analysis, and GT generation run.

### 11.1 Read Reality Extraction Results

Read the reality/ files generated in Phase 2 and Phase 6.5. These contain the code truth that GT will summarize.

### 11.2 Synthesize GT Files

Generate hub-and-spoke Ground Truth files:

| File | Purpose | Token Budget |
|------|---------|-------------|
| `index.md` | Hub document with navigation and quick stats | ~500 |
| `api-surface.md` | Public APIs, endpoints, exports | ~2000 |
| `architecture.md` | System topology, data flow, dependencies | ~2000 |
| `contracts.md` | Inter-system contracts, types, interfaces | ~2000 |
| `behaviors.md` | Runtime behaviors, triggers, thresholds | ~2000 |

Every factual claim MUST cite a source file and line range (`file:line`). The grounding ratio must be >= 0.95.

### 11.3 Generate Checksums

Invoke `ground-truth-gen.sh` for mechanical operations:

```bash
.claude/scripts/ground-truth-gen.sh \
  --reality-dir grimoires/loa/reality/ \
  --output-dir grimoires/loa/ground-truth/ \
  --max-tokens-per-section 2000 \
  --mode checksums
```

This produces `checksums.json` with SHA-256 hashes of all referenced source files.

### 11.4 Validate Token Budget

```bash
.claude/scripts/ground-truth-gen.sh \
  --output-dir grimoires/loa/ground-truth/ \
  --max-tokens-per-section 2000 \
  --mode validate
```

If any section exceeds its token budget, trim content (prioritize most-referenced APIs/components) and re-validate.

### 11.5 Log to Trajectory

```json
{"phase": 11, "action": "ground_truth_generation", "status": "complete", "details": {"files": 5, "total_tokens": N, "checksums_count": N, "within_budget": true}}
```

---

## Phase 12: Gap Tracker Generation (`ENRICH_GAPS` only)

**Skip condition**: If `ENRICH_GAPS == false`, skip this entire phase. Log skip to trajectory:
```json
{"phase": 12, "action": "gap_tracker", "status": "skipped", "details": {"reason": "ENRICH_GAPS not set"}}
```

### 12.1 Load Existing Gaps and Generate Session Hash

Read `grimoires/loa/gaps.md` if it exists. Extract the highest `GAP-NNN` numeric ID to determine the next available ID. If file doesn't exist, start at `GAP-001`. Generate a session-scoped hash to prevent concurrent ID collisions.

```bash
# Extract highest gap ID (handles both GAP-NNN and GAP-NNN-HASH formats)
NEXT_GAP_ID=1
if [[ -f grimoires/loa/gaps.md ]]; then
  HIGHEST=$(grep -oP 'GAP-\K[0-9]+' grimoires/loa/gaps.md | sort -n | tail -1)
  NEXT_GAP_ID=$((HIGHEST + 1))
fi

# Generate 4-character session hash for concurrent safety
SESSION_HASH=$(date +%s%N | sha256sum | head -c 4)
```

**Gap ID format**: `GAP-{NNN}-{SESSION_HASH}` (e.g., `GAP-005-a3f2`). The session hash ensures that concurrent `/ride --with-gaps` sessions produce unique IDs even if they read the same highest NNN value before either writes. Existing `GAP-NNN` entries (without hash) remain valid — the numeric extraction regex accepts both formats.

### 12.2 Collect Gap Sources

Scan the following ride artifacts for unknowns, unresolved items, and missing context:

| Source | What to Look For |
|--------|-----------------|
| `grimoires/loa/context/claims-to-verify.md` | Claims with status UNVERIFIED or MISSING |
| `grimoires/loa/drift-report.md` | Drift items marked HALLUCINATED or GHOST |
| `grimoires/loa/governance-report.md` | Missing governance artifacts |
| Interview responses (Phase 1) | Questions the user couldn't answer |
| `grimoires/loa/reality/hygiene-report.md` | Unexplained code patterns |

For each identified gap, assign:
- **Type**: `Fact` | `Data` | `Interview` | `Context` | `Technical`
- **Priority**: `P0` (blocks agent work) | `P1` (degrades agent quality) | `P2` (nice to know)
- **Source**: Phase and artifact where gap was identified

### 12.3 Write Gap Tracker

Write `grimoires/loa/gaps.md` with the following schema. If the file already exists, **append** new gaps to the `## Open Gaps` section — never overwrite or remove existing entries.

```markdown
# Gap Tracker

> Auto-generated by /ride --with-gaps. Gaps are NEVER auto-resolved — only humans close them.
> Generated: YYYY-MM-DD

## Open Gaps

### GAP-NNN-HASH: [Short description]
- **Type**: Fact | Data | Interview | Context | Technical
- **Priority**: P0 | P1 | P2
- **Source**: /ride Phase N, [artifact or file:line]
- **Context**: Why this matters for agent work
- **Status**: OPEN
- **Opened**: YYYY-MM-DD
- **Resolution**: _pending human input_

## Resolved Gaps

_Gaps are moved here by humans only. Agents MUST NOT modify this section._
```

### 12.4 Gap Count Validation

Check gap counts against configured thresholds:

```
IF total_open_gaps >= GAP_MAX_OPEN:
  → Log ERROR to trajectory and NOTES.md:
    "Gap tracker has N open gaps (max: GAP_MAX_OPEN). Review and resolve gaps before adding more."
  → Still write the file, but add warning banner

ELSE IF total_open_gaps >= GAP_WARN_AT:
  → Log WARNING to trajectory:
    "Gap tracker approaching limit: N/GAP_MAX_OPEN open gaps"
```

### 12.5 File Persistence Checkpoint (CP-12)

**WRITE TO DISK**: Use the `Write` tool to persist `grimoires/loa/gaps.md`.

After writing, verify with `Glob` pattern `grimoires/loa/gaps.md` — must return 1 match. If missing after Write, retry once. If still missing, log to trajectory:
```json
{"phase": 12, "action": "write_failed", "artifact": "gaps.md", "status": "error"}
```

### Gap Tracker Rules

| Rule | Description |
|------|-------------|
| Agents MAY create gaps | Append to Open Gaps section with next monotonic ID + session hash |
| Agents MUST NOT resolve gaps | Only humans move gaps to Resolved section |
| IDs are session-scoped | Format: `GAP-{NNN}-{HASH}`. NNN is monotonically increasing; HASH is per-session for concurrent safety |
| Backward compatible | Existing `GAP-NNN` entries (no hash) remain valid and parseable |
| Append-only for new gaps | Subsequent /ride runs append, never overwrite existing entries |
| Check before assuming | Agents SHOULD read gap tracker before making assumptions about unknown context |

Log phase completion to trajectory:
```json
{"phase": 12, "action": "gap_tracker", "status": "complete", "details": {"new_gaps": N, "total_open": N, "highest_id": "GAP-NNN-HASH", "session_hash": "HASH", "threshold_status": "ok|warning|exceeded"}}
```

---

## Phase 13: Decision Archaeology (`ENRICH_DECISIONS` only)

**Skip condition**: If `ENRICH_DECISIONS == false`, skip this entire phase. Log skip to trajectory:
```json
{"phase": 13, "action": "decision_archaeology", "status": "skipped", "details": {"reason": "ENRICH_DECISIONS not set"}}
```

### 13.1 ADR Directory Detection

Search for architectural decision records in these locations (in order):

| Priority | Path Pattern | Convention |
|----------|-------------|------------|
| 1 | `docs/decisions/` or `docs/adr/` | Common patterns |
| 2 | `adr/` | Root-level ADR directory |
| 3 | `knowledge/decisions/` | Hivemind pattern |
| 4 | `docs/architecture/decisions/` | Nested architecture pattern |
| 5 | `.adr-dir` file contents | adr-tools convention (file contains custom path) |

Also check `DECISION_EXTRA_PATHS` from config for additional search locations.

Log which directories were found:
```json
{"phase": 13.1, "action": "adr_detection", "dirs_checked": 5, "dirs_found": ["docs/adr/"], "total_adrs": N}
```

### 13.2 ADR Parsing

For each `.md` file found in ADR directories, extract:

| Field | Detection Strategy |
|-------|-------------------|
| **Title** | First `#` heading or filename |
| **Status** | Line matching `Status:` or `## Status` section (Accepted, Deprecated, Superseded, Proposed) |
| **Date** | Line matching `Date:`, `Decided:`, or parsed from filename (NNNN-NN-NN pattern) |
| **Decision** | First paragraph after `## Decision`, `## Context and Decision`, or `## Decision Outcome` (MADR) heading |
| **Rejected alternatives** | Content under `## Options Considered`, `## Alternatives`, `## Rejected`, `## Considered Options` (MADR), or `## Pros and Cons of the Options` (MADR) |
| **Consequences** | Content under `## Consequences`, `## Impact`, or `## Positive/Negative Consequences` (MADR) |
| **Reversal conditions** | Sentences containing "revisit when", "reconsider if", "reverse when", "sunset" |

**Heading matching**: Case-insensitive. Accept both `##` and `###` heading levels. MADR variants (marked above) follow the [Markdown Architectural Decision Records](https://adr.github.io/madr/) standard.

### 13.3 Staleness Computation

For each ADR with a detected date:

```
age_months = (current_date - adr_date) / 30
IF age_months > DECISION_STALE_MONTHS:
  → Mark as STALE with warning: "N months old, may not reflect current decisions"
```

### 13.4 Generate decisions.md

Write `grimoires/loa/reality/decisions.md`:

```markdown
# Decision Archaeology

> Extracted from N ADR files across M directories.
> Decisions are claims — verify with HITL before treating as constraints.
> Generated: YYYY-MM-DD

## Active Decisions

### [ADR Title]
- **Status**: [Status] ([Date])
- **File**: [relative/path/to/adr.md]
- **Decision**: [Summary of decision]
- **Rejected**: [Alternatives that were NOT chosen]
- **Constraints for agents**: [What agents should NOT do based on this decision]
- **Reversal condition**: [If present — when to reconsider]

## Stale Decisions (>DECISION_STALE_MONTHS months, no reconfirmation)

### [ADR Title]
- **Status**: [Status] ([Date]) — ⚠️ N months old
- **File**: [relative/path/to/adr.md]
- **Staleness note**: May not reflect current architecture decisions. Recommend HITL reconfirmation.
```

### 13.5 No ADRs Found

If no ADR directories or files are found:

- If Phase 12 ran (gap tracker available): Create a gap entry:
  ```
  GAP-NNN-HASH: No ADR/decision records found
  Type: Context
  Priority: P1
  Source: /ride Phase 13, decision archaeology scan
  Context: Project has no documented architectural decisions. Future agents will lack trade-off context.
  ```
- If Phase 12 did NOT run: Log warning to trajectory and NOTES.md

### 13.6 File Persistence Checkpoint (CP-13)

**WRITE TO DISK**: Use the `Write` tool to persist `grimoires/loa/reality/decisions.md`.

After writing, verify with `Glob` pattern `grimoires/loa/reality/decisions.md` — must return 1 match. If missing after Write, retry once. If still missing, log to trajectory:
```json
{"phase": 13, "action": "write_failed", "artifact": "decisions.md", "status": "error"}
```

Log phase completion:
```json
{"phase": 13, "action": "decision_archaeology", "status": "complete", "details": {"adr_dirs_found": N, "adrs_parsed": N, "active": N, "stale": N, "output": "grimoires/loa/reality/decisions.md"}}
```

---

## Phase 14: Domain Terminology Extraction (`ENRICH_TERMS` only)

**Skip condition**: If `ENRICH_TERMS == false`, skip this entire phase. Log skip to trajectory:
```json
{"phase": 14, "action": "terminology_extraction", "status": "skipped", "details": {"reason": "ENRICH_TERMS not set"}}
```

### 14.1 Term Extraction

Scan source code for domain-specific vocabulary from these categories (in priority order):

If `tsconfig.json` exists at the project root, include TypeScript-enhanced patterns (marked with † below). Otherwise, use base patterns only.

| Category | Detection Pattern | Example |
|----------|------------------|---------|
| Type names & enums | `type\s+\w+`, `enum\s+\w+`, `interface\s+\w+` | `type FinnNFT`, `enum PoolStatus` |
| Type names (TS-enhanced †) | `type\s+\w+<` (generics), `as const` assertions, `satisfies\s+\w+`, `.d.ts` file exports | `type Pool<T>`, `const ROLES = {...} as const` |
| Database models | `@Entity`, `model\s+\w+`, `CREATE TABLE`, schema definitions | `model CreditBalance` |
| Constants | `const\s+[A-Z_]+`, exported configuration keys | `MAX_RETRY_COUNT` |
| Component names | Domain-prefixed components, module names | `HounfourRouter`, `BridgebuilderReview` |
| Definitional comments | Comments containing "i.e.", "a.k.a.", "means", "refers to", "defined as" | `// finnNFT refers to the governance token` |

For each term found:
- Record the term name
- Record the source file and line (`file:line`)
- Extract contextual definition (from comment, type structure, or usage pattern)
- Track frequency (number of references across codebase)

### 14.2 Deduplication and Ranking

1. Deduplicate terms (case-insensitive match, keep casing from definition site)
2. Rank by frequency (most-referenced first)
3. Cap at `TERM_MAX_TERMS` (default: 50)
4. Group by domain (inferred from file path or module structure)

### 14.3 Generate terminology.md

Write `grimoires/loa/reality/terminology.md`:

```markdown
# Domain Terminology

> Extracted from source code. N terms identified.
> Generated: YYYY-MM-DD

## [Domain Group 1]

| Term | Source | Context |
|------|--------|---------|
| `TermName` | path/to/file.ts:NN | Brief definition or usage context |

## [Domain Group 2]

| Term | Source | Context |
|------|--------|---------|
| `TermName` | path/to/file.ts:NN | Brief definition or usage context |
```

### 14.4 File Persistence Checkpoint (CP-14)

**WRITE TO DISK**: Use the `Write` tool to persist `grimoires/loa/reality/terminology.md`.

After writing, verify with `Glob` pattern `grimoires/loa/reality/terminology.md` — must return 1 match. If missing after Write, retry once. If still missing, log to trajectory:
```json
{"phase": 14, "action": "write_failed", "artifact": "terminology.md", "status": "error"}
```

Log phase completion:
```json
{"phase": 14, "action": "terminology_extraction", "status": "complete", "details": {"terms_extracted": N, "domains": N, "output": "grimoires/loa/reality/terminology.md"}}
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
| 0.6 | `staleness_check` | `status`, `artifact_age_days` |
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
| 11 | `ground_truth_generation` | `files`, `total_tokens`, `checksums_count`, `within_budget` |
| 12 | `gap_tracker` | `new_gaps`, `total_open`, `highest_id`, `threshold_status` |
| 13 | `decision_archaeology` | `adr_dirs_found`, `adrs_parsed`, `active`, `stale`, `output` |
| 14 | `terminology_extraction` | `terms_extracted`, `domains`, `output` |
