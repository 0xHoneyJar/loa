# Frame Protocol

> **Version**: 1.0.0
> **Status**: Active
> **Scope**: Loa execution engine

Frames are cognitive modes with distinct physics and behaviors. They shape how agents approach work through **invisible context-switching** - agents infer the frame, users don't explicitly select it.

---

## Core Concepts

### The Three Frames

| Frame | Symbol | Tempo | Feel | Exit Condition |
|-------|--------|-------|------|----------------|
| SEARCH | ◇ | Async, patient | Loose, spacious, creative | When clarity is gained |
| BUILD | ◆ | Sync, real-time | Rigid, precise, focused | When it works |
| TUNE | ◈ | Interactive | Tactile, sliders, instrument | When craft is complete |

### Frame Physics

Each frame has distinct behavioral physics:

**◇ SEARCH** - Discovery Mode
- Divergent exploration encouraged
- Multiple paths evaluated simultaneously
- No pressure for immediate resolution
- Output: Plans, architectures, options

**◆ BUILD** - Execution Mode
- Convergent implementation
- Single path, deterministic execution
- Preview-driven iteration
- Output: Working code, Silver components

**◈ TUNE** - Refinement Mode
- Direct manipulation
- Physics-based adjustments
- Feel over function
- Output: Gold components, signed taste

---

## Frame Detection

Frames are **inferred, not explicitly entered**. Detection follows a priority order:

### 1. Command-Based (Highest Priority)

| Command | Inferred Frame |
|---------|---------------|
| `/plan-and-analyze` | ◇ SEARCH |
| `/architect` | ◇ SEARCH |
| `/sprint-plan` | ◇ SEARCH |
| `/ride` | ◇ SEARCH |
| `/implement` | ◆ BUILD |
| `/craft` | ◆ BUILD |
| `/taste` | ◈ TUNE |
| `/taste-check` | ◈ TUNE |
| `/tune` | ◈ TUNE |

### 2. File Pattern-Based

When touching certain files, context-appropriate constraints apply:

| Pattern | Constraint | Effect |
|---------|------------|--------|
| `*.sol` | Security-first | Extra validation, audit prompts |
| `*.move` | Security-first | Extra validation, audit prompts |
| `**/treasury/**` | Security-first | Elevated caution |
| `**/contracts/**` | Security-first | Review requirements |
| `*.tsx`, `*.css` | UI context | Taste awareness |
| `**/components/**` | UI context | Check @rejected patterns |

**Note**: File constraints are additive to the current frame, not frame switches.

### 3. Action-Based

| Action Pattern | Inferred Frame |
|----------------|---------------|
| "what should we...", "how might we...", "explore..." | ◇ SEARCH |
| "build X", "implement Y", "fix Z", "create..." | ◆ BUILD |
| "feels too heavy", "needs more bounce", "adjust..." | ◈ TUNE |

### 4. Default

If no signal detected: **◇ SEARCH**

---

## Status Line Format

```
{frame_symbol} {FRAME} · {context} · {status}
```

### Components

| Component | Description | Examples |
|-----------|-------------|----------|
| `frame_symbol` | Frame indicator | ◇, ◆, ◈ |
| `FRAME` | Frame name | SEARCH, BUILD, TUNE |
| `context` | Current focus | command, component, task |
| `status` | Current state | see below |

### State Values by Frame

| Frame | Possible States |
|-------|-----------------|
| ◇ SEARCH | gathering, exploring, mapping, comparing, analyzing |
| ◆ BUILD | implementing, testing, previewing, iterating, fixing |
| ◈ TUNE | adjusting, comparing, signing, capturing, reviewing |

### Examples

```
◇ SEARCH · /architect · gathering requirements
◇ SEARCH · /plan-and-analyze · mapping dependencies
◇ SEARCH · auth-flow · exploring options
◆ BUILD · LAB-892 · implementing auth flow
◆ BUILD · /craft JoyfulLoader · preview running
◆ BUILD · ClaimButton · fixing edge case
◈ TUNE · JoyfulLoader · adjusting physics
◈ TUNE · /taste-check · awaiting signature
◈ TUNE · ClaimButton (Gold) · 2 notes pending
```

---

## Frame Transitions

Transitions are **fluid, not forced**. The status line updates automatically.

### Allowed Flows

```
◇ SEARCH ──────► ◆ BUILD ──────► ◈ TUNE
     ▲                               │
     └───────────────────────────────┘
           (return to discovery)
```

### Gate Conditions

| From → To | Gate |
|-----------|------|
| SEARCH → BUILD | Clarity achieved (plan exists) |
| BUILD → TUNE | Component works (passes tests) |
| TUNE → SEARCH | Craft complete OR needs rethinking |

### Micro-Transitions

If in BUILD and user spots a TUNE opportunity:
- User can adjust without explicit frame switch
- Agent acknowledges the micro-transition
- Status line reflects momentary shift

Example:
```
User: "That loading animation feels too fast"
Agent: [◈ micro-tune] Adjusting tension to 120, friction to 14...
       [◆ BUILD] Continuing implementation...
```

---

## Agent Behavior by Frame

### ◇ SEARCH Behaviors
- Ask clarifying questions
- Present multiple options
- Reference prior decisions (beads)
- Avoid premature convergence
- Surface related context

### ◆ BUILD Behaviors
- Execute deterministically
- Show preview when possible
- Run tests frequently
- Create Silver components
- Log discovered work
- Check @rejected before suggesting patterns

### ◈ TUNE Behaviors
- Present physics options
- Allow direct manipulation
- Capture taste decisions
- Prompt for @tasteOwner signature
- Generate proto-beads on Gold

---

## Configuration

In `.loa.config.yaml`:

```yaml
frames:
  enabled: true
  auto_detect: true
  default: search
  status_line: true
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | true | Enable frame system |
| `auto_detect` | bool | true | Infer frames from context |
| `default` | string | search | Fallback when no signal |
| `status_line` | bool | true | Show status line output |

---

## Integration Points

### With Taste Governance
- BUILD creates Silver components
- TUNE graduates Silver → Gold
- Gold signature triggers proto-bead

### With Proto-Beads
- TUNE frame is where beads are born
- `/taste-check` generates proto-beads
- Physics values captured in bead

### With HivemindOS (When Connected)
- Vocabulary validation in TUNE
- "Why" enrichment on Gold signature
- North Star reference available

---

## Guiding Principles

1. **Inference over ceremony** - Detect frame from context, don't force explicit switches
2. **Fluid transitions** - Allow micro-transitions without status ceremony
3. **Frame-appropriate output** - Match response style to current frame
4. **Cognitive load awareness** - Frames are mental gates for ADHD-friendly workflow
5. **Status transparency** - Always show current frame in status line
6. **Invisible switching** - Users don't need to say "enter BUILD mode"

---

## Security Constraints

When file patterns trigger security-first context, these constraints apply regardless of frame:

| Constraint | Behavior |
|------------|----------|
| Extra validation | Prompt for confirmation on state-changing operations |
| Audit awareness | Surface security implications |
| Review requirements | Suggest security review before merge |
| Elevated logging | More detailed trajectory for audit |

Security constraints are **additive** - they enhance the current frame rather than replacing it.

---

## Cross-References

- `proto-beads.md` - Proto-bead generation in TUNE
- `taste-governance.md` - Silver/Gold tiers
- `hivemind-bridge.md` - HivemindOS integration
- `.loa.config.yaml` - Configuration
