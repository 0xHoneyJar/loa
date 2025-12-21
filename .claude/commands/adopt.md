---
name: "adopt"
version: "1.0.0"
description: |
  Adopt existing codebase into Loa-maintained documentation. Analyzes actual
  code behavior, compares against existing documentation, generates Loa-standard
  artifacts grounded in code evidence, and establishes Loa as source of truth.

agent: "adopting-codebase"
agent_path: ".claude/skills/adopting-codebase"

arguments:
  - name: "phase"
    type: "string"
    required: false
    description: "Run single phase: reality, inventory, drift, generate, deprecate, handoff"
  - name: "dry-run"
    type: "flag"
    required: false
    description: "Preview changes without writing files"
  - name: "skip-deprecation"
    type: "flag"
    required: false
    description: "Don't modify legacy docs"

pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Run /setup first to initialize Loa"
  - check: "config_value"
    path: ".claude/config/loa-config.yaml"
    key: "repo_mode"
    value: "established"
    error: "Repository must be in 'established' mode. Re-run /setup if needed."

outputs:
  - path: "loa-grimoire/reality/"
    type: "directory"
    description: "Code reality extraction results"
  - path: "loa-grimoire/legacy/"
    type: "directory"
    description: "Legacy documentation inventory"
  - path: "loa-grimoire/drift-report.md"
    type: "file"
    description: "Documentation drift analysis"
  - path: "loa-grimoire/prd.md"
    type: "file"
    description: "Product Requirements (code-grounded)"
  - path: "loa-grimoire/sdd.md"
    type: "file"
    description: "System Design (code-grounded)"

mode:
  default: "foreground"
  allow_background: true
---

# /adopt - Adopt Existing Codebase into Loa

Migrates an existing codebase to Loa-maintained documentation. Analyzes actual code behavior, compares against existing documentation, generates Loa-standard artifacts grounded in code evidence, and establishes Loa as the single source of truth.

## Prerequisites

- `/setup` completed with `repo_mode: established`
- Beads initialized
- Git repository

## Phases

| Phase | Name | Output |
|-------|------|--------|
| **0** | **Context Ingestion** | `loa-grimoire/context/` analysis |
| 1 | Code Reality Extraction | `loa-grimoire/reality/` |
| 2 | Legacy Doc Inventory | `loa-grimoire/legacy/` |
| 3 | Drift Analysis | `loa-grimoire/drift-report.md` |
| 4 | Loa Artifact Generation | `prd.md`, `sdd.md`, Beads backlog |
| 5 | Legacy Deprecation | Deprecation notices in old docs |
| 6 | Maintenance Handoff | Drift detection, protocol updates |

## Preflight: Context Check

Before beginning adoption, check for user-provided context:

```bash
if [ -d "loa-grimoire/context" ] && [ "$(ls -A loa-grimoire/context 2>/dev/null)" ]; then
  echo "📚 Found user-provided context in loa-grimoire/context/"
  ls -la loa-grimoire/context/
  echo ""
  echo "This context will GUIDE code analysis (but CODE is always truth)."
else
  echo "💡 Tip: Add context documents to loa-grimoire/context/ before running /adopt"
  echo "   Examples: architecture notes, stakeholder interviews, tribal knowledge"
  echo "   See: .claude/skills/adopting-codebase/resources/context-templates.md"
fi
```

> **⚠️ CARDINAL RULE: CODE IS TRUTH**
> User context GUIDES where to look and provides HYPOTHESES to verify.
> Context NEVER overrides code evidence. Code wins every conflict.

## Execution

Invoke the `adopting-codebase` skill and execute all phases sequentially.

## Options

| Flag | Effect |
|------|--------|
| `--phase <name>` | Run single phase (reality, inventory, drift, generate, deprecate, handoff) |
| `--dry-run` | Preview changes without writing files |
| `--skip-deprecation` | Don't modify legacy docs |

## Post-Adoption

1. Review `loa-grimoire/drift-report.md` for critical issues
2. Schedule stakeholder review of `prd.md` and `sdd.md`
3. Resolve high-priority drift items via `/implement`
4. Communicate to team that Loa docs are now source of truth

## Beads Integration

Creates migration epic with child tasks:
- Validate PRD with stakeholders
- Validate SDD with team
- Resolve critical drift items
- Deprecate legacy documentation

Plus imports all TODO/FIXME comments as tech debt issues.

## Workflow Diagram

```
                    /adopt
                       │
                       ▼
                  [Phase 0]
                   Context
                  Ingestion
                       │
     ┌─────────────────┼─────────────────┐
     ▼                 ▼                 ▼
 [Phase 1]         [Phase 2]        [Phase 3]
  Reality           Legacy           Drift
Extraction        Inventory        Analysis
     │                 │                │
     └─────────────────┼────────────────┘
                       ▼
                  [Phase 4]
               Loa Artifact
                Generation
                   │
     ┌─────────────┴─────────────┐
     ▼                           ▼
 [Phase 5]                  [Phase 6]
  Legacy                   Maintenance
Deprecation                 Handoff
```

## Example Usage

```bash
# Full adoption workflow
/adopt

# Run specific phase only
/adopt --phase drift

# Preview without changes
/adopt --dry-run

# Keep legacy docs untouched
/adopt --skip-deprecation
```

## Next Steps

After adoption:
- `/sprint-plan` to create first maintenance sprint
- `/implement sprint-1` to address critical drift items
