# Lens Pack

User truth capture skills for hypothesis-first research.

## Skills (6)

| Skill | Command | Description |
|-------|---------|-------------|
| `observing-users` | `/observe` | Capture user feedback as hypothesis-first research |
| `shaping-journeys` | `/shape` | Shape common patterns into journey definitions |
| `level-3-diagnostic` | - | Diagnostic-first user research framework |
| `analyzing-gaps` | `/analyze-gap` | Compare user expectations with code reality |
| `filing-gaps` | `/file-gap` | Create issues from gap analysis reports |
| `importing-research` | `/import-research` | Bulk convert legacy user research |

## Installation

```bash
# From your project root
cp -r /path/to/forge/lens .claude/constructs/packs/lens
.claude/constructs/packs/lens/scripts/install.sh .
```

## Quick Start

```bash
# Start observing users
/observe

# Shape research into journeys
/shape

# Analyze gaps between expectation and reality
/analyze-gap
```

## Context Composition

Lens includes a cultural context system for crypto/DeFi user research:

- **Base Context**: `contexts/base/crypto-base.md` - Universal crypto patterns
- **Overlays**: `contexts/overlays/` - Chain/protocol-specific additions
- **Composed**: `contexts/composed/` - Merged output

Run context composition:
```bash
.claude/constructs/packs/lens/scripts/compose-context.sh .
```

## Grimoire Structure

After installation, the following directories are created:

```
grimoires/lens/
├── canvas/     # User Truth Canvases (UTCs)
├── journeys/   # User journey definitions
└── state.yaml  # Lens state tracking
```

## Requirements

- Claude Code CLI
- Loa Framework with `constructs-loader.sh`
