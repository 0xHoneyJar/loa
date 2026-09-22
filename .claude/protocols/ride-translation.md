# /ride Translation Protocol

> Batch translation of `/ride` Ground Truth into executive communications.

## Truth Hierarchy

Order of trust: **CODE** (absolute source of truth) > **Loa Artifacts** (derived from code evidence) > **Legacy Docs** (claims to verify against code) > **User Context** (hypotheses to test against code). Code wins every conflict.

## Phase 0: Integrity Pre-Check

**Blocking** when `.loa.config.yaml` sets `integrity_enforcement: strict` and `.claude/checksums.json` exists.

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

## Phase 1: Memory Restoration

```bash
# Read structured memory
.claude/scripts/notes-guard.sh read   # bounded default (Blockers, latest continuity, 3 newest decisions)

# Check for existing translations
ls -la grimoires/loa/translations/ 2>/dev/null

# Check Beads for related issues
br list --label translation --label drift 2>/dev/null
```

## Phase 2: Artifact Discovery

| Artifact | Path | Focus |
|----------|------|-------|
| drift | `grimoires/loa/drift-report.md` | Ghost Features, Shadow Systems |
| governance | `grimoires/loa/governance-report.md` | Process maturity |
| consistency | `grimoires/loa/consistency-report.md` | Code patterns |
| hygiene | `grimoires/loa/reality/hygiene-report.md` | Technical debt |
| trajectory | `grimoires/loa/trajectory-audit.md` | Confidence |

## Phase 3: Just-in-Time Translation

Per artifact: load it into focused context, extract key findings with `(file:L##)` citations, translate using the Audience Adaptation Matrix, write to `translations/{name}-analysis.md`, clear the raw artifact from context, and retain only the summary for index synthesis.

## Phase 4: Health Score

```
HEALTH_SCORE = (
  (100 - drift_percentage) x 0.50 +           # Documentation: 50% (source: drift-report.md:L1)
  (consistency_score x 10) x 0.30 +           # Consistency: 30% (source: consistency-report.md)
  (100 - min(hygiene_items x 5, 100)) x 0.20  # Hygiene: 20% (source: hygiene-report.md)
)
```

## Phase 5: Executive Index Synthesis

Create `EXECUTIVE-INDEX.md` with: the weighted Health Score (visual + breakdown), top 3 strategic priorities across artifacts, a one-line-per-report navigation guide, a consolidated action plan (owner + timeline), an investment summary (effort estimates), and decisions requested from leadership.

## Phase 6: Beads Integration

For each strategic liability:

```bash
br create "Strategic Liability: {Issue}" \
  -p 1 \
  -l strategic-liability,from-ride,requires-decision \
  -d "Source: hygiene-report.md:L{N}"
```

## Phase 7: Trajectory Self-Audit

Before completion, run these checks and write the results to `translation-audit.md`:

| Check | Question | Pass criteria |
|-------|----------|---------------|
| G1 | All metrics sourced? | Every metric has `(file:L##)` |
| G2 | All claims grounded? | Zero ungrounded without `[ASSUMPTION]` |
| G3 | Assumptions flagged? | `[ASSUMPTION]` + validator assigned |
| G4 | Ghost features cited? | Evidence of absence documented |
| G5 | Health score formula? | Used the Phase 4 weighted calculation |

## Phase 8: Output & Memory Update

```bash
mkdir -p grimoires/loa/translations

# Write all translation files
# Generate translation-audit.md
# Update NOTES.md with session summary
# Log trajectory to a2a/trajectory/
```

If fewer than 2 artifacts are found, warn and produce a partial output rather than failing.

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

Every claim must use one of these formats:

| Claim Type | Format | Example |
|------------|--------|---------|
| Direct quote | `"[quote]" (file:L##)` | `"OAuth not found" (drift-report.md:L45)` |
| Metric | `{value} (source: file:L##)` | `34% drift (source: drift-report.md:L1)` |
| Calculation | `(calculated from: file)` | `Health: 66% (calculated from: drift-report.md)` |
| Assumption | `[ASSUMPTION] {claim}` | `[ASSUMPTION] OAuth was descoped` |

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
