# 🎨 Sigil of the Artisan (Artisan Pack)

> *"Design is not how it looks, but how it moves. Physics is taste made tangible."*

Brand and UI craftsmanship skills from **rune**. Survey patterns, synthesize taste, craft physics-based motion, and validate performance.

## Skills (10)

| Command | Skill | Phase | Output |
|---------|-------|-------|--------|
| `/survey` | `surveying-patterns` | Discovery | Pattern Catalog |
| `/synthesize-taste` | `synthesizing-taste` | Discovery | Taste Document |
| `/inscribe` | `inscribing-taste` | Application | Brand Tokens |
| `/craft` | `crafting-physics` | Application | Physics Config |
| `/animate` | `animating-motion` | Application | Motion Sequences |
| `/behavior` | `applying-behavior` | Application | Interaction Handlers |
| `/style` | `styling-material` | Application | Material Styling |
| `/distill` | `distilling-components` | Extraction | Component Library |
| `/validate-physics` | `validating-physics` | Validation | Performance Report |
| `/web3-test` | `web3-testing` | Validation | Wallet Test Suite |

---

## Workflow

### Discovery Phase

#### `/survey` - Pattern Discovery

```
Codebase → Pattern Frequency Analysis → Component Catalog
```

- Analyze **pattern frequency** across codebase
- Build **component catalog** with usage stats
- Generate **design system coverage** report

#### `/synthesize-taste` - Taste Synthesis

```
Reference Materials → Brand Vocabulary → Taste Document
```

- Analyze **reference materials** (screenshots, links)
- Extract **brand vocabulary** (tone, rhythm, texture)
- Generate **taste document** for team alignment

### Application Phase

#### `/inscribe` - Taste Application

```
Taste Document → Components → Brand Tokens Applied
```

- Apply **brand tokens** consistently
- Validate **color/typography** compliance
- Check **taste consistency** across surfaces

#### `/craft` - Physics Crafting

```
Animation Requirements → Spring Constants → Physics Config
```

| Parameter | Purpose |
|-----------|---------|
| `stiffness` | How snappy (higher = faster) |
| `damping` | How bouncy (lower = more oscillation) |
| `mass` | How heavy (higher = slower) |

- Optimize **spring constants** for feel
- Calculate **mass/tension/friction** values
- Visualize **physics timelines**

#### `/animate` - Motion Design

```
Physics Config → Timing Curves → Motion Sequences
```

- Generate **timing curve** functions
- Orchestrate **motion sequences**
- Calculate **spring physics** parameters

#### `/behavior` - Interaction Patterns

```
Component → State Machine → Interaction Handlers
```

- Build **interaction state machines**
- Map **hover/focus/active** states
- Create **touch gesture** handler patterns

#### `/style` - Material Design

```
Components → Material 3 → Styled Components
```

- Check **Material 3 compliance**
- Calculate **elevation/shadow** values
- Generate **surface tone** variations

### Extraction Phase

#### `/distill` - Component Extraction

```
Design Patterns → Boundaries → Component Library
```

- Detect **component boundaries**
- Generate **prop interfaces**
- Extract **variants** from usage patterns

### Validation Phase

#### `/validate-physics` - Physics Validation

```
Animations → Profiler → Performance Report
```

- Profile **animation performance**
- Analyze **frame rates** (target: 60fps)
- Detect **jank** (dropped frames, stutters)

#### `/web3-test` - Web3 Testing

```
Wallet Flows → Mocks → Test Suite
```

- Generate **wallet mocks** (MetaMask, WalletConnect)
- Test **transaction flows** (submit, confirm, fail)
- Validate **gas estimation** logic

---

## Installation

```bash
# From your project root
cp -r /path/to/forge/artisan .claude/constructs/packs/artisan
.claude/constructs/packs/artisan/scripts/install.sh .
```

---

## Grimoire Structure

After installation:

```
grimoires/artisan/
├── physics/         # Physics configurations
│   └── {component}.yaml
├── taste/           # Brand taste definitions
│   └── taste-document.md
└── observations/    # Pattern observations
    └── {date}-survey.md
```

---

## Physics Reference

### Spring Presets

| Preset | Stiffness | Damping | Use Case |
|--------|-----------|---------|----------|
| `gentle` | 100 | 15 | Page transitions |
| `snappy` | 400 | 25 | Button feedback |
| `bouncy` | 300 | 10 | Playful interactions |
| `stiff` | 700 | 30 | Instant response |

### Timing Curves

| Curve | CSS | Use Case |
|-------|-----|----------|
| `ease-out-expo` | `cubic-bezier(0.16, 1, 0.3, 1)` | Enter animations |
| `ease-in-expo` | `cubic-bezier(0.7, 0, 0.84, 0)` | Exit animations |
| `ease-in-out-expo` | `cubic-bezier(0.87, 0, 0.13, 1)` | Move/resize |

---

## Syncing from Rune

Artisan skills are sourced from the upstream **rune** repository:

```bash
# Pull latest skills
./scripts/pull-from-rune.sh
```

This updates skill definitions while preserving local grimoire data.

---

## Integration with Crucible

Artisan validates what Crucible tests:

| Crucible Command | Artisan Validation |
|------------------|------------------|
| `/walkthrough` | `/validate-physics` during walkthrough |
| `/validate` | Test animations don't jank |
| - | `/web3-test` for wallet mocks |

---

## Requirements

- Claude Code CLI
- Loa Framework with `constructs-loader.sh`
- **Framer Motion** or **React Spring** (for physics skills)
