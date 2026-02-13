---
name: "red-team"
version: "1.0.0"
description: |
  Generative adversarial security design using Flatline Protocol red team mode.
  Generates creative attack scenarios against design documents and synthesizes
  architectural counter-designs.

agent: "red-teaming"
agent_path: ".claude/skills/red-teaming/"

arguments:
  - name: "document"
    type: "string"
    required: false
    default: "auto"
    description: "Document to red-team (path or 'auto' for current SDD)"

  - name: "--spec"
    type: "string"
    required: false
    description: "Inline spec fragment text (creates temp document)"

  - name: "--focus"
    type: "string"
    required: false
    description: "Comma-separated attack surface categories"

  - name: "--section"
    type: "string"
    required: false
    description: "Target specific document section"

  - name: "--depth"
    type: "integer"
    required: false
    default: 1
    description: "Attack-counter_design iterations (1-5)"

  - name: "--mode"
    type: "enum"
    values: ["quick", "standard", "deep"]
    required: false
    default: "standard"
    description: "Execution mode (cost tier)"

enhance: false
danger_level: high
---

# /red-team — Generative Adversarial Security Design

Read `.claude/skills/red-teaming/SKILL.md` for full workflow specification.

## Quick Reference

```bash
# Red team the current SDD
/red-team grimoires/loa/sdd.md

# Focus on specific attack surfaces
/red-team grimoires/loa/sdd.md --focus "agent-identity,token-gated-access"

# Quick exploratory mode
/red-team grimoires/loa/sdd.md --mode quick

# Deep iterative mode
/red-team grimoires/loa/sdd.md --depth 3 --mode deep

# Red team an inline spec fragment
/red-team --spec "Users authenticate via wallet signature"
```

## Workflow

1. Validate `red_team.enabled: true` in config
2. Sanitize input document (multi-pass injection + secret scan)
3. Load attack surface registry (filter by `--focus` if provided)
4. Invoke `flatline-orchestrator.sh --mode red-team`
5. Present attack summary with consensus categories
6. Human validation gate for severity >800
7. Generate full report (0600) and CI-safe summary

## Output

- `.run/red-team/rt-{id}-result.json` — Full JSON result
- `.run/red-team/rt-{id}-report.md` — Restricted full report
- `.run/red-team/rt-{id}-summary.md` — CI-safe summary
