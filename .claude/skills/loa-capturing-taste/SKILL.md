---
name: loa-capturing-taste
version: "5.0.0"
description: |
  Interview developers to extract component taste.
  JSDoc is truth. Grep is discovery.
  v5: Optional vocabulary, proto-bead generation, HivemindOS bridge.
entry_point: false
invoked_by: "/taste command"
allowed_tools: [Read, Write, Edit, Grep, Glob, Bash, AskUserQuestion]
---

# Loa: Capturing Taste (v5.0.0)

> *"Extract tacit knowledge. Store in JSDoc. Find via grep."*

## Purpose

You have taste in your head. This skill extracts it through four questions, stores it in JSDoc, and enables discovery via grep.

**No manifest. No index. Filesystem is truth.**

## What's New in v5.0.0

| Feature | v4.0.0 | v5.0.0 |
|---------|--------|--------|
| Vocabulary | Required | Optional |
| Proto-beads | None | Generated on Gold |
| HivemindOS | Coupled | Bridge hooks |
| Skill name | lab-capturing-taste | loa-capturing-taste |

---

## Pre-Flight (Phase 0)

Before any operation, execute these steps in order:

### Step 1: Load Configuration

Read `.loa.config.yaml` for relevant settings:
```yaml
taste:
  vocabulary_path: null  # or path to vocabulary
  auto_proto_bead: true
proto_beads:
  local_path: "loa-grimoire/proto-beads/"
hivemind:
  connected: false
  vocabulary_path: "hivemind/vocabulary.md"
```

### Step 2: Load Vocabulary (OPTIONAL)

Check for vocabulary in priority order:

1. `.loa.config.yaml` → `taste.vocabulary_path` (if set)
2. `hivemind/vocabulary.md` (if exists)
3. `laboratory/vocabulary.md` (fallback)

**If vocabulary found**:
- Parse JTBD labels into memory
- @intent will be validated against these labels

**If NO vocabulary found**:
- Show warning: "No vocabulary loaded. @intent is freeform."
- @intent captures user's description as-is
- Continue normally (not blocked)

### Step 3: Detect Component Directory

```
Check order:
1. src/components
2. components
3. app/components
4. packages/ui/src
5. If none found -> Ask user
```

Use Glob to check each path. Store result as `COMPONENT_DIR`.

### Step 4: Detect Product Mode (First Run Only)

Check for existing @feel tags to infer mode:

```bash
grep -r "@feel.*playful\|@feel.*game" $COMPONENT_DIR/  # CultureTech
grep -r "@feel.*predictable\|@feel.*trust" $COMPONENT_DIR/  # FinTech
```

If no existing captures, ask once:

```
"First time running /taste in this repo.

 What's the product mode?

 • FinTech — trust, security, predictability
 • CultureTech — play, surprise, delight
 • Hybrid"
```

---

## Interview Protocol

### Phase 1: Identify Core Loop (Default /taste)

Ask using AskUserQuestion:
```
"Which components are in your CORE USER LOOP?
 (The actions users do most often)"
```

Accept comma-separated names. Mark each as `@critical_path true`.

### Phase 2: Four Questions Per Component

For each component (or single if `/taste [name]`):

**Q1: Problem**
```
"[ComponentName] - What PROBLEM does this solve?"
```
-> Write to `@description`

**Q2: Feel + Intent**
```
"How should [ComponentName] FEEL?"
```
-> Write raw response to `@feel`
-> Map to `@intent`:
   - If vocabulary loaded → validate against labels
   - If no vocabulary → use description as-is

**Q3: Rejected**
```
"What approaches did you REJECT for [ComponentName]?"
```
-> Write to `@rejected` (comma-separated, lowercase)

**Q4: Inspiration**
```
"Any REFERENCES for this vibe?"
```
-> Write to `@inspiration`

### Phase 3: Write JSDoc

Edit component file IN-PLACE. Extend existing JSDoc, don't replace.

### Phase 4: Depth Drilling

After capturing, offer to drill into nested components:

```
"I found nested components:
 • LoadingState
 • SuccessAnimation

 Drill into these? [Yes / No / Select]"
```

---

## Vocabulary Handling (v5.0.0)

### With Vocabulary

When vocabulary is loaded, map @feel to @intent:

```
Agent: [checks vocabulary]
       "Mapping to intent: [J] Reduce My Anxiety
        (from vocabulary — user mentioned anxiety)

        Does this fit?"
```

If no match:
```
Agent: "None of the vocabulary labels fit exactly.
        I'll capture your description in @feel.

        @intent will be: [freeform description]"
```

### Without Vocabulary

```
Agent: "⚠️ No vocabulary loaded. @intent is freeform.

        Capturing your description as-is:
        @intent Heavy, deliberate, trustworthy

        (Connect HivemindOS for validated labels)"
```

---

## Graduation Protocol (v5.0.0 Enhanced)

Invoked via `/taste graduate [component]`

### Step 1: Verify Silver Status

```bash
grep -l "@tier silver" [COMPONENT_DIR]/[component].tsx
```

### Step 2: Production Survival Check

```
"Has [component] survived in production?
 (2+ weeks, no regressions)"
```

### Step 3: Taste Owner Assignment

```
"Are you the Taste Owner for [component]?
 Enter your name/username:"
```

### Step 4: Physics Capture (if interactive)

Detect interactivity:
- onClick, onPress, onMouseEnter, onHover
- framer-motion, react-spring
- animate, transition, motion.

If interactive, capture physics:
```
"This is interactive. Physics?
 - Tension (1-500, snappier = higher):
 - Friction (1-50, settles faster = higher):
 - Delay (ms):"
```

### Step 5: Update JSDoc to Gold

```typescript
// BEFORE:
* @tier silver

// AFTER:
* @physics {"type":"spring","tension":120,"friction":14,"delay":200}
* @tier gold
* @tasteOwner soju
```

### Step 6: Generate Proto-Bead (NEW in v5.0.0)

If `.loa.config.yaml` → `taste.auto_proto_bead: true`:

```bash
.claude/scripts/proto-bead-gen.sh [ComponentName]
```

Output:
```
Proto-bead created: loa-grimoire/proto-beads/[ComponentName].yaml
Index updated: N total (M gold)
```

### Step 7: HivemindOS Sync (NEW in v5.0.0)

Check `.loa.config.yaml` → `hivemind.connected`:

**If connected**:
```
"[ComponentName] is now Gold. Let's capture the WHY for team context.

 Q: What user problem prompted this design?
 Q: What alternatives did you consider?
 Q: Any evidence (user feedback, experiments)?"
```

Then:
1. Create enriched bead at `hivemind/beads/BEAD-XXX.md`
2. Update proto-bead: `hivemind.synced: true`

**If not connected**:
- Skip silently
- Proto-bead has `why: null` (the upgrade hook)
- Output: "Proto-bead created. Connect HivemindOS to capture 'why'."

---

## JSDoc Schema

### Silver Component

```typescript
/**
 * @component ClaimButton
 *
 * @description
 * Users didn't know if their claim went through.
 *
 * @intent [J] Reduce My Anxiety  (or freeform if no vocabulary)
 *
 * @feel Heavy, deliberate. Sacrifice speed for certainty.
 *
 * @inspiration Bank vault doors - weight = security
 *
 * @rejected instant-feedback, spinner, skeleton
 *
 * @tier silver
 * @critical_path true
 */
```

### Gold Component

```typescript
/**
 * @component JoyfulLoader
 *
 * @description
 * Users rage-clicked due to subtle loading feedback.
 *
 * @intent [J] Reduce My Anxiety
 *
 * @feel Heavy, deliberate. Sacrifice speed for certainty.
 *
 * @inspiration Old Mac startup chime - deliberate, confident
 *
 * @rejected spinner, skeleton, instant-feedback
 *
 * @physics {"type":"spring","tension":120,"friction":14,"delay":200}
 *
 * @tier gold
 * @tasteOwner soju
 * @critical_path true
 */
```

---

## Agent Behavior Rules

### Rule 1: Rejection Checking (MANDATORY)

**Before suggesting ANY UI pattern, check rejections:**

```bash
grep -r "@rejected.*[pattern]" [COMPONENT_DIR]/
```

If found, DO NOT suggest that pattern.

### Rule 2: Vocabulary Respect

- If vocabulary loaded → only suggest valid @intent labels
- If no vocabulary → accept freeform descriptions

### Rule 3: Tier Respect

| Tier | Usage |
|------|-------|
| Gold | Use by default. Proven patterns. |
| Silver | Use with caveat. "This is Silver, not yet proven." |
| None | Create new. Check @rejected first. |

### Rule 4: Cite Sources

Always explain taste-based decisions with references to captured taste.

---

## Discovery Commands

```bash
# Find by rejection
grep -r "@rejected.*spinner" [COMPONENT_DIR]/

# Find by feel
grep -r "@feel.*heavy" [COMPONENT_DIR]/

# Find by intent
grep -r "@intent" [COMPONENT_DIR]/

# Find Gold
grep -r "@tier gold" [COMPONENT_DIR]/

# Find critical path
grep -r "@critical_path true" [COMPONENT_DIR]/

# List proto-beads
cat loa-grimoire/proto-beads/index.yaml
```

---

## Error Handling

| Error | Resolution |
|-------|------------|
| No vocabulary | Continue with freeform @intent |
| Component not found | Check spelling, ask for path |
| Already captured | Show current, ask to update |
| Already Gold | Cannot re-graduate |
| Proto-bead generation failed | Warn, continue (non-blocking) |

---

## Success Criteria

### Pre-Flight
- [ ] Configuration loaded from .loa.config.yaml
- [ ] Vocabulary loaded OR freeform warning shown
- [ ] Component directory detected

### Capture (Silver)
- [ ] 4 questions answered
- [ ] @intent captured (validated or freeform)
- [ ] JSDoc written in-place
- [ ] @tier silver assigned

### Graduation (Gold)
- [ ] Silver verified
- [ ] Production survival confirmed
- [ ] Taste owner assigned
- [ ] Physics captured (if interactive)
- [ ] JSDoc updated to Gold
- [ ] Proto-bead generated
- [ ] HivemindOS sync attempted (if connected)

---

## Cross-References

- Protocol: `.claude/protocols/frames.md` (TUNE frame)
- Protocol: `.claude/protocols/proto-beads.md`
- Protocol: `.claude/protocols/hivemind-bridge.md`
- Script: `.claude/scripts/proto-bead-gen.sh`
- Config: `.loa.config.yaml`

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 5.0.0 | 2024-12-28 | Loa migration. Optional vocabulary, proto-bead generation, HivemindOS bridge. |
| 4.0.0 | 2024-12-26 | Vocabulary validation, @inspiration, depth drilling. |
