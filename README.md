# Forge Constructs

Claude Code skill packs for Hivemind OS execution.

## Packs

| Pack | Skills | Purpose |
|------|--------|---------|
| **Lens** | 6 | User truth capture |
| **Crucible** | 5 | Validation & testing |
| **Sigil** | 10 | Brand/UI craftsmanship |

## Installation

```bash
# Clone this repo
git clone https://github.com/0xHoneyJar/forge /tmp/forge

# Copy desired pack
cp -r /tmp/forge/lens .claude/constructs/packs/lens

# Run installer
.claude/constructs/packs/lens/scripts/install.sh .
```

## Pack Details

### Lens Pack

User research and feedback analysis skills:
- `observing-users` - Capture user feedback as hypothesis-first research
- `shaping-journeys` - Shape common patterns into journey definitions
- `level-3-diagnostic` - Diagnostic-first user research framework
- `analyzing-gaps` - Compare user expectations with code reality
- `filing-gaps` - Create issues from gap analysis reports
- `importing-research` - Bulk convert legacy user research

### Crucible Pack

Validation and testing skills:
- `validating-journeys` - Generate Playwright tests from state diagrams
- `grounding-code` - Extract actual code behavior into reality files
- `iterating-feedback` - Update upstream artifacts from test results
- `walking-through` - Interactive dev browser walkthrough
- `diagramming-states` - Generate Mermaid state machine diagrams

### Sigil Pack

Brand and UI craftsmanship skills:
- `animating-motion` - Motion design and animation
- `applying-behavior` - Interaction behavior patterns
- `crafting-physics` - Physics-based animations
- `distilling-components` - Component extraction
- `inscribing-taste` - Brand taste application
- `styling-material` - Material design styling
- `surveying-patterns` - Pattern discovery
- `synthesizing-taste` - Taste synthesis
- `validating-physics` - Physics validation
- `web3-testing` - Web3 testing utilities

## Requirements

- Claude Code CLI
- Loa Framework with `constructs-loader.sh`

## Verification

All packs have been tested and verified:

| Pack | Skills | Install | Grimoire |
|------|--------|---------|----------|
| Lens | 6 | ✓ | grimoires/lens/ |
| Crucible | 5 | ✓ | grimoires/crucible/ |
| Sigil | 10 | ✓ | grimoires/sigil/ |

**Total: 21 skills**

See [VERIFICATION.md](VERIFICATION.md) for detailed checklist.

## License

MIT
