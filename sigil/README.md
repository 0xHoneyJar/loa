# Sigil Pack

Brand and UI craftsmanship skills from rune.

## Skills (10)

| Skill | Command | Description |
|-------|---------|-------------|
| `animating-motion` | `/animate` | Motion design and animation |
| `applying-behavior` | `/behavior` | Interaction behavior patterns |
| `crafting-physics` | `/craft` | Physics-based animations |
| `distilling-components` | `/distill` | Component extraction |
| `inscribing-taste` | `/inscribe` | Brand taste application |
| `styling-material` | `/style` | Material design styling |
| `surveying-patterns` | `/survey` | Pattern discovery |
| `synthesizing-taste` | `/synthesize-taste` | Taste synthesis |
| `validating-physics` | `/validate-physics` | Physics validation |
| `web3-testing` | `/web3-test` | Web3 testing utilities |

## Installation

```bash
# From your project root
cp -r /path/to/forge/sigil .claude/constructs/packs/sigil
.claude/constructs/packs/sigil/scripts/install.sh .
```

## Quick Start

```bash
# Survey existing patterns
/survey

# Inscribe brand taste
/inscribe

# Craft physics-based animations
/craft

# Validate physics implementation
/validate-physics
```

## Grimoire Structure

After installation, the following directories are created:

```
grimoires/sigil/
├── physics/       # Physics configurations
├── taste/         # Brand taste definitions
└── observations/  # Pattern observations
```

## Syncing from Rune

To update skills from the upstream rune repository:

```bash
./scripts/pull-from-rune.sh
```

## Requirements

- Claude Code CLI
- Loa Framework with `constructs-loader.sh`
