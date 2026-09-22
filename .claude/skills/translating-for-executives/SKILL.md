---
name: translate
description: Translate technical documentation into executive-ready communications
role: implementation
# Phase 5.5 runs validate-artifact.sh as a MUST gate; Bash is scoped to that one script.
allowed-tools: Read, Grep, Glob, Write, Bash(.claude/scripts/validate-artifact.sh *)
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands:
    allowed:
      - command: ".claude/scripts/validate-artifact.sh"
        args: ["*"]
    deny_raw_shell: true
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
---

<prompt_enhancement_prelude>
<!-- @skill-include: start prompt_enhancement_prelude | hash:73faa7b3 | DO NOT EDIT — generated from .claude/data/skill-includes/prompt_enhancement_prelude.md -->
If `.loa.config.yaml` sets `prompt_enhancement.invisible_mode.enabled: true` and this command's
frontmatter does not set `enhance: false`, silently apply the PTCF scoring + template flow from
`.claude/skills/enhancing-prompts/SKILL.md` to the user's request before main logic (log per that
skill; never show enhancement output). On any error, or when disabled: proceed with the original
prompt unchanged.
<!-- @skill-include: end prompt_enhancement_prelude -->
</prompt_enhancement_prelude>

# DevRel Translator Skill

<skill_context>
You operate as a **financial auditor for codebases**: verifying the code ledger against documentation reports to surface Ghost Assets (documented but missing features) and Undisclosed Liabilities (undocumented systems), then translating the Ground Truth discovered by /ride into strategic narratives that let non-technical stakeholders decide without losing accuracy.
</skill_context>

<zone_constraints>
## Zone Constraints

Zones per CLAUDE.loa.md Three-Zone Model (`.claude/` system = never edit — use `.claude/overrides/` or `.loa.config.yaml`; `grimoires/loa/`, `.beads/` state = read/write). This skill's app zone (`src/`, `lib/`, `app/`): **Read-only**.
</zone_constraints>

<integrity_protocol>
## Integrity Protocol

Before any translation: `yq eval '.integrity_enforcement // "strict"' .loa.config.yaml`. Under `strict`, System-Zone drift against `.claude/checksums.json` HALTs with a "SYSTEM ZONE INTEGRITY VIOLATION" report (resolution: move customizations to `.claude/overrides/`, run `/update-loa --force-restore`, or set `integrity_enforcement: warn`); `warn` logs and proceeds; `disabled` skips the check. Phase 0 runs the check through `preflight.sh check_integrity`.
</integrity_protocol>

<truth_hierarchy>
## Truth Hierarchy (Immutable — "CODE IS TRUTH")

1. CODE — absolute source of truth; 2. Loa artifacts — derived from code evidence; 3. legacy docs — claims to verify against code; 4. user context — hypotheses to test against code. Nothing overrides code.

### Conflict Resolution

When documentation claims X but code shows Y:

1. **Always side with code** — Code is the ledger of truth
2. **Document as Ghost Feature** — "Documented but not found in code"
3. **Quantify the risk** — Business impact of the discrepancy
4. **Track in Beads** — Create issue for remediation

### Terminology (Financial Audit Analogy)

| Technical Term | Audit Analogy | Business Translation |
|----------------|---------------|---------------------|
| **Ghost Feature** | Phantom Asset | "On the books but not in the vault" |
| **Shadow System** | Undisclosed Liability | "In the vault but not on the books" |
| **Drift** | Books != Inventory | "What we say != what we have" |
| **Technical Debt** | Deferred Maintenance | "Repairs we're postponing" |
| **Strategic Liability** | Material Weakness | "Risk requiring board attention" |
</truth_hierarchy>

<factual_grounding_requirements>
## Factual Grounding Protocol

### 1. Word-for-Word Extraction

Before ANY synthesis, extract **direct quotes** from /ride artifacts:

```markdown
GROUNDED:
  "Drift Score: 34%" (drift-report.md:L1)

UNGROUNDED:
  The codebase has some documentation issues
```

### 2. Citation Protocol

Every claim MUST end with citation:

| Claim Type | Format | Example |
|------------|--------|---------|
| Direct quote | `"[quote]" (file:L##)` | `"OAuth not found" (drift-report.md:L45)` |
| Metric | `{value} (source: file:L##)` | `34% drift (source: drift-report.md:L1)` |
| Calculation | `(calculated from: file)` | `Health: 66% (calculated from: drift-report.md)` |
| Code ref | `(file.ext:L##)` | `RateLimiter (src/middleware/rate.ts:45)` |

### 3. Assumption Tagging

ANY ungrounded claim MUST be prefixed:

```markdown
[ASSUMPTION] The database likely needs connection pooling
  -> Requires validation by: Engineering Lead
  -> Confidence: MEDIUM
  -> Basis: Inferred from traffic patterns
```

</factual_grounding_requirements>

<context_engineering>
## Context Engineering

Do not load all /ride artifacts at once: the orchestrator translates one artifact at a time (Phase 3), clears the raw report after synthesis, and keeps only the summary plus file reference for the index. Clearing thresholds: the Context Discipline block below.
</context_engineering>

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

<audience_adaptation_matrix>
## Audience Adaptation Matrix

### Primary Focus by Audience

| Audience | Primary Focus | Secondary | Frame As |
|----------|---------------|-----------|----------|
| **Board** | Governance & Compliance | Strategic Risk | Risk Assessment |
| **Investors** | Growth & ROI | Competitive Position | Value Metrics |
| **Executives** | Bottom Line | Operational Risk | Decision Brief |
| **Compliance** | Regulatory Gaps | Audit Readiness | Gap Analysis |
| **Eng Leadership** | Technical Debt | Velocity | Health Report |

### Translation Matrix

| Technical Term | Board | Investors | Executives |
|----------------|-------|-----------|------------|
| **Drift 34%** | "34% documentation risk exposure" | "Technical debt: 40hr remediation" | "34% of docs don't match reality" |
| **Ghost Feature** | "Phantom asset on books" | "Vaporware in prospectus" | "Promise we haven't kept" |
| **Shadow System** | "Undisclosed liability" | "Hidden dependency risk" | "System we don't know about" |
| **6/10 Consistency** | "Maintainability risk" | "15% velocity drag" | "Code organization issues" |
| **23 Hygiene Items** | "23 unresolved decisions" | "23-item cleanup backlog" | "23 things needing attention" |

### Analogy Bank by Audience

| Concept | Board (Financial) | Investors (Growth) | Executives (Operational) |
|---------|-------------------|-------------------|-------------------------|
| Drift | Books != inventory | Prospectus != product | Saying != doing |
| Ghost | Phantom asset | Vaporware | Broken promise |
| Shadow | Off-balance-sheet | Hidden risk | Unknown system |
| Debt | Deferred maintenance | Future cost | Postponed problem |
</audience_adaptation_matrix>

<batch_translation_workflow>
## Batch Translation Workflow

### Phase 0: Integrity Pre-Check (BLOCKING)

```bash
# Verify System Zone before proceeding
source .claude/scripts/preflight.sh 2>/dev/null
check_integrity || exit 1
```

### Phase 1: Memory Restoration

Run `.claude/scripts/notes-guard.sh read` (the bounded NOTES.md default) and list any existing `grimoires/loa/translations/`.

### Phase 2: Artifact Discovery

```bash
declare -A ARTIFACTS=(
  ["drift"]="grimoires/loa/drift-report.md"
  ["governance"]="grimoires/loa/governance-report.md"
  ["consistency"]="grimoires/loa/consistency-report.md"
  ["hygiene"]="grimoires/loa/reality/hygiene-report.md"
  ["trajectory"]="grimoires/loa/trajectory-audit.md"
)

for name in "${!ARTIFACTS[@]}"; do
  [[ -f "${ARTIFACTS[$name]}" ]] && FOUND+=("$name") || MISSING+=("$name")
done

echo "Ground Truth: ${#FOUND[@]}/5 artifacts"
```

### Phase 3: Just-in-Time Translation (Per Artifact)

For each artifact:

1. **Load** into focused context
2. **Extract** key findings with `(file:L##)` citations
3. **Translate** using audience adaptation matrix
4. **Write** to `translations/{name}-analysis.md`
5. **Clear** raw artifact from context
6. **Retain** only summary for index synthesis

| Source | Output | Focus |
|--------|--------|-------|
| drift-report.md | drift-analysis.md | Ghosts, shadows, risk |
| governance-report.md | governance-assessment.md | Compliance gaps |
| consistency-report.md | consistency-analysis.md | Velocity impact |
| hygiene-report.md | hygiene-assessment.md | Strategic liabilities |
| trajectory-audit.md | quality-assurance.md | Confidence level |

### Phase 4: Health Score Calculation

**Official Enterprise Formula:**

```
HEALTH_SCORE = (
  (100 - drift_percentage) x 0.50 +      # Documentation: 50%
  (consistency_score x 10) x 0.30 +       # Consistency: 30%
  (100 - min(hygiene_items x 5, 100)) x 0.20  # Hygiene: 20%
)
```

| Dimension | Weight | Source |
|-----------|--------|--------|
| Documentation Alignment | 50% | drift-report.md:L1 |
| Code Consistency | 30% | consistency-report.md:L{N} |
| Technical Hygiene | 20% | hygiene-report.md |

### Phase 5: Executive Index Synthesis

Create `EXECUTIVE-INDEX.md` with:

1. **Weighted Health Score** (visual + breakdown)
2. **Top 3 Strategic Priorities** (cross-artifact)
3. **Navigation Guide** (one-line per report)
4. **Consolidated Action Plan** (owner + timeline)
5. **Investment Summary** (effort estimates)
6. **Decisions Requested** (from leadership)

### Phase 5.5: Citation-Resolution Validation (MUST)

After the Phase 4/5 outputs are written, MUST run
`.claude/scripts/validate-artifact.sh --type translation --file grimoires/loa/translations/`
before proceeding to Phase 6; repair per its output on exit 1; exit 2
(usage/file-not-found) is a validator FAILURE — fix the path and re-run, do
not proceed.

### Phase 6: beads_rust Integration

For Strategic Liabilities found:

```bash
# Auto-suggest beads_rust issue creation
ISSUE_ID=$(br create "Strategic Liability: [Issue from hygiene]" --priority 1 --json | jq -r '.id')
br label add "$ISSUE_ID" strategic-liability
br label add "$ISSUE_ID" from-ride
br label add "$ISSUE_ID" requires-decision
br comments add "$ISSUE_ID" "Source: hygiene-report.md:L{N}"
```

### Phase 7: Trajectory Self-Audit (MANDATORY)

Execute before completion (see next section).

### Phase 8: Output & Memory Update

`mkdir -p grimoires/loa/translations`, write all files, update NOTES.md with the session summary, log the trajectory to `a2a/trajectory/`.
</batch_translation_workflow>

<trajectory_self_audit>
## Trajectory Self-Audit

Before marking complete, execute this audit:

### Grounding Audit

| Check | Question | Pass Criteria |
|-------|----------|---------------|
| G1 | All metrics sourced? | Every metric has `(file:L##)` |
| G2 | All claims grounded? | Zero ungrounded without [ASSUMPTION] |
| G3 | Assumptions flagged? | [ASSUMPTION] + validator assigned |
| G4 | Ghost features cited? | Evidence of absence documented |
| G5 | Health score formula? | Used official weighted calculation |

### Clarity Audit

| Check | Question | Pass Criteria |
|-------|----------|---------------|
| C1 | Jargon defined? | All terms have business analogy |
| C2 | "So what?" answered? | Business impact per finding |
| C3 | Actions specific? | Who/what/when for each |
| C4 | Audience appropriate? | Matches adaptation matrix |

### Completeness Audit

| Check | Question | Pass Criteria |
|-------|----------|---------------|
| X1 | All artifacts translated? | 5/5 or gaps documented |
| X2 | Health score present? | Calculated + breakdown shown |
| X3 | Priorities identified? | Top 3 strategic items |
| X4 | Beads suggested? | For strategic liabilities |

### Generate translation-audit.md

```markdown
# Translation Audit Report

**Generated:** {timestamp}
**Audience:** {target}

## Grounding Summary

| Artifact | Claims | Grounded | Assumptions | Confidence |
|----------|--------|----------|-------------|------------|
| drift-analysis.md | {N} | {N} | {N} | {X}% |
| ... | ... | ... | ... | ... |
| **TOTAL** | **{N}** | **{N}** | **{N}** | **{X}%** |

## Health Score Verification

- Formula used: Official weighted (50/30/20)
- Components cited: All sources documented
- Calculation: (100-{drift})x0.5 + ({consistency}x10)x0.3 + (100-{hygienex5})x0.2 = {SCORE}

## Assumptions Requiring Validation

| # | Assumption | Location | Validator | Priority |
|---|------------|----------|-----------|----------|
| 1 | {text} | {file}:L{N} | {Role} | {H/M/L} |

## Beads Suggested

| Issue | Priority | Labels | Source |
|-------|----------|--------|--------|
| {Strategic Liability} | P1 | strategic-liability | hygiene-report.md:L{N} |

## Self-Certification

- [x] All claims grounded or flagged [ASSUMPTION]
- [x] All technical terms have business analogies
- [x] All findings answer "So what?"
- [x] Health score uses official formula
- [x] Strategic liabilities tracked in Beads
- [x] Truth hierarchy enforced (CODE > all)

**Audit Status:** {PASSED / REVIEW NEEDED}
```
</trajectory_self_audit>

<example_translations>
Worked Board and Executive translations (drift report → board risk assessment; hygiene report → executive liabilities brief): see `resources/REFERENCE.md` §Translation Examples when calibrating tone for a new audience.
</example_translations>


<visual_communication>
## Visual Communication (Required)

Executive translations include GitHub-native Mermaid diagrams (```mermaid code blocks) for the health-score breakdown (always), a risk matrix (more than 3 risks) and a remediation timeline (action plan longer than 2 phases). Standards: `.claude/protocols/visual-communication.md`; theme from `.loa.config.yaml` `visual_communication.theme`. PNG export for decks: `echo 'graph LR; A-->B' | .claude/scripts/mermaid-url.sh --stdin --render --format png` (writes `grimoires/loa/diagrams/`).
</visual_communication>
