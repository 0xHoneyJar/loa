# HivemindOS Bridge Protocol

> **Version**: 1.0.0
> **Status**: Active
> **Scope**: Loa → HivemindOS integration

This protocol defines how Loa (free execution engine) integrates with HivemindOS (paid organizational context layer).

---

## Core Concepts

### The Bridge

Loa works standalone. HivemindOS enriches it with organizational context.

```
┌─────────────────────────┐     ┌─────────────────────────┐
│         LOA             │     │      HIVEMINDOS         │
│  ┌─────────────────┐    │     │  ┌─────────────────┐    │
│  │  proto-beads    │────┼─────┼──│  enriched beads │    │
│  │  (what/who/when)│    │     │  │  (+ WHY)        │    │
│  └─────────────────┘    │     │  └─────────────────┘    │
│                         │     │                         │
│  ┌─────────────────┐    │     │  ┌─────────────────┐    │
│  │  freeform       │────┼─────┼──│  validated      │    │
│  │  @intent        │    │     │  │  @intent        │    │
│  └─────────────────┘    │     │  └─────────────────┘    │
└─────────────────────────┘     └─────────────────────────┘
```

### The Upgrade Hook

Proto-beads have `why: null` - this gap is filled when HivemindOS is connected.

---

## Connection Detection

### Check Configuration

Read `.loa.config.yaml`:

```yaml
hivemind:
  connected: true
  endpoint: "https://..."
  vocabulary_path: "hivemind/vocabulary.md"
  north_star_path: "hivemind/north-star.md"
  sync:
    auto: true
    prompt_why: true
```

### Connection States

| State | Behavior |
|-------|----------|
| `connected: false` | Loa works standalone, proto-beads local |
| `connected: true` | Full integration activated |

---

## Vocabulary Loading

When connected, vocabulary enriches @intent validation:

### Priority Order

1. `hivemind/vocabulary.md` (HivemindOS source)
2. `.loa.config.yaml` → `taste.vocabulary_path` (override)
3. `laboratory/vocabulary.md` (fallback)

### Vocabulary Format

```yaml
# hivemind/vocabulary.md (frontmatter)
schema_version: "1.0.0"
organization: "THJ"
last_updated: "2024-12-28"

labels:
  functional:
    - code: "[J] Make Transaction"
      description: "User wants to execute a transaction"
    - code: "[J] Find Information"
      description: "User wants to discover or locate something"

  emotional:
    - code: "[J] Reduce My Anxiety"
      description: "User feels uncertain, needs reassurance"
    - code: "[J] Help Me Feel Smart"
      description: "User feels confused, needs understanding"
```

### Validation Behavior

**With vocabulary**:
```
Agent: "Mapping to intent: [J] Reduce My Anxiety
        (matches 'anxious', 'uncertain' in vocabulary)

        Does this fit?"
```

**If no match**:
```
Agent: "None of the vocabulary labels fit exactly.
        Closest match: [J] Help Me Feel Smart

        Accept closest or use freeform?"
```

---

## Proto-Bead Sync

When Gold is signed AND connected:

### Sync Flow

```
Gold Signature
      │
      ▼
Proto-bead generated locally
      │
      ▼
Check hivemind.connected
      │
      ├─── false ──► Done (proto-bead has why: null)
      │
      └─── true ──► Prompt for "why"
                          │
                          ▼
                    Create enriched bead
                          │
                          ▼
                    Update proto-bead.hivemind.synced = true
```

### "Why" Enrichment Prompt

```
"[ComponentName] is now Gold. Let's capture the WHY for team context.

Q1: What user problem prompted this design?
    (Link to user feedback, support tickets, observations)

Q2: What alternatives did you consider?
    (Other patterns you evaluated and rejected)

Q3: Any evidence supporting this choice?
    (A/B tests, user research, experiments)"
```

### Enriched Bead Creation

Location: `hivemind/beads/BEAD-{XXX}.md`

```yaml
---
schema_version: "1.0.0"
id: BEAD-042
proto_bead_id: JoyfulLoader
created_at: "2024-12-28T10:30:00Z"

# Everything from proto-bead PLUS:

why:
  problem: "Users rage-clicked during loading states"
  decision: "Heavy physics to reduce perceived wait time"
  alternatives:
    - option: "Instant feedback"
      rejected_because: "Felt cheap, didn't inspire trust"
    - option: "Spinner"
      rejected_because: "Creates anxiety through endless motion"
  evidence:
    - type: user_truth
      ref: "UTC-042"
      summary: "User feedback about loading anxiety"

intent:
  validated: true
  labels:
    - "[J] Reduce My Anxiety"

team_context:
  contributors:
    - username: soju
      role: creator
  notes: []
---

# BEAD-042: JoyfulLoader

[Body content with full context...]
```

### Proto-Bead Update

After sync:
```yaml
# In proto-bead
hivemind:
  synced: true
  bead_id: "BEAD-042"
  synced_at: "2024-12-28T10:30:00Z"
```

---

## North Star Access

When connected, agents can reference the North Star:

```bash
cat hivemind/north-star.md
```

Use for:
- Alignment checking ("Does this match our vision?")
- Entry vector framing
- Decision context

---

## Graceful Degradation

When NOT connected, Loa continues fully functional:

| Feature | Connected | Not Connected |
|---------|-----------|---------------|
| /taste capture | Full | Full |
| @intent validation | Validated | Freeform |
| Proto-bead generation | Yes | Yes |
| "Why" enrichment | Prompted | Skipped |
| Vocabulary | Loaded | Optional/fallback |
| Bead sync | Active | why: null |

---

## Configuration Options

```yaml
# .loa.config.yaml

hivemind:
  # Master toggle
  connected: false

  # API endpoint (null when not connected)
  endpoint: null

  # Vocabulary for @intent validation
  vocabulary_path: "hivemind/vocabulary.md"

  # North Star for alignment
  north_star_path: "hivemind/north-star.md"

  # Sync behavior
  sync:
    # Auto-sync on Gold signature
    auto: true
    # Prompt for "why" during sync
    prompt_why: true
```

---

## Error Handling

| Error | Behavior |
|-------|----------|
| Vocabulary file missing | Fall back to freeform |
| Sync fails | Warn, keep proto-bead local |
| Endpoint unreachable | Continue standalone |
| North Star missing | Skip alignment checks |

All errors are **non-blocking** - Loa continues to work.

---

## Integration Points

### With Frames Protocol
- TUNE frame triggers sync checks
- Status line shows sync status

### With Proto-Beads Protocol
- Proto-beads are the sync unit
- `why: null` is the upgrade hook

### With Taste Governance
- Gold signature triggers sync
- Vocabulary validates @intent

---

## Guiding Principles

1. **Standalone first** - Loa works fully without HivemindOS
2. **Non-blocking** - Sync failures never block workflow
3. **Graceful degradation** - Missing features don't break core
4. **Clear upgrade path** - `why: null` signals value of connection
5. **Vocabulary is optional** - Freeform @intent is valid

---

## Cross-References

- `frames.md` - Frame system
- `proto-beads.md` - Proto-bead schema
- `taste-governance.md` - Silver/Gold tiers
- `.loa.config.yaml` - Configuration
