# /ride Translation Protocol v2.0

> Enterprise-grade batch translation of /ride Ground Truth into executive communications

## Overview

This protocol defines the workflow for translating `/ride` analysis artifacts into executive-ready communications. It enforces enterprise standards from AWS Projen (integrity), Anthropic (memory), and Google ADK (evaluation).

## Enterprise Standards

| Standard | Source | Implementation |
|----------|--------|----------------|
| **Synthesis Protection** | AWS Projen | SHA-256 checksum verification of System Zone |
| **Agentic Memory** | Anthropic | NOTES.md protocol + Beads integration |
| **Trajectory Evaluation** | Google ADK | Self-audit with confidence scoring |
| **Context Engineering** | Anthropic | Progressive disclosure + tool result clearing |
| **Truth Hierarchy** | Loa | CODE > Artifacts > Docs > Context |

## Truth Hierarchy (Immutable)

```
+-------------------------------------------------------------+
|                    IMMUTABLE TRUTH HIERARCHY                 |
+-------------------------------------------------------------+
|   1. CODE               <- Absolute source of truth          |
|   2. Loa Artifacts      <- Derived FROM code evidence        |
|   3. Legacy Docs        <- Claims to verify against code     |
|   4. User Context       <- Hypotheses to test against code   |
|                                                              |
|   CODE WINS ALL CONFLICTS. ALWAYS.                           |
+-------------------------------------------------------------+
```

## Execution Sequence

```
Phase 0: Integrity Pre-Check (BLOCKING if strict)
    |
Phase 1: Memory Restoration (NOTES.md + Beads)
    |
Phase 2: Artifact Discovery (Progressive)
    |
Phase 3: Just-in-Time Translation (per artifact)
    |   +-- Load -> Extract -> Translate -> Write -> Clear
    |
Phase 4: Health Score (Official Formula: 50/30/20)
    |
Phase 5: Index Synthesis
    |
Phase 6: Beads Integration (Strategic Liabilities)
    |
Phase 7: Trajectory Self-Audit (MANDATORY)
    |
Phase 8: Output + Memory Update
```

## Phase Details

### Phase 0: Integrity Pre-Check

**BLOCKING** if `integrity_enforcement: strict`

```bash
enforcement=$(yq eval '.integrity_enforcement // "strict"' .loa.config.yaml 2>/dev/null || echo "strict")

if [[ "$enforcement" == "strict" ]] && [[ -f ".claude/checksums.json" ]]; then
  # Verify SHA-256 checksums of System Zone
  drift_detected=false
  while IFS= read -r file; do
    expected=$(jq -r --arg f "$file" '.files[$f]' .claude/checksums.json)
    [[ -z "$expected" || "$expected" == "null" ]] && continue
    actual=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)
    [[ "$expected" != "$actual" ]] && drift_detected=true && break
  done < <(jq -r '.files | keys[]' .claude/checksums.json)

  [[ "$drift_detected" == "true" ]] && exit 1
fi
```

### Phase 1: Memory Restoration

```bash
# Read structured memory
[[ -f "grimoires/loa/NOTES.md" ]] && cat grimoires/loa/NOTES.md

# Check for existing translations
ls -la grimoires/loa/translations/ 2>/dev/null

# Check Beads for related issues
br list --label translation --label drift 2>/dev/null
```

### Phase 2: Artifact Discovery

| Artifact | Path | Focus |
|----------|------|-------|
| drift | `grimoires/loa/drift-report.md` | Ghost Features, Shadow Systems |
| governance | `grimoires/loa/governance-report.md` | Process maturity |
| consistency | `grimoires/loa/consistency-report.md` | Code patterns |
| hygiene | `grimoires/loa/reality/hygiene-report.md` | Technical debt |
| trajectory | `grimoires/loa/trajectory-audit.md` | Confidence |

### Phase 3: Just-in-Time Translation

For each artifact:

1. **Load** into focused context
2. **Extract** key findings with `(file:L##)` citations
3. **Translate** using audience adaptation matrix
4. **Write** to `translations/{name}-analysis.md`
5. **Clear** raw artifact from context
6. **Retain** only summary for index synthesis

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
| Code Consistency | 30% | consistency-report.md |
| Technical Hygiene | 20% | hygiene-report.md |

### Phase 5: Executive Index Synthesis

Create `EXECUTIVE-INDEX.md` with:

1. Weighted Health Score (visual + breakdown)
2. Top 3 Strategic Priorities (cross-artifact)
3. Navigation Guide (one-line per report)
4. Consolidated Action Plan (owner + timeline)
5. Investment Summary (effort estimates)
6. Decisions Requested (from leadership)

### Phase 6: Beads Integration

For Strategic Liabilities:

```bash
br create "Strategic Liability: {Issue}" \
  -p 1 \
  -l strategic-liability,from-ride,requires-decision \
  -d "Source: hygiene-report.md:L{N}"
```

### Phase 7: Trajectory Self-Audit

**MANDATORY** before completion.

| Check | Question | Pass Criteria |
|-------|----------|---------------|
| G1 | All metrics sourced? | Every metric has `(file:L##)` |
| G2 | All claims grounded? | Zero ungrounded without [ASSUMPTION] |
| G3 | Assumptions flagged? | [ASSUMPTION] + validator assigned |
| G4 | Ghost features cited? | Evidence of absence documented |
| G5 | Health score formula? | Used official weighted calculation |

Generate `translation-audit.md` with results.

### Phase 8: Output & Memory Update

```bash
mkdir -p grimoires/loa/translations

# Write all translation files
# Generate translation-audit.md
# Update NOTES.md with session summary
# Log trajectory to a2a/trajectory/
```

## Quality Gates

| Gate | Condition | Action |
|------|-----------|--------|
| Integrity | Strict + drift | HALT |
| Grounding | Ungrounded claims | Flag [ASSUMPTION] |
| Formula | Wrong calculation | Reject audit |
| Completeness | <2 artifacts | Warn + partial |

## Output Structure

```
grimoires/loa/translations/
+-- EXECUTIVE-INDEX.md       <- Start here (Balance Sheet of Reality)
+-- drift-analysis.md        <- Ghost Features (Phantom Assets)
+-- governance-assessment.md <- Compliance Gaps
+-- consistency-analysis.md  <- Velocity Indicators
+-- hygiene-assessment.md    <- Strategic Liabilities
+-- quality-assurance.md     <- Confidence Assessment
+-- translation-audit.md     <- Self-audit trail
```

## Audience Adaptation Matrix

| Audience | Primary Focus | Ghost Feature As | Shadow System As |
|----------|---------------|------------------|------------------|
| **Board** | Governance | "Phantom asset on books" | "Undisclosed liability" |
| **Investors** | ROI | "Vaporware in prospectus" | "Hidden dependency risk" |
| **Executives** | Operations | "Promise we haven't kept" | "Unknown system" |
| **Compliance** | Audit | "Documentation gap" | "Untracked dependency" |

## Grounding Protocol

Every claim MUST use citation format:

| Claim Type | Format | Example |
|------------|--------|---------|
| Direct quote | `"[quote]" (file:L##)` | `"OAuth not found" (drift-report.md:L45)` |
| Metric | `{value} (source: file:L##)` | `34% drift (source: drift-report.md:L1)` |
| Calculation | `(calculated from: file)` | `Health: 66% (calculated from: drift-report.md)` |
| Assumption | `[ASSUMPTION] {claim}` | `[ASSUMPTION] OAuth was descoped` |

## Verification Checklist

Before completion:

- [ ] Integrity pre-check passes (SHA-256 verification)
- [ ] NOTES.md restored for context continuity
- [ ] All artifacts translated (or gaps documented)
- [ ] Health score uses official 50/30/20 formula
- [ ] All claims cite `(file:L##)` format
- [ ] All assumptions flagged `[ASSUMPTION]` with validator
- [ ] Strategic liabilities -> Beads suggested
- [ ] Self-audit -> translation-audit.md generated
- [ ] NOTES.md updated with session summary

## Related Commands

| Command | Description |
|---------|-------------|
| `/translate-ride` | Batch translate all /ride artifacts |
| `/translate @file for audience` | Single document translation |
| `/ride` | Generate Ground Truth artifacts |

## Related Protocols

| Protocol | Path |
|----------|------|
| Structured Memory | `.claude/protocols/structured-memory.md` |
| Trajectory Evaluation | `.claude/protocols/trajectory-evaluation.md` |
| Change Validation | `.claude/protocols/change-validation.md` |
