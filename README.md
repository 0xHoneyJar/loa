# Forge

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> *"The forge is where raw materials become precision instruments. User truth becomes testable reality."*

Claude Code skill packs for **hypothesis-driven product development**. Three packs that form a complete workflow from user observation through validation.

## Quick Start

```bash
# Clone the forge
git clone https://github.com/0xHoneyJar/forge /tmp/forge

# Install a pack (from your project root)
cp -r /tmp/forge/lens .claude/constructs/packs/lens
.claude/constructs/packs/lens/scripts/install.sh .

# Start using skills
/observe
```

## The Packs

| Pack | Emoji | Skills | Purpose |
|------|-------|--------|---------|
| **[Lens](#-sigil-of-insight-lens)** | 🔮 | 6 | User truth capture |
| **[Crucible](#-sigil-of-the-crucible-crucible)** | ⚗️ | 5 | Validation & testing |
| **[Artisan](#-sigil-of-the-artisan-artisan)** | 🎨 | 10 | Brand/UI craftsmanship |

**Total: 21 skills**

---

## 🔮 Sigil of Insight (Lens)

*Capture user truth through hypothesis-first research*

### Skills

| Command | Skill | Description |
|---------|-------|-------------|
| `/observe` | `observing-users` | Capture user feedback as hypothesis-first research with Level 3 diagnostic |
| `/shape` | `shaping-journeys` | Shape common patterns into journey definitions with JTBD clustering |
| - | `level-3-diagnostic` | Diagnostic-first user research framework (The Mom Test methodology) |
| `/analyze-gap` | `analyzing-gaps` | Compare user expectations with code reality, severity scoring |
| `/file-gap` | `filing-gaps` | Create GitHub/Linear issues from gap analysis with taxonomy labels |
| `/import-research` | `importing-research` | Bulk convert legacy user research to UTC format |

### Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    LENS WORKFLOW                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. /observe    →  User Truth Canvas (UTC)                      │
│     ↓               Capture quotes, form hypotheses             │
│                                                                 │
│  2. /shape      →  Journey Definition                           │
│     ↓               Cluster UTCs by JTBD, map states            │
│                                                                 │
│  3. /analyze-gap →  Gap Report                                  │
│     ↓               Compare expectations vs code reality        │
│                                                                 │
│  4. /file-gap   →  GitHub/Linear Issue                          │
│                     Track gaps with taxonomy labels             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Grimoire Structure

```
grimoires/lens/
├── canvas/     # User Truth Canvases (UTCs)
├── journeys/   # User journey definitions
└── state.yaml  # Lens state tracking
```

### Context Composition

Lens includes cultural context for crypto/DeFi research:

| Context | File | Purpose |
|---------|------|---------|
| Base | `crypto-base.md` | Universal crypto patterns |
| Berachain | `berachain-overlay.md` | Chain-specific terms |
| DeFi | `defi-overlay.md` | Protocol terminology |

```bash
# Compose contexts for your project
.claude/constructs/packs/lens/scripts/compose-context.sh .
```

---

## ⚗️ Sigil of the Crucible (Crucible)

*Transform user journeys into validated tests*

### Skills

| Command | Skill | Description |
|---------|-------|-------------|
| `/ground` | `grounding-code` | Extract actual code behavior into reality files with state machines |
| `/diagram` | `diagramming-states` | Generate Mermaid state diagrams (User Expects vs Code Does) |
| `/validate` | `validating-journeys` | Generate Playwright tests from state diagrams |
| `/walkthrough` | `walking-through` | Interactive dev browser walkthrough with wallet presets |
| `/iterate` | `iterating-feedback` | Update upstream artifacts from test results |

### Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    CRUCIBLE WORKFLOW                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. /ground     →  Reality File                                 │
│     ↓               Extract what code actually does             │
│                                                                 │
│  2. /diagram    →  State Diagrams                               │
│     ↓               Mermaid diagrams: expects vs does           │
│                                                                 │
│  3. /validate   →  Playwright Tests                             │
│     ↓               Generated from state diagrams               │
│                                                                 │
│  4. /walkthrough →  Manual Verification                         │
│     ↓               Interactive browser testing                 │
│                                                                 │
│  5. /iterate    →  Updated Artifacts                            │
│                     Feed results back to Lens                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Grimoire Structure

```
grimoires/crucible/
├── diagrams/      # Mermaid state diagrams
├── reality/       # Code reality files
├── gaps/          # Gap analysis reports
├── tests/         # Generated Playwright tests
├── walkthroughs/  # Walkthrough captures
└── results/       # Test results
```

### Key Features

| Feature | Description |
|---------|-------------|
| **Dual Diagrams** | Side-by-side "User Expects" vs "Code Does" |
| **Selector Inference** | Auto-generate Playwright selectors from components |
| **Wallet Presets** | Pre-configured states (empty, active, rewards-ready) |
| **Confidence Preservation** | Won't overwrite high-confidence findings |

---

## 🎨 Sigil of the Artisan (Artisan)

*Brand and UI craftsmanship through physics-based motion*

### Skills

| Command | Skill | Description |
|---------|-------|-------------|
| `/survey` | `surveying-patterns` | Pattern frequency analysis, component cataloging |
| `/synthesize-taste` | `synthesizing-taste` | Reference material analysis, brand vocabulary extraction |
| `/inscribe` | `inscribing-taste` | Brand token application, taste consistency checking |
| `/craft` | `crafting-physics` | Spring constant optimizer, mass/tension/friction calculator |
| `/animate` | `animating-motion` | Spring physics, timing curves, motion orchestration |
| `/behavior` | `applying-behavior` | Interaction state machines, gesture handlers |
| `/style` | `styling-material` | Material 3 compliance, elevation/shadow calculator |
| `/distill` | `distilling-components` | Component boundary detection, prop interface generation |
| `/validate-physics` | `validating-physics` | Animation performance profiler, jank detection |
| `/web3-test` | `web3-testing` | Wallet mocks, transaction flow testing |

### Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    ARTISAN WORKFLOW                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  DISCOVERY                                                      │
│  ─────────                                                      │
│  1. /survey     →  Pattern Observations                         │
│  2. /synthesize-taste → Taste Document                          │
│                                                                 │
│  APPLICATION                                                    │
│  ───────────                                                    │
│  3. /inscribe   →  Brand Tokens Applied                         │
│  4. /craft      →  Physics Config                               │
│  5. /animate    →  Motion Sequences                             │
│  6. /behavior   →  Interaction Handlers                         │
│  7. /style      →  Material Styling                             │
│                                                                 │
│  EXTRACTION                                                     │
│  ──────────                                                     │
│  8. /distill    →  Component Library                            │
│                                                                 │
│  VALIDATION                                                     │
│  ──────────                                                     │
│  9. /validate-physics → Performance Report                      │
│  10. /web3-test  →  Wallet Test Suite                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Grimoire Structure

```
grimoires/artisan/
├── physics/       # Physics configurations
├── taste/         # Brand taste definitions
└── observations/  # Pattern observations
```

### Syncing from Rune

```bash
# Pull latest skills from upstream rune repository
./scripts/pull-from-rune.sh
```

---

## Complete Workflow

The three packs form a continuous feedback loop:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     FORGE: COMPLETE WORKFLOW                             │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│    🔮 LENS                    ⚗️ CRUCIBLE                 🎨 ARTISAN     │
│    ───────                    ──────────                 ───────        │
│                                                                          │
│    User Feedback              Code Reality               Design System   │
│         │                          │                          │          │
│         ▼                          ▼                          ▼          │
│    ┌─────────┐               ┌─────────┐               ┌─────────┐      │
│    │ /observe│ ─────────────▶│ /ground │◀──────────── │ /survey │      │
│    └────┬────┘               └────┬────┘               └────┬────┘      │
│         │                         │                          │          │
│         ▼                         ▼                          ▼          │
│    ┌─────────┐               ┌─────────┐               ┌─────────┐      │
│    │ /shape  │ ─────────────▶│/diagram │◀──────────── │ /craft  │      │
│    └────┬────┘               └────┬────┘               └────┬────┘      │
│         │                         │                          │          │
│         ▼                         ▼                          ▼          │
│    ┌─────────┐               ┌─────────┐               ┌─────────┐      │
│    │/analyze │◀──────────────│/validate│──────────────▶│/validate│      │
│    │  -gap   │               └────┬────┘               │-physics │      │
│    └────┬────┘                    │                    └─────────┘      │
│         │                         │                                      │
│         ▼                         ▼                                      │
│    ┌─────────┐               ┌─────────┐                                │
│    │/file-gap│◀──────────────│/iterate │                                │
│    └─────────┘               └─────────┘                                │
│                                                                          │
│    Issues ◀─────────────────── Feedback Loop ──────────────────▶ Tests  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Installation

### Manual Installation

```bash
# Clone forge
git clone https://github.com/0xHoneyJar/forge /tmp/forge

# Install desired pack
cp -r /tmp/forge/lens .claude/constructs/packs/lens
.claude/constructs/packs/lens/scripts/install.sh .

# Install all packs
for pack in lens crucible artisan; do
  cp -r /tmp/forge/$pack .claude/constructs/packs/$pack
  .claude/constructs/packs/$pack/scripts/install.sh .
done
```

### Via Loa Constructs (Coming Soon)

```bash
# Install from registry
.claude/scripts/constructs-install.sh pack lens
.claude/scripts/constructs-install.sh pack crucible
.claude/scripts/constructs-install.sh pack artisan
```

---

## Requirements

- Claude Code CLI
- Loa Framework with `constructs-loader.sh`
- Playwright (for Crucible `/validate` command)

---

## Registry Status

| Pack | Slug | Registry Name | Status |
|------|------|---------------|--------|
| Lens | `lens` | Sigil of Insight | 🟡 Pending Review |
| Crucible | `crucible` | Sigil of the Crucible | 🟡 Pending Review |
| Artisan | `artisan` | Sigil of the Artisan | 📝 Draft |

---

## Documentation

- **[CHANGELOG.md](CHANGELOG.md)** - Version history
- **[VERIFICATION.md](VERIFICATION.md)** - Installation verification checklist
- **[lens/README.md](lens/README.md)** - Lens pack details
- **[crucible/README.md](crucible/README.md)** - Crucible pack details
- **[artisan/README.md](artisan/README.md)** - Artisan pack details

---

## License

[MIT](LICENSE) - Use freely in your projects.

---

## Links

- [Loa Framework](https://github.com/0xHoneyJar/loa)
- [Claude Code](https://claude.ai/code)
- [0xHoneyJar](https://github.com/0xHoneyJar)
