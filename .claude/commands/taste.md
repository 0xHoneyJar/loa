---
name: "taste"
version: "5.0.0"
description: |
  Interview developers to extract component taste.
  Stores in JSDoc. Discovers via grep.
  Supports capture (Silver), graduation (Gold), and agent integration.
  v5: Loa migration - optional vocabulary, proto-bead generation, HivemindOS bridge.
  "The agent learns your taste so it stops fighting you."

arguments:
  - name: "target"
    type: "string"
    required: false
    description: "Component name, 'graduate [name]', or empty for core-loop interview"
  - name: "dry-run"
    type: "flag"
    required: false
    description: "Preview without writing"
  - name: "list"
    type: "flag"
    required: false
    description: "List captured components via grep"
  - name: "deep"
    type: "flag"
    required: false
    description: "Drill into nested components and states after capture"

skill: "loa-capturing-taste"
skill_path: "skills/loa-capturing-taste/"

pre_flight:
  - check: "component_directory_exists"
    paths:
      - "src/components"
      - "components"
      - "app/components"
      - "packages/ui/src"
    fallback: "ask_user"

outputs:
  - path: "src/components/*.tsx"
    type: "file"
    description: "JSDoc extended in-place"
  - path: "loa-grimoire/proto-beads/*.yaml"
    type: "file"
    description: "Proto-bead on Gold graduation"

mode:
  default: "foreground"
  allow_background: false
---

# /taste - Capture Component Taste (v5.0.0)

> *"The agent learns your taste so it stops fighting you."*

## Purpose

Extract tacit design knowledge through conversation. Store in JSDoc. Discover via grep.

**No manifest. No index. JSDoc is truth.**

## What's New in v5.0.0 (Loa)

| Feature | v4.0.0 | v5.0.0 |
|---------|--------|--------|
| Vocabulary | Required | Optional |
| Proto-beads | None | Generated on Gold |
| HivemindOS | Coupled | Bridge hooks |
| @intent | Must validate | Freeform if no vocabulary |

## Invocation

```bash
/taste                          # Identify core loop, interview each
/taste ClaimButton              # Capture single component
/taste ClaimButton --deep       # Capture + drill into nested components
/taste graduate JoyfulLoader    # Promote Silver -> Gold + proto-bead
/taste --list                   # Show captured via grep
/taste --dry-run                # Preview without writing
```

## The Four Questions

| # | Question | Maps To |
|---|----------|---------|
| 1 | "What PROBLEM does this solve?" | @description |
| 2 | "How should it FEEL?" | @feel + @intent |
| 3 | "What did you REJECT?" | @rejected |
| 4 | "Any REFERENCES for this vibe?" | @inspiration |

## @intent Behavior (v5.0.0)

**With vocabulary** (HivemindOS connected or local vocabulary):
- @intent labels validated against vocabulary
- Invalid labels rejected with suggestions

**Without vocabulary** (standalone Loa):
- @intent is freeform text
- Warning shown: "No vocabulary loaded. @intent is freeform."
- User's description captured as-is

## Tags Written

| Tag | Purpose | When |
|-----|---------|------|
| `@component` | Component name | Always |
| `@description` | Problem solved | Always (Q1) |
| `@feel` | How it should feel (subjective) | Always (Q2) |
| `@intent` | JTBD labels or freeform | Always (mapped from Q2) |
| `@rejected` | Patterns to avoid | Always (Q3) |
| `@inspiration` | Reference examples | Recommended (Q4) |
| `@tier` | silver or gold | Always |
| `@states` | State-specific feel | If distinct states |
| `@physics` | JSON interaction feel | Gold interactive only |
| `@tasteOwner` | Who defends this | Gold only |
| `@critical_path` | Core user loop | If identified |

## Subcommands

### Default (core-loop)
```bash
/taste
```
1. Ask which components are in core user loop
2. Interview each (4 questions)
3. Write JSDoc in-place
4. Mark as Silver

### Single Component
```bash
/taste ClaimButton
```
1. Interview component (4 questions)
2. Write JSDoc in-place
3. Mark as Silver

### Graduate (v5.0.0 Enhanced)
```bash
/taste graduate JoyfulLoader
```
1. Verify component is Silver
2. Ask about production survival
3. Ask for Taste Owner confirmation
4. If interactive, capture physics
5. Update JSDoc to Gold
6. **NEW**: Generate proto-bead
7. **NEW**: If HivemindOS connected, prompt for "why" enrichment

### List
```bash
/taste --list
```
1. `grep -r "@tier" [component-dir]/`
2. Group by tier
3. Show uncaptured count

## Workflow: Capture

```
/taste

Agent: [checks for vocabulary]
       [if .loa.config.yaml has vocabulary_path → load it]
       [if hivemind/vocabulary.md exists → load it]
       [if laboratory/vocabulary.md exists → load it]
       [if none → "No vocabulary loaded. @intent is freeform."]

       [detects component directory]

       "Which components are in your CORE USER LOOP?"
You: "ClaimButton, QuestCard, JoyfulLoader"

Agent: "ClaimButton - Q1: What PROBLEM does it solve?"
You: "Users didn't know if their claim went through"

Agent: "Q2: How should it FEEL?"
You: "Heavy. Deliberate. They should feel the weight."

Agent: [if vocabulary loaded → maps to vocabulary]
       [if no vocabulary → uses description as-is]

       "Q3: What did you REJECT?"
You: "Instant feedback, spinner, skeleton"

Agent: "Q4: Any REFERENCES for this vibe?"
You: "Bank vault doors - weight = security"

Agent: ✓ ClaimButton captured (Silver)

       @intent [J] Reduce My Anxiety  (or freeform if no vocabulary)
       @feel Heavy, deliberate. They should feel the weight.
       @inspiration Bank vault doors - weight = security
       @rejected instant-feedback, spinner, skeleton
```

## Workflow: Graduate (v5.0.0)

```
/taste graduate JoyfulLoader

Agent: "JoyfulLoader is Silver.
        Has it survived in production?"
You: "3 weeks, no issues"

Agent: "Are you the Taste Owner?"
You: "Yes, soju"

Agent: [checks if @inspiration exists]
       "Missing @inspiration. Any references to add?"
You: "Old Mac startup chime - deliberate, confident"

Agent: "This is interactive. Physics?
        - Tension (snappier = higher):
        - Friction (settles faster = higher):
        - Delay:"
You: "120, 14, 200ms"

Agent: [updates JSDoc to Gold]
       [runs proto-bead-gen.sh JoyfulLoader]

       ✓ JoyfulLoader is Gold

       @tasteOwner soju
       @inspiration Old Mac startup chime - deliberate, confident
       @physics {"type":"spring","tension":120,"friction":14,"delay":200}

       Proto-bead created: loa-grimoire/proto-beads/JoyfulLoader.yaml

Agent: [checks .loa.config.yaml → hivemind.connected]
       [if connected → prompts for "why" enrichment]
       [if not connected → done]
```

## Proto-Bead Generation (v5.0.0)

On Gold graduation:
1. Extract all @ tags from JSDoc
2. Run `.claude/scripts/proto-bead-gen.sh {ComponentName}`
3. Proto-bead created at `loa-grimoire/proto-beads/{name}.yaml`
4. Index updated at `loa-grimoire/proto-beads/index.yaml`

Proto-bead captures what/who/when but NOT why:
```yaml
why: null  # THE GAP - HivemindOS fills this
```

## HivemindOS Bridge (v5.0.0)

If `.loa.config.yaml` has `hivemind.connected: true`:

1. After proto-bead generation, prompt for "why":
   - "What user problem prompted this design?"
   - "What alternatives did you consider?"
   - "Any evidence (user feedback, experiments)?"
2. Create enriched bead at `hivemind/beads/BEAD-XXX.md`
3. Update proto-bead: `hivemind.synced: true`
4. Vocabulary validation activates

If not connected:
- Proto-beads work fully standalone
- `why: null` remains (the upgrade hook)
- No sync prompts

## Vocabulary Loading (v5.0.0)

Priority order:
1. `.loa.config.yaml` → `taste.vocabulary_path` (if set)
2. `hivemind/vocabulary.md` (if exists)
3. `laboratory/vocabulary.md` (fallback for backwards compat)
4. None → freeform @intent with warning

## Tiers

| Tier | Meaning | Requirements |
|------|---------|--------------|
| (none) | Uncaptured | No interview |
| silver | Captured | 4 questions answered |
| gold | Proven | Silver + prod + physics (if interactive) + owner + proto-bead |

## Error Handling

| Error | Resolution |
|-------|------------|
| No components directory | Ask user for path |
| Component not found | Check spelling |
| Already captured | Show current, ask to update |
| Already Gold | Cannot re-graduate |
| Proto-bead generation failed | Show error, continue (non-blocking) |

## Discovery (Post-Capture)

```bash
# Find by rejection
grep -r "@rejected.*spinner" src/components/

# Find by feel
grep -r "@feel.*heavy" src/components/

# Find by intent
grep -r "@intent" src/components/

# Find by inspiration
grep -r "@inspiration.*RuneScape" src/components/

# Find components with states
grep -r "@states" src/components/

# Find Gold
grep -r "@tier gold" src/components/

# Find critical path
grep -r "@critical_path true" src/components/

# List proto-beads
cat loa-grimoire/proto-beads/index.yaml
```

## Configuration

In `.loa.config.yaml`:
```yaml
taste:
  enabled: true
  vocabulary_path: null  # Set for local vocabulary
  auto_proto_bead: true  # Generate on Gold

hivemind:
  connected: false  # Set true when HivemindOS configured
  vocabulary_path: "hivemind/vocabulary.md"
```

## Agent

Launches `loa-capturing-taste` from `skills/loa-capturing-taste/`.

See: `skills/loa-capturing-taste/SKILL.md` for full workflow details.

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 5.0.0 | 2024-12-28 | **Loa migration.** Optional vocabulary, proto-bead generation, HivemindOS bridge hooks. |
| 4.0.0 | 2024-12-26 | Vocabulary validation, @inspiration, depth drilling, product mode. |
| 3.0.0 | 2024-12-26 | Unified skill with graduation protocol. |
