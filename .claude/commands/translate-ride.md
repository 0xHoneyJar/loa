---
name: "translate-ride"
version: "2.0.0"
description: |
  Enterprise-grade translation of /ride Ground Truth artifacts into executive
  communications. Enforces synthesis protection, agentic memory, factual
  grounding, and trajectory self-audit.

arguments:
  - name: "audience"
    type: "string"
    required: false
    default: "executives"
    description: "Target audience for translations"
    examples: ["executives", "board", "investors", "compliance", "engineering-leadership"]

agent: "translating-for-executives"
agent_path: "skills/translating-for-executives/"

context_files:
  - path: ".loa.config.yaml"
    required: false
    priority: 0
    purpose: "Integrity enforcement configuration"
  - path: "grimoires/loa/NOTES.md"
    required: false
    priority: 1
    purpose: "Structured memory restoration"
  - path: "grimoires/loa/drift-report.md"
    required: false
    priority: 2
    purpose: "Ground Truth: Documentation vs Code"
  - path: "grimoires/loa/governance-report.md"
    required: false
    priority: 3
    purpose: "Ground Truth: Process maturity"
  - path: "grimoires/loa/consistency-report.md"
    required: false
    priority: 4
    purpose: "Ground Truth: Code patterns"
  - path: "grimoires/loa/reality/hygiene-report.md"
    required: false
    priority: 5
    purpose: "Ground Truth: Technical debt"
  - path: "grimoires/loa/trajectory-audit.md"
    required: false
    priority: 6
    purpose: "Ground Truth: Analysis confidence"

pre_flight:
  - check: "directory_exists"
    path: "grimoires/loa"
    error: "No grimoires/loa found. Run /ride first."
  - check: "file_exists"
    path: "grimoires/loa/drift-report.md"
    error: "No drift-report.md found. Run /ride to completion."

outputs:
  - path: "grimoires/loa/translations/"
    type: "directory"
  - path: "grimoires/loa/translations/EXECUTIVE-INDEX.md"
    type: "markdown"
  - path: "grimoires/loa/translations/translation-audit.md"
    type: "markdown"

mode:
  default: "foreground"
  allow_background: true
---

# /translate-ride

Enterprise-grade batch translation of /ride Ground Truth into executive communications.

## Truth Hierarchy (Immutable)

```
+-------------------------------------------------------------+
|   1. CODE               <- Absolute source of truth          |
|   2. Loa Artifacts      <- Derived FROM code evidence        |
|   3. Legacy Docs        <- Claims to verify                  |
|   4. User Context       <- Hypotheses to test                |
|                                                              |
|   CODE WINS ALL CONFLICTS. ALWAYS.                           |
+-------------------------------------------------------------+
```

## Usage

```bash
/translate-ride                    # Default: executives
/translate-ride for board          # Governance focus
/translate-ride for investors      # ROI focus
/translate-ride for compliance     # Regulatory focus
```

## Agent

Launches `translating-for-executives` from `skills/translating-for-executives/`.

See: `skills/translating-for-executives/SKILL.md` for full workflow details.

## Workflow

1. **Integrity Pre-Check**: Verify System Zone via SHA-256 checksums
2. **Memory Restoration**: Load NOTES.md for context continuity
3. **Artifact Discovery**: Identify available /ride Ground Truth reports
4. **Just-in-Time Translation**: Process each artifact with progressive disclosure
5. **Health Score Calculation**: Apply official 50/30/20 weighted formula
6. **Index Synthesis**: Generate EXECUTIVE-INDEX.md navigation
7. **Beads Integration**: Suggest tracking for strategic liabilities
8. **Trajectory Self-Audit**: Verify grounding and generate audit trail

## Output

```
grimoires/loa/translations/
+-- EXECUTIVE-INDEX.md       <- Start here
+-- drift-analysis.md        <- Ghost features, shadow systems
+-- governance-assessment.md <- Compliance gaps
+-- consistency-analysis.md  <- Velocity indicators
+-- hygiene-assessment.md    <- Strategic liabilities
+-- quality-assurance.md     <- Confidence assessment
+-- translation-audit.md     <- Self-audit trail
```

## Health Score Formula

```
HEALTH = (100 - drift%) x 0.50 + (consistency x 10) x 0.30 + (100 - hygiene x 5) x 0.20
```

| Component | Weight | Source |
|-----------|--------|--------|
| Documentation Alignment | 50% | drift-report.md |
| Code Consistency | 30% | consistency-report.md |
| Technical Hygiene | 20% | hygiene-report.md |

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "No grimoires/loa found" | Haven't run /ride | Run `/ride` first |
| "No drift-report.md found" | /ride incomplete | Complete `/ride` workflow |
| "System Zone integrity violation" | .claude/ modified | Run `/update-loa --force-restore` |
