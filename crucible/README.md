# Crucible Pack

Validation and testing skills for journey verification.

## Skills (5)

| Skill | Command | Description |
|-------|---------|-------------|
| `validating-journeys` | `/validate` | Generate Playwright tests from state diagrams |
| `grounding-code` | `/ground` | Extract actual code behavior into reality files |
| `iterating-feedback` | `/iterate` | Update upstream artifacts from test results |
| `walking-through` | `/walkthrough` | Interactive dev browser walkthrough |
| `diagramming-states` | `/diagram` | Generate Mermaid state machine diagrams |

## Installation

```bash
# From your project root
cp -r /path/to/forge/crucible .claude/constructs/packs/crucible
.claude/constructs/packs/crucible/scripts/install.sh .
```

## Quick Start

```bash
# Ground code reality
/ground

# Generate state diagrams
/diagram

# Validate journeys with Playwright
/validate

# Walk through interactively
/walkthrough
```

## Grimoire Structure

After installation, the following directories are created:

```
grimoires/crucible/
├── diagrams/      # Mermaid state diagrams
├── reality/       # Code reality files
├── gaps/          # Gap analysis reports
├── tests/         # Generated test files
├── walkthroughs/  # Walkthrough captures
└── results/       # Test results
```

## Requirements

- Claude Code CLI
- Loa Framework with `constructs-loader.sh`
- Playwright (for `/validate` command)
