# Proto-Bead Protocol

> **Version**: 1.0.0
> **Status**: Active
> **Scope**: Loa execution engine

Proto-beads are local decision captures for components. They record **what/who/when/where** but NOT **why** - the "why" gap is the upgrade hook to HivemindOS.

---

## Core Concepts

### What is a Proto-Bead?

A proto-bead is a YAML file that captures:
- Component identity and location
- Taste signature (Silver/Gold tier)
- Captured attributes (@feel, @intent, @rejected, @inspiration)
- Physics values (for interactive components)
- **NOT the "why"** - that's what HivemindOS adds

### The Upgrade Hook

```yaml
# Proto-bead (Loa local)
why: null  # THE GAP

# Enriched bead (HivemindOS)
why:
  problem: "Users felt anxious during claims"
  decision: "Heavy physics to reduce perceived wait"
  alternatives: [...]
  evidence: [...]
```

When HivemindOS is connected, proto-beads sync and get enriched with the "why".

### Storage Location

```
loa-grimoire/proto-beads/
├── index.yaml              # Registry of all proto-beads
├── JoyfulLoader.yaml       # Individual proto-bead
├── ClaimButton.yaml
└── BadgeReveal.yaml
```

---

## Proto-Bead Schema

### Full Schema (v1.0.0)

```yaml
# loa-grimoire/proto-beads/{ComponentName}.yaml

schema_version: "1.0.0"
id: string                    # Component name (unique identifier)
created_at: ISO-8601          # When created
updated_at: ISO-8601          # Last modified

component:
  name: string                # Display name
  file: string                # Relative path to component file
  type: string | null         # Optional: react, vue, svelte, etc.

signature:
  tier: silver | gold         # Must be gold to have proto-bead
  taste_owner: string         # Username who signed
  signed_at: ISO-8601         # When signed Gold

capture:
  description: string         # What problem it solves (@description)
  feel: string                # How it should feel (@feel)
  intent: string | null       # JTBD label (@intent) - freeform without vocabulary
  rejected:                   # Patterns avoided (@rejected)
    - string
  inspiration:                # Design references (@inspiration)
    - string

physics:                      # For interactive components only
  tension: number | null      # Spring stiffness (1-500)
  friction: number | null     # Resistance (1-50)
  delay: number | null        # ms before animation
  duration: number | null     # Total animation time
  preset: string | null       # Named preset if used

states:                       # State-specific feel (optional)
  hover: string | null
  loading: string | null
  success: string | null
  error: string | null
  disabled: string | null

# THE GAP - HivemindOS fills this
why: null

# Sync metadata
hivemind:
  synced: false
  bead_id: string | null      # BEAD-XXX when synced
  synced_at: ISO-8601 | null
```

### Minimal Required Fields

```yaml
schema_version: "1.0.0"
id: "ComponentName"
created_at: "2024-12-28T10:00:00Z"
updated_at: "2024-12-28T10:00:00Z"

component:
  name: "ComponentName"
  file: "src/components/ComponentName.tsx"

signature:
  tier: gold
  taste_owner: "username"
  signed_at: "2024-12-28T10:00:00Z"

capture:
  description: "Problem it solves"
  feel: "How it should feel"
  rejected: []
  inspiration: []

why: null

hivemind:
  synced: false
```

---

## Index Schema

### index.yaml Structure

```yaml
# loa-grimoire/proto-beads/index.yaml

schema_version: "1.0.0"
last_updated: ISO-8601

summary:
  total: number
  gold: number
  silver: number              # Always 0 (only Gold generates proto-beads)
  synced: number              # Count synced to HivemindOS

beads:
  - id: string                # Component name
    tier: gold
    taste_owner: string
    file: string              # Relative path to proto-bead YAML
    synced: boolean
    created_at: ISO-8601
```

### Example Index

```yaml
schema_version: "1.0.0"
last_updated: "2024-12-28T10:30:00Z"

summary:
  total: 3
  gold: 3
  silver: 0
  synced: 1

beads:
  - id: JoyfulLoader
    tier: gold
    taste_owner: soju
    file: JoyfulLoader.yaml
    synced: true
    created_at: "2024-12-15T14:00:00Z"
  - id: ClaimButton
    tier: gold
    taste_owner: soju
    file: ClaimButton.yaml
    synced: false
    created_at: "2024-12-20T09:00:00Z"
  - id: BadgeReveal
    tier: gold
    taste_owner: zerker
    file: BadgeReveal.yaml
    synced: false
    created_at: "2024-12-28T10:00:00Z"
```

---

## Generation Trigger

Proto-beads are generated **only on Gold signature**:

1. User runs `/taste graduate ComponentName`
2. Component passes graduation requirements
3. User signs as @tasteOwner
4. Proto-bead generation script runs
5. YAML created at `loa-grimoire/proto-beads/{name}.yaml`
6. Index updated

### Generation Flow

```
/taste graduate JoyfulLoader
         │
         ▼
┌─────────────────────┐
│ Graduation Protocol │
│ - Production check  │
│ - Owner assignment  │
│ - Physics capture   │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ Extract from JSDoc  │
│ - @description      │
│ - @feel, @intent    │
│ - @rejected         │
│ - @inspiration      │
│ - @physics          │
│ - @states           │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ proto-bead-gen.sh   │
│ - Create YAML       │
│ - Update index      │
└─────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ If HivemindOS connected:            │
│ - Prompt for "why"                  │
│ - Sync to hivemind/beads/           │
│ - Mark synced: true                 │
└─────────────────────────────────────┘
```

---

## JSDoc Extraction

Proto-beads extract data from component JSDoc:

### Source JSDoc (Gold Component)

```typescript
/**
 * @component JoyfulLoader
 *
 * @description
 * Users rage-clicked due to subtle loading feedback.
 * They didn't know if their action registered.
 *
 * @intent [J] Reduce My Anxiety
 *
 * @feel Heavy, deliberate. Sacrifice speed for certainty.
 *       The user should feel the system is "working hard" not "stuck".
 *
 * @inspiration
 * - Old Mac startup chime: deliberate, confident
 * - Bank vault doors: weight = security
 *
 * @rejected spinner, skeleton, instant-feedback
 *
 * @physics {"type":"spring","tension":120,"friction":14,"delay":200}
 *
 * @tier gold
 * @tasteOwner soju
 *
 * @states {
 *   "active": "Full animation, spring physics",
 *   "completing": "Slow down, settle into success"
 * }
 */
```

### Resulting Proto-Bead

```yaml
schema_version: "1.0.0"
id: JoyfulLoader
created_at: "2024-12-28T10:30:00Z"
updated_at: "2024-12-28T10:30:00Z"

component:
  name: JoyfulLoader
  file: src/components/JoyfulLoader.tsx
  type: react

signature:
  tier: gold
  taste_owner: soju
  signed_at: "2024-12-28T10:30:00Z"

capture:
  description: |
    Users rage-clicked due to subtle loading feedback.
    They didn't know if their action registered.
  feel: |
    Heavy, deliberate. Sacrifice speed for certainty.
    The user should feel the system is "working hard" not "stuck".
  intent: "[J] Reduce My Anxiety"
  rejected:
    - spinner
    - skeleton
    - instant-feedback
  inspiration:
    - "Old Mac startup chime: deliberate, confident"
    - "Bank vault doors: weight = security"

physics:
  tension: 120
  friction: 14
  delay: 200
  duration: null
  preset: heavy

states:
  active: "Full animation, spring physics"
  completing: "Slow down, settle into success"

why: null

hivemind:
  synced: false
  bead_id: null
  synced_at: null
```

---

## Discovery Commands

Find proto-beads via standard tools:

```bash
# List all proto-beads
cat loa-grimoire/proto-beads/index.yaml

# Find by taste owner
grep -l "taste_owner: soju" loa-grimoire/proto-beads/*.yaml

# Find by intent
grep -l "Reduce My Anxiety" loa-grimoire/proto-beads/*.yaml

# Find unsynced
grep -l "synced: false" loa-grimoire/proto-beads/*.yaml

# Count by tier
grep -c "tier: gold" loa-grimoire/proto-beads/index.yaml
```

---

## HivemindOS Sync

When HivemindOS is connected, proto-beads sync to enriched beads:

### Sync Trigger

1. Gold signature creates proto-bead
2. Check `.loa.config.yaml` for `hivemind.connected: true`
3. If connected, prompt for "why":
   - "What problem does this solve for users?"
   - "What alternatives did you consider?"
   - "Any evidence (user feedback, experiments)?"
4. Create enriched bead at `hivemind/beads/BEAD-XXX.md`
5. Update proto-bead: `hivemind.synced: true`, `hivemind.bead_id: BEAD-XXX`

### Without HivemindOS

- Proto-beads work fully standalone
- `why: null` remains (the upgrade hook)
- No sync prompts
- Vocabulary validation optional (freeform @intent)

---

## Validation Rules

### Required Fields

| Field | Validation |
|-------|------------|
| `id` | Non-empty string, matches component name |
| `component.name` | Non-empty string |
| `component.file` | Valid path, file should exist |
| `signature.tier` | Must be "gold" |
| `signature.taste_owner` | Non-empty string |
| `capture.description` | Non-empty string |
| `capture.feel` | Non-empty string |

### Optional Fields

| Field | Default |
|-------|---------|
| `capture.intent` | null (freeform without vocabulary) |
| `capture.rejected` | [] |
| `capture.inspiration` | [] |
| `physics.*` | null (non-interactive components) |
| `states.*` | null |

### Physics Ranges

| Parameter | Valid Range |
|-----------|-------------|
| `tension` | 1-500 |
| `friction` | 1-50 |
| `delay` | 0-2000 (ms) |
| `duration` | 0-5000 (ms) |

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| Component not found | File doesn't exist | Verify component path |
| Already has proto-bead | YAML exists | Update instead of create |
| Invalid physics | Out of range | Clamp to valid range |
| Missing @tasteOwner | Not Gold tier | Run graduation first |
| Index update failed | Permission/disk | Check write permissions |

---

## Configuration

In `.loa.config.yaml`:

```yaml
proto_beads:
  enabled: true
  local_path: "loa-grimoire/proto-beads/"

# For HivemindOS sync
hivemind:
  connected: false
  endpoint: null
  vocabulary_path: "hivemind/vocabulary.md"
```

---

## Integration Points

### With Frames Protocol
- TUNE frame is where proto-beads are born
- Gold signature triggers generation

### With Taste Governance
- Only Gold components get proto-beads
- Proto-bead is the capture artifact

### With HivemindOS (When Connected)
- Proto-beads sync to enriched beads
- "Why" enrichment adds organizational context
- Vocabulary validates @intent

---

## Guiding Principles

1. **Gold only** - Silver components don't get proto-beads
2. **JSDoc is source** - Proto-bead is extraction, not duplication
3. **why: null is intentional** - The gap is the upgrade hook
4. **Local first** - Works fully without HivemindOS
5. **Index always current** - Update atomically with bead creation

---

## Cross-References

- `frames.md` - TUNE frame triggers generation
- `taste-governance.md` - Silver/Gold tiers
- `hivemind-bridge.md` - HivemindOS sync protocol
- `.loa.config.yaml` - Configuration
- `.claude/scripts/proto-bead-gen.sh` - Generation script
